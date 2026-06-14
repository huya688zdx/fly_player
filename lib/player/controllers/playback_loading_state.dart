import 'package:flutter/foundation.dart';

import 'mpv_player_controller.dart';

/// 用户可感知的加载性质。决定“是否转圈 / 是否全屏蒙层 / 文案语义”。
///
/// 这是播放器加载状态的**单一真值枚举**：此前散落在 [MpvPlaybackPhase] 与
/// [PlayerUiController] 七个布尔旗标里的判断，全部收敛到这里统一解释，避免各
/// 调用点各自用 `||` 拼“我现在算不算加载”导致行为不一致。
enum PlaybackLoadingKind {
  /// 正常播放/暂停，无加载。
  none,

  /// 首次加载 / 切源 / 切集——黑屏蒙层 + “准备播放源”。
  preparingSource,

  /// 切清晰度 / 音轨 / 字幕引起的重载——蒙层 + 具体切换文案。
  switchingTrack,

  /// 网络波动卡顿——蒙层 + 网速/预计恢复信息。
  buffering,

  /// 进度定位中——仅播放键/进度条转圈，不弹全屏蒙层。
  seeking,
}

/// 描述转场类加载旗标的快照。由 [PlayerUiController] 在解析时提供，
/// 让 [PlaybackLoadingState.resolve] 成为不依赖页面状态的纯函数。
@immutable
class PlaybackLoadingFlags {
  /// 切清晰度/音轨/字幕等需要重载播放源的加载。
  final bool switchingTrack;

  /// 前台转场加载（切集/切源），需要立即出蒙层。
  final bool pendingTransition;

  /// 后台预载转场，不应产生任何可见 UI。
  final bool backgroundTransition;

  /// 正在等待新源的首帧可见。
  final bool awaitingVisualStart;

  /// 本次加载完成后目标处于暂停态（影响播放键图标）。
  final bool targetPaused;

  const PlaybackLoadingFlags({
    this.switchingTrack = false,
    this.pendingTransition = false,
    this.backgroundTransition = false,
    this.awaitingVisualStart = false,
    this.targetPaused = false,
  });

  static const PlaybackLoadingFlags none = PlaybackLoadingFlags();

  /// 是否存在任一前台转场加载（排除后台预载）。
  bool get hasForegroundTransition =>
      !backgroundTransition &&
      (switchingTrack || pendingTransition || awaitingVisualStart);

  /// 是否存在任一转场（含后台）。
  bool get hasAnyTransition =>
      switchingTrack || pendingTransition || awaitingVisualStart;

  @override
  bool operator ==(Object other) {
    return other is PlaybackLoadingFlags &&
        other.switchingTrack == switchingTrack &&
        other.pendingTransition == pendingTransition &&
        other.backgroundTransition == backgroundTransition &&
        other.awaitingVisualStart == awaitingVisualStart &&
        other.targetPaused == targetPaused;
  }

  @override
  int get hashCode => Object.hash(
    switchingTrack,
    pendingTransition,
    backgroundTransition,
    awaitingVisualStart,
    targetPaused,
  );
}

/// 播放器加载状态的不可变快照。UI 层只读它，不再各自拼接判定。
@immutable
class PlaybackLoadingState {
  final PlaybackLoadingKind kind;

  /// 是否属于后台预载（即便 [kind] 非 none，也不应产生可见 UI）。
  final bool background;

  /// 加载完成后目标是否为暂停态。供播放键决定显示播放/暂停图标。
  final bool targetPaused;

  const PlaybackLoadingState({
    required this.kind,
    this.background = false,
    this.targetPaused = false,
  });

  static const PlaybackLoadingState idle = PlaybackLoadingState(
    kind: PlaybackLoadingKind.none,
  );

  /// 是否处于任何加载中。
  bool get isLoading => kind != PlaybackLoadingKind.none;

  /// 是否为可见的前台加载（后台预载不算）。
  bool get isForegroundLoading => isLoading && !background;

  /// 播放键/进度条是否应转圈。定位也转，但后台预载不转。
  bool get showsPlayButtonSpinner => isForegroundLoading;

  /// 是否应弹出全屏加载蒙层。
  ///
  /// 注意：[PlaybackLoadingKind.seeking] **不**弹全屏蒙层——本地或缓冲充足
  /// 时定位极快，全屏蒙层只会闪一下，体验更差；定位仅靠播放键转圈反馈即可。
  bool get showsFullScreenOverlay {
    if (!isForegroundLoading) return false;
    switch (kind) {
      case PlaybackLoadingKind.preparingSource:
      case PlaybackLoadingKind.switchingTrack:
      case PlaybackLoadingKind.buffering:
        return true;
      case PlaybackLoadingKind.seeking:
      case PlaybackLoadingKind.none:
        return false;
    }
  }

  /// 合成加载状态的**唯一入口**。吃底层播放值 + 转场旗标，吐统一状态。
  ///
  /// 行为约定（与重构前等价，仅 seeking 不再触发全屏蒙层）：
  /// - 后台转场：保留 kind 但 [background] 置真，UI 不可见。
  /// - 切轨道重载优先级最高。
  /// - 首帧前/等待首帧/未就绪/preparing → preparingSource。
  /// - buffering / seeking 来自底层 phase。
  factory PlaybackLoadingState.resolve({
    required MpvPlayerValue value,
    required PlaybackLoadingFlags flags,
    required bool initialSourceLoadStarted,
    required bool exiting,
    required bool playbackCompleted,
    required bool completionActionInFlight,
    required bool hasVisibleError,
  }) {
    if (exiting || playbackCompleted || completionActionInFlight) {
      return idle;
    }

    final background = flags.backgroundTransition && flags.hasAnyTransition;

    // 切轨道重载优先级最高：即便底层尚未进入 buffering，也应展示切换蒙层。
    if (flags.switchingTrack) {
      return PlaybackLoadingState(
        kind: PlaybackLoadingKind.switchingTrack,
        background: background,
        targetPaused: flags.targetPaused,
      );
    }

    // 首帧尚未开始加载源：准备环境/初始化播放器阶段。
    if (!initialSourceLoadStarted) {
      return PlaybackLoadingState(
        kind: PlaybackLoadingKind.preparingSource,
        background: background,
        targetPaused: flags.targetPaused,
      );
    }

    // 可见错误时不展示加载（交由错误 UI 处理）。
    if (hasVisibleError) {
      return idle;
    }

    // 前台转场（切集/切源）或正在等待首帧：准备播放源。
    if (flags.pendingTransition || flags.awaitingVisualStart) {
      return PlaybackLoadingState(
        kind: PlaybackLoadingKind.preparingSource,
        background: background,
        targetPaused: flags.targetPaused,
      );
    }

    switch (value.playbackPhase) {
      case MpvPlaybackPhase.buffering:
        return PlaybackLoadingState(
          kind: PlaybackLoadingKind.buffering,
          background: background,
          targetPaused: flags.targetPaused,
        );
      case MpvPlaybackPhase.seeking:
        return PlaybackLoadingState(
          kind: PlaybackLoadingKind.seeking,
          background: background,
          targetPaused: flags.targetPaused,
        );
      case MpvPlaybackPhase.preparing:
        return PlaybackLoadingState(
          kind: PlaybackLoadingKind.preparingSource,
          background: background,
          targetPaused: flags.targetPaused,
        );
      case MpvPlaybackPhase.idle:
      case MpvPlaybackPhase.playing:
      case MpvPlaybackPhase.paused:
      case MpvPlaybackPhase.ended:
      case MpvPlaybackPhase.error:
        break;
    }

    // 内核尚未就绪同样视为准备播放源。
    if (!value.ready || !value.nativeLibLoaded) {
      return PlaybackLoadingState(
        kind: PlaybackLoadingKind.preparingSource,
        background: background,
        targetPaused: flags.targetPaused,
      );
    }

    return idle;
  }

  @override
  bool operator ==(Object other) {
    return other is PlaybackLoadingState &&
        other.kind == kind &&
        other.background == background &&
        other.targetPaused == targetPaused;
  }

  @override
  int get hashCode => Object.hash(kind, background, targetPaused);

  @override
  String toString() =>
      'PlaybackLoadingState(kind: $kind, background: $background, '
      'targetPaused: $targetPaused)';
}
