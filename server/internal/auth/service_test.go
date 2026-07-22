package auth

import (
	"context"
	"encoding/hex"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

const testPassword = "correct horse battery staple"

func TestServiceFirstAdministratorLifecyclePersists(t *testing.T) {
	dataDir := t.TempDir()
	service := newTestService(t, dataDir)

	status := service.RegistrationStatus(context.Background())
	if status.Initialized || !status.RegisterAllowed {
		t.Fatalf("initial status = %#v, want registration allowed", status)
	}

	user, err := service.Register(context.Background(), "Admin", testPassword)
	if err != nil {
		t.Fatalf("Register returned error: %v", err)
	}
	if user.Role != "admin" || user.Username != "Admin" {
		t.Fatalf("user = %#v, want first administrator", user)
	}
	if _, err := service.Register(context.Background(), "other", "another secure password"); !errors.Is(err, ErrRegistrationClosed) {
		t.Fatalf("second Register error = %v, want ErrRegistrationClosed", err)
	}

	usersFile, err := os.ReadFile(filepath.Join(dataDir, usersFileName))
	if err != nil {
		t.Fatalf("ReadFile returned error: %v", err)
	}
	if strings.Contains(string(usersFile), testPassword) {
		t.Fatal("persisted user database contains plaintext password")
	}
	if !strings.Contains(string(usersFile), `"algorithm": "pbkdf2-sha256"`) {
		t.Fatalf("user database = %s, want password algorithm metadata", usersFile)
	}

	session, err := service.Login(context.Background(), " admin ", testPassword)
	if err != nil {
		t.Fatalf("Login returned error: %v", err)
	}
	if session.Token == "" {
		t.Fatal("Login returned empty token")
	}
	if _, err := service.Login(context.Background(), "Admin", "wrong password"); !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("wrong-password Login error = %v, want ErrInvalidCredentials", err)
	}

	restarted := newTestService(t, dataDir)
	authenticated, err := restarted.Authenticate(context.Background(), session.Token)
	if err != nil {
		t.Fatalf("Authenticate after restart returned error: %v", err)
	}
	if authenticated.ID != user.ID {
		t.Fatalf("authenticated user = %#v, want %#v", authenticated, user)
	}
	if err := restarted.Revoke(context.Background(), session.Token); err != nil {
		t.Fatalf("Revoke returned error: %v", err)
	}
	if _, err := restarted.Authenticate(context.Background(), session.Token); !errors.Is(err, ErrInvalidToken) {
		t.Fatalf("Authenticate after revoke error = %v, want ErrInvalidToken", err)
	}
}

func TestServiceAllowsExactlyOneConcurrentFirstRegistration(t *testing.T) {
	service := newTestService(t, t.TempDir())
	var successes atomic.Int32
	var unexpected atomic.Value
	var waitGroup sync.WaitGroup
	for index := 0; index < 8; index++ {
		waitGroup.Add(1)
		go func() {
			defer waitGroup.Done()
			_, err := service.Register(context.Background(), "admin", testPassword)
			if err == nil {
				successes.Add(1)
				return
			}
			if !errors.Is(err, ErrRegistrationClosed) {
				unexpected.Store(err)
			}
		}()
	}
	waitGroup.Wait()
	if value := unexpected.Load(); value != nil {
		t.Fatalf("unexpected registration error: %v", value)
	}
	if successes.Load() != 1 {
		t.Fatalf("successful registrations = %d, want 1", successes.Load())
	}
}

func TestServiceRejectsExpiredSession(t *testing.T) {
	now := time.Date(2026, time.July, 19, 12, 0, 0, 0, time.UTC)
	service, err := NewService(t.TempDir(), time.Hour, WithPasswordIterations(10), WithClock(func() time.Time { return now }))
	if err != nil {
		t.Fatalf("NewService returned error: %v", err)
	}
	if _, err := service.Register(context.Background(), "admin", testPassword); err != nil {
		t.Fatalf("Register returned error: %v", err)
	}
	session, err := service.Login(context.Background(), "admin", testPassword)
	if err != nil {
		t.Fatalf("Login returned error: %v", err)
	}
	now = now.Add(time.Hour)
	if _, err := service.Authenticate(context.Background(), session.Token); !errors.Is(err, ErrInvalidToken) {
		t.Fatalf("Authenticate error = %v, want ErrInvalidToken", err)
	}
}

func TestServiceLeavesExistingMusicDataUntouched(t *testing.T) {
	dataDir := t.TempDir()
	tracksPath := filepath.Join(dataDir, "tracks.json")
	want := []byte("[{\"id\":\"existing-track\"}]\n")
	if err := os.WriteFile(tracksPath, want, 0o600); err != nil {
		t.Fatalf("WriteFile returned error: %v", err)
	}
	service := newTestService(t, dataDir)
	if _, err := service.Register(context.Background(), "admin", testPassword); err != nil {
		t.Fatalf("Register returned error: %v", err)
	}
	got, err := os.ReadFile(tracksPath)
	if err != nil {
		t.Fatalf("ReadFile returned error: %v", err)
	}
	if string(got) != string(want) {
		t.Fatalf("tracks.json = %q, want unchanged %q", got, want)
	}
}

func TestPBKDF2SHA256KnownVector(t *testing.T) {
	derived := pbkdf2SHA256([]byte("password"), []byte("salt"), 1, 32)
	want, err := hex.DecodeString("120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
	if err != nil {
		t.Fatalf("DecodeString returned error: %v", err)
	}
	if subtleCompare(derived, want) == false {
		t.Fatalf("derived key = %x, want %x", derived, want)
	}
}

func newTestService(t *testing.T, dataDir string) *Service {
	t.Helper()
	service, err := NewService(dataDir, time.Hour, WithPasswordIterations(10))
	if err != nil {
		t.Fatalf("NewService returned error: %v", err)
	}
	return service
}

func subtleCompare(left, right []byte) bool {
	if len(left) != len(right) {
		return false
	}
	var difference byte
	for index := range left {
		difference |= left[index] ^ right[index]
	}
	return difference == 0
}
