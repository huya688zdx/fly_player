#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#ifdef FLY_WINDOWS_AI_MASK
#include "desktop_danmaku_segmenter.h"
#endif
#include "potplayer_bridge.h"
#include "system_media_controls.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
#ifdef FLY_WINDOWS_AI_MASK
  std::unique_ptr<DesktopDanmakuSegmenter> desktop_danmaku_segmenter_;
#endif
  std::unique_ptr<PotPlayerBridge> potplayer_bridge_;
  std::unique_ptr<SystemMediaControls> system_media_controls_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> display_channel_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
