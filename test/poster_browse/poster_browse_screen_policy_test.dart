import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/media_image_ref.dart';
import 'package:fly_player/media_backend/media_item_card.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_rows.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_enrichment_commit_policy.dart';
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
      expect(decision.invalidateFocus, isTrue);
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
    expect(decision.invalidateFocus, isTrue);
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
    expect(decision.invalidateFocus, isFalse);
  });

  test('选择空行后旧补全只提交展示而不再应用焦点副作用', () {
    final selection = PosterBrowseScreenPolicy.selectionFor(
      const PosterBrowseRow(
        kind: PosterBrowseRowKind.catalog,
        items: <MediaItemCard>[],
        loadState: PosterBrowseRowLoadState.loading,
      ),
    );
    const requestFocusGeneration = 7;
    final currentFocusGeneration =
        requestFocusGeneration + (selection.invalidateFocus ? 1 : 0);

    final commit = PosterBrowseEnrichmentCommitPolicy.resolve(
      requestLoadGeneration: 4,
      currentLoadGeneration: 4,
      requestFocusGeneration: requestFocusGeneration,
      currentFocusGeneration: currentFocusGeneration,
    );

    expect(commit.commitDisplay, isTrue);
    expect(commit.applyFocusEffects, isFalse);
  });

  test('settled id 仅在与当前焦点身份一致时读取展示缓存', () {
    const oldDisplay = '旧背景';
    const currentDisplay = '当前背景';

    expect(
      PosterBrowseScreenPolicy.settledItemFor<String>(
        settledItemId: 'old',
        focusedItemId: null,
        displayById: const <String, String>{'old': oldDisplay},
        focusedItem: null,
      ),
      isNull,
    );
    expect(
      PosterBrowseScreenPolicy.settledItemFor<String>(
        settledItemId: 'old',
        focusedItemId: 'current',
        displayById: const <String, String>{'old': oldDisplay},
        focusedItem: currentDisplay,
      ),
      currentDisplay,
    );
    expect(
      PosterBrowseScreenPolicy.settledItemFor<String>(
        settledItemId: 'current',
        focusedItemId: 'current',
        displayById: const <String, String>{'current': '已补全背景'},
        focusedItem: currentDisplay,
      ),
      '已补全背景',
    );
  });

  test('目录索引失败行立即选择、失效旧焦点并仅重试目录元数据', () {
    final decision = PosterBrowseScreenPolicy.selectionFor(
      const PosterBrowseRow(
        kind: PosterBrowseRowKind.catalogIndex,
        items: <MediaItemCard>[],
        loadState: PosterBrowseRowLoadState.failed,
      ),
    );

    expect(decision.selectImmediately, isTrue);
    expect(decision.invalidateFocus, isTrue);
    expect(decision.reloadCatalogs, isTrue);
    expect(decision.loadCatalog, isFalse);
    expect(decision.settleItem, isFalse);
  });

  test('目录索引加载中重复选择不再次请求', () {
    final decision = PosterBrowseScreenPolicy.selectionFor(
      const PosterBrowseRow(
        kind: PosterBrowseRowKind.catalogIndex,
        items: <MediaItemCard>[],
        loadState: PosterBrowseRowLoadState.loading,
      ),
    );

    expect(decision.reloadCatalogs, isFalse);
    expect(decision.loadCatalog, isFalse);
  });

  test('目录元数据返回时仅在占位行仍被选中时选择首目录', () {
    expect(
      PosterBrowseScreenPolicy.shouldSelectReloadedCatalog(
        catalogIndexRow: 1,
        currentSelectedRow: 1,
      ),
      isTrue,
    );
    expect(
      PosterBrowseScreenPolicy.shouldSelectReloadedCatalog(
        catalogIndexRow: 1,
        currentSelectedRow: 0,
      ),
      isFalse,
    );
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
