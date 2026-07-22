package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"time"

	"music-player-server/internal/auth"
)

type authenticatedUserContextKey struct{}

type credentialsRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

type sessionResponse struct {
	Token     string    `json:"token"`
	TokenType string    `json:"token_type"`
	ExpiresAt time.Time `json:"expires_at"`
	User      auth.User `json:"user"`
}

func WithAuthService(service *auth.Service) HandlerOption {
	return func(handler *Handler) {
		handler.auth = service
	}
}

func (h *Handler) authSetup(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusOK, h.auth.RegistrationStatus(r.Context()))
}

func (h *Handler) register(w http.ResponseWriter, r *http.Request) {
	var request credentialsRequest
	if err := decodeJSONBody(r, &request); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	user, err := h.auth.Register(r.Context(), request.Username, request.Password)
	if errors.Is(err, auth.ErrRegistrationClosed) {
		writeError(w, http.StatusForbidden, "registration is closed")
		return
	}
	if errors.Is(err, auth.ErrInvalidUsername) || errors.Is(err, auth.ErrInvalidPassword) {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to create administrator")
		return
	}
	writeJSON(w, http.StatusCreated, user)
}

func (h *Handler) login(w http.ResponseWriter, r *http.Request) {
	var request credentialsRequest
	if err := decodeJSONBody(r, &request); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	session, err := h.auth.Login(r.Context(), request.Username, request.Password)
	if errors.Is(err, auth.ErrInvalidCredentials) {
		writeError(w, http.StatusUnauthorized, "invalid username or password")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to create session")
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusOK, sessionResponse{
		Token:     session.Token,
		TokenType: "Bearer",
		ExpiresAt: session.ExpiresAt,
		User:      session.User,
	})
}

func (h *Handler) currentUser(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(authenticatedUserContextKey{}).(auth.User)
	if !ok {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusOK, user)
}

func (h *Handler) logout(w http.ResponseWriter, r *http.Request) {
	token, ok := bearerToken(r.Header.Get("Authorization"))
	if !ok {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}
	if err := h.auth.Revoke(r.Context(), token); err != nil && !errors.Is(err, auth.ErrInvalidToken) {
		writeError(w, http.StatusInternalServerError, "failed to revoke session")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) authMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if h.auth == nil || isPublicRequest(r) {
			next.ServeHTTP(w, r)
			return
		}
		token, ok := bearerToken(r.Header.Get("Authorization"))
		if !ok {
			w.Header().Set("WWW-Authenticate", `Bearer realm="LyraNest Community"`)
			writeError(w, http.StatusUnauthorized, "authentication required")
			return
		}
		user, err := h.auth.Authenticate(r.Context(), token)
		if err != nil {
			w.Header().Set("WWW-Authenticate", `Bearer realm="LyraNest Community", error="invalid_token"`)
			writeError(w, http.StatusUnauthorized, "invalid or expired token")
			return
		}
		ctx := context.WithValue(r.Context(), authenticatedUserContextKey{}, user)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func isPublicRequest(r *http.Request) bool {
	if r.URL.Path == "/healthz" {
		return r.Method == http.MethodGet || r.Method == http.MethodHead
	}
	if r.URL.Path == "/api/v1/auth/setup" && r.Method == http.MethodGet {
		return true
	}
	if r.URL.Path == "/api/v1/auth/register" && r.Method == http.MethodPost {
		return true
	}
	if r.URL.Path == "/api/v1/auth/login" && r.Method == http.MethodPost {
		return true
	}
	if (r.Method == http.MethodGet || r.Method == http.MethodHead) && strings.HasPrefix(r.URL.Path, "/api/v1/tracks/") {
		return strings.HasSuffix(r.URL.Path, "/stream") || strings.HasSuffix(r.URL.Path, "/artwork")
	}
	return !strings.HasPrefix(r.URL.Path, "/api/")
}

func bearerToken(header string) (string, bool) {
	parts := strings.Fields(header)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") || parts[1] == "" {
		return "", false
	}
	return parts[1], true
}

func decodeJSONBody(r *http.Request, target any) error {
	decoder := json.NewDecoder(io.LimitReader(r.Body, 1<<20))
	decoder.DisallowUnknownFields()
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
