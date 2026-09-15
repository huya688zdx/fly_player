#ifndef RUNNER_MPV_DISPLAY_SYNC_H_
#define RUNNER_MPV_DISPLAY_SYNC_H_

#include <dxgi.h>
#include <wrl/client.h>

#include <client.h>
#include <render.h>

#include <cstdint>
#include <iostream>

// 由 media_kit 的同一个渲染线程持有，等待时不占用视频纹理锁。
class FlyMpvDisplaySync {
 public:
  void WaitForFrame(mpv_render_context* context, mpv_handle* player, HWND window) {
    mpv_render_frame_info frame = {};
    mpv_render_param parameter{MPV_RENDER_PARAM_NEXT_FRAME_INFO, &frame};
    if (mpv_render_context_get_info(context, parameter) < 0) {
      UseAudioSync(player);
      return;
    }
    if (!(frame.flags & MPV_RENDER_FRAME_INFO_BLOCK_VSYNC)) {
      return;
    }

    const auto monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
    if (monitor != monitor_) {
      monitor_ = monitor;
      output_.Reset();
      Microsoft::WRL::ComPtr<IDXGIFactory1> factory;
      if (SUCCEEDED(CreateDXGIFactory1(IID_PPV_ARGS(&factory)))) {
        Microsoft::WRL::ComPtr<IDXGIAdapter1> adapter;
        for (UINT i = 0; factory->EnumAdapters1(i, &adapter) == S_OK; ++i) {
          Microsoft::WRL::ComPtr<IDXGIOutput> output;
          for (UINT j = 0; adapter->EnumOutputs(j, &output) == S_OK; ++j) {
            DXGI_OUTPUT_DESC description = {};
            if (SUCCEEDED(output->GetDesc(&description)) &&
                description.Monitor == monitor && description.AttachedToDesktop) {
              output_ = output;
              break;
            }
            output.Reset();
          }
          if (output_) {
            break;
          }
          adapter.Reset();
        }
      }
    }

    if (!output_ || FAILED(output_->WaitForVBlank())) {
      output_.Reset();
      monitor_ = nullptr;
      UseAudioSync(player);
      return;
    }
    failure_logged_ = false;
  }

 private:
  void UseAudioSync(mpv_handle* player) {
    // 渲染线程不能同步调用播放属性；异步退回音频同步，避免无节拍快进。
    const char* sync = "audio";
    // 保留独立请求编号，避免碰到 media_kit 从 0 递增的待处理请求。
    mpv_set_property_async(player, UINT64_MAX, "video-sync", MPV_FORMAT_STRING,
                          &sync);
    if (!failure_logged_) {
      std::cerr << "Fly Player: 显示器垂直同步等待失败，已请求切回音频同步。"
                << std::endl;
      failure_logged_ = true;
    }
  }

  HMONITOR monitor_ = nullptr;
  Microsoft::WRL::ComPtr<IDXGIOutput> output_;
  bool failure_logged_ = false;
};

#endif  // RUNNER_MPV_DISPLAY_SYNC_H_
