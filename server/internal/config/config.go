package config

import (
	"log/slog"
	"os"
	"strings"
	"time"
)

type Config struct {
	Addr            string
	LibraryDir      string
	DataDir         string
	LogLevel        slog.Level
	ShutdownTimeout time.Duration
	AuthSessionTTL  time.Duration
}

func Load() Config {
	return Config{
		Addr:            getEnv("SERVER_ADDR", ":8080"),
		LibraryDir:      getEnv("MUSIC_LIBRARY_DIR", "./music"),
		DataDir:         getEnv("MUSIC_DATA_DIR", "./data"),
		LogLevel:        parseLogLevel(getEnv("LOG_LEVEL", "info")),
		ShutdownTimeout: parseDuration(getEnv("SHUTDOWN_TIMEOUT", "10s"), 10*time.Second),
		AuthSessionTTL:  parseDuration(getEnv("AUTH_SESSION_TTL", "24h"), 24*time.Hour),
	}
}

func getEnv(key, fallback string) string {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}
	return value
}

func parseDuration(value string, fallback time.Duration) time.Duration {
	parsed, err := time.ParseDuration(value)
	if err != nil {
		return fallback
	}
	return parsed
}

func parseLogLevel(value string) slog.Level {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "debug":
		return slog.LevelDebug
	case "warn", "warning":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
}
