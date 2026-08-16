import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Locale;

import '../danmaku/settings/danmaku_settings_store.dart';
import '../l10n/generated/app_localizations.dart';
import '../media_backend/playback/media_session_reload.dart';
import '../playback/settings/mpv_settings_store.dart';
import '../providers/app_locale_provider.dart';
import '../providers/nas_provider.dart';
import 'app_log_service.dart';
import 'native_artwork_prefetch.dart';
import 'native_danmaku_prefetch.dart';
import 'native_player_localized_strings.dart';
import 'native_reentry_support.dart';

/// 启动纯原生播放壳（`NativePlayerActivity`）的桥。
///
/// 渐进原生化：Flutter 编排层（详情页 launcher）解析好 source、拉好弹幕后，用它把
/// 播放交给原生壳——视频(SurfaceView) + 弹幕(原生 Canvas) + 控制(原生 View) 全在原生
/// 层级，没有 Flutter overlay 的 Hybrid Composition，弹幕可 120fps 丝滑、二级界面不卡。
class NativePlayerBridge {
  const NativePlayerBridge._();

  static const bool preferNativePlayerShell = true;

  static const MethodChannel _channel = MethodChannel(
    'fly_player/native_player',
  );

  /// 当前反向通道的持有者标识。bindReentry 是全局单 handler（最近注册的入口生效），
  /// 用 token 让 unbindReentry 只清「自己仍是当前持有者」的情形，避免旧入口 dispose
  /// 误清最新入口刚注册的 handler。
  static Object? _activeBindToken;

  /// 启动原生播放壳。
  ///
  /// - [loadArgs]：`MpvMediaSource.toMap()`，含 `url` 等，即 `controller.load` 的入参。
  /// - [danmakuFilePath]：弹幕 payload 的临时 JSON 文件路径（可选）。弹幕量大，走文件
  ///   而非 Intent extra，避开 Binder 的 `TransactionTooLarge`。
  static Future<void> launch({
    required Map<String, dynamic> loadArgs,
    String? danmakuFilePath,
    List<Map<String, dynamic>>? episodes,
    Map<String, dynamic>? initialPlayInfo,
    String? startSource,
    int? introDurationSeconds,
    int? outroDurationSeconds,
    NasProvider? nas,
  }) async {
    // episodes 合并进 loadArgs（原生壳从 loadArgsMap["episodes"] 取，供本地弹"选集"
    // 对话框，无需再反向请求列表）。不污染 source.toMap() 本身。
    final mergedArgs = <String, dynamic>{
      ...loadArgs,
      if (episodes != null && episodes.isNotEmpty) 'episodes': episodes,
      if (initialPlayInfo != null) 'initialPlayInfo': initialPlayInfo,
      if (startSource != null) 'startSource': startSource,
      if (introDurationSeconds != null)
        'introDurationSeconds': introDurationSeconds,
      if (outroDurationSeconds != null)
        'outroDurationSeconds': outroDurationSeconds,
    };
    // MPV 画质/画面调整：注入 Flutter「MPV播放器设置」页的当前值（含快速预设/保存预设的应用
    // 结果）。原生壳是独立 task、读不到本地引擎的 SharedPreferences，靠这里随 payload 带过去，
    // 据此覆盖本地镜像 → 设置页的改动在原生播放直接生效（原生壳内改动经反向通道回写，双向同步）。
    try {
      final mpvBundle = await const MpvSettingsStore().loadBundle();
      mergedArgs['mpvAdvancedSettings'] = mpvBundle.settings;
      mergedArgs['videoAdjustments'] = mpvBundle.videoAdjustments;
    } catch (_) {
      // 读取失败则不注入，原生壳回退到自身已存的镜像。
    }
    // 弹幕显示偏好：同样以 Flutter 全局设置为单一事实源注入原生壳（透明度/密度/字号/速度/
    // 区域/帧率/按类型屏蔽…）。原生壳内改动经反向通道 persistDanmakuSettings 回写，双向同步。
    try {
      final danmaku = await const DanmakuSettingsStore().load();
      mergedArgs['danmakuDisplaySettings'] = <String, Object?>{
        'opacity': danmaku.opacity,
        'density': danmaku.density,
        'fontScale': danmaku.fontScale,
        'fontThickness': danmaku.fontThickness,
        'speed': danmaku.speed,
        'displayAreaRatio': danmaku.displayAreaRatio,
        'targetFrameRateHz': danmaku.targetFrameRateHz,
        'scrollEnabled': danmaku.scrollEnabled,
        'topEnabled': danmaku.topEnabled,
        'bottomEnabled': danmaku.bottomEnabled,
        'colorEnabled': danmaku.colorEnabled,
        'hideDuplicate': danmaku.hideDuplicate,
        'avoidSubtitleArea': danmaku.avoidSubtitleArea,
      };
    } catch (_) {
      // 读取失败则不注入，原生壳回退到自身已存的镜像。
    }
    // 原生壳文案：以 Flutter l10n 为单一事实源注入（key=Android 资源条目名），使通知栏/
    // 播放器内文案跟随应用内语言设置而非系统语言。原生缺表时回退自带的 strings.xml 兜底。
    try {
      mergedArgs['localizedStrings'] = await _loadLocalizedStrings();
    } catch (_) {
      // 注入失败原生壳回退 strings.xml 兜底。
    }
    // 封面离线预取：把网络封面缓存为本地文件，原生壳优先取本地路径（纯听背景/海报、
    // MediaSession 通知封面），断网也能显示。失败静默（原生回退网络 URL）。
    await _mergeArtworkLocalPath(mergedArgs, nas);
    await _channel.invokeMethod<void>('launch', <String, dynamic>{
      'loadArgs': jsonEncode(mergedArgs),
      if (danmakuFilePath != null && danmakuFilePath.isNotEmpty)
        'danmakuFile': danmakuFilePath,
    });
  }

  /// 绑定原生壳 → Flutter 的反向 handler。详情页 State 在发起原生壳前调用，注入「选集
  /// 解析」「进度回写」两个回调（回调持 BuildContext / NasProvider）。最近一次绑定生效
  /// （对齐 Kotlin 侧 host channel 的 attach 语义），State dispose 时 [unbindReentry]。
  static Object bindReentry({
    required Future<Map<String, dynamic>?> Function(
      String itemGuid, {
      int? qualityIndex,
      String? qualityMediaGuid,
      int? startPositionMs,
      String? subtitleGuid,
      String? audioGuid,
      int? audioTrackIndex,
      int? subtitleTrackIndex,
      String? preferredQualityResolution,
    })
    onResolvePlayback,
    required Future<void> Function(Map<String, dynamic> progress)
    onRecordProgress,
    Future<String?> Function(String guid, {String? format})?
    onResolveSubtitleFile,
    Future<Map<String, dynamic>?> Function(
      String currentLoadArgs,
      MediaSessionReloadIntent intent,
    )?
    onReloadServerSession,
    Future<Map<String, dynamic>?> Function(
      String currentLoadArgs, {
      String? seasonGuid,
    })?
    onLoadEpisodePickerData,
    Future<Map<String, dynamic>?> Function(String seasonGuid)?
    onLoadSeasonEpisodes,
    Future<bool> Function(String viewType)? onSetEpisodePickerViewType,
    Future<void> Function(Map<String, dynamic> args)? onLocalSubtitleImported,
    Future<void> Function(Map<String, dynamic> args)? onLocalSubtitleRemoved,
  }) {
    final token = Object();
    _activeBindToken = token;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'resolvePlayback':
          final args = (call.arguments as Map?) ?? const <Object?, Object?>{};
          final guid = (args['itemGuid'] ?? '').toString();
          if (guid.isEmpty) return null;
          debugPrint(
            '[DANMAKU][NATIVE_SWITCH] bridge resolvePlayback recv '
            'item="$guid" keys=${args.keys.toList()}',
          );
          final resolved = await onResolvePlayback(
            guid,
            qualityIndex: (args['qualityIndex'] as num?)?.toInt(),
            qualityMediaGuid: () {
              final v = (args['qualityMediaGuid'] ?? '').toString().trim();
              return v.isEmpty ? null : v;
            }(),
            startPositionMs: (args['startPositionMs'] as num?)?.toInt(),
            // 字幕重载（转码/服务端托管）：带 key 即为 override，空串=关闭字幕；
            // 不带 key（画质/选集）则 null=沿用服务端默认字幕。
            subtitleGuid: args.containsKey('subtitleGuid')
                ? (args['subtitleGuid'] ?? '').toString()
                : null,
            // 音轨重载（转码切音轨）：带 key 即 override；不带则沿用服务端默认音轨。
            audioGuid: args.containsKey('audioGuid')
                ? (args['audioGuid'] ?? '').toString()
                : null,
            // 切集按序号继承轨道（Bug B）：native 传当前音轨/字幕序号；字幕 -1=继承「关闭」。
            audioTrackIndex: (args['audioTrackIndex'] as num?)?.toInt(),
            subtitleTrackIndex: (args['subtitleTrackIndex'] as num?)?.toInt(),
            // 切集按分辨率继承画质：native（转码态）传当前分辨率；空=不继承，走默认梯度。
            preferredQualityResolution: () {
              final v = (args['preferredQualityResolution'] ?? '')
                  .toString()
                  .trim();
              return v.isEmpty ? null : v;
            }(),
          );
          final resultKeys = resolved?.keys.toList() ?? const <String>[];
          final danmakuFile = (resolved?['danmakuFile'] ?? '').toString();
          debugPrint(
            '[DANMAKU][NATIVE_SWITCH] bridge resolvePlayback done '
            'item="$guid" keys=$resultKeys danmakuFile=${danmakuFile.isNotEmpty}',
          );
          return resolved;
        case 'reloadServerSession':
          if (onReloadServerSession == null) return null;
          final args = (call.arguments as Map?) ?? const <Object?, Object?>{};
          final current = (args['loadArgs'] ?? '').toString();
          if (current.isEmpty) return null;
          // 把 channel 的「带 key=override / 空串=关闭 / 不带=保留」语义组装成中立意图：
          // audioGuid 带 key→切音轨，不带→保留；subtitleGuid 空串→关闭，非空→切轨，
          // 不带→保留；qualityIndex 不带→保留当前画质。
          final hasSubtitle = args.containsKey('subtitleGuid');
          final subtitleValue = hasSubtitle
              ? (args['subtitleGuid'] ?? '').toString()
              : null;
          final startMs = (args['startPositionMs'] as num?)?.toInt();
          return await onReloadServerSession(
            current,
            MediaSessionReloadIntent(
              audioTrackId: args.containsKey('audioGuid')
                  ? (args['audioGuid'] ?? '').toString()
                  : null,
              subtitleTrackId:
                  (subtitleValue != null && subtitleValue.isNotEmpty)
                  ? subtitleValue
                  : null,
              subtitleDisabled: subtitleValue == '',
              qualityIndex: (args['qualityIndex'] as num?)?.toInt(),
              startPosition: startMs != null
                  ? Duration(milliseconds: startMs)
                  : null,
            ),
          );
        case 'loadEpisodePickerData':
          if (onLoadEpisodePickerData == null) return null;
          final args = (call.arguments as Map?) ?? const <Object?, Object?>{};
          final current = (args['loadArgs'] ?? '').toString();
          if (current.isEmpty) return null;
          return await onLoadEpisodePickerData(
            current,
            seasonGuid: (args['seasonGuid'] ?? '').toString(),
          );
        case 'loadSeasonEpisodes':
          if (onLoadSeasonEpisodes == null) return null;
          final args = (call.arguments as Map?) ?? const <Object?, Object?>{};
          final seasonGuid = (args['seasonGuid'] ?? '').toString().trim();
          if (seasonGuid.isEmpty) return null;
          return await onLoadSeasonEpisodes(seasonGuid);
        case 'setEpisodePickerViewType':
          if (onSetEpisodePickerViewType == null) return false;
          final args = (call.arguments as Map?) ?? const <Object?, Object?>{};
          return await onSetEpisodePickerViewType(
            (args['viewType'] ?? '').toString(),
          );
        case 'resolveSubtitleFile':
          if (onResolveSubtitleFile == null) return null;
          final args = (call.arguments as Map?) ?? const <Object?, Object?>{};
          final guid = (args['guid'] ?? '').toString().trim();
          if (guid.isEmpty) return null;
          final format = () {
            final v = (args['format'] ?? '').toString().trim();
            return v.isEmpty ? null : v;
          }();
          return await onResolveSubtitleFile(guid, format: format);
        case 'recordProgress':
          final args = (call.arguments as Map?) ?? const <Object?, Object?>{};
          await onRecordProgress(
            args.map((key, value) => MapEntry(key.toString(), value)),
          );
          return null;
        case 'recordNativeLog':
          // 原生 mpv 内核的 error/warn 级日志 → 写进应用内日志，使设置→日志界面能看到
          // 播放内核报错。纯记录，不依赖 State/context。
          final args = (call.arguments as Map?) ?? const <Object?, Object?>{};
          final message = (args['message'] ?? '').toString().trim();
          if (message.isEmpty) return null;
          final prefix = (args['prefix'] ?? '').toString().trim();
          final source = (args['source'] ?? 'mpv').toString().trim();
          await AppLogService.instance.record(
            level: (args['level'] ?? 'error').toString() == 'warning'
                ? AppLogLevel.warning
                : AppLogLevel.error,
            error: message,
            source: source.isEmpty ? 'mpv' : source,
            details: prefix.isEmpty ? null : 'prefix=$prefix',
          );
          return true;
        case 'searchDanmakuSource':
          // 纯网络（DanDanPlay 检索），不依赖 State/context，直接处理。
          final args = (call.arguments as Map?) ?? const <Object?, Object?>{};
          return await NativeDanmakuPrefetch.searchCandidates(
            keyword: (args['keyword'] ?? '').toString(),
            episodeNumber: (args['episodeNumber'] as num?)?.toInt() ?? 0,
            tmdbId: (args['tmdbId'] ?? '').toString(),
          );
        case 'loadDanmakuEpisode':
          final args = (call.arguments as Map?) ?? const <Object?, Object?>{};
          final episodeId = (args['episodeId'] as num?)?.toInt() ?? 0;
          if (episodeId <= 0) return null;
          return await NativeDanmakuPrefetch.importEpisodeToFile(
            episodeId: episodeId,
            animeTitle: (args['animeTitle'] ?? '').toString(),
            episodeTitle: (args['episodeTitle'] ?? '').toString(),
            episodeNumber: (args['episodeNumber'] as num?)?.toInt() ?? 0,
          );
        case 'importDanmakuFile':
          // 原生壳已用 SAF 选好弹幕文件并拷到可读路径，这里解析并落 payload 文件回传。
          final args = (call.arguments as Map?) ?? const <Object?, Object?>{};
          final path = (args['path'] ?? '').toString().trim();
          if (path.isEmpty) return null;
          return await NativeDanmakuPrefetch.importLocalFileToFile(path);
        case 'listSavedDanmakuSources':
          // 原生壳弹幕源面板合并显示 Flutter 弹幕源库（随片下载/在线自动匹配注册的源）。
          final args = (call.arguments as Map?) ?? const <Object?, Object?>{};
          return await NativeDanmakuPrefetch.listSavedSources(
            itemGuid: (args['itemGuid'] ?? '').toString(),
            mediaGuid: (args['mediaGuid'] ?? '').toString(),
            seasonGuid: (args['seasonGuid'] ?? '').toString(),
            seasonNumber: (args['seasonNumber'] as num?)?.toInt() ?? 0,
            episodeNumber: (args['episodeNumber'] as num?)?.toInt() ?? 0,
            seriesTitle: (args['seriesTitle'] ?? '').toString(),
          );
        case 'loadSavedDanmakuSource':
          // 用户在原生面板点选某条 Flutter 弹幕源 → 按 sourceKey 加载成 payload 回传。
          final args = (call.arguments as Map?) ?? const <Object?, Object?>{};
          final sourceKey = (args['sourceKey'] ?? '').toString().trim();
          if (sourceKey.isEmpty) return null;
          return await NativeDanmakuPrefetch.loadSavedSourceToFile(
            sourceKey: sourceKey,
            itemGuid: (args['itemGuid'] ?? '').toString(),
            mediaGuid: (args['mediaGuid'] ?? '').toString(),
            seasonGuid: (args['seasonGuid'] ?? '').toString(),
            seasonNumber: (args['seasonNumber'] as num?)?.toInt() ?? 0,
            episodeNumber: (args['episodeNumber'] as num?)?.toInt() ?? 0,
            seriesTitle: (args['seriesTitle'] ?? '').toString(),
          );
        case 'setUseNativeRenderer':
          // 原生壳「切换到 Flutter 播放器」出口：持久化关闭原生渲染器开关（该开关 UI 只在
          // Flutter 播放器内，开启后每次播放都进原生壳，没有这个出口就回不去）。纯持久化、
          // 不依赖 State/context，任何 host 绑定时都能处理。
          final args = (call.arguments as Map?) ?? const <Object?, Object?>{};
          final enabled = args['enabled'] == true;
          const store = DanmakuSettingsStore();
          final current = await store.load();
          await store.save(current.copyWith(useNativeRenderer: enabled));
          return true;
        case 'persistMpvAdvanced':
          // 原生壳内改了画质/解码/EQ 等高级设置 → 回写 Flutter 全局 MPV 设置，使两端同步、
          // 下次进设置页/Flutter 播放器都是最新值。纯持久化（savePatch 自带白名单过滤）。
          final args = (call.arguments as Map?) ?? const <Object?, Object?>{};
          final patch = <String, String>{};
          args.forEach((key, value) {
            if (value != null) patch[key.toString()] = value.toString();
          });
          if (patch.isNotEmpty) {
            await const MpvSettingsStore().savePatch(patch);
          }
          return true;
        case 'persistVideoAdjustments':
          // 原生壳内改了亮度/对比度等画面调整 → 回写 Flutter 全局设置（saveVideoAdjustments
          // 自带 key 白名单 + 归一化）。
          final args = (call.arguments as Map?) ?? const <Object?, Object?>{};
          final adjustments = <String, double>{};
          args.forEach((key, value) {
            final asDouble = (value as num?)?.toDouble();
            if (asDouble != null) adjustments[key.toString()] = asDouble;
          });
          if (adjustments.isNotEmpty) {
            await const MpvSettingsStore().saveVideoAdjustments(adjustments);
          }
          return true;
        case 'persistDanmakuSettings':
          // 原生壳内改了弹幕显示偏好 → 回写 Flutter 全局弹幕设置，使设置页/Flutter 播放器
          // 同步。savePatch 只认显示偏好键，不动 enabled/source/AI 等。
          final args = (call.arguments as Map?) ?? const <Object?, Object?>{};
          final patch = <String, Object?>{};
          args.forEach((key, value) {
            if (value != null) patch[key.toString()] = value;
          });
          if (patch.isNotEmpty) {
            await const DanmakuSettingsStore().savePatch(patch);
          }
          return true;
        case 'loadPlayerGlobalSettings':
          // 原生壳前台恢复时主动拉最新的 Flutter 全局设置（MPV/画面/弹幕），让在别处（设置页/
          // Flutter 播放器）的改动回到原生壳即时生效，而非只在启动注入那一刻。
          final mpvBundle = await const MpvSettingsStore().loadBundle();
          final danmaku = await const DanmakuSettingsStore().load();
          final result = <String, dynamic>{
            'mpvAdvancedSettings': mpvBundle.settings,
            'videoAdjustments': mpvBundle.videoAdjustments,
            'danmakuDisplaySettings': <String, Object?>{
              'opacity': danmaku.opacity,
              'density': danmaku.density,
              'fontScale': danmaku.fontScale,
              'fontThickness': danmaku.fontThickness,
              'speed': danmaku.speed,
              'displayAreaRatio': danmaku.displayAreaRatio,
              'targetFrameRateHz': danmaku.targetFrameRateHz,
              'scrollEnabled': danmaku.scrollEnabled,
              'topEnabled': danmaku.topEnabled,
              'bottomEnabled': danmaku.bottomEnabled,
              'colorEnabled': danmaku.colorEnabled,
              'hideDuplicate': danmaku.hideDuplicate,
              'avoidSubtitleArea': danmaku.avoidSubtitleArea,
            },
          };
          // 原生壳前台恢复时一并刷新文案：覆盖播放中途切换应用语言的场景，不必等下次
          // 重新 launch。读取失败则不带该字段，原生壳保留已安装的旧表。
          try {
            result['localizedStrings'] = await _loadLocalizedStrings();
          } catch (_) {
            // 忽略，保留原生壳已安装的旧表。
          }
          return result;
        case 'listSavedMpvPresets':
          // 原生壳画质/音频抽屉里列出 Flutter「保存预设」供选择。
          final args = (call.arguments as Map?) ?? const <Object?, Object?>{};
          final kind = (args['kind'] ?? 'picture').toString() == 'audio'
              ? SavedMpvPresetKind.audio
              : SavedMpvPresetKind.picture;
          final presets = await const MpvSettingsStore().loadSavedPresets(kind);
          return <Map<String, dynamic>>[
            for (final p in presets)
              <String, dynamic>{
                'id': p.id,
                'name': p.name,
                'description': p.description,
              },
          ];
        case 'applySavedMpvPreset':
          // 应用某保存预设：写入 Flutter 全局设置（单一事实源）并把结果 bundle 回传原生壳套用。
          final args = (call.arguments as Map?) ?? const <Object?, Object?>{};
          final id = (args['id'] ?? '').toString().trim();
          if (id.isEmpty) return null;
          final kind = (args['kind'] ?? 'picture').toString() == 'audio'
              ? SavedMpvPresetKind.audio
              : SavedMpvPresetKind.picture;
          const store = MpvSettingsStore();
          final presets = await store.loadSavedPresets(kind);
          SavedMpvPreset? match;
          for (final p in presets) {
            if (p.id == id) {
              match = p;
              break;
            }
          }
          if (match == null) return null;
          final bundle = await store.applySavedPreset(match);
          return <String, dynamic>{
            'settings': bundle.settings,
            'videoAdjustments': bundle.videoAdjustments,
          };
        case 'localSubtitleImported':
          // 原生壳手动导入本地字幕（SAF「+添加」）→ 通知详情页刷新字幕面板。
          // 元数据已由原生侧写入共享 SharedPreferences，这里仅触发界面刷新。
          final args = (call.arguments as Map?) ?? const <Object?, Object?>{};
          await onLocalSubtitleImported?.call(Map<String, dynamic>.from(args));
          return true;
        case 'localSubtitleRemoved':
          // 原生壳删除本地字幕 → 通知详情页刷新字幕面板。
          final args = (call.arguments as Map?) ?? const <Object?, Object?>{};
          await onLocalSubtitleRemoved?.call(Map<String, dynamic>.from(args));
          return true;
        default:
          throw MissingPluginException('native_player reentry: ${call.method}');
      }
    });
    // 通知 Kotlin：把"本 engine 的 channel"设为反向通道目标。多 host engine 下不能在
    // engine 配置时 eager attach（会被最后配置的 engine 覆盖，导致 dispatch 落到没有
    // reentry handler 的 engine → notImplemented）；必须由真正注册了 handler 的 engine
    // 主动认领。
    unawaited(_channel.invokeMethod<void>('bindReentryHost'));
    return token;
  }

  /// 解绑反向通道。仅当 [token] 仍是当前持有者时才真正清除——避免旧入口 dispose 清掉
  /// 后注册入口的 handler。launcher 内部注册的（捕获 nas、闭包不持 State）可不解绑。
  static void unbindReentry(Object token) {
    if (!identical(_activeBindToken, token)) return;
    _activeBindToken = null;
    unawaited(_channel.invokeMethod<void>('unbindReentryHost'));
    _channel.setMethodCallHandler(null);
  }

  /// 灰度统一入口：读"原生渲染器"开关，开启则启动原生壳并返回 true（调用方据此
  /// `return`、不再走 Flutter 播放器）；关闭则返回 false。所有播放入口都应在 push
  /// Flutter 播放器前调用它，避免漏接某条路径。
  static Future<bool> maybeLaunch(
    Map<String, dynamic> loadArgs, {
    String? danmakuFilePath,
    List<Map<String, dynamic>>? episodes,
    Map<String, dynamic>? initialPlayInfo,
    String? startSource,
    int? introDurationSeconds,
    int? outroDurationSeconds,
    NasProvider? nas,
  }) async {
    final settings = await const DanmakuSettingsStore().load();
    if (!preferNativePlayerShell) return false;
    // 弹幕：详情页 engine 仍存活时，用 source 的媒体上下文做一次 DanDanPlay 自动匹配+
    // 拉取，序列化落临时文件，随 Intent 传给原生壳。失败则无弹幕、不阻塞播放。
    var resolvedDanmakuFile = danmakuFilePath;
    if (resolvedDanmakuFile == null && settings.enabled) {
      resolvedDanmakuFile = await NativeDanmakuPrefetch.resolveToFile(
        seriesTitle: (loadArgs['seriesTitle'] ?? '').toString(),
        itemTitle: (loadArgs['title'] ?? '').toString(),
        seasonNumber: (loadArgs['seasonNumber'] as num?)?.toInt() ?? 0,
        episodeNumber: (loadArgs['episodeNumber'] as num?)?.toInt() ?? 0,
        tmdbId: (loadArgs['tmdbId'] ?? '').toString(),
        settings: settings,
        itemGuid: (loadArgs['itemGuid'] ?? '').toString(),
        mediaGuid: (loadArgs['mediaGuid'] ?? '').toString(),
        seasonGuid: (loadArgs['seasonGuid'] ?? '').toString(),
      );
    }
    await launch(
      loadArgs: loadArgs,
      danmakuFilePath: resolvedDanmakuFile,
      episodes: episodes,
      initialPlayInfo: initialPlayInfo,
      startSource: startSource,
      introDurationSeconds: introDurationSeconds,
      outroDurationSeconds: outroDurationSeconds,
      nas: nas,
    );
    return true;
  }

  /// 取原生壳文案表：语言取 [AppLocaleProvider] 持久化的应用内覆盖值（system 模式为
  /// null 时回退 `PlatformDispatcher.instance.locale` 即系统语言），再用其查找对应的
  /// [AppLocalizations] 文案实例。查不到（当前仅支持 zh/zh_CN）时回退中文，保证原生壳
  /// 始终能拿到一份完整表。
  static Future<Map<String, String>> _loadLocalizedStrings() async {
    final override = await AppLocaleProvider.loadStoredLocale();
    final locale = override ?? PlatformDispatcher.instance.locale;
    AppLocalizations l10n;
    try {
      l10n = lookupAppLocalizations(locale);
    } catch (_) {
      l10n = lookupAppLocalizations(const Locale('zh'));
    }
    return buildNativePlayerLocalizedStrings(l10n);
  }

  /// 把封面缓存为本地文件并写进 [args] 的 `posterLocalPath`。仅在有 [nas]（需鉴权下载）、
  /// 有 `posterPath` 且尚未带本地路径时执行。任何失败都静默——原生壳回退网络 URL。
  static Future<void> _mergeArtworkLocalPath(
    Map<String, dynamic> args,
    NasProvider? nas,
  ) async {
    if (nas == null) return;
    final posterPath = (args['posterPath'] ?? '').toString().trim();
    if (posterPath.isEmpty) return;
    args.addAll(
      NativeReentrySupport.buildNativeImageFields(
        poster: posterPath,
        token: nas.token,
        accessCode: nas.accessCode,
        baseUrl: nas.baseUrl,
        usingLocal: false,
      ),
    );
    final existing = (args['posterLocalPath'] ?? '').toString().trim();
    if (existing.isNotEmpty) return;
    final local = await NativeArtworkPrefetch.resolveToFile(nas, posterPath);
    if (local != null && local.isNotEmpty) {
      args['posterLocalPath'] = local;
    }
  }
}
