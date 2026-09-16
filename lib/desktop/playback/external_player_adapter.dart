import 'dart:io';

/// 接入受 Fly 管理的外部播放器。必须提供真实进度、媒体身份与基本播放控制；
/// 仅能拉起程序、无法读取状态的播放器不满足此接口。
/// 新实现登记到 ExternalPlayerAdapters.available 后，由 playerId 选择。
abstract interface class ExternalPlayerAdapter {
  String get id;
  String get displayName;
  String get executableHint;
  List<String> get fileExtensions;
  String get usageNotes;

  /// 能否加载公共层导出的 ASS 字幕（包含合成弹幕）。
  bool get supportsSubtitles;

  /// 是否支持导出原生列表并跟踪播放器内部切集；Fly 目录切集不依赖此项。
  bool get supportsPlaylist;
  bool get supportsMiniPlayer;

  Future<String?> validateExecutable(String executablePath);
  Future<String?> detectExecutable();

  /// 格式由具体播放器决定；公共层只提供条目与当前媒体。
  Future<String> writePlaylist({
    required Directory directory,
    required String currentUrl,
    required Map<String, String> titlesByUrl,
  });

  /// 启动后即返回拥有该进程的会话，采样与回调由会话的 start 开始。
  /// url 可以是播放列表；mediaUrl 始终是待确认的实际媒体身份。
  Future<ExternalPlayerSession> launch({
    required String executablePath,
    required String url,
    required String mediaUrl,
    required Duration startPosition,
    required String title,
    required Map<String, String> headers,
    required bool Function() isCurrentSession,
    required void Function(Duration position, Duration duration, bool paused)
    onProgress,
    required Future<void> Function() onFinished,
    required void Function(String message) onError,
    Future<Duration?> Function(String mediaUrl)? onMediaChanged,
  });

  /// 由播放器实现处理其全屏窗口与 Fly 悬浮条之间的置顶关系。
  Future<void> setMiniPinned(bool pinned);
}

/// 公共宿主不依赖进程号、原生消息编号或播放器的状态编码。
abstract interface class ExternalPlayerSession {
  String get mediaUrl;
  bool get finished;
  bool get isCurrent;
  bool get hasPlaylist;

  Future<void> start({
    required bool paused,
    required double speed,
    required Duration initialPosition,
    void Function()? onWaiting,
  });
  Future<void> poll();
  Future<bool> matchesMedia(String expectedUrl);

  /// 返回命令是否被接受；不能代替 confirmPlayback 的实际采样确认。
  Future<bool> setPaused(bool paused);
  Future<bool> seek(Duration position);
  Future<bool> stepPlaylist(int direction);
  Future<bool> confirmPlayback({Duration? position, bool? paused});
  Future<bool> activate({Duration? position, bool resumePlayback = true});

  /// 切集交接时媒体身份可能还未写回会话，必须传入本次字幕所属的媒体。
  Future<void> loadSubtitle({required String path, required String mediaUrl});
  Future<void> finish({bool reportFinal = true, bool closePlayer = false});
}
