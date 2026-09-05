import 'dart:async';

import 'package:fly_player/media_backend/media_backend.dart';
import 'package:fly_player/media_backend/media_image_ref.dart';
import 'package:fly_player/media_backend/media_item_card.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_catalog_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MediaItemCard card(String id) => MediaItemCard(
    id: id,
    title: id,
    type: 'Movie',
    primaryImage: const MediaImageRef(url: 'primary'),
  );

  test('规范化 ID 的并发请求合并，并缓存成功结果', () async {
    final completer = Completer<List<MediaItemCard>>();
    final backend = _FakeMediaBackend(
      responses: <String, Future<List<MediaItemCard>>>{
        ' library-a ': completer.future,
      },
    );
    final session = PosterBrowseCatalogSession(backend: backend, itemLimit: 3);

    final first = session.load(' library-a ');
    final second = session.load('library-a');

    expect(identical(first, second), isTrue);
    expect(backend.calls, 1);
    expect(backend.catalogIds, <String>[' library-a ']);
    completer.complete(<MediaItemCard>[card('a')]);
    final results = await Future.wait(<Future<List<MediaItemCard>>>[
      first,
      second,
    ]);

    expect(identical(results[0], results[1]), isTrue);
    expect(await session.load(' library-a '), same(results[0]));
    expect(backend.calls, 1);
  });

  test('成功结果不可修改', () async {
    final backend = _FakeMediaBackend(
      responses: <String, Future<List<MediaItemCard>>>{
        'library-a': Future<List<MediaItemCard>>.value(<MediaItemCard>[
          card('a'),
        ]),
      },
    );
    final session = PosterBrowseCatalogSession(backend: backend, itemLimit: 3);

    final result = await session.load('library-a');

    expect(() => result.add(card('b')), throwsUnsupportedError);
  });

  test('请求失败不会缓存，后续调用会重试并继续抛出异常', () async {
    final backend = _FakeMediaBackend(
      responses: <String, Future<List<MediaItemCard>>>{
        'library-a': Future<List<MediaItemCard>>.error(StateError('first')),
      },
    );
    final session = PosterBrowseCatalogSession(backend: backend, itemLimit: 3);

    await expectLater(session.load('library-a'), throwsA(isA<StateError>()));
    backend.responses['library-a'] = Future<List<MediaItemCard>>.value(
      <MediaItemCard>[card('a')],
    );

    expect(await session.load('library-a'), hasLength(1));
    expect(backend.calls, 2);
  });

  test('后端同步抛错会以 Future 失败，并可在后续调用重试', () async {
    final backend = _FakeMediaBackend(
      synchronousFailures: 1,
      responses: <String, Future<List<MediaItemCard>>>{
        'library-a': Future<List<MediaItemCard>>.value(<MediaItemCard>[
          card('a'),
        ]),
      },
    );
    final session = PosterBrowseCatalogSession(backend: backend, itemLimit: 3);

    final first = session.load('library-a');
    await expectLater(first, throwsA(isA<StateError>()));

    expect((await session.load('library-a')).single.id, 'a');
    expect(backend.calls, 2);
  });

  test('负数 itemLimit 会在构造时失败', () {
    expect(
      () => PosterBrowseCatalogSession(
        backend: _FakeMediaBackend(),
        itemLimit: -1,
      ),
      throwsArgumentError,
    );
  });

  test('将 itemLimit 透传给后端，并截断到该上限', () async {
    final backend = _FakeMediaBackend(
      responses: <String, Future<List<MediaItemCard>>>{
        'library-a': Future<List<MediaItemCard>>.value(<MediaItemCard>[
          card('a'),
          card('b'),
          card('c'),
        ]),
      },
    );
    final session = PosterBrowseCatalogSession(backend: backend, itemLimit: 2);

    final result = await session.load('library-a');

    expect(backend.limits, <int>[2]);
    expect(result.map((item) => item.id), <String>['a', 'b']);
  });

  test('clear 会清空成功缓存，下一次调用重新请求', () async {
    final backend = _FakeMediaBackend(
      responses: <String, Future<List<MediaItemCard>>>{
        'library-a': Future<List<MediaItemCard>>.value(<MediaItemCard>[
          card('a'),
        ]),
      },
    );
    final session = PosterBrowseCatalogSession(backend: backend, itemLimit: 3);

    await session.load('library-a');
    session.clear();
    await session.load('library-a');

    expect(backend.calls, 2);
  });

  test('clear 前迟到的请求不会污染 clear 后新请求的缓存或在途状态', () async {
    final oldCompleter = Completer<List<MediaItemCard>>();
    final newCompleter = Completer<List<MediaItemCard>>();
    final backend = _FakeMediaBackend(
      queuedResponses: <Future<List<MediaItemCard>>>[
        oldCompleter.future,
        newCompleter.future,
      ],
    );
    final session = PosterBrowseCatalogSession(backend: backend, itemLimit: 3);

    final oldRequest = session.load(' library-a ');
    session.clear();
    final newRequest = session.load('library-a');
    oldCompleter.complete(<MediaItemCard>[card('old')]);
    await oldRequest;

    final duplicateNewRequest = session.load(' library-a ');
    expect(backend.calls, 2);
    newCompleter.complete(<MediaItemCard>[card('new')]);
    final result = await newRequest;

    expect(await duplicateNewRequest, same(result));
    expect(result.single.id, 'new');
    expect(await session.load('library-a'), same(result));
    expect(backend.calls, 2);
  });
}

class _FakeMediaBackend extends MediaBackend {
  _FakeMediaBackend({
    this.responses = const <String, Future<List<MediaItemCard>>>{},
    this.queuedResponses = const <Future<List<MediaItemCard>>>[],
    this.synchronousFailures = 0,
  });

  final Map<String, Future<List<MediaItemCard>>> responses;
  final List<Future<List<MediaItemCard>>> queuedResponses;
  int synchronousFailures;
  final List<String> catalogIds = <String>[];
  final List<int> limits = <int>[];
  int calls = 0;

  @override
  Future<List<MediaItemCard>> getCatalogPreviewItems(
    String catalogId, {
    int page = 1,
    int limit = 30,
  }) {
    calls += 1;
    catalogIds.add(catalogId);
    limits.add(limit);
    if (synchronousFailures > 0) {
      synchronousFailures -= 1;
      throw StateError('synchronous failure');
    }
    if (queuedResponses.isNotEmpty) {
      return queuedResponses.removeAt(0);
    }
    return responses[catalogId] ??
        Future<List<MediaItemCard>>.value(<MediaItemCard>[]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
