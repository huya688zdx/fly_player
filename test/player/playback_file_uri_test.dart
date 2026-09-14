import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/playback/playback_file_uri.dart';

void main() {
  test(
    'Apple subtitle paths round-trip spaces and Unicode without backslashes',
    () {
      const path = '/Users/test/Movies/中文字幕 1.srt';
      final uri = playbackFileUri(path, windows: false);
      expect(uri, startsWith('file:///Users/test/Movies/'));
      expect(uri, contains('%20'));
      expect(playbackFilePath(uri, windows: false), path);
    },
  );

  test('Windows drive paths keep Windows syntax when converted', () {
    const path = r'C:\Movies\episode 1.srt';
    final uri = playbackFileUri(path, windows: true);
    expect(uri, 'file:///C:/Movies/episode%201.srt');
    expect(playbackFilePath(uri, windows: true), path);
  });

  test('HTTP and existing file URIs stay intact', () {
    for (final uri in [
      'https://example.test/subtitle.srt?token=abc',
      'file:///var/mobile/Documents/subtitle.srt',
    ]) {
      expect(playbackFileUri(uri, windows: false), uri);
    }
  });
}
