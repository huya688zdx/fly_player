import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/screens/fly_catalog_screen.dart';
import 'package:fly_player/services/fly_data/fly_account_controller.dart';
import 'package:fly_player/services/fly_data/fly_data_service.dart';
import 'package:fly_player/services/play_stats/play_stats_database.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/providers/backend_session_provider.dart';
import 'package:fly_player/services/secure_credential_store.dart';
import 'package:fly_player/ui/app_info_popover.dart';
import 'package:fly_player/ui/media_detail_components.dart';
import 'package:fly_player/widgets/common/app_error_state.dart';
import 'package:fly_player/widgets/common/app_option_list.dart';

class _CatalogService extends FlyDataService {
  _CatalogService()
    : super(database: SqflitePlayStatsDatabase(), drainWrites: () async {}) {
    session = FlyDataSession(
      serverUrl: 'https://test.example',
      userId: 'alice',
      username: 'alice',
      deviceId: 'd',
      deviceName: 'd',
      token: 'test',
      installationId: 'i',
      serviceInstanceId: 'instance',
    );
  }
  final requests = <String>[];
  final queries = <Map<String, dynamic>?>[];
  Future<Map<String, dynamic>> Function(String, Map<String, dynamic>?)? respond;
  Future<Uint8List> Function(String)? image;
  void switchUser(String user) {
    session = FlyDataSession(
      serverUrl: 'https://test.example',
      userId: user,
      username: user,
      deviceId: 'd',
      deviceName: 'd',
      token: 'test',
      installationId: 'i',
      serviceInstanceId: 'instance',
    );
  }

  @override
  Future<Uint8List> imageBytes(String mediaId) => image!(mediaId);
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    bool patch = false,
  }) async {
    requests.add(path);
    queries.add(query);
    if (respond != null) return respond!(path, query);
    final episode = {
      'id': 'episode',
      'binding_id': 'binding',
      'title': '第 1 集',
      'kind': 'episode',
      'remote_item_id': 'ep',
      'parent_id': 'season',
      'overview': '真实单集简介',
      'catalog_completeness': 'confirmed',
    };
    final season = {
      'id': 'season',
      'binding_id': 'binding',
      'title': '第 1 季',
      'kind': 'season',
      'remote_item_id': 's',
      'parent_id': 'series',
      'season_number': 1,
      'catalog_completeness': 'confirmed',
    };
    final series = {
      'id': 'series',
      'binding_id': 'binding',
      'title': 'NAS 番剧',
      'kind': 'series',
      'remote_item_id': 'series-remote',
      'overview': '真实剧集简介',
      'year': 2026,
      'catalog_completeness': 'confirmed',
    };
    if (path == '/media') {
      expect(query?['binding_id'], 'binding');
      return {
        'items': [series],
        'total': 1,
        'next_cursor': null,
      };
    }
    if (path == '/media/series') {
      return {
        ...series,
        'children': [season],
        'sources': [],
      };
    }
    if (path == '/media/season') {
      return {
        ...season,
        'children': [episode],
        'sources': [],
      };
    }
    return {...episode, 'children': [], 'sources': []};
  }
}

void main() {
  _scopeTests();
  for (final (locale, catalogTitle, syncTooltip, openDetails, metadata, count)
      in [
        (
          const Locale('zh', 'CN'),
          '已同步节目',
          '同步信息：NAS 番剧',
          '打开节目详情',
          '剧集 · 2026 · 评分 未知',
          '1 部节目',
        ),
        (
          const Locale('en'),
          'Synced titles',
          'Sync information: NAS 番剧',
          'Open title details',
          'TV series · 2026 · Rating Unknown',
          '1 title',
        ),
        (
          const Locale('ja'),
          '同期済みの作品',
          '同期情報：NAS 番剧',
          '作品の詳細を開く',
          'TVシリーズ · 2026 · 評価 不明',
          '1 作品',
        ),
      ]) {
    testWidgets(
      'synced poster collection localizes sync information in $locale',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        SecureCredentialStore.setBackendForTesting(
          MemorySecureCredentialBackend(),
        );
        final nas = NasProvider(),
            backend = BackendSessionProvider(autoLoad: false),
            service = _CatalogService();
        final account =
            FlyAccountController(
                nas: nas,
                backendSession: backend,
                service: service,
                autoLoad: false,
              )
              ..ready = true
              ..activeBindingId = 'binding';
        account.bindings = [
          {'id': 'binding', 'label': 'Emby'},
        ];
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: account,
            child: MaterialApp(
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const FlyCatalogScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(catalogTitle), findsOneWidget);
        expect(find.text(count), findsOneWidget);
        expect(find.byType(SliverGrid), findsOneWidget);
        expect(find.byType(ListTile), findsNothing);
        expect(find.text('NAS 番剧'), findsOneWidget);
        expect(find.byType(AppInfoPopoverAnchor), findsOneWidget);
        expect(
          find.byTooltip(switch (locale.languageCode) {
            'en' => 'About synced titles',
            'ja' => '同期済み作品について',
            _ => '同步节目说明',
          }),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip(syncTooltip));
        await tester.pumpAndSettle();
        expect(find.text('真实剧集简介'), findsOneWidget);
        expect(find.byType(DetailOverview), findsOneWidget);
        expect(
          find.text(switch (locale.languageCode) {
            'en' => 'Info assistant · Current title',
            'ja' => '情報アシスタント · 現在の作品',
            _ => '资料助手 · 当前节目',
          }),
          findsOneWidget,
        );
        expect(find.byType(AppOptionListTile), findsOneWidget);
        expect(find.text(metadata), findsOneWidget);
        await tester.tap(find.text('第 1 季'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('第 1 集'));
        await tester.pumpAndSettle();
        expect(find.text('真实单集简介'), findsOneWidget);
        expect(find.text(openDetails), findsOneWidget);
        expect(service.requests, [
          '/media',
          '/media/series',
          '/media/season',
          '/media/episode',
        ]);
        await tester.pumpWidget(const SizedBox());
        account.dispose();
        nas.dispose();
        backend.dispose();
      },
    );
  }
}

class _ScopeService extends _CatalogService {
  final loads = <Completer<Map<String, dynamic>>>[];
  final pictures = <Completer<Uint8List>>[];
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    bool patch = false,
  }) {
    final request = Completer<Map<String, dynamic>>();
    loads.add(request);
    return request.future;
  }

  @override
  Future<Uint8List> imageBytes(String mediaId) {
    final picture = Completer<Uint8List>();
    pictures.add(picture);
    return picture.future;
  }
}

class _ScopeAccount extends FlyAccountController {
  _ScopeAccount(FlyDataService service)
    : super(
        nas: NasProvider(),
        backendSession: BackendSessionProvider(autoLoad: false),
        service: service,
        autoLoad: false,
      ) {
    activeBindingId = 'binding';
    bindings = [
      {'id': 'binding', 'label': '家里的飞牛'},
    ];
  }
  void changeAccount() {
    service.session = FlyDataSession(
      serverUrl: 'https://test.example',
      userId: 'bob',
      username: 'bob',
      deviceId: 'd2',
      deviceName: 'd2',
      token: 'bob-token',
      installationId: 'i2',
      serviceInstanceId: 'instance',
    );
    notifyListeners();
  }

  @override
  void dispose() {
    nas.dispose();
    backendSession.dispose();
    super.dispose();
  }
}

void _scopeTests() {
  late _ScopeService service;
  late _ScopeAccount account;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SecureCredentialStore.setBackendForTesting(MemorySecureCredentialBackend());
    service = _ScopeService();
    account = _ScopeAccount(service);
  });
  tearDown(() {
    account.dispose();
    SecureCredentialStore.resetBackendForTesting();
  });
  Widget host(Widget child, {Locale locale = const Locale('zh', 'CN')}) =>
      ChangeNotifierProvider<FlyAccountController>.value(
        value: account,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: child,
        ),
      );
  Map<String, dynamic> page(String name) => {
    'items': [
      {
        'id': name,
        'binding_id': 'binding',
        'title': name,
        'kind': 'series',
        'remote_item_id': 'remote-$name',
      },
    ],
    'total': 1,
    'next_cursor': null,
  };

  testWidgets('late catalog response cannot replace another account posters', (
    tester,
  ) async {
    await tester.pumpWidget(host(const FlyCatalogScreen()));
    await tester.pump();
    expect(service.loads, hasLength(1));
    account.changeAccount();
    await tester.pump();
    await tester.pump();
    expect(service.loads, hasLength(2));
    service.loads[1].complete(page('新账号节目'));
    await tester.pumpAndSettle();
    service.loads[0].complete(page('旧账号节目'));
    await tester.pumpAndSettle();
    expect(find.text('新账号节目'), findsOneWidget);
    expect(find.text('旧账号节目'), findsNothing);
  });

  testWidgets(
    'catalog load failure reuses the app error state and retries the same source',
    (tester) async {
      await tester.pumpWidget(host(const FlyCatalogScreen()));
      await tester.pump();
      service.loads.single.completeError(StateError('节目读取失败'));
      await tester.pumpAndSettle();
      expect(find.byType(AppErrorState), findsOneWidget);
      final error = tester.widget<AppErrorState>(find.byType(AppErrorState));
      expect(error.error.message, '节目读取失败');
      expect(find.text('节目读取失败').hitTestable(), findsOneWidget);
      error.onRetry!();
      await tester.pump();
      expect(service.loads, hasLength(2));
      service.loads.last.complete(page('重试后的节目'));
      await tester.pumpAndSettle();
      expect(find.text('重试后的节目'), findsOneWidget);
    },
  );

  testWidgets(
    'poster never reuses the previous account image while next request waits',
    (tester) async {
      await tester.pumpWidget(
        host(
          const Scaffold(
            body: SizedBox(
              width: 160,
              height: 240,
              child: FlyCatalogPoster(mediaId: 'same-item'),
            ),
          ),
        ),
      );
      final oldPicture = Uint8List.fromList(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aXioAAAAASUVORK5CYII=',
        ),
      );
      service.pictures[0].complete(oldPicture);
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      account.changeAccount();
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      final newPicture = Uint8List.fromList(oldPicture);
      service.pictures[1].complete(newPicture);
      await tester.pumpAndSettle();
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as MemoryImage).bytes, same(newPicture));
    },
  );

  testWidgets('stale program action does not navigate after account changes', (
    tester,
  ) async {
    late BuildContext pageContext;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) {
            pageContext = context;
            return const Scaffold(body: Text('首页'));
          },
        ),
      ),
    );
    final originalAccount = account.accountKey;
    account.changeAccount();
    await tester.pump();
    await expectLater(
      openFlyCatalogItem(pageContext, {
        'binding_id': 'binding',
        'remote_item_id': 'old-remote',
        'kind': 'series',
      }, expectedAccountKey: originalAccount),
      throwsStateError,
    );
    expect(find.text('首页'), findsOneWidget);
    expect(service.loads, isEmpty);
  });

  testWidgets('missing media source uses the active English locale', (
    tester,
  ) async {
    late BuildContext pageContext;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) {
            pageContext = context;
            return const Scaffold(body: Text('Home'));
          },
        ),
        locale: const Locale('en'),
      ),
    );
    await expectLater(
      openFlyCatalogItem(pageContext, {
        'binding_id': 'binding',
        'remote_item_id': '',
        'kind': 'series',
      }, expectedAccountKey: account.accountKey),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'This title is not linked to a media source yet. Refresh the sync information.',
        ),
      ),
    );
    expect(service.loads, isEmpty);
    expect(find.text('Home'), findsOneWidget);
  });
}
