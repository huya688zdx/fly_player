#ifndef RUNNER_SYSTEM_MEDIA_CONTROLS_H_
#define RUNNER_SYSTEM_MEDIA_CONTROLS_H_

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <winrt/Windows.Media.h>

#include <memory>

// 将系统媒体事件转发到 Flutter 所在的窗口线程。
class SystemMediaControls {
 public:
  static constexpr UINT kCommandMessage = WM_APP + 0x53;
  SystemMediaControls(HWND window, flutter::BinaryMessenger *messenger);
  ~SystemMediaControls();
  void HandleCommand(WPARAM command, LPARAM position);

 private:
  void EnsureInitialized();
  void Clear();

  HWND window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  winrt::Windows::Media::SystemMediaTransportControls controls_{nullptr};
  winrt::Windows::Media::SystemMediaTransportControls::ButtonPressed_revoker
      button_revoker_;
  winrt::Windows::Media::SystemMediaTransportControls::
      PlaybackPositionChangeRequested_revoker position_revoker_;
};

#endif
