import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/media_backend/action/media_item_action_target.dart';

void main() {
  test('操作目标使用后端中立的布尔已看状态', () {
    const target = MediaItemActionTarget(
      id: 'item-1',
      baseTitle: '测试条目',
      type: 'movie',
      watched: true,
    );

    expect(target.watched, isTrue);
    expect(target.isWatched, isTrue);
  });
}
