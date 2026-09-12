#include "desktop_danmaku_segmenter.h"

#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <MNN/ErrorCode.hpp>
#include <MNN/Tensor.hpp>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <filesystem>
#include <stdexcept>
#include <utility>

namespace {
constexpr int kModelSize = 512;
using Map = flutter::EncodableMap;
using Value = flutter::EncodableValue;

int ReadInteger(const Map& arguments, const char* key) {
  const auto found = arguments.find(Value(key));
  if (found == arguments.end()) return 0;
  if (const auto* value = std::get_if<int32_t>(&found->second)) return *value;
  if (const auto* value = std::get_if<int64_t>(&found->second)) {
    return *value > INT_MAX || *value < INT_MIN ? 0 : static_cast<int>(*value);
  }
  return 0;
}

std::filesystem::path ModelPath() {
  std::wstring executable(MAX_PATH, L'\0');
  for (;;) {
    const DWORD length = GetModuleFileNameW(
        nullptr, executable.data(), static_cast<DWORD>(executable.size()));
    if (length == 0) return {};
    if (length < executable.size() - 1) {
      executable.resize(length);
      break;
    }
    executable.resize(executable.size() * 2);
  }
  return std::filesystem::path(executable).parent_path() / L"data" / L"models" /
         L"isnet-anime-512-fp16.mnn";
}

std::string Utf8Path(const std::filesystem::path& path) {
  const auto wide = path.wstring();
  const int length = WideCharToMultiByte(CP_UTF8, 0, wide.data(),
                                        static_cast<int>(wide.size()), nullptr,
                                        0, nullptr, nullptr);
  std::string result(length, '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()),
                      result.data(), length, nullptr, nullptr);
  return result;
}

float Clamp(float value, float low, float high) {
  return std::max(low, std::min(value, high));
}

float SampleBgra(const std::vector<uint8_t>& pixels, int width, int height,
                 int stride, float x, float y, int channel) {
  const float safe_x = Clamp(x, 0.0f, static_cast<float>(width - 1));
  const float safe_y = Clamp(y, 0.0f, static_cast<float>(height - 1));
  const int x0 = static_cast<int>(std::floor(safe_x));
  const int y0 = static_cast<int>(std::floor(safe_y));
  const int x1 = std::min(x0 + 1, width - 1);
  const int y1 = std::min(y0 + 1, height - 1);
  const float dx = safe_x - x0;
  const float dy = safe_y - y0;
  const auto at = [&](int px, int py) {
    return static_cast<float>(pixels[py * stride + px * 4 + channel]);
  };
  return (at(x0, y0) * (1 - dx) + at(x1, y0) * dx) * (1 - dy) +
         (at(x0, y1) * (1 - dx) + at(x1, y1) * dx) * dy;
}

float SampleMask(const float* mask, float x, float y) {
  const float safe_x = Clamp(x, 0.0f, kModelSize - 1.0f);
  const float safe_y = Clamp(y, 0.0f, kModelSize - 1.0f);
  const int x0 = static_cast<int>(std::floor(safe_x));
  const int y0 = static_cast<int>(std::floor(safe_y));
  const int x1 = std::min(x0 + 1, kModelSize - 1);
  const int y1 = std::min(y0 + 1, kModelSize - 1);
  const float dx = safe_x - x0;
  const float dy = safe_y - y0;
  const auto at = [&](int px, int py) { return mask[py * kModelSize + px]; };
  return (at(x0, y0) * (1 - dx) + at(x1, y0) * dx) * (1 - dy) +
         (at(x0, y1) * (1 - dx) + at(x1, y1) * dx) * dy;
}
}  // 匿名命名空间

DesktopDanmakuSegmenter::DesktopDanmakuSegmenter(
    flutter::BinaryMessenger* messenger)
    : channel_(std::make_unique<flutter::MethodChannel<Value>>(
          messenger, "fly_player/desktop_danmaku_segmentation",
          &flutter::StandardMethodCodec::GetInstance())),
      worker_([this]() { Run(); }) {
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<Value>& call,
             std::unique_ptr<Result> result) {
        if (call.method_name() != "segment") {
          result->NotImplemented();
          return;
        }
        const auto* arguments = call.arguments()
                                    ? std::get_if<Map>(call.arguments())
                                    : nullptr;
        const auto bytes = arguments
                               ? arguments->find(Value("bgra"))
                               : Map::const_iterator{};
        const auto* bgra = arguments && bytes != arguments->end()
                               ? std::get_if<std::vector<uint8_t>>(&bytes->second)
                               : nullptr;
        const int width = arguments ? ReadInteger(*arguments, "width") : 0;
        const int height = arguments ? ReadInteger(*arguments, "height") : 0;
        const int stride = arguments ? ReadInteger(*arguments, "stride") : 0;
        const int display_width =
            arguments ? ReadInteger(*arguments, "displayWidth") : 0;
        const int display_height =
            arguments ? ReadInteger(*arguments, "displayHeight") : 0;
        const int output_width = arguments
                                     ? ReadInteger(*arguments, "outputWidth")
                                     : 0;
        if (!bgra || width <= 0 || height <= 0 || stride < width * 4 ||
            display_width <= 0 || display_height <= 0 ||
            output_width < 64 || output_width > 512 ||
            bgra->size() < static_cast<size_t>(stride) * height) {
          result->Error("invalid_frame", "AI 遮罩取帧数据无效");
          return;
        }
        Request request;
        request.bgra = *bgra;
        request.width = width;
        request.height = height;
        request.stride = stride;
        request.display_width = display_width;
        request.display_height = display_height;
        request.output_width = output_width;
        request.result = std::move(result);
        {
          std::lock_guard<std::mutex> lock(mutex_);
          requests_.push_back(std::move(request));
        }
        ready_.notify_one();
      });
}

DesktopDanmakuSegmenter::~DesktopDanmakuSegmenter() {
  channel_->SetMethodCallHandler(nullptr);
  {
    std::lock_guard<std::mutex> lock(mutex_);
    stopping_ = true;
  }
  ready_.notify_one();
  if (worker_.joinable()) worker_.join();
  if (net_ && session_) net_->releaseSession(session_);
}

void DesktopDanmakuSegmenter::Run() {
  for (;;) {
    Request request;
    {
      std::unique_lock<std::mutex> lock(mutex_);
      ready_.wait(lock, [this]() { return stopping_ || !requests_.empty(); });
      if (stopping_) return;
      request = std::move(requests_.front());
      requests_.pop_front();
    }
    Execute(std::move(request));
  }
}

bool DesktopDanmakuSegmenter::EnsureModel(std::string* error) {
  if (session_ && input_ && output_) return true;
  const auto model = ModelPath();
  if (!std::filesystem::is_regular_file(model)) {
    *error = "AI 遮罩模型未随应用安装";
    return false;
  }
  net_ = std::shared_ptr<MNN::Interpreter>(
      MNN::Interpreter::createFromFile(Utf8Path(model).c_str()));
  if (!net_) {
    *error = "AI 遮罩模型无法加载";
    return false;
  }
  MNN::ScheduleConfig config;
  config.type = MNN_FORWARD_CPU;
  config.numThread = 4;
  MNN::BackendConfig backend;
  backend.precision = MNN::BackendConfig::Precision_Low;
  backend.power = MNN::BackendConfig::Power_High;
  config.backendConfig = &backend;
  session_ = net_->createSession(config);
  input_ = session_ ? net_->getSessionInput(session_, nullptr) : nullptr;
  output_ = session_ ? net_->getSessionOutput(session_, nullptr) : nullptr;
  if (!session_ || !input_ || !output_ ||
      input_->elementSize() != 3 * kModelSize * kModelSize ||
      output_->elementSize() != kModelSize * kModelSize) {
    *error = "AI 遮罩模型输入输出不兼容";
    return false;
  }
  return true;
}

void DesktopDanmakuSegmenter::Execute(Request request) {
  try {
    std::string error;
    if (!EnsureModel(&error)) {
      request.result->Error("model_unavailable", error);
      return;
    }
    const float scale = std::min(
        static_cast<float>(kModelSize) / request.width,
        static_cast<float>(kModelSize) / request.height);
    const int scaled_width =
        std::max(1, static_cast<int>(std::lround(request.width * scale)));
    const int scaled_height =
        std::max(1, static_cast<int>(std::lround(request.height * scale)));
    const int pad_x = (kModelSize - scaled_width) / 2;
    const int pad_y = (kModelSize - scaled_height) / 2;

    MNN::Tensor host_input(input_, input_->getDimensionType());
    auto* tensor = host_input.host<float>();
    std::fill(tensor, tensor + host_input.elementSize(), 0.0f);
    const int plane = kModelSize * kModelSize;
    for (int y = 0; y < scaled_height; ++y) {
      const float source_y =
          (y + 0.5f) * request.height / scaled_height - 0.5f;
      for (int x = 0; x < scaled_width; ++x) {
        const float source_x =
            (x + 0.5f) * request.width / scaled_width - 0.5f;
        const int destination = (pad_y + y) * kModelSize + pad_x + x;
        tensor[destination] = SampleBgra(request.bgra, request.width,
                                         request.height, request.stride,
                                         source_x, source_y, 2) /
                              255.0f;
        tensor[plane + destination] =
            SampleBgra(request.bgra, request.width, request.height,
                       request.stride, source_x, source_y, 1) /
            255.0f;
        tensor[2 * plane + destination] =
            SampleBgra(request.bgra, request.width, request.height,
                       request.stride, source_x, source_y, 0) /
            255.0f;
      }
    }
    input_->copyFromHostTensor(&host_input);
    const auto started = std::chrono::steady_clock::now();
    if (static_cast<int>(net_->runSession(session_)) != 0) {
      request.result->Error("inference_failed", "AI 遮罩推理失败");
      return;
    }
    MNN::Tensor host_output(output_, output_->getDimensionType());
    output_->copyToHostTensor(&host_output);

    const int output_height = std::max(
        1, static_cast<int>(std::lround(
               static_cast<double>(request.output_width) *
               request.display_height / request.display_width)));
    std::vector<uint8_t> rgba(static_cast<size_t>(request.output_width) *
                              output_height * 4);
    const auto* mask = host_output.host<float>();
    for (int y = 0; y < output_height; ++y) {
      const float mask_y = pad_y +
                           (y + 0.5f) * scaled_height / output_height - 0.5f;
      for (int x = 0; x < request.output_width; ++x) {
        const float mask_x =
            pad_x + (x + 0.5f) * scaled_width / request.output_width - 0.5f;
        const float probability = Clamp(SampleMask(mask, mask_x, mask_y),
                                        0.0f, 1.0f);
        const size_t offset =
            (static_cast<size_t>(y) * request.output_width + x) * 4;
        rgba[offset] = rgba[offset + 1] = rgba[offset + 2] = 255;
        rgba[offset + 3] =
            static_cast<uint8_t>(std::lround(probability * 255));
      }
    }
    const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - started);
    request.result->Success(Value(Map{
        {Value("width"), Value(request.output_width)},
        {Value("height"), Value(output_height)},
        {Value("rgba"), Value(std::move(rgba))},
        {Value("inferenceMs"), Value(static_cast<int64_t>(elapsed.count()))},
    }));
  } catch (const std::exception& exception) {
    request.result->Error("segmentation_failed", exception.what());
  }
}
