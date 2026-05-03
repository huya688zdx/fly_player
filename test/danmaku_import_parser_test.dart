import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/danmaku/models/danmaku_comment.dart';
import 'package:fly_player/danmaku/parser/danmaku_import_parser.dart';

void main() {
  group('DanmakuImportParser fixed-position modes', () {
    test('maps Bilibili XML mode 4 to bottom and mode 5 to top', () {
      final result = DanmakuImportParser.parseXmlString(
        '<i>'
        '<d p="1.0,4,25,16777215,0,0,0,1">bottom</d>'
        '<d p="2.0,5,25,16777215,0,0,0,2">top</d>'
        '</i>',
      );

      expect(result.comments[0].type, DanmakuCommentType.bottom);
      expect(result.comments[1].type, DanmakuCommentType.top);
    });

    test('maps DanDanPlay XML mode 4 to bottom and mode 5 to top', () {
      final result = DanmakuImportParser.parseContentString(
        '<Danmaku>'
        '<item time="1.0" mode="4" color="16777215" text="bottom" />'
        '<item time="2.0" mode="5" color="16777215" text="top" />'
        '</Danmaku>',
      );

      expect(result.comments[0].type, DanmakuCommentType.bottom);
      expect(result.comments[1].type, DanmakuCommentType.top);
    });

    test('maps JSON mode 4 to bottom and mode 5 to top', () {
      final result = DanmakuImportParser.parseContentString(
        '['
        '{"time":1,"mode":4,"color":16777215,"text":"bottom"},'
        '{"time":2,"mode":5,"color":16777215,"text":"top"}'
        ']',
      );

      expect(result.comments[0].type, DanmakuCommentType.bottom);
      expect(result.comments[1].type, DanmakuCommentType.top);
    });
  });
}
