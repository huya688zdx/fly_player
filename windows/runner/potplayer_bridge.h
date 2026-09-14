#ifndef RUNNER_POTPLAYER_BRIDGE_H_
#define RUNNER_POTPLAYER_BRIDGE_H_

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <condition_variable>
#include <deque>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

class PotPlayerBridge {
 public:
  PotPlayerBridge(HWND host_window, flutter::BinaryMessenger* messenger);
  ~PotPlayerBridge();

 private:
  struct Request {
    std::string method;
    DWORD pid = 0;
    int64_t position_ms = -1;
    bool focus = true;
    int paused = -1;
    int speed = -1;
    int playlist_direction = 0;
    std::wstring subtitle_path;
    std::string media_url;
    std::wstring executable;
    std::wstring command_line;
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result;
  };
  struct Completion {
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result;
    flutter::EncodableValue value;
    std::string error;
    std::string error_message;
  };

  void Run();
  bool SetMiniPinned(bool pinned);
  void StopMiniPinWatch();
  Completion Execute(Request request, HWND receiver);
  static LRESULT CALLBACK ReceiverProc(HWND window, UINT message, WPARAM wparam,
                                       LPARAM lparam);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  HWND host_window_;
  HWINEVENTHOOK mini_foreground_hook_ = nullptr;
  HWINEVENTHOOK mini_location_hook_ = nullptr;
  std::thread worker_;
  std::mutex mutex_;
  std::condition_variable ready_;
  std::deque<Request> requests_;
  bool stopping_ = false;

  // 仅后台查询线程读写，返回文件必须来自当前查询的进程。
  DWORD expected_pid_ = 0;
  bool received_file_ = false;
  std::string current_file_;
};

#endif
