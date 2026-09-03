import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/desktop_floating_panel.dart';
import 'package:fly_player/desktop/desktop_search_overlay.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/media_backend/media_backend.dart';
import 'package:fly_player/media_backend/media_backend_capabilities.dart';
import 'package:fly_player/media_backend/media_image_ref.dart';
import 'package:fly_player/media_backend/media_item_card.dart';
import 'package:fly_player/providers/media_backend_provider.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/ui/player_pane_host_scope.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

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
    expect(source, isNot(contains('_searchDebounce')));
    expect(source, isNot(contains('_contentKey')));
  });

  testWidgets('输入立即搜索且请求切换期间结果窗持续存在', (tester) async {
    final backend = _ControlledSearchBackend();
    final hostContext = await _pumpSearchHost(tester, backend);
    unawaited(showDesktopSearch(hostContext));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '白');
    await tester.pump();
    expect(backend.queries, <String>['白']);

    backend.complete('白', const <MediaItemCard>[
      MediaItemCard(
        id: 'item-1',
        title: '白箱',
        type: 'Movie',
        primaryImage: MediaImageRef.empty,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('白箱'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '白箱');
    await tester.pump();
    expect(backend.queries, <String>['白', '白箱']);
    expect(find.byType(DesktopFloatingPanel), findsOneWidget);
    final resultTitle = find.descendant(
      of: find.byType(DesktopFloatingPanel),
      matching: find.text('白箱'),
    );
    expect(resultTitle, findsOneWidget);

    backend.complete('白箱', const <MediaItemCard>[]);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopFloatingPanel), findsOneWidget);
    expect(resultTitle, findsNothing);
  });

  testWidgets('搜索弹层外滚轮继续滚动底层页面', (tester) async {
    final backend = _ControlledSearchBackend();
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    final hostContext = await _pumpSearchHost(
      tester,
      backend,
      scrollController: scrollController,
    );
    unawaited(showDesktopSearch(hostContext));
    await tester.pumpAndSettle();

    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(100, 500),
        scrollDelta: Offset(0, 240),
      ),
    );
    await tester.pumpAndSettle();

    expect(scrollController.offset, greaterThan(0));
  });
}

Future<BuildContext> _pumpSearchHost(
  WidgetTester tester,
  _ControlledSearchBackend backend, {
  ScrollController? scrollController,
}) async {
  final nasProvider = NasProvider();
  final mediaProvider = _TestMediaBackendProvider(nasProvider, backend);
  late BuildContext hostContext;
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<NasProvider>.value(value: nasProvider),
        ChangeNotifierProvider<MediaBackendProvider>.value(
          value: mediaProvider,
        ),
      ],
      child: MaterialApp(
        theme: AppThemeBuilder.build(AppThemePreset.midnight),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            hostContext = context;
            return Scaffold(
              body: ListView(
                controller: scrollController,
                children: const <Widget>[SizedBox(height: 1800)],
              ),
            );
          },
        ),
      ),
    ),
  );
  return hostContext;
}

class _ControlledSearchBackend extends Fake implements MediaBackend {
  final List<String> queries = <String>[];
  final Map<String, Completer<List<MediaItemCard>>> _requests =
      <String, Completer<List<MediaItemCard>>>{};

  @override
  MediaBackendCapabilities get capabilities =>
      const MediaBackendCapabilities.feiniu();

  @override
  Future<List<MediaItemCard>> searchItems(String query) {
    queries.add(query);
    final request = Completer<List<MediaItemCard>>();
    _requests[query] = request;
    return request.future;
  }

  void complete(String query, List<MediaItemCard> results) {
    _requests[query]!.complete(results);
  }
}

class _TestMediaBackendProvider extends MediaBackendProvider {
  _TestMediaBackendProvider(super.nasProvider, this.backendValue);

  final MediaBackend backendValue;

  @override
  MediaBackend get backend => backendValue;
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
