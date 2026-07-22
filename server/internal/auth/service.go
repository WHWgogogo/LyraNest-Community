package auth

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

const (
	usersFileName             = "auth-users.json"
	sessionsFileName          = "auth-sessions.json"
	keyFileName               = "auth.key"
	defaultPasswordIterations = 600_000
	passwordKeyLength         = 32
	saltLength                = 16
	tokenLength               = 32
)

var (
	ErrRegistrationClosed = errors.New("registration is closed")
	ErrInvalidCredentials = errors.New("invalid username or password")
	ErrInvalidToken       = errors.New("invalid or expired token")
	ErrInvalidUsername    = errors.New("username must be 3 to 64 characters")
	ErrInvalidPassword    = errors.New("password must be 12 to 1024 characters")
)

type User struct {
	ID        string    `json:"id"`
	Username  string    `json:"username"`
	Role      string    `json:"role"`
	CreatedAt time.Time `json:"created_at"`
}

type RegistrationStatus struct {
	Initialized     bool `json:"initialized"`
	RegisterAllowed bool `json:"register_allowed"`
}

type Session struct {
	Token     string    `json:"token"`
	ExpiresAt time.Time `json:"expires_at"`
	User      User      `json:"user"`
}

type Service struct {
	mu                 sync.Mutex
	dataDir            string
	usersPath          string
	sessionsPath       string
	keyPath            string
	key                []byte
	users              map[string]storedUser
	sessions           map[string]storedSession
	sessionTTL         time.Duration
	passwordIterations int
	dummyPassword      passwordHash
	now                func() time.Time
}

type Option func(*Service)

func WithPasswordIterations(iterations int) Option {
	return func(service *Service) {
		if iterations > 0 {
			service.passwordIterations = iterations
		}
	}
}

func WithClock(now func() time.Time) Option {
	return func(service *Service) {
		if now != nil {
			service.now = now
		}
	}
}

type storedUser struct {
	User
	Password passwordHash `json:"password"`
}

type passwordHash struct {
	Algorithm  string `json:"algorithm"`
	Iterations int    `json:"iterations"`
	Salt       string `json:"salt"`
	Hash       string `json:"hash"`
}

type storedSession struct {
	UserID    string    `json:"user_id"`
	ExpiresAt time.Time `json:"expires_at"`
}

type usersDocument struct {
	Version int          `json:"version"`
	Users   []storedUser `json:"users"`
}

type sessionsDocument struct {
	Version  int                      `json:"version"`
	Sessions map[string]storedSession `json:"sessions"`
}

func NewService(dataDir string, sessionTTL time.Duration, options ...Option) (*Service, error) {
	if strings.TrimSpace(dataDir) == "" {
		return nil, errors.New("auth data directory is required")
	}
	if sessionTTL <= 0 {
		return nil, errors.New("auth session TTL must be positive")
	}
	absoluteDataDir, err := filepath.Abs(dataDir)
	if err != nil {
		return nil, fmt.Errorf("resolve auth data directory: %w", err)
	}
	if err := os.MkdirAll(absoluteDataDir, 0o700); err != nil {
		return nil, fmt.Errorf("create auth data directory: %w", err)
	}
	if err := os.Chmod(absoluteDataDir, 0o700); err != nil {
		return nil, fmt.Errorf("secure auth data directory: %w", err)
	}
	service := &Service{
		dataDir:            absoluteDataDir,
		usersPath:          filepath.Join(absoluteDataDir, usersFileName),
		sessionsPath:       filepath.Join(absoluteDataDir, sessionsFileName),
		keyPath:            filepath.Join(absoluteDataDir, keyFileName),
		users:              make(map[string]storedUser),
		sessions:           make(map[string]storedSession),
		sessionTTL:         sessionTTL,
		passwordIterations: defaultPasswordIterations,
		now:                time.Now,
	}
	for _, option := range options {
		if option != nil {
			option(service)
		}
	}
	dummyPassword, err := newPasswordHash("invalid-password-placeholder", service.passwordIterations)
	if err != nil {
		return nil, err
	}
	service.dummyPassword = dummyPassword
	if err := service.loadOrCreateKey(); err != nil {
		return nil, err
	}
	if err := service.loadUsers(); err != nil {
		return nil, err
	}
	if err := service.loadSessions(); err != nil {
		return nil, err
	}
	if service.pruneExpiredLocked() {
		if err := service.writeSessionsLocked(); err != nil {
			return nil, err
		}
	}
	return service, nil
}

func (s *Service) RegistrationStatus(_ context.Context) RegistrationStatus {
	s.mu.Lock()
	defer s.mu.Unlock()
	allowed := len(s.users) == 0
	return RegistrationStatus{Initialized: !allowed, RegisterAllowed: allowed}
}

func (s *Service) Register(ctx context.Context, username, password string) (User, error) {
	if err := ctx.Err(); err != nil {
		return User{}, err
	}
	username = strings.TrimSpace(username)
	if len([]rune(username)) < 3 || len([]rune(username)) > 64 {
		return User{}, ErrInvalidUsername
	}
	if len(password) < 12 || len(password) > 1024 {
		return User{}, ErrInvalidPassword
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.users) != 0 {
		return User{}, ErrRegistrationClosed
	}
	passwordRecord, err := newPasswordHash(password, s.passwordIterations)
	if err != nil {
		return User{}, err
	}
	userID, err := randomID()
	if err != nil {
		return User{}, err
	}
	user := User{ID: userID, Username: username, Role: "admin", CreatedAt: s.now().UTC()}
	key := normalizeUsername(username)
	s.users[key] = storedUser{User: user, Password: passwordRecord}
	if err := s.writeUsersLocked(); err != nil {
		delete(s.users, key)
		return User{}, err
	}
	return user, nil
}

func (s *Service) Login(ctx context.Context, username, password string) (Session, error) {
	if err := ctx.Err(); err != nil {
		return Session{}, err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	stored, ok := s.users[normalizeUsername(username)]
	passwordRecord := s.dummyPassword
	if ok {
		passwordRecord = stored.Password
	}
	passwordMatches := verifyPassword(password, passwordRecord)
	if !ok || !passwordMatches {
		return Session{}, ErrInvalidCredentials
	}
	tokenBytes := make([]byte, tokenLength)
	if _, err := rand.Read(tokenBytes); err != nil {
		return Session{}, fmt.Errorf("generate session token: %w", err)
	}
	token := base64.RawURLEncoding.EncodeToString(tokenBytes)
	expiresAt := s.now().UTC().Add(s.sessionTTL)
	digest := s.tokenDigest(token)
	s.sessions[digest] = storedSession{UserID: stored.ID, ExpiresAt: expiresAt}
	if err := s.writeSessionsLocked(); err != nil {
		delete(s.sessions, digest)
		return Session{}, err
	}
	return Session{Token: token, ExpiresAt: expiresAt, User: stored.User}, nil
}

func (s *Service) Authenticate(ctx context.Context, token string) (User, error) {
	if err := ctx.Err(); err != nil {
		return User{}, err
	}
	if strings.TrimSpace(token) == "" {
		return User{}, ErrInvalidToken
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	digest := s.tokenDigest(token)
	session, ok := s.sessions[digest]
	if !ok {
		return User{}, ErrInvalidToken
	}
	if !session.ExpiresAt.After(s.now()) {
		delete(s.sessions, digest)
		_ = s.writeSessionsLocked()
		return User{}, ErrInvalidToken
	}
	for _, user := range s.users {
		if user.ID == session.UserID {
			return user.User, nil
		}
	}
	return User{}, ErrInvalidToken
}

func (s *Service) Revoke(ctx context.Context, token string) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	digest := s.tokenDigest(token)
	session, ok := s.sessions[digest]
	if !ok {
		return ErrInvalidToken
	}
	delete(s.sessions, digest)
	if err := s.writeSessionsLocked(); err != nil {
		s.sessions[digest] = session
		return err
	}
	return nil
}

func (s *Service) tokenDigest(token string) string {
	mac := hmac.New(sha256.New, s.key)
	_, _ = mac.Write([]byte(token))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

func (s *Service) pruneExpiredLocked() bool {
	changed := false
	now := s.now()
	for digest, session := range s.sessions {
		if !session.ExpiresAt.After(now) {
			delete(s.sessions, digest)
			changed = true
		}
	}
	return changed
}

func (s *Service) loadOrCreateKey() error {
	key, err := os.ReadFile(s.keyPath)
	if err == nil {
		if len(key) != 32 {
			return fmt.Errorf("auth key %q must contain exactly 32 bytes", s.keyPath)
		}
		if err := os.Chmod(s.keyPath, 0o600); err != nil {
			return fmt.Errorf("secure auth key: %w", err)
		}
		s.key = key
		return nil
	}
	if !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("read auth key: %w", err)
	}
	key = make([]byte, 32)
	if _, err := rand.Read(key); err != nil {
		return fmt.Errorf("generate auth key: %w", err)
	}
	file, err := os.OpenFile(s.keyPath, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if errors.Is(err, os.ErrExist) {
		return s.loadOrCreateKey()
	}
	if err != nil {
		return fmt.Errorf("create auth key: %w", err)
	}
	if _, err := file.Write(key); err != nil {
		_ = file.Close()
		_ = os.Remove(s.keyPath)
		return fmt.Errorf("write auth key: %w", err)
	}
	if err := file.Sync(); err != nil {
		_ = file.Close()
		return fmt.Errorf("sync auth key: %w", err)
	}
	if err := file.Close(); err != nil {
		return fmt.Errorf("close auth key: %w", err)
	}
	s.key = key
	return nil
}

func (s *Service) loadUsers() error {
	var document usersDocument
	if err := readJSONFile(s.usersPath, &document); errors.Is(err, os.ErrNotExist) {
		return nil
	} else if err != nil {
		return fmt.Errorf("load auth users: %w", err)
	}
	if document.Version != 1 {
		return fmt.Errorf("unsupported auth users version %d", document.Version)
	}
	if err := os.Chmod(s.usersPath, 0o600); err != nil {
		return fmt.Errorf("secure auth users: %w", err)
	}
	for _, user := range document.Users {
		s.users[normalizeUsername(user.Username)] = user
	}
	return nil
}

func (s *Service) loadSessions() error {
	var document sessionsDocument
	if err := readJSONFile(s.sessionsPath, &document); errors.Is(err, os.ErrNotExist) {
		return nil
	} else if err != nil {
		return fmt.Errorf("load auth sessions: %w", err)
	}
	if document.Version != 1 {
		return fmt.Errorf("unsupported auth sessions version %d", document.Version)
	}
	if err := os.Chmod(s.sessionsPath, 0o600); err != nil {
		return fmt.Errorf("secure auth sessions: %w", err)
	}
	if document.Sessions != nil {
		s.sessions = document.Sessions
	}
	return nil
}

func (s *Service) writeUsersLocked() error {
	users := make([]storedUser, 0, len(s.users))
	for _, user := range s.users {
		users = append(users, user)
	}
	return writeJSONFile(s.dataDir, s.usersPath, usersDocument{Version: 1, Users: users})
}

func (s *Service) writeSessionsLocked() error {
	return writeJSONFile(s.dataDir, s.sessionsPath, sessionsDocument{Version: 1, Sessions: s.sessions})
}

func newPasswordHash(password string, iterations int) (passwordHash, error) {
	salt := make([]byte, saltLength)
	if _, err := rand.Read(salt); err != nil {
		return passwordHash{}, fmt.Errorf("generate password salt: %w", err)
	}
	hash := pbkdf2SHA256([]byte(password), salt, iterations, passwordKeyLength)
	return passwordHash{
		Algorithm:  "pbkdf2-sha256",
		Iterations: iterations,
		Salt:       base64.RawStdEncoding.EncodeToString(salt),
		Hash:       base64.RawStdEncoding.EncodeToString(hash),
	}, nil
}

func verifyPassword(password string, record passwordHash) bool {
	if record.Algorithm != "pbkdf2-sha256" || record.Iterations <= 0 {
		return false
	}
	salt, err := base64.RawStdEncoding.DecodeString(record.Salt)
	if err != nil {
		return false
	}
	expected, err := base64.RawStdEncoding.DecodeString(record.Hash)
	if err != nil || len(expected) == 0 {
		return false
	}
	actual := pbkdf2SHA256([]byte(password), salt, record.Iterations, len(expected))
	return subtle.ConstantTimeCompare(actual, expected) == 1
}

func pbkdf2SHA256(password, salt []byte, iterations, keyLength int) []byte {
	blocks := (keyLength + sha256.Size - 1) / sha256.Size
	derived := make([]byte, 0, blocks*sha256.Size)
	buffer := make([]byte, len(salt)+4)
	copy(buffer, salt)
	for block := 1; block <= blocks; block++ {
		binary.BigEndian.PutUint32(buffer[len(salt):], uint32(block))
		mac := hmac.New(sha256.New, password)
		_, _ = mac.Write(buffer)
		value := mac.Sum(nil)
		result := append([]byte(nil), value...)
		for iteration := 1; iteration < iterations; iteration++ {
			mac.Reset()
			_, _ = mac.Write(value)
			value = mac.Sum(nil)
			for index := range result {
				result[index] ^= value[index]
			}
		}
		derived = append(derived, result...)
	}
	return derived[:keyLength]
}

func normalizeUsername(username string) string {
	return strings.ToLower(strings.TrimSpace(username))
}

func randomID() (string, error) {
	value := make([]byte, 16)
	if _, err := rand.Read(value); err != nil {
		return "", fmt.Errorf("generate user ID: %w", err)
	}
	return base64.RawURLEncoding.EncodeToString(value), nil
}

func readJSONFile(path string, target any) error {
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer file.Close()
	decoder := json.NewDecoder(file)
	if err := decoder.Decode(target); err != nil {
		return err
	}
	var trailing any
	if err := decoder.Decode(&trailing); err != io.EOF {
		if err == nil {
			return errors.New("multiple JSON values")
		}
		return err
	}
	return nil
}

func writeJSONFile(dataDir, path string, value any) error {
	temp, err := os.CreateTemp(dataDir, ".auth-*.tmp")
	if err != nil {
		return err
	}
	tempPath := temp.Name()
	remove := true
	defer func() {
		_ = temp.Close()
		if remove {
			_ = os.Remove(tempPath)
		}
	}()
	if err := os.Chmod(tempPath, 0o600); err != nil {
		return err
	}
	encoder := json.NewEncoder(temp)
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(value); err != nil {
		return err
	}
	if err := temp.Sync(); err != nil {
		return err
	}
	if err := temp.Close(); err != nil {
		return err
	}
	if err := os.Rename(tempPath, path); err != nil {
		return err
	}
	remove = false
	directory, err := os.Open(dataDir)
	if err == nil {
		_ = directory.Sync()
		_ = directory.Close()
	}
	return nil
}
