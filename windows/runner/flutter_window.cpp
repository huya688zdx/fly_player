#include "flutter_window.h"

#include <optional>
#include <vector>

#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

namespace {

// GDI 的整数频率会把 59.94 Hz 截断为 59，显示同步必须使用当前模式的分数。
std::optional<double> GetWindowRefreshRate(HWND window) {
  MONITORINFOEXW monitor = {};
  monitor.cbSize = sizeof(monitor);
  if (!GetMonitorInfoW(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST),
                       &monitor)) {
    return std::nullopt;
  }

  std::vector<DISPLAYCONFIG_PATH_INFO> paths;
  std::vector<DISPLAYCONFIG_MODE_INFO> modes;
  LONG status;
  do {
    UINT32 path_count = 0;
    UINT32 mode_count = 0;
    status = GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, &path_count,
                                        &mode_count);
    if (status != ERROR_SUCCESS) {
      return std::nullopt;
    }
    paths.resize(path_count);
    modes.resize(mode_count);
    status = QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, &path_count, paths.data(),
                                &mode_count, modes.data(), nullptr);
    paths.resize(path_count);
  } while (status == ERROR_INSUFFICIENT_BUFFER);
  if (status != ERROR_SUCCESS) {
    return std::nullopt;
  }

  for (const auto& path : paths) {
    DISPLAYCONFIG_SOURCE_DEVICE_NAME source = {};
    source.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME;
    source.header.size = sizeof(source);
    source.header.adapterId = path.sourceInfo.adapterId;
    source.header.id = path.sourceInfo.id;
    if (DisplayConfigGetDeviceInfo(&source.header) != ERROR_SUCCESS ||
        wcscmp(source.viewGdiDeviceName, monitor.szDevice) != 0) {
      continue;
    }
    const auto rate = path.targetInfo.refreshRate;
    if (rate.Denominator != 0 && rate.Numerator > rate.Denominator) {
      return static_cast<double>(rate.Numerator) / rate.Denominator;
    }
  }
  return std::nullopt;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  desktop_danmaku_segmenter_ = std::make_unique<DesktopDanmakuSegmenter>(
      flutter_controller_->engine()->messenger());
  potplayer_bridge_ = std::make_unique<PotPlayerBridge>(
      flutter_controller_->engine()->messenger());
  system_media_controls_ = std::make_unique<SystemMediaControls>(
      GetHandle(), flutter_controller_->engine()->messenger());
  display_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "fly_player/display",
          &flutter::StandardMethodCodec::GetInstance());
  display_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() != "getRefreshRate") {
          result->NotImplemented();
          return;
        }
        const auto rate = GetWindowRefreshRate(GetHandle());
        result->Success(rate ? flutter::EncodableValue(*rate)
                             : flutter::EncodableValue());
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  display_channel_ = nullptr;
  system_media_controls_ = nullptr;
  potplayer_bridge_ = nullptr;
  desktop_danmaku_segmenter_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_DISPLAYCHANGE && display_channel_) {
    display_channel_->InvokeMethod("changed", nullptr);
  }
  if (message == SystemMediaControls::kCommandMessage && system_media_controls_) {
    system_media_controls_->HandleCommand(wparam, lparam);
    return 0;
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
