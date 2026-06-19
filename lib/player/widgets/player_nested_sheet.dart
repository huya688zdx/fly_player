import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../ui/app_motion.dart';
import '../../ui/app_sheet_transitions.dart';

typedef PlayerNestedSheetPageBuilder<T> =
    Widget Function(
      BuildContext context,
      PlayerNestedSheetController<T> controller,
    );

class PlayerNestedSheetPage<T> {
  final String id;
  final PlayerNestedSheetPageBuilder<T> builder;

  const PlayerNestedSheetPage({required this.id, required this.builder});
}

class PlayerNestedSheetController<T> extends ChangeNotifier {
  final void Function(T? result) _closeWithResult;
  final List<String> _pageStack;
  bool _forward = true;
  int _version = 0;

  PlayerNestedSheetController({
    required String initialPageId,
    required void Function(T? result) closeWithResult,
  }) : _closeWithResult = closeWithResult,
       _pageStack = <String>[initialPageId];

  String get currentPageId => _pageStack.last;
  bool get canPop => _pageStack.length > 1;
  bool get isForward => _forward;
  int get version => _version;

  void refresh() {
    notifyListeners();
  }

  void push(String pageId) {
    if (pageId.isEmpty || pageId == currentPageId) return;
    _forward = true;
    _pageStack.add(pageId);
    _version += 1;
    notifyListeners();
  }

  void popPage() {
    if (_pageStack.length <= 1) return;
    _forward = false;
    _pageStack.removeLast();
    _version += 1;
    notifyListeners();
  }

  void close([T? result]) {
    _closeWithResult(result);
  }
}

class PlayerNestedSheet {
  static Future<T?> show<T>(
    BuildContext context, {
    required String initialPageId,
    required List<PlayerNestedSheetPage<T>> pages,
    bool barrierDismissible = true,
    String barrierLabel = '',
  }) {
    return AppSheetTransitions.showAdaptiveSheet<T>(
      context,
      barrierDismissible: barrierDismissible,
      barrierLabel: barrierLabel,
      barrierColor: Colors.transparent,
      builder: (dialogContext) {
        return _PlayerNestedSheetHost<T>(
          initialPageId: initialPageId,
          pages: pages,
        );
      },
    );
  }
}

class PlayerNestedSheetScaffold extends StatelessWidget {
  final Widget header;
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const PlayerNestedSheetScaffold({
    super.key,
    required this.header,
    required this.child,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final landscape = media.size.width > media.size.height;
    return Padding(
      padding:
          padding ??
          EdgeInsets.fromLTRB(
            landscape ? 16 : 14,
            landscape ? math.max(media.padding.top, 10) : 12,
            landscape ? 12 : 14,
            landscape ? math.max(media.padding.bottom, 10) : 10,
          ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          SizedBox(height: landscape ? 12 : 10),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class PlayerNestedSheetHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final List<Widget> actions;

  const PlayerNestedSheetHeader({
    super.key,
    required this.title,
    this.onBack,
    this.actions = const <Widget>[],
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      children: [
        if (onBack != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: onBack,
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                width: 32,
                height: 32,
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: colors.textPrimary,
                  size: 20,
                ),
              ),
            ),
          ),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              height: 1.05,
            ),
          ),
        ),
        if (actions.isNotEmpty) ...actions,
      ],
    );
  }
}

class _PlayerNestedSheetHost<T> extends StatefulWidget {
  final String initialPageId;
  final List<PlayerNestedSheetPage<T>> pages;

  const _PlayerNestedSheetHost({
    required this.initialPageId,
    required this.pages,
  });

  @override
  State<_PlayerNestedSheetHost<T>> createState() =>
      _PlayerNestedSheetHostState<T>();
}

class _PlayerNestedSheetHostState<T> extends State<_PlayerNestedSheetHost<T>> {
  late final PlayerNestedSheetController<T> _controller;
  late final Map<String, PlayerNestedSheetPage<T>> _pageById;

  @override
  void initState() {
    super.initState();
    _pageById = <String, PlayerNestedSheetPage<T>>{
      for (final page in widget.pages) page.id: page,
    };
    _controller = PlayerNestedSheetController<T>(
      initialPageId: widget.initialPageId,
      closeWithResult: (result) =>
          AppSheetTransitions.close<T>(context, result),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final media = MediaQuery.of(context);
    final isLandscape = media.size.width > media.size.height;
    final drawerWidth = _drawerWidth(media.size);
    final sheetHeight = isLandscape
        ? null
        : math.max(300.0, media.size.height * 0.45);

    // 外壳（barrier / 定位 / 背景）保持静态：仅在尺寸或主题变化时重建。
    // 页面切换与 refresh() 通过下方的 ListenableBuilder 只重建内容子树，
    // 避免每次点击层级都重建整张抽屉的外壳。
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => AppSheetTransitions.close(context),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            top: isLandscape ? 0 : null,
            right: 0,
            left: isLandscape ? null : 0,
            bottom: 0,
            width: isLandscape ? drawerWidth : null,
            height: sheetHeight,
            child: RepaintBoundary(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    colors.surfaceStrong.withValues(
                      alpha: isLandscape ? 0.96 : 0.98,
                    ),
                    colors.surface,
                  ),
                ),
                child: ClipRect(
                  child: ListenableBuilder(
                    listenable: _controller,
                    builder: (context, _) => _buildAnimatedContent(context),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedContent(BuildContext context) {
    final currentPage = _pageById[_controller.currentPageId];
    if (currentPage == null) {
      throw FlutterError(
        'Missing nested sheet page: ${_controller.currentPageId}',
      );
    }
    final activeKey = ValueKey<String>(
      '${_controller.currentPageId}:${_controller.version}',
    );
    return AnimatedSwitcher(
      duration: AppMotion.nestedSheetPageTransition,
      switchInCurve: AppMotion.sheetEnterCurve,
      switchOutCurve: AppMotion.sheetExitCurve,
      layoutBuilder: (currentChild, previousChildren) {
        return currentChild ??
            (previousChildren.isNotEmpty
                ? previousChildren.last
                : const SizedBox.shrink());
      },
      transitionBuilder: (child, animation) {
        return _buildPageTransition(
          child: child,
          animation: animation,
          isCurrent: child.key == activeKey,
          isForward: _controller.isForward,
        );
      },
      child: KeyedSubtree(
        key: activeKey,
        child: RepaintBoundary(
          child: currentPage.builder(context, _controller),
        ),
      ),
    );
  }

  Widget _buildPageTransition({
    required Widget child,
    required Animation<double> animation,
    required bool isCurrent,
    required bool isForward,
  }) {
    return _NestedPageTransition(
      animation: animation,
      isCurrent: isCurrent,
      isForward: isForward,
      child: child,
    );
  }

  double _drawerWidth(Size size) {
    final screenWidth = size.width;
    final screenHeight = size.height;
    final isLandscape = screenWidth > screenHeight;

    if (!isLandscape) {
      return math.min(screenWidth - 24, math.max(320, screenWidth * 0.84));
    }
    if (screenWidth >= 1400) {
      return math.min(460, math.max(360, screenWidth * 0.31));
    }
    if (screenWidth >= 1000) {
      return math.min(430, math.max(340, screenWidth * 0.33));
    }
    return math.min(400, math.max(320, screenWidth * 0.38));
  }
}

class _NestedPageTransition extends StatefulWidget {
  final Animation<double> animation;
  final bool isCurrent;
  final bool isForward;
  final Widget child;

  const _NestedPageTransition({
    required this.animation,
    required this.isCurrent,
    required this.isForward,
    required this.child,
  });

  @override
  State<_NestedPageTransition> createState() => _NestedPageTransitionState();
}

class _NestedPageTransitionState extends State<_NestedPageTransition> {
  late CurvedAnimation _curved;
  late Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _curved = CurvedAnimation(
      parent: widget.animation,
      curve: AppMotion.sheetEnterCurve,
      reverseCurve: AppMotion.sheetExitCurve,
    );
    _offset = _buildOffsetTween().animate(_curved);
  }

  @override
  void didUpdateWidget(covariant _NestedPageTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    final animationChanged = oldWidget.animation != widget.animation;
    final paramsChanged =
        oldWidget.isCurrent != widget.isCurrent ||
        oldWidget.isForward != widget.isForward;
    if (animationChanged) {
      _curved.dispose();
      _curved = CurvedAnimation(
        parent: widget.animation,
        curve: AppMotion.sheetEnterCurve,
        reverseCurve: AppMotion.sheetExitCurve,
      );
      _offset = _buildOffsetTween().animate(_curved);
    } else if (paramsChanged) {
      _offset = _buildOffsetTween().animate(_curved);
    }
  }

  Tween<Offset> _buildOffsetTween() {
    final begin = widget.isForward
        ? AppMotion.sheetForwardOffset
        : AppMotion.sheetBackwardOffset;
    final end = widget.isForward
        ? const Offset(-0.04, 0)
        : const Offset(0.04, 0);
    return Tween<Offset>(
      begin: widget.isCurrent ? begin : Offset.zero,
      end: widget.isCurrent ? Offset.zero : end,
    );
  }

  @override
  void dispose() {
    _curved.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 关键：进/出页面都做淡入淡出。AnimatedSwitcher 会让退出页的动画反向
    // (1→0)，所以同一个 _curved 既能让进入页淡入、又能让退出页淡出，
    // 退出页不再保持全不透明，避免转场期间两张整页 + 视频纹理三层叠加过绘。
    return FadeTransition(
      opacity: _curved,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}
