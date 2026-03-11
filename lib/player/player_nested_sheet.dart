import 'dart:math' as math;

import 'package:flutter/material.dart';

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
    final media = MediaQuery.of(context);
    final isLandscape = media.size.width > media.size.height;

    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierLabel: barrierLabel,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, _, __) {
        return _PlayerNestedSheetHost<T>(
          initialPageId: initialPageId,
          pages: pages,
        );
      },
      transitionBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: isLandscape
                  ? const Offset(0.08, 0)
                  : const Offset(0, 0.12),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
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
    return Row(
      children: [
        if (onBack != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: onBack,
              borderRadius: BorderRadius.circular(18),
              child: const SizedBox(
                width: 32,
                height: 32,
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
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
      closeWithResult: (result) => Navigator.of(context).pop(result),
    )..addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isLandscape = media.size.width > media.size.height;
    final drawerWidth = _drawerWidth(media.size);
    final sheetHeight = isLandscape
        ? null
        : math.max(300.0, media.size.height * 0.45);
    final currentPage = _pageById[_controller.currentPageId];
    if (currentPage == null) {
      throw FlutterError(
        'Missing nested sheet page: ${_controller.currentPageId}',
      );
    }
    final activeKey = ValueKey<String>(
      '${_controller.currentPageId}:${_controller.version}',
    );

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
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
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(
                  alpha: isLandscape ? 0.56 : 0.78,
                ),
                border: isLandscape
                    ? Border.all(color: Colors.white.withValues(alpha: 0.08))
                    : null,
              ),
              child: ClipRect(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  layoutBuilder: (currentChild, previousChildren) {
                    return currentChild ??
                        (previousChildren.isNotEmpty
                            ? previousChildren.last
                            : const SizedBox.shrink());
                  },
                  transitionBuilder: (child, animation) {
                    final isCurrent = child.key == activeKey;
                    if (!isCurrent) {
                      return FadeTransition(
                        opacity: ReverseAnimation(animation),
                        child: child,
                      );
                    }
                    final begin = _controller.isForward
                        ? const Offset(0.12, 0)
                        : const Offset(-0.12, 0);
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: begin,
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: KeyedSubtree(
                    key: activeKey,
                    child: currentPage.builder(context, _controller),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
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
