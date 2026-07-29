import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/media_image_ref.dart';
import 'package:fly_player/media_backend/media_item_card.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_rows.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_screen_policy.dart';

void main() {
  test('已有 rows 且焦点为空时构建页面壳而非全局错误', () {
    expect(
      PosterBrowseScreenPolicy.bodyFor(
        loading: false,
        hasRows: true,
        hasFocusedItem: false,
      ),
      PosterBrowseScreenBody.shell,
    );
  });

  test('目录 idle loading failed 点击均立即选择并请求加载', () {
    for (final state in const [
      PosterBrowseRowLoadState.idle,
      PosterBrowseRowLoadState.loading,
      PosterBrowseRowLoadState.failed,
    ]) {
      final decision = PosterBrowseScreenPolicy.selectionFor(
        PosterBrowseRow(
          kind: PosterBrowseRowKind.catalog,
          items: const <MediaItemCard>[],
          loadState: state,
        ),
      );

      expect(decision.selectImmediately, isTrue);
      expect(decision.loadCatalog, isTrue);
      expect(decision.settleItem, isFalse);
    }
  });

  test('loaded 空目录只立即选择且不重复请求', () {
    final decision = PosterBrowseScreenPolicy.selectionFor(
      const PosterBrowseRow(
        kind: PosterBrowseRowKind.catalog,
        items: <MediaItemCard>[],
        loadState: PosterBrowseRowLoadState.loaded,
      ),
    );

    expect(decision.selectImmediately, isTrue);
    expect(decision.loadCatalog, isFalse);
    expect(decision.settleItem, isFalse);
  });

  test('有条目时立即选择并 settle 且不请求目录', () {
    final decision = PosterBrowseScreenPolicy.selectionFor(
      PosterBrowseRow(
        kind: PosterBrowseRowKind.catalog,
        items: [_card('item-1')],
        loadState: PosterBrowseRowLoadState.loaded,
      ),
    );

    expect(decision.selectImmediately, isTrue);
    expect(decision.loadCatalog, isFalse);
    expect(decision.settleItem, isTrue);
  });
}

MediaItemCard _card(String id) {
  return MediaItemCard(
    id: id,
    title: id,
    type: 'Movie',
    primaryImage: MediaImageRef.empty,
  );
}
