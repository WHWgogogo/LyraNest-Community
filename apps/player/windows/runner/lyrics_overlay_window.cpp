#include "lyrics_overlay_window.h"

#include <gdiplus.h>

#include <algorithm>
#include <cmath>
#include <limits>
#include <memory>
#include <string>
#include <utility>

#include "utils.h"

namespace {

constexpr wchar_t kLyricsOverlayWindowClass[] =
    L"HARMONY_MUSIC_LYRICS_OVERLAY_WINDOW";
constexpr int kBaseWindowWidth = 960;
constexpr int kBaseWindowHeight = 104;
constexpr int kBaseMaximumHeight = 220;
constexpr int kMaximumLyricsLines = 2;
constexpr int kBaseHorizontalPadding = 30;
constexpr int kBaseVerticalPadding = 18;
constexpr int kBaseBottomMargin = 92;
constexpr Gdiplus::REAL kOutlineReferenceFontSize = 36.0f;
constexpr Gdiplus::REAL kBaseOutlineWidth = 5.0f;
constexpr Gdiplus::REAL kBaseBackgroundCornerRadius = 24.0f;

ATOM g_window_class = 0;

bool RegisterLyricsOverlayWindowClass() {
  if (g_window_class != 0) {
    return true;
  }

  WNDCLASSEXW window_class{};
  window_class.cbSize = sizeof(window_class);
  window_class.style = CS_HREDRAW | CS_VREDRAW;
  window_class.lpfnWndProc = LyricsOverlayWindow::WindowProc;
  window_class.hInstance = GetModuleHandleW(nullptr);
  window_class.hCursor = LoadCursorW(nullptr, IDC_SIZEALL);
  window_class.hbrBackground = nullptr;
  window_class.lpszClassName = kLyricsOverlayWindowClass;

  g_window_class = RegisterClassExW(&window_class);
  if (g_window_class != 0) {
    return true;
  }

  return GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}

UINT GetWindowDpi(HWND window) {
  const UINT dpi = GetDpiForWindow(window);
  return dpi == 0 ? 96 : dpi;
}

int ScaleForDpi(int value, UINT dpi) {
  return MulDiv(value, static_cast<int>(dpi), 96);
}

std::string GetWindowsErrorMessage(const std::string& operation,
                                   DWORD error_code) {
  wchar_t* message_buffer = nullptr;
  const DWORD length = FormatMessageW(
      FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
          FORMAT_MESSAGE_IGNORE_INSERTS,
      nullptr, error_code, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
      reinterpret_cast<wchar_t*>(&message_buffer), 0, nullptr);

  std::wstring message;
  if (length != 0 && message_buffer != nullptr) {
    message.assign(message_buffer, length);
    while (!message.empty() &&
           (message.back() == L'\r' || message.back() == L'\n' ||
            message.back() == L' ')) {
      message.pop_back();
    }
  }
  if (message_buffer != nullptr) {
    LocalFree(message_buffer);
  }

  std::string result = operation + " failed";
  if (!message.empty()) {
    result += ": " + Utf8FromUtf16(message.c_str());
  } else {
    result += " with Windows error " + std::to_string(error_code);
  }
  return result;
}

const Gdiplus::FontFamily* SelectFontFamily(
    const Gdiplus::FontFamily& preferred,
    const Gdiplus::FontFamily& fallback) {
  if (preferred.IsAvailable()) {
    return &preferred;
  }
  if (fallback.IsAvailable()) {
    return &fallback;
  }
  return Gdiplus::FontFamily::GenericSansSerif();
}

Gdiplus::StringAlignment ToGdiplusAlignment(
    LyricsTextAlignment alignment) {
  switch (alignment) {
    case LyricsTextAlignment::kLeft:
      return Gdiplus::StringAlignmentNear;
    case LyricsTextAlignment::kCenter:
      return Gdiplus::StringAlignmentCenter;
    case LyricsTextAlignment::kRight:
      return Gdiplus::StringAlignmentFar;
    case LyricsTextAlignment::kSplit:
      return Gdiplus::StringAlignmentNear;
  }
  return Gdiplus::StringAlignmentCenter;
}

struct SplitLyricsText {
  std::wstring current_line;
  std::wstring next_line;
};

void RemoveTrailingCarriageReturn(std::wstring* line) {
  if (!line->empty() && line->back() == L'\r') {
    line->pop_back();
  }
}

SplitLyricsText SplitCurrentAndNextLyrics(const std::wstring& text) {
  const std::wstring::size_type first_line_break = text.find(L'\n');
  if (first_line_break == std::wstring::npos) {
    return {text, L""};
  }

  std::wstring current_line = text.substr(0, first_line_break);
  const std::wstring::size_type next_line_start = first_line_break + 1;
  const std::wstring::size_type next_line_break =
      text.find(L'\n', next_line_start);
  std::wstring next_line = text.substr(
      next_line_start,
      next_line_break == std::wstring::npos
          ? std::wstring::npos
          : next_line_break - next_line_start);
  RemoveTrailingCarriageReturn(&current_line);
  RemoveTrailingCarriageReturn(&next_line);
  return {std::move(current_line), std::move(next_line)};
}

void ConfigureTextFormat(Gdiplus::StringFormat* text_format,
                         Gdiplus::StringAlignment alignment,
                         bool single_line) {
  text_format->SetAlignment(alignment);
  text_format->SetLineAlignment(Gdiplus::StringAlignmentNear);
  text_format->SetTrimming(Gdiplus::StringTrimmingEllipsisCharacter);
  if (single_line) {
    text_format->SetFormatFlags(
        text_format->GetFormatFlags() | Gdiplus::StringFormatFlagsNoWrap);
  }
}

BYTE OpacityToAlpha(double opacity) {
  return static_cast<BYTE>(
      std::lround((std::clamp)(opacity, 0.0, 1.0) * 255.0));
}

Gdiplus::Color ColorFromArgb(uint32_t color) {
  return Gdiplus::Color(static_cast<BYTE>((color >> 24) & 0xff),
                        static_cast<BYTE>((color >> 16) & 0xff),
                        static_cast<BYTE>((color >> 8) & 0xff),
                        static_cast<BYTE>(color & 0xff));
}

void AddRoundedRectangle(Gdiplus::GraphicsPath* path,
                         const Gdiplus::RectF& bounds,
                         Gdiplus::REAL corner_radius) {
  if (corner_radius <= 0.0f) {
    path->AddRectangle(bounds);
    return;
  }

  const Gdiplus::REAL diameter = corner_radius * 2.0f;
  path->AddArc(bounds.X, bounds.Y, diameter, diameter, 180.0f, 90.0f);
  path->AddArc(bounds.GetRight() - diameter, bounds.Y, diameter, diameter,
               270.0f, 90.0f);
  path->AddArc(bounds.GetRight() - diameter, bounds.GetBottom() - diameter,
               diameter, diameter, 0.0f, 90.0f);
  path->AddArc(bounds.X, bounds.GetBottom() - diameter, diameter, diameter,
               90.0f, 90.0f);
  path->CloseFigure();
}

POINT GetDefaultOverlayPosition(const RECT& work_area,
                                int width,
                                int height,
                                UINT dpi) {
  const int work_width = work_area.right - work_area.left;
  return {
      work_area.left + (work_width - width) / 2,
      work_area.bottom - height - ScaleForDpi(kBaseBottomMargin, dpi),
  };
}

}

LyricsOverlayWindow::LyricsOverlayWindow() {
  Gdiplus::GdiplusStartupInput startup_input;
  const Gdiplus::Status status =
      Gdiplus::GdiplusStartup(&gdiplus_token_, &startup_input, nullptr);
  if (status != Gdiplus::Ok) {
    gdiplus_token_ = 0;
    SetLastError("GDI+ initialization failed.");
  }
}

LyricsOverlayWindow::~LyricsOverlayWindow() {
  Dispose();
  if (gdiplus_token_ != 0) {
    Gdiplus::GdiplusShutdown(gdiplus_token_);
    gdiplus_token_ = 0;
  }
}

bool LyricsOverlayWindow::IsAvailable() const {
  return gdiplus_token_ != 0;
}

bool LyricsOverlayWindow::IsVisible() const {
  return visible_ && window_ != nullptr && IsWindowVisible(window_) != FALSE;
}

bool LyricsOverlayWindow::IsLocked() const {
  return locked_;
}

const std::string& LyricsOverlayWindow::GetLastError() const {
  return last_error_;
}

bool LyricsOverlayWindow::ShowText(const std::wstring& text) {
  if (!EnsureCreated()) {
    return false;
  }

  text_ = text;
  if (!Render()) {
    return false;
  }

  SetWindowPos(window_, HWND_TOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE |
                   SWP_SHOWWINDOW);
  visible_ = true;
  return true;
}

bool LyricsOverlayWindow::UpdateText(const std::wstring& text) {
  if (!EnsureCreated()) {
    return false;
  }

  text_ = text;
  return Render();
}

bool LyricsOverlayWindow::Configure(double background_opacity,
                                     uint32_t text_color,
                                     double font_size,
                                     LyricsTextAlignment text_alignment,
                                     bool reset_position) {
  if (!std::isfinite(background_opacity) || background_opacity < 0.0 ||
      background_opacity > 1.0 || !std::isfinite(font_size) ||
      font_size < kMinimumFontSize || font_size > kMaximumFontSize) {
    SetLastError("The lyrics overlay configuration is invalid.");
    return false;
  }

  background_opacity_ = background_opacity;
  text_color_ = text_color;
  font_size_ = font_size;
  text_alignment_ = text_alignment;
  if (window_ != nullptr && !Render()) {
    return false;
  }
  return !reset_position || window_ == nullptr || ResetPosition();
}

void LyricsOverlayWindow::Hide() {
  if (window_ != nullptr) {
    ShowWindow(window_, SW_HIDE);
  }
  visible_ = false;
}

void LyricsOverlayWindow::Dispose() {
  visible_ = false;
  if (window_ != nullptr) {
    const HWND window = window_;
    window_ = nullptr;
    SetWindowLongPtrW(window, GWLP_USERDATA, 0);
    DestroyWindow(window);
  }
  text_.clear();
  content_width_ = 0;
}

void LyricsOverlayWindow::SetLocked(bool locked) {
  locked_ = locked;
  UpdateClickThroughStyle();
}

LRESULT CALLBACK LyricsOverlayWindow::WindowProc(HWND window,
                                                 UINT message,
                                                 WPARAM wparam,
                                                 LPARAM lparam) {
  LyricsOverlayWindow* overlay = reinterpret_cast<LyricsOverlayWindow*>(
      GetWindowLongPtrW(window, GWLP_USERDATA));

  if (message == WM_NCCREATE) {
    const auto* create_struct =
        reinterpret_cast<const CREATESTRUCTW*>(lparam);
    overlay =
        static_cast<LyricsOverlayWindow*>(create_struct->lpCreateParams);
    SetWindowLongPtrW(window, GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(overlay));
  }

  if (overlay != nullptr) {
    return overlay->HandleMessage(window, message, wparam, lparam);
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

LRESULT LyricsOverlayWindow::HandleMessage(HWND window,
                                           UINT message,
                                           WPARAM wparam,
                                           LPARAM lparam) {
  switch (message) {
    case WM_NCHITTEST:
      return locked_ ? HTTRANSPARENT : HTCAPTION;
    case WM_MOUSEACTIVATE:
      return MA_NOACTIVATE;
    case WM_SETCURSOR:
      if (!locked_) {
        SetCursor(LoadCursorW(nullptr, IDC_SIZEALL));
        return TRUE;
      }
      break;
    case WM_DPICHANGED: {
      const auto* suggested_rect = reinterpret_cast<const RECT*>(lparam);
      SetWindowPos(window, HWND_TOPMOST, suggested_rect->left,
                   suggested_rect->top,
                   suggested_rect->right - suggested_rect->left,
                   suggested_rect->bottom - suggested_rect->top,
                   SWP_NOACTIVATE);
      content_width_ = static_cast<int>((std::max)(
          1L, suggested_rect->right - suggested_rect->left));
      Render();
      return 0;
    }
    case WM_DISPLAYCHANGE:
      Render();
      return 0;
    case WM_NCDESTROY:
      SetWindowLongPtrW(window, GWLP_USERDATA, 0);
      if (window_ == window) {
        window_ = nullptr;
        visible_ = false;
      }
      break;
    default:
      break;
  }

  return DefWindowProcW(window, message, wparam, lparam);
}

bool LyricsOverlayWindow::EnsureCreated() {
  if (window_ != nullptr) {
    return true;
  }
  if (!IsAvailable()) {
    if (last_error_.empty()) {
      SetLastError("The native lyrics renderer is unavailable.");
    }
    return false;
  }
  if (!RegisterLyricsOverlayWindowClass()) {
    SetLastWindowsError("RegisterClassExW");
    return false;
  }

  POINT cursor_position{};
  GetCursorPos(&cursor_position);
  const HMONITOR monitor =
      MonitorFromPoint(cursor_position, MONITOR_DEFAULTTONEAREST);
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(monitor_info);
  if (GetMonitorInfoW(monitor, &monitor_info) == FALSE) {
    SetLastWindowsError("GetMonitorInfoW");
    return false;
  }

  HDC screen_dc = GetDC(nullptr);
  const UINT initial_dpi =
      screen_dc == nullptr
          ? 96
          : static_cast<UINT>(GetDeviceCaps(screen_dc, LOGPIXELSX));
  if (screen_dc != nullptr) {
    ReleaseDC(nullptr, screen_dc);
  }

  const int work_width =
      monitor_info.rcWork.right - monitor_info.rcWork.left;
  const int width =
      (std::min)(ScaleForDpi(kBaseWindowWidth, initial_dpi),
                 (std::max)(1, work_width - ScaleForDpi(32, initial_dpi)));
  const int height = ScaleForDpi(kBaseWindowHeight, initial_dpi);
  const POINT position = GetDefaultOverlayPosition(
      monitor_info.rcWork, width, height, initial_dpi);

  const DWORD extended_style =
      WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE |
      (locked_ ? WS_EX_TRANSPARENT : 0);
  window_ = CreateWindowExW(
      extended_style, kLyricsOverlayWindowClass, L"LyraNest Lyrics",
      WS_POPUP, position.x, position.y, width, height, nullptr, nullptr,
      GetModuleHandleW(nullptr), this);
  if (window_ == nullptr) {
    SetLastWindowsError("CreateWindowExW");
    return false;
  }

  content_width_ = width;
  last_error_.clear();
  return true;
}

bool LyricsOverlayWindow::ResetPosition() {
  if (window_ == nullptr) {
    return true;
  }

  RECT current_rect{};
  if (GetWindowRect(window_, &current_rect) == FALSE) {
    SetLastWindowsError("GetWindowRect");
    return false;
  }

  POINT cursor_position{};
  if (GetCursorPos(&cursor_position) == FALSE) {
    SetLastWindowsError("GetCursorPos");
    return false;
  }
  const HMONITOR monitor =
      MonitorFromPoint(cursor_position, MONITOR_DEFAULTTONEAREST);
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(monitor_info);
  if (GetMonitorInfoW(monitor, &monitor_info) == FALSE) {
    SetLastWindowsError("GetMonitorInfoW");
    return false;
  }

  const POINT position = GetDefaultOverlayPosition(
      monitor_info.rcWork, current_rect.right - current_rect.left,
      current_rect.bottom - current_rect.top, GetWindowDpi(window_));
  if (SetWindowPos(window_, HWND_TOPMOST, position.x, position.y, 0, 0,
                   SWP_NOSIZE | SWP_NOACTIVATE) == FALSE) {
    SetLastWindowsError("SetWindowPos");
    return false;
  }
  return true;
}

bool LyricsOverlayWindow::Render() {
  if (window_ == nullptr) {
    SetLastError("The lyrics overlay window has not been created.");
    return false;
  }

  RECT current_rect{};
  if (GetWindowRect(window_, &current_rect) == FALSE) {
    SetLastWindowsError("GetWindowRect");
    return false;
  }

  const UINT dpi = GetWindowDpi(window_);
  const int width = (std::max)(1, content_width_);
  const int horizontal_padding =
      ScaleForDpi(kBaseHorizontalPadding, dpi);
  const int vertical_padding = ScaleForDpi(kBaseVerticalPadding, dpi);
  const Gdiplus::REAL font_size =
      static_cast<Gdiplus::REAL>(font_size_) *
      static_cast<Gdiplus::REAL>(dpi) / 96.0f;
  const Gdiplus::REAL outline_width = (std::max)(
      1.0f, kBaseOutlineWidth * font_size / kOutlineReferenceFontSize);
  const int two_line_height = static_cast<int>(std::ceil(
      font_size * 1.45f * static_cast<Gdiplus::REAL>(kMaximumLyricsLines))) +
                              vertical_padding * 2 +
                              static_cast<int>(std::ceil(outline_width * 2));
  const int minimum_height = (std::max)(
      ScaleForDpi(kBaseWindowHeight, dpi), two_line_height);
  const int maximum_height = (std::max)(
      ScaleForDpi(kBaseMaximumHeight, dpi), minimum_height);

  Gdiplus::FontFamily preferred_font(L"Microsoft YaHei UI");
  Gdiplus::FontFamily fallback_font(L"Segoe UI");
  const Gdiplus::FontFamily* font_family =
      SelectFontFamily(preferred_font, fallback_font);

  const int text_width = (std::max)(1, width - horizontal_padding * 2);
  const int text_height =
      (std::max)(1, maximum_height - vertical_padding * 2);
  const Gdiplus::RectF layout_rect(
      static_cast<Gdiplus::REAL>(horizontal_padding),
      static_cast<Gdiplus::REAL>(vertical_padding),
      static_cast<Gdiplus::REAL>(text_width),
      static_cast<Gdiplus::REAL>(text_height));

  Gdiplus::GraphicsPath current_text_path;
  Gdiplus::GraphicsPath next_text_path;
  bool has_current_text_path = false;
  bool has_next_text_path = false;
  const auto add_text_path =
      [font_family, font_size](Gdiplus::GraphicsPath* text_path,
                               const std::wstring& text,
                               const Gdiplus::RectF& text_layout,
                               const Gdiplus::StringFormat& text_format) {
        return text.empty()
                   ? Gdiplus::Ok
                   : text_path->AddString(
                         text.c_str(), -1, font_family,
                         Gdiplus::FontStyleBold, font_size, text_layout,
                         &text_format);
      };

  if (text_alignment_ == LyricsTextAlignment::kSplit) {
    const SplitLyricsText split_text = SplitCurrentAndNextLyrics(text_);
    const Gdiplus::REAL split_line_height = font_size * 1.45f;
    const Gdiplus::RectF current_line_layout(
        layout_rect.X, layout_rect.Y, layout_rect.Width, split_line_height);
    const Gdiplus::RectF next_line_layout(
        layout_rect.X, layout_rect.Y + split_line_height, layout_rect.Width,
        split_line_height);
    Gdiplus::StringFormat current_line_format;
    ConfigureTextFormat(&current_line_format, Gdiplus::StringAlignmentNear,
                        true);
    Gdiplus::StringFormat next_line_format;
    ConfigureTextFormat(&next_line_format, Gdiplus::StringAlignmentFar,
                        true);
    const Gdiplus::Status current_path_status = add_text_path(
        &current_text_path, split_text.current_line, current_line_layout,
        current_line_format);
    if (current_path_status != Gdiplus::Ok) {
      SetLastError("GDI+ could not create the current lyrics text path.");
      return false;
    }
    has_current_text_path = !split_text.current_line.empty();
    const Gdiplus::Status next_path_status =
        add_text_path(&next_text_path, split_text.next_line, next_line_layout,
                      next_line_format);
    if (next_path_status != Gdiplus::Ok) {
      SetLastError("GDI+ could not create the next lyrics text path.");
      return false;
    }
    has_next_text_path = !split_text.next_line.empty();
  } else if (!text_.empty()) {
    Gdiplus::StringFormat text_format;
    ConfigureTextFormat(&text_format, ToGdiplusAlignment(text_alignment_),
                        false);
    const Gdiplus::Status path_status = add_text_path(
        &current_text_path, text_, layout_rect, text_format);
    if (path_status != Gdiplus::Ok) {
      SetLastError("GDI+ could not create the lyrics text path.");
      return false;
    }
    has_current_text_path = true;
  }

  Gdiplus::RectF text_bounds;
  bool has_text_path = false;
  const auto include_text_bounds =
      [&text_bounds, &has_text_path](const Gdiplus::GraphicsPath& text_path,
                                     bool has_path) {
        if (!has_path) {
          return;
        }
        Gdiplus::RectF path_bounds;
        text_path.GetBounds(&path_bounds);
        if (!has_text_path) {
          text_bounds = path_bounds;
          has_text_path = true;
          return;
        }
        const Gdiplus::REAL left =
            (std::min)(text_bounds.GetLeft(), path_bounds.GetLeft());
        const Gdiplus::REAL top =
            (std::min)(text_bounds.GetTop(), path_bounds.GetTop());
        const Gdiplus::REAL right =
            (std::max)(text_bounds.GetRight(), path_bounds.GetRight());
        const Gdiplus::REAL bottom =
            (std::max)(text_bounds.GetBottom(), path_bounds.GetBottom());
        text_bounds = Gdiplus::RectF(left, top, right - left, bottom - top);
      };
  include_text_bounds(current_text_path, has_current_text_path);
  include_text_bounds(next_text_path, has_next_text_path);
  const int measured_height =
      static_cast<int>(std::ceil(text_bounds.GetBottom())) + vertical_padding;
  const int height =
      (std::clamp)(measured_height, minimum_height, maximum_height);
  Gdiplus::RectF background_bounds;
  if (has_text_path) {
    const Gdiplus::REAL left = (std::max)(
        0.0f, text_bounds.GetLeft() - static_cast<Gdiplus::REAL>(
                                         horizontal_padding));
    const Gdiplus::REAL top = (std::max)(
        0.0f, text_bounds.GetTop() - static_cast<Gdiplus::REAL>(
                                        vertical_padding));
    const Gdiplus::REAL right = (std::min)(
        static_cast<Gdiplus::REAL>(width),
        text_bounds.GetRight() + static_cast<Gdiplus::REAL>(
                                    horizontal_padding));
    const Gdiplus::REAL bottom = (std::min)(
        static_cast<Gdiplus::REAL>(height),
        text_bounds.GetBottom() + static_cast<Gdiplus::REAL>(
                                     vertical_padding));
    background_bounds =
        Gdiplus::RectF(left, top, right - left, bottom - top);
  }

  HDC screen_dc = GetDC(nullptr);
  if (screen_dc == nullptr) {
    SetLastWindowsError("GetDC");
    return false;
  }

  HDC memory_dc = CreateCompatibleDC(screen_dc);
  if (memory_dc == nullptr) {
    const DWORD error = ::GetLastError();
    ReleaseDC(nullptr, screen_dc);
    SetLastError(GetWindowsErrorMessage("CreateCompatibleDC", error));
    return false;
  }

  BITMAPINFO bitmap_info{};
  bitmap_info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bitmap_info.bmiHeader.biWidth = width;
  bitmap_info.bmiHeader.biHeight = -height;
  bitmap_info.bmiHeader.biPlanes = 1;
  bitmap_info.bmiHeader.biBitCount = 32;
  bitmap_info.bmiHeader.biCompression = BI_RGB;

  void* bitmap_bits = nullptr;
  HBITMAP bitmap = CreateDIBSection(memory_dc, &bitmap_info, DIB_RGB_COLORS,
                                    &bitmap_bits, nullptr, 0);
  if (bitmap == nullptr || bitmap_bits == nullptr) {
    const DWORD error = ::GetLastError();
    DeleteDC(memory_dc);
    ReleaseDC(nullptr, screen_dc);
    SetLastError(GetWindowsErrorMessage("CreateDIBSection", error));
    return false;
  }

  HGDIOBJ previous_bitmap = SelectObject(memory_dc, bitmap);
  const int stride = width * 4;
  {
    Gdiplus::Bitmap surface(width, height, stride,
                            PixelFormat32bppPARGB,
                            static_cast<BYTE*>(bitmap_bits));
    Gdiplus::Graphics graphics(&surface);
    graphics.SetCompositingMode(Gdiplus::CompositingModeSourceCopy);
    graphics.Clear(Gdiplus::Color(0, 0, 0, 0));
    graphics.SetCompositingMode(Gdiplus::CompositingModeSourceOver);
    graphics.SetCompositingQuality(Gdiplus::CompositingQualityHighQuality);
    graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    graphics.SetPixelOffsetMode(Gdiplus::PixelOffsetModeHighQuality);
    graphics.SetTextRenderingHint(
        Gdiplus::TextRenderingHintAntiAliasGridFit);

    if (has_text_path) {
      const Gdiplus::REAL corner_radius = (std::min)(
          kBaseBackgroundCornerRadius * static_cast<Gdiplus::REAL>(dpi) /
              96.0f,
          (std::min)(background_bounds.Width / 2.0f,
                     background_bounds.Height / 2.0f));
      if (background_opacity_ > 0.0) {
        Gdiplus::GraphicsPath background_path;
        AddRoundedRectangle(&background_path, background_bounds,
                            corner_radius);
        Gdiplus::SolidBrush background_brush(
            Gdiplus::Color(OpacityToAlpha(background_opacity_), 0, 0, 0));
        graphics.FillPath(&background_brush, &background_path);
      }

      const BYTE text_alpha = static_cast<BYTE>((text_color_ >> 24) & 0xff);
      const BYTE outline_alpha =
          static_cast<BYTE>(static_cast<unsigned int>(text_alpha) * 224 / 255);
      Gdiplus::Pen outline_pen(Gdiplus::Color(outline_alpha, 0, 0, 0),
                               outline_width);
      outline_pen.SetLineJoin(Gdiplus::LineJoinRound);
      Gdiplus::SolidBrush text_brush(ColorFromArgb(text_color_));
      if (has_current_text_path) {
        graphics.DrawPath(&outline_pen, &current_text_path);
        graphics.FillPath(&text_brush, &current_text_path);
      }
      if (has_next_text_path) {
        graphics.DrawPath(&outline_pen, &next_text_path);
        graphics.FillPath(&text_brush, &next_text_path);
      }
    }
  }

  POINT destination = {current_rect.left, current_rect.top};
  SIZE size = {width, height};
  POINT source = {0, 0};
  BLENDFUNCTION blend{};
  blend.BlendOp = AC_SRC_OVER;
  blend.SourceConstantAlpha = 255;
  blend.AlphaFormat = AC_SRC_ALPHA;

  const BOOL updated =
      UpdateLayeredWindow(window_, screen_dc, &destination, &size, memory_dc,
                          &source, 0, &blend, ULW_ALPHA);
  const DWORD update_error =
      updated == FALSE ? ::GetLastError() : ERROR_SUCCESS;

  SelectObject(memory_dc, previous_bitmap);
  DeleteObject(bitmap);
  DeleteDC(memory_dc);
  ReleaseDC(nullptr, screen_dc);

  if (updated == FALSE) {
    SetLastError(
        GetWindowsErrorMessage("UpdateLayeredWindow", update_error));
    return false;
  }

  last_error_.clear();
  return true;
}

void LyricsOverlayWindow::UpdateClickThroughStyle() {
  if (window_ == nullptr) {
    return;
  }

  LONG_PTR extended_style = GetWindowLongPtrW(window_, GWL_EXSTYLE);
  if (locked_) {
    extended_style |= WS_EX_TRANSPARENT;
  } else {
    extended_style &= ~static_cast<LONG_PTR>(WS_EX_TRANSPARENT);
  }
  SetWindowLongPtrW(window_, GWL_EXSTYLE, extended_style);
  SetWindowPos(window_, HWND_TOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE |
                   SWP_FRAMECHANGED);
}

void LyricsOverlayWindow::SetLastError(const std::string& message) {
  last_error_ = message;
}

void LyricsOverlayWindow::SetLastWindowsError(
    const std::string& operation) {
  SetLastError(GetWindowsErrorMessage(operation, ::GetLastError()));
}
