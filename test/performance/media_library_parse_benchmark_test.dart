import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/models/media_library_item.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_loader.dart';

/// 媒体库列表的**客户端**解析压力基准。
///
/// 为什么需要它：真机大库（400+ 剧集）无法在测试 NAS 上复现，但客户端这条链
/// （`jsonDecode` → `MediaLibraryItem.fromJson` × N）是可以在本地用合成数据压的。
/// 行结构照抄实测抓到的真实字段（见下方 `_syntheticRow`）。
///
/// 注意：`flutter test` 跑在 JIT 下，绝对耗时比 release AOT 偏慢，**看量级与比例，
/// 不要当绝对值**。
///
/// 结论只用于回答一个问题：页大小从 500 改成 50 之后，客户端每页的解析负担降到多少。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 实测单条约 1.1–1.5 KB（抓包口径），这里按 ~1.3 KB 构造。
  Map<String, Object?> syntheticRow(int i) => <String, Object?>{
    'guid': 'guid-${i.toString().padLeft(6, '0')}-0123456789abcdef',
    'title': '示例剧集名称 $i',
    'tv_title': '示例剧集名称 $i',
    'type': i.isEven ? 'TV' : 'Movie',
    'poster': 'https://example.invalid/media/poster/${i}_poster_400x600.jpg',
    'poster_list': <String>[
      'https://example.invalid/media/poster/${i}_poster_400x600.jpg',
      'https://example.invalid/media/poster/${i}_poster_800x1200.jpg',
    ],
    'poster_width': 400,
    'poster_height': 600,
    'overview':
        '这是一段用于压测的剧情简介，长度接近真实数据。'
        '在真实库里 overview 常见两三百字，中文占三字节，是单行体积的主要来源之一。'
        '再补一些字让长度更接近真实情况，避免低估解析开销。',
    'first_air_date': '2023-04-01',
    'last_air_date': '2024-09-20',
    'vote_average': '8.6',
    'watched': i % 3 == 0 ? 1 : 0,
    'watched_ts': 1234 + i,
    'ts': 5678 + i,
    'duration': 1440,
    'season_number': 1 + (i % 3),
    'episode_number': 1 + (i % 24),
    'number_of_seasons': 3,
    'number_of_episodes': 24,
    'local_number_of_seasons': 3,
    'local_number_of_episodes': 24,
    'parent_guid': i.isEven ? '' : 'parent-$i',
    'ancestor_guid': 'd98318daec6e4bb7972c78b9ea2de317',
    'ancestor_name': '动漫TV',
    'is_favorite': 0,
    'status': 'Ended',
    'lan': 'zh-CN',
    'imdb_id': 'tt0000$i',
    'trim_id': 'trim-$i',
    'media_stream': <String, Object?>{
      'resolutions': <String>['4k', '1080p', '720p'],
      'audio_type': <String>['AAC', 'AC3'],
      'color_range': <String>['SDR'],
    },
  };

  /// 按条数构造一页的原始 JSON 文本（模拟服务器响应体）。
  String pageJson(int rows) => jsonEncode(<String, Object?>{
    'code': 0,
    'data': <String, Object?>{
      'total': rows,
      'list': <Object?>[for (var i = 0; i < rows; i++) syntheticRow(i)],
    },
  });

  /// 跑 n 次取中位数，压掉单次抖动。
  int medianMicros(int Function() body, {int runs = 5}) {
    final samples = <int>[];
    for (var i = 0; i < runs; i++) {
      final sw = Stopwatch()..start();
      body();
      sw.stop();
      samples.add(sw.elapsedMicroseconds);
    }
    samples.sort();
    return samples[samples.length ~/ 2];
  }

  test('媒体库单页解析开销（jsonDecode + fromJson + 卡片映射）', () {
    const sizes = <int>[50, 100, 500, 1317, 5000];
    final rows = <String>[];

    for (final n in sizes) {
      final payload = pageJson(n);

      final decode = medianMicros(() {
        jsonDecode(payload);
        return 0;
      });
      final parse = medianMicros(() {
        final map = jsonDecode(payload) as Map<String, dynamic>;
        final list =
            (map['data'] as Map<String, dynamic>)['list'] as List<dynamic>;
        return list
            .whereType<Map<String, dynamic>>()
            .map(MediaLibraryItem.fromJson)
            .toList(growable: false)
            .length;
      });
      final card = medianMicros(() {
        final map = jsonDecode(payload) as Map<String, dynamic>;
        final list =
            (map['data'] as Map<String, dynamic>)['list'] as List<dynamic>;
        return list
            .whereType<Map<String, dynamic>>()
            .map(MediaLibraryItem.fromJson)
            .map(cardFromLibraryItem)
            .toList(growable: false)
            .length;
      });

      final kb = payload.length / 1024;
      rows.add(
        '  ${n.toString().padLeft(5)} 条  '
        '${kb.toStringAsFixed(0).padLeft(6)} KB  '
        'decode ${(decode / 1000).toStringAsFixed(1).padLeft(7)} ms  '
        'fromJson ${(parse / 1000).toStringAsFixed(1).padLeft(7)} ms  '
        '+卡片映射 ${(card / 1000).toStringAsFixed(1).padLeft(7)} ms',
      );
    }

    // ignore: avoid_print
    print('\n媒体库列表客户端解析开销（JIT，看量级不看绝对值）');
    // ignore: avoid_print
    print('  条数        体积      jsonDecode      解析模型          含卡片映射');
    for (final line in rows) {
      // ignore: avoid_print
      print(line);
    }

    // 只做灾难性回归兜底：50 条一页（当前页大小）解析必须远低于一帧预算。
    final payload50 = pageJson(50);
    final cost50 = medianMicros(() {
      final map = jsonDecode(payload50) as Map<String, dynamic>;
      final list =
          (map['data'] as Map<String, dynamic>)['list'] as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(MediaLibraryItem.fromJson)
          .toList(growable: false)
          .length;
    });
    expect(cost50, lessThan(500000), reason: '50 条一页的解析超过 500ms，说明解析链出了结构性问题');
  });

  test('翻完一个 1317 条的库需要多少页 / 多少请求', () {
    const total = 1317;
    for (final pageSize in <int>[500, 100, 50]) {
      final pages = (total / pageSize).ceil();
      // ignore: avoid_print
      print(
        '  page_size=${pageSize.toString().padLeft(3)}  '
        '需要 $pages 页'
        '${pageSize == 500 ? '（原实现只拉第 1 页，其余 $total-500 条不可达）' : ''}',
      );
    }
  });
}
