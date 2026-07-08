import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/utils/media_language_mapper.dart';

void main() {
  group('MediaLanguageMapper', () {
    test('normalizes additional built-in subtitle languages', () {
      expect(MediaLanguageMapper.normalizeLanguageCode('dan'), 'dan');
      expect(MediaLanguageMapper.normalizeLanguageCode('hun'), 'hun');
      expect(MediaLanguageMapper.normalizeLanguageCode('ces'), 'ces');
    });

    test('does not return UI fallback labels from the utility layer', () {
      expect(MediaLanguageMapper.normalizeLanguageCode('unknown'), isNull);
      expect(MediaLanguageMapper.languageName('unknown'), '');
      expect(MediaLanguageMapper.audioLabel('unknown'), '');
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
