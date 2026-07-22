#ifndef RUNNER_LYRICS_OVERLAY_WINDOW_H_
#define RUNNER_LYRICS_OVERLAY_WINDOW_H_

#include <windows.h>

#include <cstdint>
#include <string>

enum class LyricsTextAlignment {
  kLeft,
  kCenter,
  kRight,
  kSplit,
};

class LyricsOverlayWindow {
 public:
  static constexpr double kMinimumFontSize = 14.0;
  static constexpr double kMaximumFontSize = 36.0;

  LyricsOverlayWindow();
  ~LyricsOverlayWindow();

  LyricsOverlayWindow(const LyricsOverlayWindow&) = delete;
  LyricsOverlayWindow& operator=(const LyricsOverlayWindow&) = delete;

  bool IsAvailable() const;
  bool IsVisible() const;
  bool IsLocked() const;
  const std::string& GetLastError() const;

  bool ShowText(const std::wstring& text);
  bool UpdateText(const std::wstring& text);
  bool Configure(double background_opacity,
                 uint32_t text_color,
                 double font_size,
                 LyricsTextAlignment text_alignment,
                 bool reset_position);
  void Hide();
  void Dispose();
  void SetLocked(bool locked);

  static LRESULT CALLBACK WindowProc(HWND window,
                                     UINT message,
                                     WPARAM wparam,
                                     LPARAM lparam);

 private:
  LRESULT HandleMessage(HWND window,
                        UINT message,
                        WPARAM wparam,
                        LPARAM lparam);
  bool EnsureCreated();
  bool Render();
  bool ResetPosition();
  void UpdateClickThroughStyle();
  void SetLastError(const std::string& message);
  void SetLastWindowsError(const std::string& operation);

  HWND window_ = nullptr;
  ULONG_PTR gdiplus_token_ = 0;
  std::wstring text_;
  std::string last_error_;
  int content_width_ = 0;
  double background_opacity_ = 0.35;
  uint32_t text_color_ = 0xffffffff;
  double font_size_ = 22.0;
  LyricsTextAlignment text_alignment_ = LyricsTextAlignment::kCenter;
  bool visible_ = false;
  bool locked_ = false;
};

#endif
