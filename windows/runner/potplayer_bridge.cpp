#include "potplayer_bridge.h"

#include <shlobj.h>

#include <cmath>
#include <cstring>
#include <limits>
#include <utility>

namespace {
constexpr wchar_t kReceiverClass[] = L"FlyPlayerPotPlayerReceiver";
// 协议定义：https://github.com/ld3l/PotPlayerControl/blob/main/InternalSimpleCmd.h
constexpr WPARAM kGetDuration = 0x5002;
constexpr WPARAM kGetPosition = 0x5004;
constexpr WPARAM kSetPosition = 0x5005;
constexpr WPARAM kGetState = 0x5006;
constexpr WPARAM kSetState = 0x5007;
constexpr WPARAM kSetPlayOrder = 0x5008;
constexpr WPARAM kSetSpeed = 0x5016;
constexpr WPARAM kGetFile = 0x6020;
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;

// 只在极简模式钉住期间监听；回调和通道均在主窗口线程执行。
HWND pinned_mini_window = nullptr;

void CALLBACK KeepMiniAbovePlayer(HWINEVENTHOOK, DWORD event, HWND player,
                                  LONG object, LONG child, DWORD, DWORD) {
  const HWND mini = pinned_mini_window;
  if (!mini || !IsWindowVisible(mini) || IsIconic(mini)) return;
  if (event != EVENT_SYSTEM_FOREGROUND && event != EVENT_OBJECT_SHOW &&
      event != EVENT_OBJECT_REORDER && event != EVENT_OBJECT_LOCATIONCHANGE) return;
  if (event != EVENT_SYSTEM_FOREGROUND &&
      (object != OBJID_WINDOW || child != CHILDID_SELF)) return;
  if (event == EVENT_OBJECT_REORDER) player = GetForegroundWindow();
  if (!player || player == mini || !IsWindowVisible(player) || IsIconic(player)) {
    return;
  }
  wchar_t name[64] = {};
  GetClassNameW(player, name, 64);
  if (wcscmp(name, L"PotPlayer64") != 0 && wcscmp(name, L"PotPlayer") != 0) {
    return;
  }
  // 同为 TOPMOST 的播放器进入全屏后仍能盖住小窗；已在上方时不重复调整。
  for (HWND above = GetWindow(player, GW_HWNDPREV); above;
       above = GetWindow(above, GW_HWNDPREV)) {
    if (above == mini) return;
  }
  SetWindowPos(mini, HWND_TOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER);
}

struct WindowSearch {
  DWORD pid;
  HWND window = nullptr;
};

HWND FindPlayerWindow(DWORD pid) {
  WindowSearch search{pid};
  EnumWindows(
      [](HWND window, LPARAM data) -> BOOL {
        auto* search = reinterpret_cast<WindowSearch*>(data);
        DWORD pid = 0;
        GetWindowThreadProcessId(window, &pid);
        if (pid == search->pid) {
          wchar_t name[64] = {};
          GetClassNameW(window, name, 64);
          if (wcscmp(name, L"PotPlayer64") == 0 ||
              wcscmp(name, L"PotPlayer") == 0) {
            search->window = window;
            return FALSE;
          }
        }
        return TRUE;
      },
      reinterpret_cast<LPARAM>(&search));
  return search.window;
}

bool Query(HWND window, WPARAM command, LPARAM argument, int64_t* value) {
  DWORD_PTR result = 0;
  // 不使用 SMTO_BLOCK，让播放器回传的 WM_COPYDATA 能在等待期间处理。
  if (!SendMessageTimeoutW(window, WM_USER, command, argument,
                           SMTO_ABORTIFHUNG | SMTO_ERRORONEXIT, 200, &result)) {
    return false;
  }
  *value = static_cast<int64_t>(static_cast<LONG_PTR>(result));
  return true;
}

int64_t ReadInteger(const Map& arguments, const char* key, int64_t fallback) {
  const auto found = arguments.find(Value(key));
  if (found == arguments.end()) return fallback;
  if (const auto* value = std::get_if<int32_t>(&found->second)) return *value;
  if (const auto* value = std::get_if<int64_t>(&found->second)) return *value;
  return fallback;
}

std::string ReadString(const Map& arguments, const char* key) {
  const auto found = arguments.find(Value(key));
  if (found == arguments.end()) return {};
  const auto* value = std::get_if<std::string>(&found->second);
  return value ? *value : std::string();
}

std::wstring WideString(const std::string& text) {
  if (text.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
                                      static_cast<int>(text.size()), nullptr, 0);
  std::wstring result(size, L'\0');
  if (size) {
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
                        static_cast<int>(text.size()), result.data(), size);
  }
  return result;
}

std::wstring QuoteArgument(const std::wstring& text) {
  std::wstring result = L"\"";
  size_t slashes = 0;
  for (wchar_t character : text) {
    if (character == L'\\') {
      ++slashes;
      continue;
    }
    result.append(character == L'\"' ? slashes * 2 + 1 : slashes, L'\\');
    result.push_back(character);
    slashes = 0;
  }
  result.append(slashes * 2, L'\\');
  return result + L'\"';
}
}

PotPlayerBridge::PotPlayerBridge(HWND host_window,
                                 flutter::BinaryMessenger* messenger)
    : channel_(std::make_unique<flutter::MethodChannel<Value>>(
          messenger, "fly_player/potplayer",
          &flutter::StandardMethodCodec::GetInstance())),
      host_window_(host_window) {
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<Value>& call,
             std::unique_ptr<flutter::MethodResult<Value>> result) {
        const auto& method = call.method_name();
        if (method == "setMiniPinned") {
          const auto* pinned = call.arguments()
                                   ? std::get_if<bool>(call.arguments())
                                   : nullptr;
          if (!pinned || !SetMiniPinned(*pinned)) {
            result->Error("mini_pin_failed", "悬浮条置顶设置失败");
          } else {
            result->Success();
          }
          return;
        }
        if (method != "snapshot" && method != "activate" && method != "close" &&
            method != "configure" && method != "launch" &&
            method != "subtitle" && method != "stepPlaylist") {
          result->NotImplemented();
          return;
        }
        const auto* args = call.arguments()
                               ? std::get_if<Map>(call.arguments())
                               : nullptr;
        const int64_t pid = args ? ReadInteger(*args, "pid", 0) : 0;
        if (!args || (method != "launch" &&
                      (pid <= 0 || pid > std::numeric_limits<DWORD>::max()))) {
          result->Error("invalid_pid", "播放器进程编号无效");
          return;
        }
        Request request;
        request.method = method;
        request.media_url = ReadString(*args, "mediaUrl");
        if ((method == "activate" || method == "configure" ||
             method == "stepPlaylist") &&
            args->count(Value("mediaUrl")) && request.media_url.empty()) {
          result->Error("invalid_media_url", "播放媒体标识为空");
          return;
        }
        if (method == "subtitle") {
          request.subtitle_path = WideString(ReadString(*args, "path"));
          if (request.subtitle_path.empty() || request.media_url.empty()) {
            result->Error("invalid_subtitle", "字幕文件或媒体标识为空");
            return;
          }
        }
        if (method == "stepPlaylist") {
          const int64_t direction = ReadInteger(*args, "direction", 0);
          if (request.media_url.empty() || (direction != -1 && direction != 1)) {
            result->Error("invalid_playlist_step", "播放列表切换方向或媒体标识无效");
            return;
          }
          request.playlist_direction = static_cast<int>(direction);
        }
        if (method == "launch") {
          request.executable = WideString(ReadString(*args, "executable"));
          const auto url = WideString(ReadString(*args, "url"));
          if (request.executable.empty() || url.empty()) {
            result->Error("invalid_launch", "播放器路径或视频地址为空");
            return;
          }
          // PotPlayer 要求只引用等号右侧；标准 argv 引用整项会污染视频 URL。
          request.command_line = QuoteArgument(request.executable) + L" " +
                                 QuoteArgument(url) + L" /new";
          const auto subtitle = WideString(ReadString(*args, "subtitlePath"));
          if (!subtitle.empty()) {
            request.command_line += L" /sub=" + QuoteArgument(subtitle);
          }
          const auto title = WideString(ReadString(*args, "title"));
          if (!title.empty()) {
            request.command_line += L" /title=" + QuoteArgument(title);
          }
          const int64_t start_ms = ReadInteger(*args, "startMs", 0);
          if (start_ms > 0) {
            const auto milliseconds = std::to_wstring(start_ms % 1000 + 1000);
            request.command_line += L" /seek=" + std::to_wstring(start_ms / 1000) +
                                    L"." + milliseconds.substr(1);
          }
          std::string headers;
          const auto found_headers = args->find(Value("headers"));
          if (found_headers != args->end()) {
            if (const auto* entries = std::get_if<Map>(&found_headers->second)) {
              for (const auto& entry : *entries) {
                const auto* key = std::get_if<std::string>(&entry.first);
                const auto* value = std::get_if<std::string>(&entry.second);
                if (!key || !value || key->empty() ||
                    key->find_first_of(":\r\n") != std::string::npos ||
                    value->find_first_of("\r\n") != std::string::npos) {
                  result->Error("invalid_headers", "播放请求头格式无效");
                  return;
                }
                headers += *key + ": " + *value + "\r\n";
              }
            }
          }
          if (!headers.empty()) {
            request.command_line += L" /headers=" + QuoteArgument(WideString(headers));
          }
          if (request.command_line.size() >= 32767) {
            result->Error("invalid_launch", "播放器启动参数过长");
            return;
          }
        }
        request.pid = static_cast<DWORD>(pid);
        request.position_ms = ReadInteger(*args, "positionMs", -1);
        const auto focus = args->find(Value("focus"));
        if (focus != args->end()) {
          if (const auto* value = std::get_if<bool>(&focus->second)) {
            request.focus = *value;
          }
        }
        const auto paused = args->find(Value("paused"));
        if (paused != args->end()) {
          if (const auto* value = std::get_if<bool>(&paused->second)) {
            request.paused = *value ? 1 : 2;
          }
        }
        const auto speed = args->find(Value("speed"));
        if (speed != args->end()) {
          if (const auto* value = std::get_if<double>(&speed->second)) {
            if (std::isfinite(*value) && *value >= 0.2 && *value <= 12.0) {
              request.speed = static_cast<int>(std::lround(*value * 1000));
            }
          }
        }
        request.result = std::move(result);
        {
          std::lock_guard<std::mutex> lock(mutex_);
          requests_.push_back(std::move(request));
        }
        if (!worker_.joinable()) worker_ = std::thread([this]() { Run(); });
        ready_.notify_one();
      });
}

PotPlayerBridge::~PotPlayerBridge() {
  StopMiniPinWatch();
  channel_->SetMethodCallHandler(nullptr);
  {
    std::lock_guard<std::mutex> lock(mutex_);
    stopping_ = true;
  }
  ready_.notify_one();
  if (worker_.joinable()) worker_.join();
}

void PotPlayerBridge::StopMiniPinWatch() {
  if (pinned_mini_window == host_window_) pinned_mini_window = nullptr;
  if (mini_foreground_hook_) UnhookWinEvent(mini_foreground_hook_);
  if (mini_location_hook_) UnhookWinEvent(mini_location_hook_);
  mini_foreground_hook_ = nullptr;
  mini_location_hook_ = nullptr;
}

bool PotPlayerBridge::SetMiniPinned(bool pinned) {
  if (pinned && !mini_foreground_hook_) {
    const DWORD flags = WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS;
    mini_foreground_hook_ = SetWinEventHook(
        EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, nullptr,
        KeepMiniAbovePlayer, 0, 0, flags);
    mini_location_hook_ = SetWinEventHook(
        EVENT_OBJECT_SHOW, EVENT_OBJECT_LOCATIONCHANGE, nullptr,
        KeepMiniAbovePlayer, 0, 0, flags);
    if (!mini_foreground_hook_ || !mini_location_hook_) {
      StopMiniPinWatch();
      return false;
    }
  }
  if (!SetWindowPos(host_window_, pinned ? HWND_TOPMOST : HWND_NOTOPMOST,
                    0, 0, 0, 0,
                    SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER)) {
    if (pinned_mini_window != host_window_) StopMiniPinWatch();
    return false;
  }
  if (pinned) {
    pinned_mini_window = host_window_;
  } else {
    StopMiniPinWatch();
  }
  return true;
}

void PotPlayerBridge::Run() {
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = ReceiverProc;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpszClassName = kReceiverClass;
  RegisterClassW(&window_class);
  HWND receiver = CreateWindowExW(0, kReceiverClass, L"", 0, 0, 0, 0, 0,
                                  HWND_MESSAGE, nullptr,
                                  window_class.hInstance, this);
  while (true) {
    Request request;
    {
      std::unique_lock<std::mutex> lock(mutex_);
      ready_.wait(lock, [this]() { return stopping_ || !requests_.empty(); });
      if (stopping_) break;
      request = std::move(requests_.front());
      requests_.pop_front();
    }
    auto completion = Execute(std::move(request), receiver);
    // Flutter Windows 的 BinaryReply 在内部持有 messenger 锁，允许后台回复。
    if (completion.error.empty()) {
      completion.result->Success(completion.value);
    } else {
      completion.result->Error(completion.error, completion.error_message);
    }
  }
  if (receiver) DestroyWindow(receiver);
}

PotPlayerBridge::Completion PotPlayerBridge::Execute(Request request,
                                                     HWND receiver) {
  Completion completion;
  completion.result = std::move(request.result);
  completion.error_message = "无法读取外部播放器状态，请稍后重试";
  if (request.method == "subtitle") {
    completion.error_message = "无法加载外部播放器字幕，请稍后重试";
    const DWORD attributes = GetFileAttributesW(request.subtitle_path.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES ||
        (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
      completion.error = "potplayer_subtitle_missing";
      completion.error_message = "字幕文件不存在或不可访问";
      return completion;
    }
  }
  if (request.method == "launch") {
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESHOWWINDOW;
    startup.wShowWindow = SW_SHOWNORMAL;
    PROCESS_INFORMATION process{};
    if (!CreateProcessW(request.executable.c_str(), request.command_line.data(),
                         nullptr, nullptr, FALSE, 0, nullptr, nullptr, &startup,
                         &process)) {
      completion.error = "potplayer_launch_failed";
    } else {
      completion.value = Value(static_cast<int64_t>(process.dwProcessId));
      CloseHandle(process.hThread);
      CloseHandle(process.hProcess);
    }
    return completion;
  }
  const HWND window = FindPlayerWindow(request.pid);
  if (!window) {
    if (request.method == "subtitle") {
      completion.error = "potplayer_not_running";
      completion.error_message = "外部播放器已关闭";
      return completion;
    }
    completion.value = request.method == "snapshot"
                           ? Value(Map{{Value("alive"), Value(false)}})
                           : Value(false);
    return completion;
  }
  if (request.method == "close") {
    completion.value = Value(PostMessageW(window, WM_CLOSE, 0, 0) != FALSE);
    return completion;
  }
  if ((request.method == "activate" || request.method == "configure" ||
       request.method == "stepPlaylist") &&
      !request.media_url.empty()) {
    if (!receiver) {
      completion.error = "potplayer_receiver";
      return completion;
    }
    // 控制命令排队期间可能切集，投递前再次核对同一进程的媒体身份。
    expected_pid_ = request.pid;
    received_file_ = false;
    current_file_.clear();
    int64_t ignored = 0;
    const bool queried =
        Query(window, kGetFile, reinterpret_cast<LPARAM>(receiver), &ignored);
    expected_pid_ = 0;
    if (!queried || !received_file_) {
      completion.error = queried ? "potplayer_file_unavailable"
                                 : "potplayer_timeout";
      return completion;
    }
    if (current_file_ != request.media_url) {
      completion.error = "potplayer_file_changed";
      completion.error_message = "播放内容已切换，已取消控制操作";
      return completion;
    }
  }
  if (request.method == "activate") {
    bool sent = true;
    if (request.position_ms >= 0) {
      sent = PostMessageW(window, WM_USER, kSetPosition,
                           static_cast<LPARAM>(request.position_ms)) != FALSE;
    }
    if (request.focus) {
      ShowWindowAsync(window, SW_RESTORE);
      sent = (SetForegroundWindow(window) != FALSE) && sent;
    }
    completion.value = Value(sent);
    return completion;
  }
  if (request.method == "configure") {
    bool sent = true;
    if (request.paused >= 0) {
      sent = PostMessageW(window, WM_USER, kSetState, request.paused) != FALSE;
    }
    if (request.speed >= 0) {
      sent = (PostMessageW(window, WM_USER, kSetSpeed, request.speed) != FALSE) &&
             sent;
    }
    completion.value = Value(sent);
    return completion;
  }
  if (request.method == "stepPlaylist") {
    const LPARAM order = request.playlist_direction < 0 ? 0 : 1;
    completion.value = Value(
        PostMessageW(window, WM_USER, kSetPlayOrder, order) != FALSE);
    return completion;
  }
  if (!receiver) {
    completion.error = "potplayer_receiver";
    return completion;
  }
  expected_pid_ = request.pid;
  received_file_ = false;
  current_file_.clear();
  int64_t ignored = 0;
  int64_t position = 0;
  int64_t duration = 0;
  int64_t state = -1;
  if (!Query(window, kGetFile, reinterpret_cast<LPARAM>(receiver), &ignored)) {
    completion.error = "potplayer_timeout";
    expected_pid_ = 0;
    return completion;
  }
  const std::string initial_file = current_file_;
  if (request.method == "subtitle") {
    expected_pid_ = 0;
    if (!received_file_) {
      completion.error = "potplayer_file_unavailable";
      return completion;
    }
    if (current_file_ != request.media_url) {
      completion.error = "potplayer_file_changed";
      completion.error_message = "播放内容已切换，已取消加载该字幕";
      return completion;
    }
    const SIZE_T size = sizeof(DROPFILES) +
                        (request.subtitle_path.size() + 2) * sizeof(wchar_t);
    HGLOBAL block = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, size);
    auto* drop = block ? static_cast<DROPFILES*>(GlobalLock(block)) : nullptr;
    if (!drop) {
      if (block) GlobalFree(block);
      completion.error = "potplayer_subtitle_failed";
      return completion;
    }
    drop->pFiles = sizeof(DROPFILES);
    drop->fWide = TRUE;
    memcpy(reinterpret_cast<char*>(drop) + sizeof(DROPFILES),
           request.subtitle_path.data(),
           request.subtitle_path.size() * sizeof(wchar_t));
    GlobalUnlock(block);
    // 投递成功后由播放器通过 DragFinish 释放，路径列表保留双零结尾。
    if (!PostMessageW(window, WM_DROPFILES, reinterpret_cast<WPARAM>(block), 0)) {
      GlobalFree(block);
      completion.error = "potplayer_subtitle_failed";
      return completion;
    }
    completion.value = Value(true);
    return completion;
  }
  const bool received_initial_file = received_file_;
  received_file_ = false;
  // 前后文件身份必须一致，避免切换媒体时混用两部影片的进度。
  if (!Query(window, kGetPosition, 0, &position) ||
      !Query(window, kGetDuration, 0, &duration) ||
      !Query(window, kGetState, 0, &state) ||
      !Query(window, kGetFile, reinterpret_cast<LPARAM>(receiver), &ignored)) {
    completion.error = "potplayer_timeout";
  } else if (!received_initial_file || !received_file_) {
    completion.error = "potplayer_file_unavailable";
  } else if (initial_file != current_file_) {
    completion.error = "potplayer_file_changed";
  } else {
    completion.value = Value(Map{
        {Value("alive"), Value(true)},
        {Value("positionMs"), Value(position)},
        {Value("durationMs"), Value(duration)},
        {Value("state"), Value(state)},
        {Value("file"), Value(current_file_)},
    });
  }
  expected_pid_ = 0;
  return completion;
}

LRESULT CALLBACK PotPlayerBridge::ReceiverProc(HWND window, UINT message,
                                               WPARAM wparam, LPARAM lparam) {
  if (message == WM_NCCREATE) {
    auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    SetWindowLongPtrW(window, GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(create->lpCreateParams));
  }
  auto* self = reinterpret_cast<PotPlayerBridge*>(
      GetWindowLongPtrW(window, GWLP_USERDATA));
  if (message == WM_COPYDATA && self && self->expected_pid_ != 0 && lparam) {
    DWORD sender_pid = 0;
    GetWindowThreadProcessId(reinterpret_cast<HWND>(wparam), &sender_pid);
    const auto* data = reinterpret_cast<const COPYDATASTRUCT*>(lparam);
    if (sender_pid == self->expected_pid_ && data->dwData == kGetFile &&
        data->lpData && data->cbData > 0 && data->cbData <= 131072) {
      self->current_file_.assign(static_cast<const char*>(data->lpData),
                                 data->cbData);
      while (!self->current_file_.empty() && self->current_file_.back() == '\0') {
        self->current_file_.pop_back();
      }
      self->received_file_ = true;
      return TRUE;
    }
  }
  return DefWindowProcW(window, message, wparam, lparam);
}
