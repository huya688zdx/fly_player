import 'dart:collection';

class PosterBrowseSelectionState {
  final Map<int, int> _rowIndexes = <int, int>{};

  int selectedRow = 0;

  int get currentIndex => indexForRow(selectedRow);

  UnmodifiableMapView<int, int> get snapshot =>
      UnmodifiableMapView<int, int>(Map<int, int>.from(_rowIndexes));

  int indexForRow(int row) => _rowIndexes[_nonNegative(row)] ?? 0;

  void select({required int rowIndex, required int itemIndex}) {
    final row = _nonNegative(rowIndex);
    selectedRow = row;
    _rowIndexes[row] = _nonNegative(itemIndex);
  }

  void selectRow(int rowIndex) {
    selectedRow = _nonNegative(rowIndex);
  }

  void reset({int rowIndex = 0}) {
    _rowIndexes.clear();
    selectedRow = _nonNegative(rowIndex);
  }

  void normalizeForRows(List<int> lengths) {
    if (lengths.isEmpty) {
      _rowIndexes.clear();
      selectedRow = 0;
      return;
    }

    _rowIndexes.removeWhere((row, _) => row >= lengths.length);
    for (final row in _rowIndexes.keys.toList(growable: false)) {
      final length = lengths[row];
      final index = _rowIndexes[row] ?? 0;
      _rowIndexes[row] = length <= 0 ? 0 : _clamp(index, 0, length - 1);
    }
    selectedRow = _clamp(selectedRow, 0, lengths.length - 1);
  }

  static int _nonNegative(int value) => value < 0 ? 0 : value;

  static int _clamp(int value, int min, int max) {
    if (value < min) {
      return min;
    }
    if (value > max) {
      return max;
    }
    return value;
  }
}
