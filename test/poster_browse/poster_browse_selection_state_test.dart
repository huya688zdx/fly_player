import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_selection_state.dart';

void main() {
  group('PosterBrowseSelectionState', () {
    test('分组分别记忆 4/2 并切回', () {
      final state = PosterBrowseSelectionState();

      state.select(rowIndex: 0, itemIndex: 4);
      state.select(rowIndex: 1, itemIndex: 2);
      state.selectRow(0);

      expect(state.selectedRow, 0);
      expect(state.currentIndex, 4);
      expect(state.indexForRow(1), 2);

      state.selectRow(1);

      expect(state.selectedRow, 1);
      expect(state.currentIndex, 2);
    });

    test('未知行返回 0', () {
      final state = PosterBrowseSelectionState();

      expect(state.indexForRow(99), 0);
      state.selectRow(99);
      expect(state.currentIndex, 0);
    });

    test('负输入归零', () {
      final state = PosterBrowseSelectionState();

      state.select(rowIndex: -1, itemIndex: -3);

      expect(state.selectedRow, 0);
      expect(state.currentIndex, 0);
      expect(state.snapshot, {0: 0});

      state.selectRow(-2);
      expect(state.selectedRow, 0);
      expect(state.indexForRow(-1), 0);
    });

    test('normalize 会删除超出行数的记录并按条目长度收缩索引', () {
      final state = PosterBrowseSelectionState()
        ..select(rowIndex: 0, itemIndex: 4)
        ..select(rowIndex: 1, itemIndex: 2)
        ..select(rowIndex: 2, itemIndex: 5);

      state.normalizeForRows([3, 0]);

      expect(state.selectedRow, 1);
      expect(state.snapshot, {0: 2, 1: 0});
      expect(state.currentIndex, 0);
    });

    test('normalize 空列表会清空记录并把选中行归零', () {
      final state = PosterBrowseSelectionState()
        ..select(rowIndex: 2, itemIndex: 5);

      state.normalizeForRows([]);

      expect(state.selectedRow, 0);
      expect(state.currentIndex, 0);
      expect(state.snapshot, isEmpty);
    });

    test('reset 清空记忆并可指定选中行', () {
      final state = PosterBrowseSelectionState()
        ..select(rowIndex: 0, itemIndex: 4)
        ..select(rowIndex: 1, itemIndex: 2);

      state.reset(rowIndex: 3);

      expect(state.selectedRow, 3);
      expect(state.currentIndex, 0);
      expect(state.snapshot, isEmpty);
    });

    test('reset 的负行号归零', () {
      final state = PosterBrowseSelectionState()
        ..select(rowIndex: 1, itemIndex: 2);

      state.reset(rowIndex: -1);

      expect(state.selectedRow, 0);
      expect(state.snapshot, isEmpty);
    });

    test('snapshot 不可修改', () {
      final state = PosterBrowseSelectionState()
        ..select(rowIndex: 0, itemIndex: 4);

      expect(state.snapshot, isA<UnmodifiableMapView<int, int>>());
      expect(() => state.snapshot[0] = 1, throwsUnsupportedError);
      expect(state.indexForRow(0), 4);
    });
  });
}
