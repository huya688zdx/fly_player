#ifndef RUNNER_DESKTOP_DANMAKU_SEGMENTER_H_
#define RUNNER_DESKTOP_DANMAKU_SEGMENTER_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <condition_variable>
#include <deque>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include <MNN/Interpreter.hpp>

// Windows 桌面弹幕的人物分割桥。取帧由 Dart/media_kit 负责，本类只在后台线程
// 执行固定 512 输入的 MNN 推理，并返回与原帧等比的 RGBA alpha 蒙版。
class DesktopDanmakuSegmenter {
 public:
  explicit DesktopDanmakuSegmenter(flutter::BinaryMessenger* messenger);
  ~DesktopDanmakuSegmenter();

 private:
  using Value = flutter::EncodableValue;
  using Result = flutter::MethodResult<Value>;

  struct Request {
    std::vector<uint8_t> bgra;
    int width = 0;
    int height = 0;
    int stride = 0;
    int display_width = 0;
    int display_height = 0;
    int output_width = 0;
    std::unique_ptr<Result> result;
  };

  void Run();
  void Execute(Request request);
  bool EnsureModel(std::string* error);

  std::unique_ptr<flutter::MethodChannel<Value>> channel_;
  std::mutex mutex_;
  std::condition_variable ready_;
  std::deque<Request> requests_;
  bool stopping_ = false;
  std::thread worker_;

  std::shared_ptr<MNN::Interpreter> net_;
  MNN::Session* session_ = nullptr;
  MNN::Tensor* input_ = nullptr;
  MNN::Tensor* output_ = nullptr;
};

#endif  // RUNNER_DESKTOP_DANMAKU_SEGMENTER_H_
