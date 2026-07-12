<!-- CHECKPOINT
已审文件数: 37 / 37
最后完成: lib/player/models/player_runtime_preferences.dart
下一个: 无
阶段: 已完成
更新时间: 2026-07-02 20:44
-->

# TASK D findings —— 播放器核心链路

### [D-001] 播放器页面直接创建系统 MethodChannel
- 级别: P2
- 分类: 耦合 / 约束违规(C5)
- 位置: lib/player/mpv_player_page.dart:339
- 问题: 页面 State 直接持有平台通道，通道名也散落在页面层，违反平台通道只能收敛在桥接文件或专职 service/store 的约束。代码摘录：
  ```dart
  static const MethodChannel _systemChannel = MethodChannel(
    'fly_player/system',
  );
  ```
- 建议方向: 将 `fly_player/system` 的调用统一收敛到现有桥接服务中，页面和 mixin 只依赖桥接方法，避免页面层直接知道通道名。
- 状态: 已确认

### [D-002] Android-only 提示文案硬编码在播放器 build 中
- 级别: P2
- 分类: 可维护性 / 约束违规(M3)
- 位置: lib/player/mpv_player_page.dart:1333
- 问题: UI 展示文案直接写英文字符串，没有走 `AppLocalizations` getter。代码摘录：
  ```dart
  child: Text(
    'The libmpv integration in this project is currently implemented for Android only.',
    textAlign: TextAlign.center,
  ),
  ```
- 建议方向: 在 ARB 中新增对应本地化 key，并通过 `AppLocalizations.of(context)` 读取。
- 状态: 已确认

### [D-003] 书签元数据获取从播放器 UI mixin 直连 FeiniuApi
- 级别: P2
- 分类: 耦合 / 可扩展性 / 约束违规(C2)
- 位置: lib/player/page_parts/core/mpv_player_bookmark_mixin.dart:92
- 问题: 书签 mixin 属于播放器 UI/页面 part，却直接创建具体飞牛 API，书签元数据读取无法替换为 Emby/Jellyfin 等后端。代码摘录：
  ```dart
  final playInfo = await FeiniuApi(
    context.read<NasProvider>(),
  ).getPlayInfo(itemGuid);
  ```
- 建议方向: 通过播放器 source/controller 或 `lib/media_backend/` 抽象提供“当前条目元数据”读取能力，UI mixin 只依赖后端无关接口。
- 状态: 已确认

### [D-004] 书签元数据获取失败被空 catch 静默吞掉
- 级别: P2
- 分类: 可维护性 / 约束违规(M4)
- 位置: lib/player/page_parts/core/mpv_player_bookmark_mixin.dart:112
- 问题: 获取书签元数据失败时直接吞异常并返回 fallback，既不记录错误也不上抛，后续排查“书签标题/剧集信息错误”时没有可追踪证据。代码摘录：
  ```dart
  } catch (_) {
    return fallback;
  }
  ```
- 建议方向: 至少通过 `AppLogService` 或统一错误上报记录失败的 itemGuid 与异常；如果 fallback 是预期降级，也应保留可诊断日志。
- 状态: 已确认

### [D-005] 连续切集的旧异步结果可能覆盖新剧集
- 级别: P0
- 分类: Bug / 性能
- 位置: lib/player/page_parts/core/mpv_player_episode_mixin.dart:2641
- 问题: `_switchToEpisode` 没有互斥、取消令牌或代次校验；连续点击下一集/上一集时，先发起的 `_prepareEpisodeSwitchResult` 如果后返回，仍会执行 `_applyPreparedEpisodeSwitchResult` 并 reload，可能把当前播放状态回滚到旧选择。代码摘录：
  ```dart
  Future<void> _switchToEpisode(
    MediaLibraryItem episode, {
    bool fromAutoPlay = false,
  }) async {
    ...
    final prepared =
        _prefetchedEpisodeSwitchResultFor(episode) ??
        await _prepareEpisodeSwitchResult(episode);
    await _applyPreparedEpisodeSwitchResult(
  ```
- 建议方向: 为每次切集分配递增 generation，准备结果返回后、应用状态前、`reload` 前后都校验仍是最新请求；或在切集期间禁用/串行化新的切集请求。
- 状态: 已确认

### [D-006] 选集与切集核心逻辑直接绑定 FeiniuApi
- 级别: P1
- 分类: 可扩展性 / 耦合 / 约束违规(C2)
- 位置: lib/player/page_parts/core/mpv_player_episode_mixin.dart:52
- 问题: 播放器选集 UI/状态 mixin 直接读写飞牛接口，覆盖视图偏好、季/集列表、播放信息、切集流地址等关键路径，导致新增后端必须修改播放器公共逻辑。代码摘录：
  ```dart
  final viewType = await FeiniuApi(provider).getPlaylistViewType();
  ...
  final items = await FeiniuApi(
    provider,
  ).getEpisodeList(normalizedSeasonGuid);
  ...
  final api = FeiniuApi(context.read<NasProvider>());
  final info = await api.getPlayInfo(episode.guid);
  ```
- 建议方向: 把“选集列表/播放准备/偏好读写”抽到后端无关的 media backend 或 player source service；mixin 只消费统一模型和 controller 方法。
- 状态: 已确认

### [D-007] 选集链路多处空 catch 使失败不可追踪
- 级别: P2
- 分类: 可维护性 / 约束违规(M4)
- 位置: lib/player/page_parts/core/mpv_player_episode_mixin.dart:910
- 问题: 解析剧集/季信息时多处直接吞异常并返回空值或继续尝试，用户看到的现象只是选集缺失/季列表不完整，日志里没有失败 API、guid 或异常。代码摘录：
  ```dart
  } catch (_) {
    return '';
  }
  ...
  } catch (_) {
    continue;
  }
  ```
- 建议方向: 对预期降级保留 warning/debug 日志，至少记录当前 item/season/series guid；批量候选尝试可以聚合最后失败原因。
- 状态: 已确认

### [D-008] 连续替换播放源时旧 reload 可能覆盖新 source
- 级别: P0
- 分类: Bug
- 位置: lib/player/page_parts/core/mpv_player_runtime_mixin.dart:1328
- 问题: `_replacePlayerSource` 在读取偏好/字幕调整后只检查 `mounted` 和 `_exitInProgress`，没有校验当前请求仍是最新 source；随后又用 `unawaited` 发起 reload。快速连续进入/切换 source 时，旧请求晚返回仍会 `_hydrateFromSource` 并 reload，造成播放器状态回退。代码摘录：
  ```dart
  Future<void> _replacePlayerSource(MpvMediaSource incomingSource) async {
    final source = incomingSource.loadNonce > 0
        ? incomingSource
        : incomingSource.copyWith(loadNonce: _issueNextLoadNonce());
    final preferences = await _runtimePreferencesStore.load();
    ...
    _hydrateFromSource(source);
    ...
    unawaited(
      _prepareAndReloadSource(
  ```
- 建议方向: 引入 source load generation/token，并在每个 await 后、`_hydrateFromSource` 前、reload 前后校验；旧请求应直接丢弃并取消后续刷新。
- 状态: 已确认

### [D-009] 运行时链路直接依赖 FeiniuApi 处理 OP/ED、会话恢复和播放记录
- 级别: P1
- 分类: 可扩展性 / 耦合 / 约束违规(C2)
- 位置: lib/player/page_parts/core/mpv_player_runtime_mixin.dart:1144
- 问题: runtime mixin 直接创建飞牛 API，用于 OP/ED 配置、服务端播放会话续期、播放记录和详情预取等核心链路，多后端接入必须修改播放器 runtime。代码摘录：
  ```dart
  final api = FeiniuApi(context.read<NasProvider>());
  final info = await api.getPlayInfo(normalizedItemGuid);
  ...
  final effectiveApi = api ?? FeiniuApi(context.read<NasProvider>());
  ...
  final api = FeiniuApi(nasProvider);
  await api.recordPlayback(
  ```
- 建议方向: 把播放记录、会话续期、OP/ED 配置、详情刷新收敛到后端无关服务接口；runtime 只调用抽象能力。
- 状态: 已确认

### [D-010] runtime 中多处空 catch 吞掉关键恢复失败
- 级别: P2
- 分类: 可维护性 / 约束违规(M4)
- 位置: lib/player/page_parts/core/mpv_player_runtime_mixin.dart:1158
- 问题: OP/ED 配置加载、服务端会话过期检查、章节加载、缓存导入、系统通道调用等多处直接空 catch，失败后用户只看到功能不生效，日志无法定位。代码摘录：
  ```dart
  } catch (_) {}
  ...
  } catch (_) {
    return false;
  }
  ...
  } catch (_) {
    _uiController.chapterLoading = false;
    _scheduleChapterRetry(mediaGuid);
  }
  ```
- 建议方向: 对可忽略失败至少记录 debug/warning 日志并带上 itemGuid/mediaGuid/方法名；对用户触发动作保留错误上报或可见提示。
- 状态: 已确认

### [D-011] 系统通道方法名裸字符串散在 runtime mixin
- 级别: P2
- 分类: 耦合 / 约束违规(C5)
- 位置: lib/player/page_parts/core/mpv_player_runtime_mixin.dart:2627
- 问题: runtime mixin 直接通过页面静态 channel 调用平台方法，`setPlayerOrientation`、`setPlayerImmersiveMode`、`getPlayerStatusSnapshot` 等方法名没有收敛到桥接层单一定义点。代码摘录：
  ```dart
  await _MpvPlayerPageState._systemChannel.invokeMethod<void>(
    'setPlayerOrientation',
    <String, String>{'mode': mode},
  );
  ...
  .invokeMapMethod<String, dynamic>('getPlayerStatusSnapshot');
  ```
- 建议方向: 将这些方法封装到专职 bridge/service，由 bridge 维护通道名和方法名常量；runtime mixin 只调用 Dart 方法。
- 状态: 已确认

### [D-012] 章节跳过标签硬编码英文展示文案
- 级别: P2
- 分类: 可维护性 / 约束违规(M3)
- 位置: lib/player/page_parts/core/mpv_player_runtime_mixin.dart:2129
- 问题: 章节跳过 UI 使用硬编码英文标签，未走 `AppLocalizations`。代码摘录：
  ```dart
  label: 'Official intro',
  ...
  label: 'Official outro',
  ...
  return title.isNotEmpty ? title : 'Chapter ${chapter.index + 1}';
  ```
- 建议方向: 为官方片头/片尾和章节 fallback 新增本地化 getter，并在生成 skip segment / chapter label 时注入 l10n。
- 状态: 已确认

### [D-013] 代理延迟释放 Timer 未在播放器 dispose 时统一取消
- 级别: P2
- 分类: 性能 / 约束违规(P6)
- 位置: lib/player/page_parts/core/mpv_player_source_mixin.dart:130
- 问题: `_scheduleProxySessionRelease` 把 Timer 存入 `_proxyReleaseTimers`，但 `MpvPlayerPage.dispose()` 只取消了固定字段 Timer，没有遍历取消这个 map。退出播放器后，延迟释放回调仍会持有已 dispose 的 State 最多 12 秒。代码摘录：
  ```dart
  _proxyReleaseTimers[sessionId] = Timer(delay, () {
    _proxyReleaseTimers.remove(sessionId)?.cancel();
    MpvProxyServer.instance.unregister(sessionId);
  });
  ```
- 建议方向: 在 dispose 中遍历 `_proxyReleaseTimers.values` 取消并清空；需要保留释放语义时，先同步 unregister 待释放 session，再清理 Timer。
- 状态: 已确认

### [D-014] 系统媒体命令回调未防护 dispose/退出状态
- 级别: P1
- 分类: Bug / 约束违规(P7)
- 位置: lib/player/page_parts/core/mpv_player_system_session_mixin.dart:4
- 问题: 系统媒体会话命令 handler 直接执行 play/pause/seek/切集，没有先检查 `mounted` 或 `_exitInProgress`。页面 dispose 中注销 handler 是 `unawaited`，若系统命令在退出窗口内到达，仍可能操作已销毁页面的 controller 或触发切集链路。代码摘录：
  ```dart
  Future<void> _handleSystemPlaybackMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'systemPlay':
        await _controller.play();
        return;
      ...
      case 'systemSkipToNext':
        await _showNextEpisode();
  ```
- 建议方向: handler 入口先判断 `mounted && !_exitInProgress`；dispose 时尽量 await/串行注销，或让 bridge 在解绑后丢弃旧 owner 的命令。
- 状态: 已确认

### [D-015] 系统媒体封面 URL/鉴权直接绑定 NasProvider
- 级别: P1
- 分类: 可扩展性 / 耦合 / 约束违规(C3)
- 位置: lib/player/page_parts/core/mpv_player_system_session_mixin.dart:292
- 问题: 系统媒体会话封面构建直接读取 `NasProvider.baseUrl/token`，并用 NAS/飞牛图片 header 规则拼 URL。公共播放器系统会话因此假设单一后端。代码摘录：
  ```dart
  final baseUrl = context.read<NasProvider>().baseUrl;
  return ApiUrlHelper.imageCandidates(baseUrl, rawPath, width: 480);
  ...
  final token = context.read<NasProvider>().token.trim();
  final headers = Map<String, String>.of(
    nasImageHeaders(token, url: artworkUrl),
  );
  ```
- 建议方向: 由 media backend 或 source model 提供已解析的 artwork URL/header 候选；系统会话只消费后端无关的媒体元数据。
- 状态: 已确认

### [D-016] 连续清晰度切换缺少代次保护，旧 reload 可覆盖新选择
- 级别: P0
- 分类: Bug
- 位置: lib/player/page_parts/view/mpv_player_options_mixin.dart:149
- 问题: `_switchQuality` 对用户连续选择清晰度没有 in-flight 互斥或 generation 校验；各 reload 分支异步获取流信息后会直接 `_updatePlayerState` 并 `reload`。旧请求晚返回时会把当前播放源切回旧清晰度。代码摘录：
  ```dart
  Future<void> _switchQuality(
    PlaybackQualityOption quality, {
    String? loadingMessage,
  }) async {
    ...
    if (_currentSourceIsDownloadedFile && localDownloadRecord != null) {
      await _reloadDownloadedLocalQuality(...);
    } else if (_isDirectPlaybackQuality(quality)) {
      await _reloadDirectPlayback(...);
    } else {
      await _reloadServerPlaySession(...);
    }
  ```
- 建议方向: 为质量切换分配 generation，所有 reload 分支在网络返回后、写状态前、调用 `_controller.reload` 前校验仍是最新请求；或在切换期间禁用新的质量选择。
- 状态: 已确认

### [D-017] 播放操作菜单直接调用 FeiniuApi 切换质量和下载字幕
- 级别: P1
- 分类: 可扩展性 / 耦合 / 约束违规(C2)
- 位置: lib/player/page_parts/view/mpv_player_options_mixin.dart:269
- 问题: view/options mixin 直接创建飞牛 API，覆盖本地下载质量元数据补齐、直链播放、服务端播放会话、字幕轨刷新和字幕下载等用户操作路径。代码摘录：
  ```dart
  final api = FeiniuApi(context.read<NasProvider>());
  ...
  final playbackStream = await api.getPlaybackStream(directMediaGuid);
  final trackData = await api.getStreamTrackData(_currentItemGuid);
  ...
  final text = await api.downloadSubtitleText(guid);
  ```
- 建议方向: 通过 player source/controller 的后端无关接口完成质量切换和字幕下载；options mixin 只负责收集用户选择和展示反馈。
- 状态: 已确认

### [D-018] 下载元数据超时/失败被空 catch 静默吞掉
- 级别: P2
- 分类: 可维护性 / 约束违规(M4)
- 位置: lib/player/page_parts/view/mpv_player_options_mixin.dart:231
- 问题: 本地下载清晰度切换时，播放信息和轨道信息查询失败会直接返回 null，没有记录超时、guid 或异常；后续只能以缺失元数据的 fallback 继续，排查质量/字幕不匹配困难。代码摘录：
  ```dart
  try {
    return await loader().timeout(_downloadedPlaybackMetadataLookupTimeout);
  } catch (_) {
    return null;
  }
  ```
- 建议方向: 对 timeout/API 失败记录 debug 或 warning 日志，附当前 itemGuid、目标 quality 和 loader 类型；仍可保留 fallback 行为。
- 状态: 已确认

### [D-019] 播放器视图层残留硬编码英文可见/无障碍文案
- 级别: P2
- 分类: 可维护性 / 约束违规(M3)
- 位置: lib/player/page_parts/view/mpv_player_view_mixin.dart:120
- 问题: skip prompt 标签和云盘模式抽屉 barrierLabel 使用硬编码英文，没有走 `AppLocalizations`；这些会直接进入 UI 或无障碍语义。代码摘录：
  ```dart
  label: _uiController.activeChapterSkipPrompt == null
      ? ''
      : (_uiController.activeChapterSkipPrompt!.isIntro
            ? 'Intro'
            : 'Outro'),
  ...
  barrierLabel: 'cloud drive mode drawer',
  ```
- 建议方向: 新增本地化 getter，或复用已有片头/片尾、云盘模式文案；无障碍 label 也应由 l10n 提供。
- 状态: 已确认

### [D-020] 截图失败 catch 未记录异常细节
- 级别: P2
- 分类: 可维护性 / 约束违规(M4)
- 位置: lib/player/page_parts/view/mpv_player_view_mixin.dart:1202
- 问题: 截图流程捕获未知异常后只显示泛化提示，没有记录异常、栈或 savePathMode/includeSubtitles 等上下文，用户反馈截图失败时无法诊断原生层、权限还是路径问题。代码摘录：
  ```dart
  } catch (_) {
    if (!mounted) return;
    _showTopTip(
      AppLocalizations.of(context).playerScreenshotFailed,
      context.appColors.warning,
    );
  }
  ```
- 建议方向: 改为捕获 `error, stackTrace` 并通过 `AppErrorReporter` 或日志服务记录截图参数和异常，同时保留现有用户提示。
- 状态: 已确认

### [D-021] controller 反向依赖播放器 panel UI 类型
- 级别: P2
- 分类: 耦合 / 约束违规(C1)
- 位置: lib/player/controllers/episode_picker_presenter.dart:6
- 问题: `controllers` 层直接 import `panels/episode_picker_sheet.dart`，让 presenter 返回 UI panel 的数据类型，形成 controller → UI 的反向依赖。代码摘录：
  ```dart
  import '../panels/episode_picker_sheet.dart';
  ...
  List<TvEpisodeSeasonOptionData> buildEpisodePickerSeasonOptions(
  ...
  EpisodePickerSheetItem buildEpisodePickerSheetItem(
  ```
- 建议方向: 将 `EpisodePickerSheetItem` / `TvEpisodeSeasonOptionData` 等纯数据结构下沉到 `models` 或 controller 自有 model，panel 只消费这些 model。
- 状态: 已确认

### [D-022] 选集 presenter 默认英文文案可绕过 AppLocalizations
- 级别: P2
- 分类: 可维护性 / 约束违规(M3)
- 位置: lib/player/controllers/episode_picker_presenter.dart:17
- 问题: `EpisodePickerPresenterLabels` 默认构造函数内置英文 UI 文案，且多个 builder 参数默认使用 `const EpisodePickerPresenterLabels()`；调用方一旦漏传 `fromL10n` 就会把英文硬编码展示到 UI。代码摘录：
  ```dart
  const EpisodePickerPresenterLabels({
    this.episodeList = 'Episode list',
    this.specialSeason = 'Specials',
    this.seasonTemplate = 'Season {season}',
    this.playing = 'Playing..',
    this.watched = 'Watched',
  });
  ```
- 建议方向: 移除展示文案默认值，要求调用方显式传入 l10n labels；测试需要默认值时应放在测试 helper 中。
- 状态: 已确认

### [D-023] native 命令失败被 _invoke 吞掉，调用方会误判操作成功
- 级别: P1
- 分类: Bug / 可维护性 / 约束违规(M4)
- 位置: lib/player/controllers/mpv_player_controller.dart:1632
- 问题: `_invoke` 捕获 `PlatformException` 后只写入 controller error，不重新抛出或返回失败状态；`reload`、切轨、调速、seek 等上层 `await` 后无法知道 native 拒绝了命令，会继续执行“切源/切质量已开始”等后续状态更新。代码摘录：
  ```dart
  Future<void> _invoke(String method, [Object? arguments]) async {
    final channel = _methodChannel;
    if (channel == null) return;
    try {
      await channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      return;
    } on PlatformException catch (error) {
      _setError(error.message ?? error.code);
    }
  }
  ```
- 建议方向: 对需要可靠完成语义的命令返回 `bool`/结果对象或重新抛出异常，让 source/quality/track 切换链路能中止并回滚 UI 状态；只对明确可忽略的 teardown race 单独吞掉。
- 状态: 已确认

### [D-024] 重新 attach 时旧 EventChannel 事件可能串入新播放器实例
- 级别: P0
- 分类: Bug / 性能
- 位置: lib/player/controllers/mpv_player_controller.dart:1225
- 问题: `attach` 发现已有订阅时异步取消但不等待，随后立即把 `_eventSubscription` 指向新流；旧流在 cancel 完成前仍可调用同一个 `_handleEvent`，而事件没有携带 viewId/generation 校验，可能把旧 PlatformView 的播放状态或弹幕遮挡状态发布到新播放器。代码摘录：
  ```dart
  final previousSubscription = _eventSubscription;
  if (previousSubscription != null) {
    unawaited(_cancelSubscription(previousSubscription));
  }
  ...
  _eventSubscription = _eventChannel!.receiveBroadcastStream().listen(
    _handleEvent,
    onError: _handleError,
  );
  ```
- 建议方向: attach 引入递增 generation/viewId token，事件 handler 应闭包捕获 token 并丢弃非当前流事件；或串行等待旧订阅取消后再接新流。
- 状态: 已确认

### [D-025] MpvPlayerController 内直接创建平台通道并散落 method 字符串
- 级别: P2
- 分类: 耦合 / 约束违规(C5)
- 位置: lib/player/controllers/mpv_player_controller.dart:1227
- 问题: controller 直接 new `MethodChannel` / `EventChannel`，并在同一文件散落 native 方法名字符串；通道创建与契约字符串没有收敛到明确 bridge/service，后续修改 native 契约需要跨 controller 搜索。代码摘录：
  ```dart
  _methodChannel = MethodChannel('fly_player/mpv_view_$viewId/methods');
  _eventChannel = EventChannel('fly_player/mpv_view_$viewId/events');
  ...
  await _invoke('load', source.toMap());
  return _invoke('setAudioTrack', <String, Object?>{
  ```
- 建议方向: 将 mpv view channel 封装为专职 bridge/service，统一定义通道名模板、event 类型和 method 名；controller 只依赖类型化接口。
- 状态: 已确认

### [D-026] controller 状态文案硬编码英文并直接展示到状态卡
- 级别: P2
- 分类: 可维护性 / 约束违规(M3)
- 位置: lib/player/controllers/mpv_player_controller.dart:910
- 问题: `MpvPlayerValue.statusText` 默认值、seek 状态和错误状态都写死英文；该字段会被播放器状态卡直接渲染，因此会绕过 `AppLocalizations`。代码摘录：
  ```dart
  statusText = 'Preparing player',
  ...
  statusText: 'Seeking',
  ...
  statusText: 'Player error',
  ```
- 建议方向: controller 输出枚举/状态码或由页面传入本地化后的文案；状态卡渲染前统一通过 l10n 映射。
- 状态: 已确认

### [D-027] 片头片尾提示 dismiss 统计没有任何可观察输出
- 级别: P2
- 分类: Bug / 可维护性 / 约束违规(M5)
- 位置: lib/player/controllers/play_stats_session_controller.dart:400
- 问题: `recordOpEdDismiss` 最终只把 `_TrackedOpEdState.dismissed` 置为 true，但 `snapshotAtFinish` 没有读取该字段，`OpEdSnapshot`/`PlayHistoryRecord` 也没有 dismiss 字段，导致“用户忽略片头/片尾提示”这一统计入口无持久化效果。代码摘录：
  ```dart
  void markDismiss({required bool intro}) {
    final state = intro ? _intro : _outro;
    if (state == null) return;
    state.dismissed = true;
  }
  ...
  bool dismissed = false;
  ```
- 建议方向: 如果需要统计忽略行为，应在 snapshot/history model 中显式持久化；如果不需要，删除 `recordOpEdDismiss`/`dismissed` 死状态，避免调用方误以为该行为已被统计。
- 状态: 已确认

### [D-028] 手势 controller 反向依赖 widgets 层类型
- 级别: P2
- 分类: 耦合 / 约束违规(C1)
- 位置: lib/player/controllers/player_gesture_controller.dart:5
- 问题: `controllers` 层直接 import `../widgets/...`，并使用其中的 `PlayerAdjustmentOverlayData`、`PlayerAdjustmentType`、`PlayerSystemController`，形成 controller → widgets 的反向依赖；其中系统控制桥接还被放在 widgets 文件里，使手势状态机与 UI 文件边界纠缠。代码摘录：
  ```dart
  import '../widgets/player_gesture_overlay.dart';
  import '../widgets/player_system_controls.dart';
  ...
  final PlayerSystemController _systemController;
  PlayerAdjustmentOverlayData? _gestureOverlayData;
  ```
- 建议方向: 将纯数据模型和系统控制接口下沉到 `models`/`services` 或 controller 自有文件，widgets 只消费 controller 输出，不被 controller import。
- 状态: 已确认

### [D-029] 手势基线异步读取返回后可能写入已 dispose 的 notifier
- 级别: P0
- 分类: Bug / 资源泄漏 / 约束违规(P7)
- 位置: lib/player/controllers/player_gesture_controller.dart:280
- 问题: `_syncAdjustmentBaseline` 在 `await _systemController.readSnapshot()` 后没有 disposed 标记检查；如果用户开始亮度/音量手势后立即退出播放器，`dispose` 会释放 `_overlayRevision`，但异步返回后仍可能执行 `_notifyOverlayChanged()`，对已 dispose 的 `ValueNotifier` 写值会触发运行时异常。代码摘录：
  ```dart
  final snapshot = await _systemController.readSnapshot();
  if (_adjustmentSessionId != sessionId || _activeAdjustmentType != type) {
    return;
  }
  ...
  _gestureOverlayData = PlayerAdjustmentOverlayData(
    type: type,
    value: baseline,
  );
  _notifyOverlayChanged();
  ```
- 建议方向: controller 增加 `_disposed` 标记，`dispose` 时递增 session/清空 active，并在所有 await 返回后先检查 disposed；或让异步读取可取消。
- 状态: 已确认

### [D-030] 播放设置 controller 残留未引用的公开 UI 文案 helper
- 级别: P2
- 分类: 可维护性 / 约束违规(M3/M5)
- 位置: lib/player/controllers/player_settings_controller.dart:68
- 问题: `playbackMonitorStatusLabel` 和 `decoderSwitchMessage` 是公开方法且返回硬编码英文 UI 文案，但代码库内没有调用点；同一文件的 `introOutroMode` 也只写不读。这类残留会误导后续调用方绕过 `AppLocalizations`，并让设置状态来源变得不清晰。代码摘录：
  ```dart
  String playbackMonitorStatusLabel() {
    return performanceOverlayEnabled ? 'Partially enabled' : 'Off';
  }

  String decoderSwitchMessage(String modeLabel) {
    return 'Switching to $modeLabel. Please wait...';
  }
  ```
- 建议方向: 删除未引用 helper 和死状态；若未来仍需要这些展示文案，应放回 UI 层并通过 l10n getter 获取。
- 状态: 已确认

### [D-031] 播放源核心 controller 直接绑定 FeiniuApi
- 级别: P1
- 分类: 耦合 / 可扩展性 / 约束违规(C3)
- 位置: lib/player/controllers/player_source_controller.dart:4
- 问题: `PlayerSourceController` 是播放器核心源构建/重载入口，但公开方法直接要求 `FeiniuApi`，并用它创建服务端播放会话、拼 URL、构造 headers；这会让 Emby/Jellyfin 等后端无法复用同一源控制器，只能继续在核心链路里扩散具体后端分支。代码摘录：
  ```dart
  import '../../api/feiniu_api.dart';
  ...
  Future<PlayerInitialPlaybackResult> buildInitialPlaybackResult({
    required FeiniuApi api,
  ...
  Future<PlayerServerReloadResult> reloadServerPlaySession({
    required FeiniuApi api,
  ```
- 建议方向: 将后端差异收敛到 media backend/source bridge，`PlayerSourceController` 只依赖类型化的播放源服务接口（创建会话、取轨道、取 headers/URL）。
- 状态: 已确认

### [D-032] 播放源 controller 残留未引用的英文质量切换文案
- 级别: P2
- 分类: 可维护性 / 约束违规(M3/M5)
- 位置: lib/player/controllers/player_source_controller.dart:792
- 问题: `qualitySwitchMessageFor` 是公开静态 helper，返回硬编码英文 UI 文案；当前代码库没有调用它，实际 UI 已在 options mixin 通过 l10n 生成同类文案，保留这个 helper 容易让后续调用方回退到未本地化路径。代码摘录：
  ```dart
  static String qualitySwitchMessageFor(PlaybackQualityOption quality) {
    final title = quality.resolution.trim().isNotEmpty
        ? quality.resolution.trim()
        : (quality.isDefault == 1 ? 'Original' : 'Quality');
    ...
    return 'Switching to $title$bitrate quality. Please wait...';
  }
  ```
- 建议方向: 删除未引用 helper；若需要公共展示格式，应迁移到 UI/presenter 层并强制传入 l10n。
- 状态: 已确认

### [D-033] 字幕 controller 残留未引用的英文 UI 文案 helper
- 级别: P2
- 分类: 可维护性 / 约束违规(M3)
- 位置: lib/player/controllers/player_subtitle_controller.dart:284
- 问题: `subtitleSearchLanguageLabel` 和 `subtitleDrawerSwitchMessageForTrack` 返回硬编码英文展示文案；生产 UI 已在 settings subtitle mixin 中使用 l10n 版本，但这些 controller helper 仍作为公开接口存在且被测试覆盖，后续误用会绕过本地化。代码摘录：
  ```dart
  String subtitleSearchLanguageLabel(String language) {
    switch (language) {
      case 'en':
        return 'English';
      case 'zh-CN':
      default:
        return 'Chinese';
    }
  }
  ```
- 建议方向: 删除 controller 内的展示文案 helper，或改为要求调用方传入 l10n formatter；保留纯状态/格式推断逻辑。
- 状态: 已确认

### [D-034] 弱网提示详情在 controller 工具函数中硬编码中文
- 级别: P2
- 分类: 可维护性 / 约束违规(M3)
- 位置: lib/player/controllers/weak_network_quality_recommender.dart:65
- 问题: `buildWeakNetworkBufferingDetails` 直接拼接中文“当前网速/预计恢复”，并被播放反馈和弱网建议 UI 调用，导致英文等语言环境下仍展示中文。代码摘录：
  ```dart
  final speedLabel = formatWeakNetworkSpeedLabel(networkSpeedBytesPerSecond);
  final etaLabel = _formatWeakNetworkEta(estimatedResumeWait);
  if (etaLabel == null) {
    return '当前网速 $speedLabel';
  }
  return '当前网速 $speedLabel · 预计恢复 $etaLabel';
  ```
- 建议方向: 该函数只返回结构化数值（速度、ETA）或接受 l10n formatter；实际展示文案由调用处通过 `AppLocalizations` 生成。
- 状态: 已确认

### [D-035] 通用 mpv 代理服务仍绑定 FeiniuApi 且注册入口未接入
- 级别: P2
- 分类: 耦合 / 可维护性 / 约束违规(C3/M5)
- 位置: lib/player/services/mpv_proxy_server.dart:26
- 问题: `MpvProxyServer` 命名为通用播放器代理服务，但注册接口直接要求 `FeiniuApi` 并用它签名 headers；同时代码库内没有任何 `registerStream` 调用，只有播放器清理路径在调用 `unregister`，该服务目前像是未接入的 Feiniu 专用残留。代码摘录：
  ```dart
  Future<MpvProxyRegistration> registerStream({
    required FeiniuApi api,
    required String remoteUrl,
  }) async {
    ...
    _sessions[sessionId] = _ProxySession(
      api: api,
      remoteUri: remoteUri,
  ```
- 建议方向: 若本地代理仍需要保留，应改为依赖后端无关的 header signer/source adapter，并补齐注册调用与生命周期；若已被 native proxy 替代，应删除该未接入路径和对应清理调用。
- 状态: 已确认

### [D-036] 字幕样式记录解码失败被空 catch 静默丢弃
- 级别: P2
- 分类: 可维护性 / 约束违规(M4)
- 位置: lib/player/services/player_runtime_preferences_store.dart:259
- 问题: 读取字幕样式记录 JSON 时，任何解析异常都会直接返回空 map，没有记录损坏的 key、异常或原始长度；下一次保存会基于空集合覆盖旧记录，排查用户字幕样式记忆丢失会缺少证据。代码摘录：
  ```dart
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return <String, Object?>{};
    return decoded.map(
      (key, value) => MapEntry(key.toString(), _normalizeRecordMap(value)),
    );
  } catch (_) {
    return <String, Object?>{};
  }
  ```
- 建议方向: 捕获 `error, stackTrace` 并记录 warning，附 pref key 与 raw 长度；如果要重置损坏数据，应显式迁移/清理而不是静默覆盖。
- 状态: 已确认

### [D-037] 字幕服务直接依赖 FeiniuApi，远程字幕能力无法替换后端
- 级别: P1
- 分类: 耦合 / 可扩展性 / 约束违规(C3)
- 位置: lib/player/services/player_subtitle_service.dart:6
- 问题: `PlayerSubtitleService` 是播放器字幕服务，但搜索/下载远程字幕的公开接口直接要求 `FeiniuApi`；Emby/Jellyfin 或独立字幕源接入时无法复用该服务，只能在 UI/settings 链路继续扩散具体后端 API。代码摘录：
  ```dart
  import '../../api/feiniu_api.dart';
  ...
  Future<List<RemoteSubtitleSearchItem>> searchRemoteSubtitles({
    required FeiniuApi api,
    required String mediaGuid,
  ...
  Future<SubtitleTrackOption> downloadRemoteSubtitleTrack({
    required FeiniuApi api,
  ```
- 建议方向: 定义后端无关的 remote subtitle provider/adapter，由 Feiniu 实现放在后端桥接层；播放器字幕服务只依赖抽象接口和统一字幕模型。
- 状态: 已确认

### [D-038] 书签 JSON 解析失败被空 catch 静默吞掉
- 级别: P2
- 分类: 可维护性 / 约束违规(M4)
- 位置: lib/player/stores/bookmark_store.dart:149
- 问题: 书签持久化数据解析失败时直接返回空列表，没有记录异常、pref key 或 raw 长度；用户书签损坏/丢失时无法判断是 JSON 损坏、字段迁移还是 SharedPreferences 读写问题。代码摘录：
  ```dart
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <PlayerBookmarkEntry>[];
    ...
    return entries;
  } catch (_) {
    return <PlayerBookmarkEntry>[];
  }
  ```
- 建议方向: 记录 warning 级日志并保留诊断上下文；必要时把损坏数据迁移到备份 key 后再重置，避免静默“看起来像没有书签”。
- 状态: 已确认

### [D-039] 音频 EQ 预设解析失败被空 catch 静默吞掉
- 级别: P2
- 分类: 可维护性 / 约束违规(M4)
- 位置: lib/player/stores/mpv_audio_eq_preset_store.dart:58
- 问题: 自定义 EQ 预设 JSON 解析异常会直接返回空列表，没有任何日志；随后保存新预设会覆盖旧集合，用户自定义音效丢失无法追踪。代码摘录：
  ```dart
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <MpvAudioEqPresetEntry>[];
    return decoded
        .whereType<Map>()
        ...
  } catch (_) {
    return <MpvAudioEqPresetEntry>[];
  }
  ```
- 建议方向: 捕获 `error, stackTrace` 并记录 pref key/raw 长度；遇到损坏数据时考虑保留备份，避免下一次保存覆盖。
- 状态: 已确认

### [D-040] 截图设置 store 内置英文展示标签但没有 l10n 路径
- 级别: P2
- 分类: 可维护性 / 约束违规(M3/M5)
- 位置: lib/player/stores/screenshot_settings_store.dart:33
- 问题: `ScreenshotSettingsStore` 在 store 层保存 `Pictures`、`Custom folder`、`With subtitles` 等英文展示文案；生产 UI 当前只使用 `savePathOptions.value` 并自行走 l10n，但这些 label/description/helper 公开保留会诱导后续 UI 直接读取 store 文案并绕过 `AppLocalizations`。代码摘录：
  ```dart
  ScreenshotSavePathOption(
    value: 'pictures',
    label: 'Pictures',
    description: 'Save to Pictures/FlyPlayer.',
  ),
  ...
  String subtitleModeLabel(bool includeSubtitles) {
    return includeSubtitles ? 'With subtitles' : 'Image only';
  }
  ```
- 建议方向: store 只保留 value/default 等持久化语义；展示 label/description 放到 UI presenter 或 l10n mapper，并删除未被生产 UI 使用的英文 helper。
- 状态: 已确认

### [D-041] mpv 设置 catalog 在 store 中硬编码大量英文 UI 文案
- 级别: P2
- 分类: 可维护性 / 约束违规(M3)
- 位置: lib/player/stores/mpv_settings_store.dart:386
- 问题: `MpvSettingsCatalog` 同时承载设置定义和可见文案，内置大量英文 preset/category/option/warning/recommendation 文案；虽然存在 `MpvSettingsL10n` 包装，但当前代码仍有直接调用 `MpvSettingsCatalog.performanceWarningForSelection`、`recommendScenePreset` 的路径，用户可见文案会绕过 l10n。代码摘录：
  ```dart
  MpvSettingPreset(
    id: 'anime',
    label: 'Anime Clear',
    description: 'Light contrast and saturation tuning for line art.',
    settings: <String, String>{},
  ),
  ...
  title: 'Stable profile recommended',
  reason: 'Detected ${reasons.join(', ')}. Use a lighter stable profile first.',
  ```
- 建议方向: catalog 只保留稳定 id、key、默认值和算法；所有 label/description/warning/recommendation 文案统一由 `MpvSettingsL10n` 或 ARB getter 生成，并消除直接访问 catalog 文案的调用点。
- 状态: 已确认

### [D-042] mpv_settings_store 同时承担 catalog、推荐算法与持久化，文件过大
- 级别: P2
- 分类: 可维护性 / 约束违规(M1/C6)
- 位置: lib/player/stores/mpv_settings_store.dart:252
- 问题: 单文件 2290 行，混合了设置元数据 catalog、内置预设、场景推荐算法、性能警告、显示文案格式化、SharedPreferences 持久化和自定义预设 CRUD；任一 mpv 设置改动都要在同一个巨大 store 中穿梭，维护成本高。代码摘录：
  ```dart
  class MpvSettingsCatalog {
    static const List<MpvSettingPreset> builtInPicturePresets =
        <MpvSettingPreset>[
    ...
    static MpvScenePresetRecommendation? recommendScenePreset({
  ...
  class MpvSettingsStore {
    Future<MpvSettingsBundle> loadBundle() async {
  ```
- 建议方向: 拆为 catalog 数据、推荐/警告规则、展示文案 mapper、SharedPreferences store、saved preset repository 等文件；让 store 只负责读写。
- 状态: 已确认

### [D-043] 已保存 mpv 预设解析失败被空 catch 静默吞掉
- 级别: P2
- 分类: 可维护性 / 约束违规(M4)
- 位置: lib/player/stores/mpv_settings_store.dart:2086
- 问题: 自定义 mpv 预设读取时解析异常直接返回空列表，没有日志；随后保存/重命名会基于空集合继续，可能把用户保存的画面/音频预设静默清空。代码摘录：
  ```dart
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <SavedMpvPreset>[];
    ...
    return result;
  } catch (_) {
    return const <SavedMpvPreset>[];
  }
  ```
- 建议方向: 记录异常并保留损坏数据备份；对迁移失败、格式不兼容和真实空列表做可区分处理。
- 状态: 已确认

### [D-044] player model 反向依赖 controller 与 play_stats mapper
- 级别: P2
- 分类: 耦合 / 约束违规(C1)
- 位置: lib/player/models/player_host_launch_args.dart:1
- 问题: `player_host_launch_args.dart` 位于 models 层，却 import `controllers/mpv_player_controller.dart` 获取 `MpvMediaSource`，并 import play_stats service mapper 做枚举序列化；这让 model 层依赖上层 controller 和服务实现，打破“controller/service 依赖 model”的方向。代码摘录：
  ```dart
  import '../controllers/mpv_player_controller.dart';
  import '../../models/play_info.dart';
  import '../../services/play_stats/play_stats.dart';
  ...
  final MpvMediaSource source;
  ```
- 建议方向: 将 `MpvMediaSource` 下沉到 player models，或为 launch args 定义纯 DTO；startSource 的文本转换应放到 mapper/adapter 层，model 只保存枚举或原始字段。
- 状态: 已确认

## 总结

- 共确认 44 条问题，未撤回。
- 优先处理 P0：连续切集/切源/切清晰度竞态（D-005/D-008/D-016）、EventChannel 重挂载串流（D-024）、手势异步返回写已释放 notifier（D-029）。
- 多后端扩展的主要阻塞集中在播放器核心仍直接绑定 `FeiniuApi`/`NasProvider`：选集、runtime、options、source controller、subtitle service、proxy service。
- 平台通道收敛问题集中在播放器页面与 `MpvPlayerController`，建议统一 bridge/service 接口后再清理裸 method 字符串。
- i18n 回潮集中在 controller/store/catalog 层输出 UI 文案，尤其 mpv settings catalog、弱网详情、截图/字幕/质量切换 helper。
- 持久化 store 普遍存在 JSON 解析空 catch，建议统一日志与损坏数据备份策略。
