import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/utils/route_query_json.dart';

void main() {
  group('RouteQueryJson.tryDecodeMap', () {
    test('returns decoded map for valid object JSON', () {
      expect(
        RouteQueryJson.tryDecodeMap('{"guid":"item-1","title":"标题"}'),
        <String, dynamic>{'guid': 'item-1', 'title': '标题'},
      );
    });

    test('returns null for empty, malformed, or non-object JSON', () {
      expect(RouteQueryJson.tryDecodeMap(''), isNull);
      expect(RouteQueryJson.tryDecodeMap('{bad json'), isNull);
      expect(RouteQueryJson.tryDecodeMap('["not","a","map"]'), isNull);
    });
  });

  group('RouteQueryJson.tryDecodeStringList', () {
    test('returns stringified values for valid array JSON', () {
      expect(RouteQueryJson.tryDecodeStringList('["电影", 2026, true]'), <String>[
        '电影',
        '2026',
        'true',
      ]);
    });

    test('returns null for empty, malformed, or non-array JSON', () {
      expect(RouteQueryJson.tryDecodeStringList(''), isNull);
      expect(RouteQueryJson.tryDecodeStringList('[bad json'), isNull);
      expect(RouteQueryJson.tryDecodeStringList('{"not":"a list"}'), isNull);
    });
  });
}
