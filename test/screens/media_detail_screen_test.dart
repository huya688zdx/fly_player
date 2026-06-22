import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/media_backend/detail/media_detail.dart';
import 'package:fly_player/media_backend/media_backend.dart';
import 'package:fly_player/media_backend/media_image_ref.dart';
import 'package:fly_player/providers/media_backend_provider.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/screens/media_detail_screen.dart';

/// 只实现 getItemDetail，其余成员经 noSuchMethod 抛错（本屏不应触达）。
class _FakeBackend implements MediaBackend {
  _FakeBackend(this.detail);

  final MediaDetail detail;
  String? lastItemId;

  @override
  Future<MediaDetail> getItemDetail(String itemId) async {
    lastItemId = itemId;
    return detail;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// 覆盖 backend getter，注入 fake，绕开真实后端构造。
class _FakeBackendProvider extends MediaBackendProvider {
  _FakeBackendProvider(super.nasProvider, this._backend);

  final MediaBackend _backend;

  @override
  MediaBackend get backend => _backend;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const detail = MediaDetail(
    id: 'm-1',
    type: 'Movie',
    title: '银翼杀手 2049',
    primaryImage: MediaImageRef(url: 'https://e.test/p?api_key=t'),
    overview: '简介文本内容',
    rating: '8.0',
    releaseDate: '2017-10-06T00:00:00.0000000Z',
    runtimeMinutes: 164,
    genreLabels: <String>['科幻', '剧情'],
    regionLabels: <String>['美国'],
    people: <MediaDetailPerson>[
      MediaDetailPerson(
        id: 'pp-1',
        name: 'Ryan Gosling',
        role: 'K',
        department: 'Actor',
      ),
    ],
  );

  testWidgets('Emby 详情：标题/元信息/题材/简介/演职员/播放占位 渲染', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final fake = _FakeBackend(detail);
    final provider = _FakeBackendProvider(NasProvider(), fake);

    await tester.pumpWidget(
      ChangeNotifierProvider<MediaBackendProvider>.value(
        value: provider,
        child: const MaterialApp(home: MediaDetailScreen(itemId: 'm-1')),
      ),
    );
    await tester.pump(); // 解析 getItemDetail future
    await tester.pump(const Duration(milliseconds: 300));

    expect(fake.lastItemId, 'm-1');
    expect(find.text('银翼杀手 2049'), findsOneWidget);
    expect(find.text('科幻'), findsOneWidget);
    expect(find.text('美国'), findsOneWidget);
    expect(find.textContaining('简介文本内容'), findsWidgets);
    expect(find.text('Ryan Gosling'), findsOneWidget);
    expect(find.text('饰 K'), findsOneWidget); // CreditPersonPresenter 角色文案
    expect(find.text('2017'), findsNothing); // 年份并入元信息行，非独立文本

    // 播放入口为占位、禁用态。
    final playButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '播放功能即将到来'),
    );
    expect(playButton.onPressed, isNull);
  });

  testWidgets('加载失败显示重试', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final provider = _FakeBackendProvider(NasProvider(), _ThrowingBackend());

    await tester.pumpWidget(
      ChangeNotifierProvider<MediaBackendProvider>.value(
        value: provider,
        child: const MaterialApp(home: MediaDetailScreen(itemId: 'm-1')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });
}

class _ThrowingBackend implements MediaBackend {
  @override
  Future<MediaDetail> getItemDetail(String itemId) async =>
      throw StateError('boom');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
