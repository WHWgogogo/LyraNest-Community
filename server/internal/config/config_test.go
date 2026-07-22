package config

import (
	"log/slog"
	"testing"
	"time"
)

func TestLoadDefaults(t *testing.T) {
	for _, key := range []string{
		"SERVER_ADDR",
		"MUSIC_LIBRARY_DIR",
		"MUSIC_DATA_DIR",
		"LOG_LEVEL",
		"SHUTDOWN_TIMEOUT",
		"AUTH_SESSION_TTL",
	} {
		t.Setenv(key, "")
	}

	cfg := Load()

	if cfg.Addr != ":8080" {
		t.Fatalf("Addr = %q, want :8080", cfg.Addr)
	}
	if cfg.LibraryDir != "./music" {
		t.Fatalf("LibraryDir = %q, want ./music", cfg.LibraryDir)
	}
	if cfg.DataDir != "./data" {
		t.Fatalf("DataDir = %q, want ./data", cfg.DataDir)
	}
	if cfg.LogLevel != slog.LevelInfo {
		t.Fatalf("LogLevel = %v, want %v", cfg.LogLevel, slog.LevelInfo)
	}
	if cfg.ShutdownTimeout != 10*time.Second {
		t.Fatalf("ShutdownTimeout = %v, want 10s", cfg.ShutdownTimeout)
	}
	if cfg.AuthSessionTTL != 24*time.Hour {
		t.Fatalf("AuthSessionTTL = %v, want 24h", cfg.AuthSessionTTL)
	}
}

func TestLoadEnvironmentOverrides(t *testing.T) {
	t.Setenv("SERVER_ADDR", " 127.0.0.1:9090 ")
	t.Setenv("MUSIC_LIBRARY_DIR", " C:\\Music ")
	t.Setenv("MUSIC_DATA_DIR", " C:\\MusicData ")
	t.Setenv("LOG_LEVEL", " debug ")
	t.Setenv("SHUTDOWN_TIMEOUT", " 3s ")
	t.Setenv("AUTH_SESSION_TTL", " 12h ")

	cfg := Load()

	if cfg.Addr != "127.0.0.1:9090" {
		t.Fatalf("Addr = %q, want 127.0.0.1:9090", cfg.Addr)
	}
	if cfg.LibraryDir != "C:\\Music" {
		t.Fatalf("LibraryDir = %q, want C:\\Music", cfg.LibraryDir)
	}
	if cfg.DataDir != "C:\\MusicData" {
		t.Fatalf("DataDir = %q, want C:\\MusicData", cfg.DataDir)
	}
	if cfg.LogLevel != slog.LevelDebug {
		t.Fatalf("LogLevel = %v, want %v", cfg.LogLevel, slog.LevelDebug)
	}
	if cfg.ShutdownTimeout != 3*time.Second {
		t.Fatalf("ShutdownTimeout = %v, want 3s", cfg.ShutdownTimeout)
	}
	if cfg.AuthSessionTTL != 12*time.Hour {
		t.Fatalf("AuthSessionTTL = %v, want 12h", cfg.AuthSessionTTL)
	}
}
