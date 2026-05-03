import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/utils/media_language_mapper.dart';

void main() {
  group('MediaLanguageMapper', () {
    test('maps additional built-in subtitle languages', () {
      expect(MediaLanguageMapper.subtitleLabel('dan'), '丹麦语');
      expect(MediaLanguageMapper.subtitleLabel('hun'), '匈牙利语');
      expect(MediaLanguageMapper.subtitleLabel('ces'), '捷克语');
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
