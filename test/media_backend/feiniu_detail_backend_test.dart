import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/feiniu/feiniu_detail_mappers.dart';

void main() {
  group('extractFeiniuImdbId', () {
    test('顶层 imdb_id 优先', () {
      expect(
        extractFeiniuImdbId(<String, dynamic>{'imdb_id': 'tt100'}),
        'tt100',
      );
    });

    test('顶层缺失时回退 item.imdb_id', () {
      expect(
        extractFeiniuImdbId(<String, dynamic>{
          'imdb_id': '',
          'item': <String, dynamic>{'imdb_id': 'tt200'},
        }),
        'tt200',
      );
    });

    test('两处皆空返回空串', () {
      expect(extractFeiniuImdbId(<String, dynamic>{}), '');
      expect(
        extractFeiniuImdbId(<String, dynamic>{
          'item': <String, dynamic>{'imdb_id': '  '},
        }),
        '',
      );
    });
  });
}
