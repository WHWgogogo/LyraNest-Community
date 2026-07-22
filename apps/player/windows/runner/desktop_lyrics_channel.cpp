#include "desktop_lyrics_channel.h"

#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <cmath>
#include <cstdint>
#include <limits>
#include <string>
#include <utility>

namespace {

constexpr char kChannelName[] =
    "com.harmonymusic.player/desktop_lyrics";

const flutter::EncodableMap* GetArgumentsMap(
    const flutter::MethodCall<flutter::EncodableValue>& call) {
  if (call.arguments() == nullptr) {
    return nullptr;
  }
  return std::get_if<flutter::EncodableMap>(call.arguments());
}

const flutter::EncodableValue* FindArgument(
    const flutter::EncodableMap& arguments,
    const char* key) {
  const auto iterator =
      arguments.find(flutter::EncodableValue(std::string(key)));
  return iterator == arguments.end() ? nullptr : &iterator->second;
}

bool ReadTextArgument(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::string* text) {
  const flutter::EncodableMap* arguments = GetArgumentsMap(call);
  if (arguments == nullptr) {
    return false;
  }
  const flutter::EncodableValue* value =
      FindArgument(*arguments, "text");
  if (value == nullptr) {
    return false;
  }
  const std::string* native_text = std::get_if<std::string>(value);
  if (native_text == nullptr) {
    return false;
  }
  *text = *native_text;
  return true;
}

bool ReadLockedArgument(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    bool* locked) {
  const flutter::EncodableMap* arguments = GetArgumentsMap(call);
  if (arguments == nullptr) {
    return false;
  }
  const flutter::EncodableValue* value =
      FindArgument(*arguments, "locked");
  if (value == nullptr) {
    return false;
  }
  const bool* native_locked = std::get_if<bool>(value);
  if (native_locked == nullptr) {
    return false;
  }
  *locked = *native_locked;
  return true;
}

bool ReadDoubleArgument(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    const char* key,
    double* output) {
  const flutter::EncodableMap* arguments = GetArgumentsMap(call);
  if (arguments == nullptr) {
    return false;
  }
  const flutter::EncodableValue* value = FindArgument(*arguments, key);
  if (value == nullptr) {
    return false;
  }
  if (const double* number = std::get_if<double>(value)) {
    *output = *number;
    return true;
  }
  return false;
}

bool ReadArgbArgument(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    uint32_t* color) {
  const flutter::EncodableMap* arguments = GetArgumentsMap(call);
  if (arguments == nullptr) {
    return false;
  }
  const flutter::EncodableValue* value = FindArgument(*arguments, "textColor");
  if (value == nullptr) {
    return false;
  }

  int64_t number = 0;
  if (const int32_t* native_number = std::get_if<int32_t>(value)) {
    number = *native_number;
  } else if (const int64_t* native_int64 = std::get_if<int64_t>(value)) {
    number = *native_int64;
  } else {
    return false;
  }

  if (number < 0 || number > 0xffffffffLL) {
    return false;
  }
  *color = static_cast<uint32_t>(number);
  return true;
}

bool ReadTextAlignmentArgument(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    LyricsTextAlignment* alignment) {
  const flutter::EncodableMap* arguments = GetArgumentsMap(call);
  if (arguments == nullptr) {
    return false;
  }
  const flutter::EncodableValue* value =
      FindArgument(*arguments, "textAlignment");
  if (value == nullptr) {
    return false;
  }
  const std::string* native_alignment = std::get_if<std::string>(value);
  if (native_alignment == nullptr) {
    return false;
  }

  if (*native_alignment == "left") {
    *alignment = LyricsTextAlignment::kLeft;
    return true;
  }
  if (*native_alignment == "center") {
    *alignment = LyricsTextAlignment::kCenter;
    return true;
  }
  if (*native_alignment == "right") {
    *alignment = LyricsTextAlignment::kRight;
    return true;
  }
  if (*native_alignment == "split") {
    *alignment = LyricsTextAlignment::kSplit;
    return true;
  }
  return false;
}

bool ReadBooleanArgument(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    const char* key,
    bool* output) {
  const flutter::EncodableMap* arguments = GetArgumentsMap(call);
  if (arguments == nullptr) {
    return false;
  }
  const flutter::EncodableValue* value = FindArgument(*arguments, key);
  if (value == nullptr) {
    return false;
  }
  const bool* native_value = std::get_if<bool>(value);
  if (native_value == nullptr) {
    return false;
  }
  *output = *native_value;
  return true;
}

bool Utf16FromUtf8(const std::string& utf8, std::wstring* utf16) {
  if (utf8.empty()) {
    utf16->clear();
    return true;
  }
  if (utf8.size() >
      static_cast<size_t>((std::numeric_limits<int>::max)())) {
    return false;
  }

  const int input_length = static_cast<int>(utf8.size());
  const int required_length =
      MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8.data(),
                          input_length, nullptr, 0);
  if (required_length == 0) {
    return false;
  }

  utf16->resize(required_length);
  const int converted_length =
      MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8.data(),
                          input_length, utf16->data(), required_length);
  return converted_length == required_length;
}

}

DesktopLyricsChannel::DesktopLyricsChannel(
    flutter::BinaryMessenger* messenger)
    : channel_(
          std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
              messenger, kChannelName,
              &flutter::StandardMethodCodec::GetInstance())) {
  channel_->SetMethodCallHandler(
      [this](
          const flutter::MethodCall<flutter::EncodableValue>& call,
          std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
              result) {
        HandleMethodCall(call, std::move(result));
      });
}

DesktopLyricsChannel::~DesktopLyricsChannel() {
  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
  }
  overlay_.Dispose();
}

void DesktopLyricsChannel::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();

  if (method == "getCapability") {
    result->Success(CreateCapability());
    return;
  }

  if (method == "getStatus") {
    result->Success(CreateStatus(
        state_, overlay_.IsAvailable()
                    ? "Windows lyrics overlay is ready."
                    : overlay_.GetLastError()));
    return;
  }

  if (method == "requestPermission") {
    if (!overlay_.IsAvailable()) {
      ReturnError(overlay_.GetLastError(), std::move(result));
      return;
    }
    state_ = "permissionGranted";
    result->Success(
        CreateStatus(state_, "Windows does not require overlay permission."));
    return;
  }

  if (method == "configure") {
    double background_opacity = 0.0;
    if (!ReadDoubleArgument(call, "backgroundOpacity", &background_opacity) ||
        !std::isfinite(background_opacity) || background_opacity < 0.0 ||
        background_opacity > 1.0) {
      ReturnError("The backgroundOpacity argument must be between 0 and 1.",
                  std::move(result));
      return;
    }

    uint32_t text_color = 0;
    if (!ReadArgbArgument(call, &text_color)) {
      ReturnError("The textColor argument must be a valid ARGB value.",
                  std::move(result));
      return;
    }

    double font_size = 0.0;
    if (!ReadDoubleArgument(call, "fontSize", &font_size) ||
        !std::isfinite(font_size) ||
        font_size < LyricsOverlayWindow::kMinimumFontSize ||
        font_size > LyricsOverlayWindow::kMaximumFontSize) {
      ReturnError("The fontSize argument must be between 14 and 36.",
                  std::move(result));
      return;
    }

    LyricsTextAlignment text_alignment = LyricsTextAlignment::kCenter;
    if (!ReadTextAlignmentArgument(call, &text_alignment)) {
      ReturnError(
          "The textAlignment argument must be left, center, right, or split.",
          std::move(result));
      return;
    }

    bool reset_position = false;
    if (!ReadBooleanArgument(call, "resetPosition", &reset_position)) {
      ReturnError("The resetPosition argument is missing or invalid.",
                  std::move(result));
      return;
    }

    if (!overlay_.Configure(background_opacity, text_color, font_size,
                            text_alignment, reset_position)) {
      ReturnError(overlay_.GetLastError(), std::move(result));
      return;
    }

    state_ = "updated";
    result->Success(CreateStatus(
        state_, "Windows desktop lyrics configuration was updated."));
    return;
  }

  if (method == "show" || method == "update") {
    std::string utf8_text;
    if (!ReadTextArgument(call, &utf8_text)) {
      ReturnError("The lyrics text argument is missing or invalid.",
                  std::move(result));
      return;
    }

    std::wstring utf16_text;
    if (!Utf16FromUtf8(utf8_text, &utf16_text)) {
      ReturnError("The lyrics text is not valid UTF-8.", std::move(result));
      return;
    }

    const bool succeeded =
        method == "show" ? overlay_.ShowText(utf16_text)
                         : overlay_.UpdateText(utf16_text);
    if (!succeeded) {
      ReturnError(overlay_.GetLastError(), std::move(result));
      return;
    }

    state_ = method == "show" ? "visible" : "updated";
    result->Success(CreateStatus(
        state_, method == "show" ? "Lyrics overlay shown."
                                  : "Lyrics overlay updated."));
    return;
  }

  if (method == "hide") {
    overlay_.Hide();
    state_ = "hidden";
    result->Success(CreateStatus(state_, "Lyrics overlay hidden."));
    return;
  }

  if (method == "dispose") {
    overlay_.Dispose();
    state_ = "disposed";
    result->Success(
        CreateStatus(state_, "Lyrics overlay resources released."));
    return;
  }

  if (method == "setLocked") {
    bool locked = false;
    if (!ReadLockedArgument(call, &locked)) {
      ReturnError("The locked argument is missing or invalid.",
                  std::move(result));
      return;
    }
    overlay_.SetLocked(locked);
    result->Success(CreateStatus(
        state_, locked ? "Lyrics overlay locked with click-through enabled."
                       : "Lyrics overlay unlocked and draggable."));
    return;
  }

  result->NotImplemented();
}

flutter::EncodableValue DesktopLyricsChannel::CreateCapability() const {
  const bool available = overlay_.IsAvailable();
  flutter::EncodableMap capability;
  capability[flutter::EncodableValue("platform")] =
      flutter::EncodableValue("windows");
  capability[flutter::EncodableValue("supportsSystemOverlay")] =
      flutter::EncodableValue(available);
  capability[flutter::EncodableValue("supportsTransparentWindow")] =
      flutter::EncodableValue(available);
  capability[flutter::EncodableValue("supportsClickThrough")] =
      flutter::EncodableValue(available);
  capability[flutter::EncodableValue("supportsLockPosition")] =
      flutter::EncodableValue(available);
  capability[flutter::EncodableValue("requiresRuntimePermission")] =
      flutter::EncodableValue(false);
  capability[flutter::EncodableValue("supportsDrag")] =
      flutter::EncodableValue(available);
  capability[flutter::EncodableValue("isLocked")] =
      flutter::EncodableValue(overlay_.IsLocked());
  capability[flutter::EncodableValue("notes")] = flutter::EncodableValue(
      available
          ? "Native transparent topmost Win32 lyrics window is available. "
            "Drag to move; locking and click-through are available through "
            "the native setLocked channel extension."
          : overlay_.GetLastError());
  return flutter::EncodableValue(capability);
}

flutter::EncodableValue DesktopLyricsChannel::CreateStatus(
    const std::string& state,
    const std::string& message) const {
  flutter::EncodableMap status;
  status[flutter::EncodableValue("platform")] =
      flutter::EncodableValue("windows");
  status[flutter::EncodableValue("state")] =
      flutter::EncodableValue(state);
  status[flutter::EncodableValue("canDrawOverlays")] =
      flutter::EncodableValue(overlay_.IsAvailable());
  status[flutter::EncodableValue("isVisible")] =
      flutter::EncodableValue(overlay_.IsVisible());
  status[flutter::EncodableValue("isLocked")] =
      flutter::EncodableValue(overlay_.IsLocked());
  status[flutter::EncodableValue("message")] =
      flutter::EncodableValue(message);
  return flutter::EncodableValue(status);
}

void DesktopLyricsChannel::ReturnError(
    const std::string& message,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  state_ = "error";
  result->Success(CreateStatus(
      state_, message.empty() ? "Unknown Windows lyrics overlay error."
                              : message));
}
