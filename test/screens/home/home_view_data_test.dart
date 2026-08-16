import 'package:fly_player/screens/home/home_view_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty 快照可只替换概要，其余首页区块保持为空', () {
    const empty = HomeViewData.empty();

    final updated = empty.copyWith(
      summary: const <String, dynamic>{'movie': 12},
    );

    expect(updated.summary, const <String, dynamic>{'movie': 12});
    expect(updated.catalogs, isEmpty);
    expect(updated.continueWatching, isEmpty);
    expect(updated.nextUp, isEmpty);
    expect(updated.latest, isEmpty);
  });
}
