import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/models/media_item.dart';
import 'package:fly_player/models/media_library_item.dart';
import 'package:fly_player/models/person_credit.dart';

void main() {
  test('媒体模型缺少标题时不写入英文 Unknown', () {
    final mediaItem = MediaItem.fromJson(const <String, dynamic>{});
    final libraryItem = MediaLibraryItem.fromJson(const <String, dynamic>{});

    expect(mediaItem.name, '');
    expect(libraryItem.title, '');
    expect(libraryItem.displayTitle, '');
  });

  test('人物模型缺少展示字段时不生成中文 UI 占位文案', () {
    final credit = PersonCredit.fromJson(const <String, dynamic>{});

    expect(credit.displayName, '');
    expect(credit.displaySubTitle, '');
  });
}
