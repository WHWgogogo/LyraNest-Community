package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"music-player-server/internal/auth"
	"music-player-server/internal/config"
	"music-player-server/internal/httpapi"
	"music-player-server/internal/library"
	"music-player-server/internal/store"
	"music-player-server/internal/userdata"
)

const defaultMusicBrainzUserAgent = "LyraNest Community/1.0.0 (+https://github.com/WHWgogogo/LyraNest-Community)"

func main() {
	if len(os.Args) > 1 && os.Args[1] == "healthcheck" {
		if err := runHealthcheck(); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		return
	}

	cfg := config.Load()
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: cfg.LogLevel,
	}))
	slog.SetDefault(logger)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	application, err := buildServer(ctx, cfg)
	if err != nil {
		logger.Error(
			"server initialization failed",
			"error", err,
			"library_dir", cfg.LibraryDir,
			"data_dir", cfg.DataDir,
		)
		os.Exit(1)
	}

	go func() {
		logger.Info(
			"server started",
			"addr", cfg.Addr,
			"library_dir", cfg.LibraryDir,
			"data_dir", cfg.DataDir,
			"tracks", application.trackCount,
		)
		if err := application.server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("server failed", "error", err)
			stop()
		}
	}()

	<-ctx.Done()
	logger.Info("shutdown signal received")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), cfg.ShutdownTimeout)
	defer cancel()
	if err := application.server.Shutdown(shutdownCtx); err != nil {
		logger.Error("graceful shutdown failed", "error", err)
		os.Exit(1)
	}
	logger.Info("server stopped")
}

type serverApplication struct {
	server     *http.Server
	trackCount int
}

func buildServer(ctx context.Context, cfg config.Config) (*serverApplication, error) {
	repository, err := store.NewJSONRepository(cfg.DataDir)
	if err != nil {
		return nil, fmt.Errorf("create JSON track repository: %w", err)
	}
	authSessionTTL := cfg.AuthSessionTTL
	if authSessionTTL <= 0 {
		authSessionTTL = 24 * time.Hour
	}
	authService, err := auth.NewService(cfg.DataDir, authSessionTTL)
	if err != nil {
		return nil, fmt.Errorf("create authentication service: %w", err)
	}
	userDataStore, err := userdata.NewStore(cfg.DataDir)
	if err != nil {
		return nil, fmt.Errorf("create user data store: %w", err)
	}

	lyrics := library.NewLyricsService()
	scanner := library.NewScanner(cfg.LibraryDir)
	libraryManagement := httpapi.NewLibraryManagementService(cfg.LibraryDir, scanner, repository)
	scanResult, err := libraryManagement.Scan(ctx)
	if err != nil {
		return nil, fmt.Errorf("scan music library: %w", err)
	}

	handler := httpapi.NewHandler(
		repository,
		lyrics,
		httpapi.WithAuthService(authService),
		httpapi.WithUserDataRepository(userDataStore),
		httpapi.WithLibraryManagementService(libraryManagement),
	)
	return &serverApplication{
		server: &http.Server{
			Addr:              cfg.Addr,
			Handler:           handler.Routes(),
			ReadHeaderTimeout: 5 * time.Second,
			ReadTimeout:       15 * time.Second,
			IdleTimeout:       60 * time.Second,
			MaxHeaderBytes:    1 << 20,
		},
		trackCount: scanResult.Total,
	}, nil
}

func runHealthcheck() error {
	client := &http.Client{Timeout: 3 * time.Second}
	response, err := client.Get("http://127.0.0.1:8080/healthz")
	if err != nil {
		return err
	}
	defer response.Body.Close()

	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("healthcheck returned status %d", response.StatusCode)
	}
	return nil
}
