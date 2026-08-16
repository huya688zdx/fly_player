import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/utils/media_language_mapper.dart';

void main() {
  group('MediaLanguageMapper', () {
    test('normalizes additional built-in subtitle languages', () {
      expect(MediaLanguageMapper.normalizeLanguageCode('dan'), 'dan');
      expect(MediaLanguageMapper.normalizeLanguageCode('hun'), 'hun');
      expect(MediaLanguageMapper.normalizeLanguageCode('ces'), 'ces');
    });

    test('maps common ISO 639 language aliases to Chinese names', () {
      const cases = <String, String>{
        'afr': '南非荷兰语',
        'sq': '阿尔巴尼亚语',
        'arm': '亚美尼亚语',
        'az': '阿塞拜疆语',
        'baq': '巴斯克语',
        'bn': '孟加拉语',
        'bs': '波斯尼亚语',
        'bur': '缅甸语',
        'fil': '菲律宾语',
        'geo': '格鲁吉亚语',
        'is': '冰岛语',
        'ga': '爱尔兰语',
        'kn': '卡纳达语',
        'kk': '哈萨克语',
        'km': '高棉语',
        'lo': '老挝语',
        'mac': '马其顿语',
        'ml': '马拉雅拉姆语',
        'mn': '蒙古语',
        'ne': '尼泊尔语',
        'per': '波斯语',
        'pa': '旁遮普语',
        'ta': '泰米尔语',
        'te': '泰卢固语',
        'ur': '乌尔都语',
        'wel': '威尔士语',
        'be': '白俄罗斯语',
        'sw': '斯瓦希里语',
        'uz': '乌兹别克语',
        'si': '僧伽罗语',
        'mr': '马拉地语',
        'gu': '古吉拉特语',
        'ku': '库尔德语',
        'am': '阿姆哈拉语',
        'la': '拉丁语',
        'gl': '加利西亚语',
      };

      for (final entry in cases.entries) {
        expect(
          MediaLanguageMapper.languageName(entry.key),
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('does not return UI fallback labels from the utility layer', () {
      expect(MediaLanguageMapper.normalizeLanguageCode('unknown'), isNull);
      expect(MediaLanguageMapper.languageName('unknown'), '');
      expect(MediaLanguageMapper.subtitleLabel('unknown'), '');
    });

    test('infers language code from local subtitle file names', () {
      expect(
        MediaLanguageMapper.inferLanguageCodeFromText('episode.01.da.ass'),
        'dan',
      );
      expect(
        MediaLanguageMapper.inferLanguageCodeFromText('episode.01.日语字幕.ass'),
        'jpn',
      );
      expect(
        MediaLanguageMapper.inferLanguageCodeFromText('episode.01.chs.ass'),
        'zho',
      );
    });
  });
}
