#include "system_media_controls.h"

#include <systemmediatransportcontrolsinterop.h>
#include <winrt/Windows.Foundation.h>

#include <algorithm>
#include <chrono>
#include <string>

namespace {
using flutter::EncodableMap;
using flutter::EncodableValue;
using namespace winrt::Windows::Media;

template <typename T>
T Value(const EncodableMap &values, const char *key) {
  return std::get<T>(values.at(EncodableValue(key)));
}

int64_t Milliseconds(const EncodableMap &values, const char *key) {
  const auto &value = values.at(EncodableValue(key));
  return std::holds_alternative<int32_t>(value) ? std::get<int32_t>(value)
                                                : std::get<int64_t>(value);
}
}  // 匿名命名空间

SystemMediaControls::SystemMediaControls(HWND window,
                                         flutter::BinaryMessenger *messenger)
    : window_(window) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "fly_player/system_media_controls",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto &call, auto result) {
    try {
      if (call.method_name() == "clear") {
        Clear();
      } else if (call.method_name() == "metadata") {
        EnsureInitialized();
        const auto &values = std::get<EncodableMap>(*call.arguments());
        const auto display = controls_.DisplayUpdater();
        display.ClearAll();
        display.Type(MediaPlaybackType::Video);
        display.VideoProperties().Title(
            winrt::to_hstring(Value<std::string>(values, "title")));
        display.VideoProperties().Subtitle(
            winrt::to_hstring(Value<std::string>(values, "subtitle")));
        display.Update();
        controls_.PlaybackStatus(MediaPlaybackStatus::Changing);
        controls_.IsEnabled(true);
      } else if (call.method_name() == "state") {
        if (controls_) {
          const auto &values = std::get<EncodableMap>(*call.arguments());
          const auto status = Value<std::string>(values, "status");
          controls_.IsEnabled(status != "closed");
          controls_.PlaybackStatus(
              status == "playing"    ? MediaPlaybackStatus::Playing
              : status == "paused"   ? MediaPlaybackStatus::Paused
              : status == "changing" ? MediaPlaybackStatus::Changing
              : status == "stopped"  ? MediaPlaybackStatus::Stopped
                                     : MediaPlaybackStatus::Closed);
          controls_.PlaybackRate(Value<double>(values, "rate"));
          const auto duration =
              std::max<int64_t>(0, Milliseconds(values, "duration"));
          const auto position = std::clamp<int64_t>(
              Milliseconds(values, "position"), 0, duration);
          SystemMediaTransportControlsTimelineProperties timeline;
          timeline.StartTime(std::chrono::milliseconds(0));
          timeline.MinSeekTime(std::chrono::milliseconds(0));
          timeline.EndTime(std::chrono::milliseconds(duration));
          timeline.MaxSeekTime(std::chrono::milliseconds(duration));
          timeline.Position(std::chrono::milliseconds(position));
          controls_.UpdateTimelineProperties(timeline);
        }
      } else {
        result->NotImplemented();
        return;
      }
      result->Success();
    } catch (const winrt::hresult_error &error) {
      result->Error("system_media_controls", winrt::to_string(error.message()));
    } catch (const std::exception &error) {
      result->Error("system_media_controls", error.what());
    }
  });
}

void SystemMediaControls::EnsureInitialized() {
  if (controls_) return;
  const auto interop =
      winrt::get_activation_factory<SystemMediaTransportControls,
                                    ISystemMediaTransportControlsInterop>();
  winrt::check_hresult(interop->GetForWindow(
      window_, winrt::guid_of<SystemMediaTransportControls>(),
      winrt::put_abi(controls_)));
  controls_.IsPlayEnabled(true);
  controls_.IsPauseEnabled(true);
  // 系统回调来自工作线程，只投递值；不捕获桥对象，避免退出时访问已释放对象。
  button_revoker_ = controls_.ButtonPressed(
      winrt::auto_revoke, [window = window_](const auto &, const auto &args) {
        if (args.Button() == SystemMediaTransportControlsButton::Play) {
          PostMessage(window, kCommandMessage, 0, 0);
        } else if (args.Button() == SystemMediaTransportControlsButton::Pause) {
          PostMessage(window, kCommandMessage, 1, 0);
        }
      });
  position_revoker_ = controls_.PlaybackPositionChangeRequested(
      winrt::auto_revoke, [window = window_](const auto &, const auto &args) {
        const auto milliseconds =
            std::chrono::duration_cast<std::chrono::milliseconds>(
                args.RequestedPlaybackPosition())
                .count();
        PostMessage(window, kCommandMessage, 2,
                    static_cast<LPARAM>(milliseconds));
      });
}

void SystemMediaControls::HandleCommand(WPARAM command, LPARAM position) {
  if (!controls_ || !controls_.IsEnabled()) return;
  channel_->InvokeMethod(
      command == 0   ? "play"
      : command == 1 ? "pause"
                     : "seek",
      std::make_unique<EncodableValue>(static_cast<int64_t>(position)));
}

void SystemMediaControls::Clear() {
  if (!controls_) return;
  controls_.IsEnabled(false);
  controls_.PlaybackStatus(MediaPlaybackStatus::Closed);
  controls_.DisplayUpdater().ClearAll();
  controls_.DisplayUpdater().Update();
}

SystemMediaControls::~SystemMediaControls() {
  channel_->SetMethodCallHandler(nullptr);
  button_revoker_.revoke();
  position_revoker_.revoke();
  try {
    Clear();
  } catch (const winrt::hresult_error &) {
    // 窗口销毁时系统会话可能已经撤销。
  }
}
