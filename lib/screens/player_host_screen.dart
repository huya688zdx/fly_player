import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../controllers/play_detail_data_loader.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/download_task_record.dart';
import '../models/play_info.dart';
import '../playback/playback_source.dart';
import '../player/models/player_host_launch_args.dart';
import '../player/mpv_player_page.dart';
import '../providers/nas_provider.dart';
import '../providers/parallel_window_settings_provider.dart';
import '../services/download_task_service.dart';
import '../services/player_host_bridge.dart';
import '../services/play_stats/play_stats.dart';
import '../theme/app_theme.dart';
import '../ui/app_motion.dart';
import '../ui/player_pane_host_scope.dart';
import '../utils/back_dismiss_manager.dart';
import '../utils/local_subtitle_bundle.dart';
import '../utils/playback_resume_position_resolver.dart';
import 'connection_screen.dart';
import 'detail_host_screen.dart';
import 'settings_destination_routes.dart';

class PlayerHostScreen extends StatefulWidget {
  const PlayerHostScreen({super.key});

  @override
  State<PlayerHostScreen> createState() => _PlayerHostScreenState();
}

class _PlayerHostScreenState extends State<PlayerHostScreen>
    with TickerProviderStateMixin
    implements PlayerPaneHostController {
  static const MethodChannel _stateChannel = MethodChannel(
    'fly_player/player_host_state',
  );
  static const String _fullscreenMode = 'fullscreen';
  static const String _splitMode = 'split';
  static const String _homeRoute = '/screen/home';
  static const Duration _paneTransitionDuration = Duration(milliseconds: 240);

  final ValueNotifier<String> _rightPaneRouteNotifier = ValueNotifier<String>(
    _homeRoute,
  );
  final BackDismissManager _playerBackDismissManager = BackDismissManager();
  final GlobalKey<DetailHostScreenState> _detailHostKey =
      GlobalKey<DetailHostScreenState>();
  final List<String> _rightPaneRouteStack = <String>[_homeRoute];
  late final AnimationController _paneTransitionController;
  late final CurvedAnimation _paneTransition;
  late final AnimationController _exitTransitionController;
  late final CurvedAnimation _exitTransition;
  bool _splitBackExitGuardArmed = false;
  bool _detailPaneReserved = false;
  bool _pictureInPictureActive = false;
  bool _exitInProgress = false;
  Future<bool> Function()? _playerBackActionHandler;

  PlayerHostLaunchArgs? _currentArgs;
  String _layoutMode = _fullscreenMode;
  bool _loadingInitialArgs = true;

  bool get _isSplitMode => _layoutMode == _splitMode;

  @override
  void initState() {
    super.initState();
    _paneTransitionController = AnimationController(
      vsync: this,
      duration: _paneTransitionDuration,
      value: 0,
    );
    _paneTransition = CurvedAnimation(
      parent: _paneTransitionController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );
    _exitTransitionController = AnimationController(
      vsync: this,
      duration: AppMotion.playerRoute,
      value: 1,
    );
    _exitTransition = CurvedAnimation(
      parent: _exitTransitionController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );
    _stateChannel.setMethodCallHandler(_handleStateMethodCall);
    unawaited(_loadInitialArgs());
  }

  @override
  void dispose() {
    _stateChannel.setMethodCallHandler(null);
    _paneTransitionController.dispose();
    _exitTransitionController.dispose();
    _rightPaneRouteNotifier.dispose();
    super.dispose();
  }

  Future<void> _loadInitialArgs() async {
    final args = await _resolveRecoveredDownloadArgs(
      await PlayerHostBridge.consumeInitialPlayerArgs(),
    );
    if (!mounted) return;
    setState(() {
      _loadingInitialArgs = false;
      if (args != null) {
        _applyLaunchArgs(args, replaceSourceOnly: false);
      }
    });
  }

  void _applyLaunchArgs(
    PlayerHostLaunchArgs args, {
    required bool replaceSourceOnly,
  }) {
    _currentArgs = args;
    _layoutMode = args.layoutMode == _splitMode ? _splitMode : _fullscreenMode;
    _detailPaneReserved = _layoutMode == _splitMode;
    _syncPaneTransition(animate: false);
    final nextInitialRoute = args.initialRightPaneRoute.trim();
    if (!replaceSourceOnly) {
      _splitBackExitGuardArmed =
          nextInitialRoute.isNotEmpty &&
          _normalizeRoute(nextInitialRoute) != _homeRoute;
      _resetRightPaneStack(nextInitialRoute);
      return;
    }
    final currentRoute = _currentRightPaneRoute;
    if ((currentRoute.isEmpty || currentRoute == _homeRoute) &&
        nextInitialRoute.isNotEmpty) {
      _replaceOrPushRightPaneRoute(nextInitialRoute);
    }
  }

  Future<PlayerHostLaunchArgs?> _resolveRecoveredDownloadArgs(
    PlayerHostLaunchArgs? args,
  ) async {
    if (args == null || !args.source.externalLocalSource) return args;
    final record = await DownloadTaskService.instance
        .recoverDownloadedRecordForExternalOpen(
          sourceUrl: args.source.url,
          displayName: args.source.title,
          sizeBytes: args.source.externalLocalFileSizeBytes,
          provider: context.read<NasProvider>(),
        );
    if (record == null) return args;
    final source = await _buildRecoveredDownloadSource(
      record: record,
      fallbackSource: args.source,
    );
    return PlayerHostLaunchArgs(
      title: source.title.trim().isEmpty ? args.title : source.title,
      source: source,
      initialPlayInfo: args.initialPlayInfo,
      startSource: args.startSource,
      fromParallelHost: args.fromParallelHost,
      layoutMode: args.layoutMode,
      initialRightPaneRoute: args.initialRightPaneRoute,
    );
  }

  Future<MpvMediaSource> _buildRecoveredDownloadSource({
    required DownloadTaskRecord record,
    required MpvMediaSource fallbackSource,
  }) async {
    final title = _downloadTitleForRecord(record, fallbackSource.title);
    final mediaGuid = record.mediaGuid.trim().isNotEmpty
        ? record.mediaGuid.trim()
        : (fallbackSource.mediaGuid.trim().isNotEmpty
              ? fallbackSource.mediaGuid.trim()
              : record.id);
    final resume = await PlaybackResumePositionResolver.resolve(
      videoIds: <String>[record.itemGuid, fallbackSource.itemGuid, record.id],
      durationSeconds: fallbackSource.durationSeconds,
      networkPositionAvailable: false,
    );
    final localSubtitleBundle = await discoverLocalSubtitleBundleAsync(
      mediaGuid: mediaGuid,
      videoFilePath: record.filePath,
    );
    return MpvMediaSource.localFile(
      filePath: record.filePath,
      itemGuid: record.itemGuid,
      mediaGuid: mediaGuid,
      seriesGuid: fallbackSource.seriesGuid,
      seasonGuid: fallbackSource.seasonGuid.trim().isNotEmpty
          ? fallbackSource.seasonGuid
          : record.groupId,
      posterPath: _firstPosterUrl(record),
      mediaType: fallbackSource.mediaType,
      ancestorName: fallbackSource.ancestorName,
      videoGuid: fallbackSource.videoGuid.trim().isNotEmpty
          ? fallbackSource.videoGuid
          : mediaGuid,
      title: title,
      seriesTitle: record.groupTitle,
      seasonNumber: fallbackSource.seasonNumber,
      tmdbId: fallbackSource.tmdbId,
      episodeNumber: fallbackSource.episodeNumber,
      startPosition: resume.position,
      audioTrackIndex: fallbackSource.audioTrackIndex,
      subtitleTrackIndex: fallbackSource.subtitleTrackIndex,
      audioTrackGuid: fallbackSource.audioTrackGuid,
      subtitleTrackGuid: fallbackSource.subtitleTrackGuid,
      localSubtitleBundle: localSubtitleBundle,
      resolution: record.resolution,
      bitrate: fallbackSource.bitrate,
      durationSeconds: resume.effectiveDurationSeconds,
      videoWidth: fallbackSource.videoWidth,
      videoHeight: fallbackSource.videoHeight,
      videoCodecName: fallbackSource.videoCodecName,
      videoProfile: fallbackSource.videoProfile,
      colorSpace: fallbackSource.colorSpace,
      colorTransfer: fallbackSource.colorTransfer,
      colorPrimaries: fallbackSource.colorPrimaries,
      bitDepth: fallbackSource.bitDepth,
      playbackSpeed: fallbackSource.playbackSpeed,
      listenVideoModeEnabled: fallbackSource.listenVideoModeEnabled,
      danmakuAutoSearchAllowed: true,
      audioTracks: record.audioTracks.isNotEmpty
          ? record.audioTracks
          : fallbackSource.audioTracks,
      subtitleTracks: record.subtitleTracks.isNotEmpty
          ? record.subtitleTracks
          : fallbackSource.subtitleTracks,
      qualities: fallbackSource.qualities,
    );
  }

  String _downloadTitleForRecord(
    DownloadTaskRecord record,
    String fallbackTitle,
  ) {
    final groupTitle = record.groupTitle.trim();
    final title = DownloadTaskService.instance
        .displayTitleForRecord(record)
        .trim();
    if (title.isEmpty) {
      final fileName = record.fileName.trim();
      if (fileName.isNotEmpty) return fileName;
      return fallbackTitle.trim();
    }
    if (groupTitle.isEmpty || title.startsWith(groupTitle)) return title;
    return '$groupTitle $title';
  }

  String _firstPosterUrl(DownloadTaskRecord record) {
    if (record.posterUrls.isNotEmpty) return record.posterUrls.first;
    if (record.groupPosterUrls.isNotEmpty) return record.groupPosterUrls.first;
    return '';
  }

  String _normalizeRoute(String routeName) {
    final trimmed = routeName.trim();
    return trimmed.isEmpty ? _homeRoute : trimmed;
  }

  String _routePath(String routeName) {
    final uri = Uri.tryParse(routeName);
    final path = uri?.path.trim() ?? '';
    return path.isEmpty ? _homeRoute : path;
  }

  String get _currentRightPaneRoute =>
      _rightPaneRouteStack.isEmpty ? _homeRoute : _rightPaneRouteStack.last;

  void _syncRightPaneState() {
    final currentRoute = _currentRightPaneRoute;
    if (_rightPaneRouteNotifier.value != currentRoute) {
      _rightPaneRouteNotifier.value = currentRoute;
    }
    _detailHostKey.currentState?.syncRouteStack(_rightPaneRouteStack);
  }

  void _adoptDetailHostStack() {
    final detailHost = _detailHostKey.currentState;
    if (detailHost == null) return;
    _applyRightPaneRouteStackSnapshot(detailHost.routeStackSnapshot);
  }

  void _applyRightPaneRouteStackSnapshot(List<String> snapshot) {
    if (snapshot.isEmpty) return;
    final normalizedSnapshot = snapshot
        .map(_normalizeRoute)
        .where((route) => route.isNotEmpty)
        .toList(growable: false);
    if (normalizedSnapshot.isEmpty) return;
    if (_sameRouteStack(_rightPaneRouteStack, normalizedSnapshot)) return;
    _rightPaneRouteStack
      ..clear()
      ..addAll(normalizedSnapshot);
    final currentRoute = _currentRightPaneRoute;
    _splitBackExitGuardArmed = currentRoute != _homeRoute;
    if (_rightPaneRouteNotifier.value != currentRoute) {
      _rightPaneRouteNotifier.value = currentRoute;
    }
  }

  bool _sameRouteStack(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i += 1) {
      if (_normalizeRoute(a[i]) != _normalizeRoute(b[i])) {
        return false;
      }
    }
    return true;
  }

  void _resetRightPaneStack(String initialRoute) {
    final settingsStack = _mergeSettingsRouteStack(initialRoute);
    if (settingsStack != null) {
      _rightPaneRouteStack
        ..clear()
        ..addAll(settingsStack);
      _splitBackExitGuardArmed = _currentRightPaneRoute != _homeRoute;
      _syncRightPaneState();
      return;
    }
    final normalizedRoute = _normalizeRoute(initialRoute);
    _rightPaneRouteStack
      ..clear()
      ..add(_homeRoute);
    if (normalizedRoute != _homeRoute) {
      _rightPaneRouteStack.add(normalizedRoute);
      _splitBackExitGuardArmed = true;
    } else {
      _splitBackExitGuardArmed = false;
    }
    _syncRightPaneState();
  }

  void _replaceOrPushRightPaneRoute(String routeName) {
    final settingsStack = _mergeSettingsRouteStack(routeName);
    if (settingsStack != null) {
      _rightPaneRouteStack
        ..clear()
        ..addAll(settingsStack);
      _splitBackExitGuardArmed = _currentRightPaneRoute != _homeRoute;
      _syncRightPaneState();
      return;
    }
    final normalizedRoute = _normalizeRoute(routeName);
    final currentRoute = _currentRightPaneRoute;
    if (normalizedRoute == currentRoute) {
      _syncRightPaneState();
      return;
    }
    if (_routePath(currentRoute) == _routePath(normalizedRoute)) {
      if (_rightPaneRouteStack.isEmpty) {
        _rightPaneRouteStack.add(normalizedRoute);
      } else {
        _rightPaneRouteStack[_rightPaneRouteStack.length - 1] = normalizedRoute;
      }
    } else {
      _rightPaneRouteStack.add(normalizedRoute);
    }
    _splitBackExitGuardArmed = normalizedRoute != _homeRoute;
    _syncRightPaneState();
  }

  List<String>? _mergeSettingsRouteStack(String routeName) {
    final settingsStack = SettingsDestinationRoutes.buildNavigationStack(
      routeName,
    );
    if (settingsStack == null || settingsStack.isEmpty) {
      return null;
    }
    final existingSettingsIndex = _rightPaneRouteStack.indexWhere(
      _isSettingsRoute,
    );
    final prefix = existingSettingsIndex >= 0
        ? _rightPaneRouteStack.take(existingSettingsIndex).toList()
        : List<String>.from(_rightPaneRouteStack);
    final merged = <String>[
      if (prefix.isEmpty || prefix.first != _homeRoute) _homeRoute,
      ...prefix.where((route) => route != _homeRoute),
      ...settingsStack,
    ];
    return _dedupeSequentialRoutes(merged);
  }

  bool _isSettingsRoute(String routeName) {
    final path = Uri.tryParse(routeName.trim())?.path.trim() ?? '';
    return path == SettingsDestinationRoutes.home ||
        path.startsWith('${SettingsDestinationRoutes.home}/');
  }

  List<String> _dedupeSequentialRoutes(List<String> routes) {
    final normalized = <String>[];
    for (final route in routes) {
      final trimmed = route.trim();
      if (trimmed.isEmpty) continue;
      if (normalized.isNotEmpty && normalized.last == trimmed) {
        continue;
      }
      normalized.add(trimmed);
    }
    return normalized;
  }

  Future<void> _syncPlatformLayoutMode(String nextMode) async {
    final args = _currentArgs;
    if (args == null) return;
    await PlayerHostBridge.switchPlayerLayoutMode(
      title: args.title,
      source: args.source.toMap(),
      initialPlayInfo: args.initialPlayInfo,
      startSource: args.startSource,
      targetMode: nextMode,
      result: PlayDetailPlayerReturnData(
        itemGuid: args.source.itemGuid,
        currentTsSeconds: 0,
      ),
    );
  }

  Future<void> _applyPlatformLayoutModeChange(
    String nextMode, {
    String initialRightPaneRoute = '',
  }) async {
    final normalizedMode = nextMode == _splitMode
        ? _splitMode
        : _fullscreenMode;
    final normalizedRoute = _normalizeRoute(initialRightPaneRoute);
    final currentArgs = _currentArgs;
    if (currentArgs != null) {
      _currentArgs = PlayerHostLaunchArgs(
        title: currentArgs.title,
        source: currentArgs.source,
        initialPlayInfo: currentArgs.initialPlayInfo,
        startSource: currentArgs.startSource,
        fromParallelHost: currentArgs.fromParallelHost,
        layoutMode: normalizedMode,
        initialRightPaneRoute: normalizedMode == _splitMode
            ? normalizedRoute
            : currentArgs.initialRightPaneRoute,
      );
    }
    if (normalizedMode == _splitMode &&
        normalizedRoute != _homeRoute &&
        _currentRightPaneRoute == _homeRoute) {
      _replaceOrPushRightPaneRoute(normalizedRoute);
    }
    await _setLayoutMode(normalizedMode, syncPlatform: false);
  }

  Future<void> _setLayoutMode(
    String nextMode, {
    required bool syncPlatform,
  }) async {
    final normalizedMode = nextMode == _splitMode
        ? _splitMode
        : _fullscreenMode;
    final layoutChanged = _layoutMode != normalizedMode;
    if (mounted) {
      setState(() {
        _layoutMode = normalizedMode;
      });
    } else {
      _layoutMode = normalizedMode;
    }
    if (layoutChanged) {
      unawaited(_syncPaneTransition());
    }
    if (syncPlatform) {
      await _syncPlatformLayoutMode(normalizedMode);
    }
  }

  Future<void> _syncPaneTransition({bool animate = true}) async {
    final target = _isSplitMode ? 1.0 : 0.0;
    if (!animate) {
      _detailPaneReserved = target > 0.0;
      _paneTransitionController.value = target;
      return;
    }
    if ((_paneTransitionController.value - target).abs() < 0.001) {
      return;
    }
    if (target > 0.0 && !_detailPaneReserved && mounted) {
      setState(() => _detailPaneReserved = true);
    } else if (target > 0.0) {
      _detailPaneReserved = true;
    }
    await _paneTransitionController.animateTo(target);
    if (target == 0.0) {
      if (mounted) {
        setState(() => _detailPaneReserved = false);
      } else {
        _detailPaneReserved = false;
      }
    }
  }

  Future<void> _handleStateMethodCall(MethodCall call) async {
    if (call.method == 'replaceSource') {
      final rawArgs = call.arguments;
      if (rawArgs is! Map<Object?, Object?>) return;
      final args = await _resolveRecoveredDownloadArgs(
        PlayerHostLaunchArgs.fromPlatformMap(rawArgs),
      );
      if (args == null || !mounted) return;
      setState(() => _applyLaunchArgs(args, replaceSourceOnly: true));
      return;
    }
    if (call.method == 'replaceRightPaneRoute') {
      final routeName =
          (call.arguments as Map<Object?, Object?>?)?['routeName']
              ?.toString()
              .trim() ??
          '';
      if (routeName.isEmpty) return;
      await openRoute(routeName);
      return;
    }
    if (call.method == 'layoutModeChanged') {
      final payload = call.arguments as Map<Object?, Object?>?;
      final nextMode = (payload?['layoutMode'] ?? _fullscreenMode).toString();
      final initialRightPaneRoute = (payload?['initialRightPaneRoute'] ?? '')
          .toString()
          .trim();
      await _applyPlatformLayoutModeChange(
        nextMode,
        initialRightPaneRoute: initialRightPaneRoute,
      );
      return;
    }
    if (call.method == 'systemMultiWindowModeChanged') {
      final active =
          (call.arguments as Map<Object?, Object?>?)?['active'] == true;
      if (!active || !_isSplitMode || !mounted) return;
      await _setLayoutMode(_fullscreenMode, syncPlatform: true);
      return;
    }
    if (call.method == 'pictureInPictureModeChanged') {
      final active =
          (call.arguments as Map<Object?, Object?>?)?['active'] == true;
      if (!mounted || _pictureInPictureActive == active) return;
      setState(() => _pictureInPictureActive = active);
    }
  }

  @override
  Future<bool> openRoute(String routeName) async {
    final normalizedRoute = routeName.trim();
    if (normalizedRoute.isEmpty) return false;
    _replaceOrPushRightPaneRoute(normalizedRoute);
    await _setLayoutMode(_splitMode, syncPlatform: true);
    return true;
  }

  @override
  Future<bool> backInPane() async {
    final detailHost = _detailHostKey.currentState;
    if (detailHost != null && await detailHost.maybePopRoute()) {
      _adoptDetailHostStack();
      _splitBackExitGuardArmed = _currentRightPaneRoute != _homeRoute;
      return true;
    }
    final currentRoute = _currentRightPaneRoute;
    if (currentRoute != _homeRoute) {
      _resetRightPaneStack(_homeRoute);
      return true;
    }
    return false;
  }

  @override
  Future<bool> closePane() async {
    if (!_isSplitMode) return true;
    _resetRightPaneStack(_homeRoute);
    await _setLayoutMode(_fullscreenMode, syncPlatform: true);
    return true;
  }

  @override
  Future<bool> replacePlayerSource({
    required String title,
    required MpvMediaSource source,
    PlayInfoData? initialPlayInfo,
    PlayStartSource startSource = PlayStartSource.manual,
  }) async {
    final current = _currentArgs;
    final nextArgs = PlayerHostLaunchArgs(
      title: title.trim(),
      source: source,
      initialPlayInfo: initialPlayInfo,
      startSource: startSource,
      fromParallelHost: current?.fromParallelHost ?? true,
      layoutMode: _layoutMode,
      initialRightPaneRoute: _rightPaneRouteNotifier.value,
    );
    if (!mounted) {
      _applyLaunchArgs(nextArgs, replaceSourceOnly: true);
      return true;
    }
    setState(() => _applyLaunchArgs(nextArgs, replaceSourceOnly: true));
    return true;
  }

  Future<bool> _consumeSplitBackProtection() async {
    if (!_isSplitMode) return false;
    if (await backInPane()) return true;
    if (_splitBackExitGuardArmed) {
      _splitBackExitGuardArmed = false;
      _resetRightPaneStack(_homeRoute);
      return true;
    }
    return false;
  }

  Future<void> _handleSystemBack() async {
    if (await _playerBackDismissManager.dismissActive()) {
      return;
    }
    if (await _consumeSplitBackProtection()) {
      return;
    }
    final playerBackActionHandler = _playerBackActionHandler;
    if (playerBackActionHandler != null && await playerBackActionHandler()) {
      return;
    }
    await _finishPlayer(force: false);
  }

  Future<void> _finishPlayer({Object? result, bool force = false}) async {
    if (!force && await _consumeSplitBackProtection()) {
      return;
    }
    if (_exitInProgress) return;
    _exitInProgress = true;
    if (mounted) {
      FocusScope.of(context).unfocus();
    }
    if (_exitTransitionController.value > 0.001) {
      await _exitTransitionController.reverse();
    }
    final playResult = result is PlayDetailPlayerReturnData
        ? result
        : PlayDetailPlayerReturnData(
            itemGuid: _currentArgs?.source.itemGuid ?? '',
            currentTsSeconds: 0,
          );
    final closed = await PlayerHostBridge.finishPlayerActivity(playResult);
    if (!closed && mounted) {
      Navigator.of(
        context,
      ).maybePop(result is PlayDetailPlayerReturnData ? result : null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NasProvider>();
    final colors = context.appColors;
    if (!provider.isReady || _loadingInitialArgs) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: colors.accent)),
      );
    }
    final args = _currentArgs;
    if (args == null) {
      return _PlayerHostError(
        message: AppLocalizations.of(context).playerHostInvalidArgs,
      );
    }
    if (!provider.isConfigured && !_sourceCanRunWithoutNas(args.source)) {
      return const ConnectionScreen();
    }
    final playbackPrimaryOnLeft = context
        .watch<ParallelWindowSettingsProvider>()
        .playbackPrimaryOnLeft;
    return PlayerPaneHostScope(
      controller: this,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, __) {
          if (didPop || _exitInProgress) {
            return;
          }
          unawaited(_handleSystemBack());
        },
        child: FadeTransition(
          opacity: _exitTransition,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset.zero,
              end: const Offset(0, 0.018),
            ).animate(_exitTransition),
            child: Scaffold(
              backgroundColor: Colors.black,
              body: SafeArea(
                top: false,
                bottom: false,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final totalWidth = constraints.maxWidth;
                    final splitWidth = totalWidth < 720
                        ? totalWidth * 0.48
                        : (totalWidth * 0.42).clamp(360.0, 640.0);
                    final detailContent = SizedBox(
                      width: splitWidth,
                      height: constraints.maxHeight,
                      child: Builder(
                        builder: (context) {
                          final media = MediaQuery.of(context);
                          return MediaQuery(
                            data: media.copyWith(
                              size: Size(splitWidth, constraints.maxHeight),
                            ),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: context.appColors.backgroundBase,
                              ),
                              child: DetailHostScreen(
                                key: _detailHostKey,
                                initialRouteName: _rightPaneRouteNotifier.value,
                                rootRouteName: _homeRoute,
                                routeListenable: _rightPaneRouteNotifier,
                                onRouteStackChanged:
                                    _applyRightPaneRouteStackSnapshot,
                                enablePlatformChannel: false,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                    // 重型子树（视频播放器、详情导航）在每次布局时只构建一次，
                    // 不放进 AnimatedBuilder 的 builder 闭包里。窗格展开/收起动画
                    // 期间，相同的 widget 实例会触发 Flutter 的 short-circuit，
                    // 避免 MpvPlayerPage 与详情页每帧重建导致的掉帧。
                    final playerPane = Expanded(
                      child: DecoratedBox(
                        decoration: const BoxDecoration(color: Colors.black),
                        child: KeyedSubtree(
                          key: const ValueKey<String>('player-pane'),
                          child: MpvPlayerPage(
                            title: args.title,
                            source: args.source,
                            initialPlayInfo: args.initialPlayInfo,
                            startSource: args.startSource,
                            pictureInPictureActive: _pictureInPictureActive,
                            onBackActionHandlerChanged: (handler) {
                              _playerBackActionHandler = handler;
                            },
                            backDismissManager: _playerBackDismissManager,
                            parallelLayoutToggleEnabled: args.fromParallelHost,
                            parallelLayoutMode: _layoutMode,
                            interceptSystemBack: false,
                            onParallelLayoutModeChanged: (nextMode) async {
                              await _setLayoutMode(
                                nextMode,
                                syncPlatform: true,
                              );
                            },
                            onCloseRequested: (result) async {
                              await _finishPlayer(result: result, force: true);
                            },
                          ),
                        ),
                      ),
                    );
                    final detailPaneContent = RepaintBoundary(
                      child: detailContent,
                    );
                    return AnimatedBuilder(
                      animation: _paneTransition,
                      builder: (context, _) {
                        final reveal = _paneTransition.value.clamp(0.0, 1.0);
                        final reserveDetailPaneSpace =
                            _detailPaneReserved || reveal > 0.001;
                        final detailPaneWidth = reserveDetailPaneSpace
                            ? splitWidth * reveal
                            : 0.0;
                        // The outer box width still animates so the player
                        // pane expands/contracts smoothly via the Row. But the
                        // detail content is given a FIXED splitWidth via
                        // OverflowBox, so the heavy detail subtree lays out once
                        // (at its final width) and is merely clipped/translated
                        // during the transition — instead of relaying out the
                        // whole tree (and re-running flushSemantics geometry,
                        // which dominated the CPU profile) every animation frame.
                        final detailPane = SizedBox(
                          width: detailPaneWidth,
                          child: IgnorePointer(
                            ignoring: reveal < 0.98,
                            child: ClipRect(
                              child: OverflowBox(
                                minWidth: splitWidth,
                                maxWidth: splitWidth,
                                alignment: playbackPrimaryOnLeft
                                    ? Alignment.centerLeft
                                    : Alignment.centerRight,
                                child: Opacity(
                                  opacity: reveal,
                                  child: Transform.translate(
                                    offset: Offset(
                                      (1 - reveal) *
                                          (playbackPrimaryOnLeft ? 24 : -24),
                                      0,
                                    ),
                                    child: detailPaneContent,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                        final children = playbackPrimaryOnLeft
                            ? <Widget>[playerPane, detailPane]
                            : <Widget>[detailPane, playerPane];
                        return Stack(
                          children: [
                            Positioned.fill(child: Row(children: children)),
                            if (reveal > 0.001)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: Align(
                                    alignment: playbackPrimaryOnLeft
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    child: Opacity(
                                      opacity: reveal,
                                      child: Container(
                                        width: 1,
                                        color: Colors.white.withValues(
                                          alpha: 0.08,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _sourceCanRunWithoutNas(MpvMediaSource source) {
    if (source.externalLocalSource) return true;
    if (!source.isDownloadedFile) return false;
    final normalizedUrl = source.url.trim().toLowerCase();
    return normalizedUrl.startsWith('file:') ||
        normalizedUrl.startsWith('content:');
  }
}

class _PlayerHostError extends StatelessWidget {
  final String message;

  const _PlayerHostError({required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      body: Center(
        child: Text(
          message,
          style: TextStyle(color: colors.textSecondary, fontSize: 16),
        ),
      ),
    );
  }
}
