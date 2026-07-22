#ifndef RUNNER_DESKTOP_LYRICS_CHANNEL_H_
#define RUNNER_DESKTOP_LYRICS_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/method_result.h>

#include <memory>
#include <string>

#include "lyrics_overlay_window.h"

class DesktopLyricsChannel {
 public:
  explicit DesktopLyricsChannel(flutter::BinaryMessenger* messenger);
  ~DesktopLyricsChannel();

  DesktopLyricsChannel(const DesktopLyricsChannel&) = delete;
  DesktopLyricsChannel& operator=(const DesktopLyricsChannel&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  flutter::EncodableValue CreateCapability() const;
  flutter::EncodableValue CreateStatus(const std::string& state,
                                       const std::string& message) const;
  void ReturnError(
      const std::string& message,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  LyricsOverlayWindow overlay_;
  std::string state_ = "permissionGranted";
};

#endif
