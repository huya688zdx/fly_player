import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/desktop_search_overlay.dart';
import 'package:fly_player/media_backend/media_image_ref.dart';
import 'package:fly_player/media_backend/media_item_card.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/ui/player_pane_host_scope.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('搜索结果打开详情后不会被关闭搜索层的 pop 撤销', (tester) async {
    final nestedNavigatorKey = GlobalKey<NavigatorState>();
    final paneHost = _NavigatorPaneHost(nestedNavigatorKey);
    late BuildContext hostContext;

    await tester.pumpWidget(
      ChangeNotifierProvider<NasProvider>(
        create: (_) => NasProvider(),
        child: MaterialApp(
          home: PlayerPaneHostScope(
            controller: paneHost,
            child: Navigator(
              key: nestedNavigatorKey,
              onGenerateRoute: (settings) => MaterialPageRoute<void>(
                settings: settings,
                builder: (context) {
                  if (settings.name?.startsWith('/detail/person') ?? false) {
                    return const Scaffold(body: Text('人物详情'));
                  }
                  if (settings.name == '/search-overlay') {
                    return Scaffold(
                      body: Center(
                        child: FilledButton(
                          onPressed: () {
                            final navigator = Navigator.of(context);
                            unawaited(
                              openSearchItemDetail(
                                hostContext,
                                const MediaItemCard(
                                  id: 'person-1',
                                  title: '测试人物',
                                  type: 'Person',
                                  primaryImage: MediaImageRef.empty,
                                ),
                                closeOverlay: navigator.pop,
                              ),
                            );
                          },
                          child: const Text('选择结果'),
                        ),
                      ),
                    );
                  }
                  hostContext = context;
                  return Scaffold(
                    body: Center(
                      child: FilledButton(
                        onPressed: () =>
                            Navigator.of(context).pushNamed('/search-overlay'),
                        child: const Text('打开搜索'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开搜索'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择结果'));
    await tester.pumpAndSettle();

    expect(find.text('人物详情'), findsOneWidget);
    expect(find.text('选择结果'), findsNothing);
  });

  test('搜索结果使用公共小窗，人物与剧集缩略图使用同一尺寸', () {
    final source = File(
      'lib/desktop/desktop_search_overlay.dart',
    ).readAsStringSync();

    expect(source, contains('DesktopFloatingPanel'));
    expect(source, contains('const size = Size(54, 72)'));
    expect(source, isNot(contains('Size.square(54)')));
    expect(source, contains('Duration(milliseconds: 650)'));
    expect(source, isNot(contains('Duration(milliseconds: 260)')));
  });
}

class _NavigatorPaneHost implements PlayerPaneHostController {
  _NavigatorPaneHost(this.navigatorKey);

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Future<bool> openRoute(String routeName) async {
    unawaited(navigatorKey.currentState!.pushNamed(routeName));
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
