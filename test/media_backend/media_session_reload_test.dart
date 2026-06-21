import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/playback/media_session_reload.dart';

void main() {
  group('MediaSessionReloadIntent', () {
    test('默认值：全部保留当前选择（null / 非 disabled）', () {
      const intent = MediaSessionReloadIntent();
      expect(intent.audioTrackId, isNull, reason: 'null=保留当前音轨');
      expect(intent.subtitleTrackId, isNull);
      expect(intent.subtitleDisabled, isFalse, reason: 'null+非disabled=保留当前字幕');
      expect(intent.qualityIndex, isNull, reason: 'null=保留当前画质');
      expect(intent.startPosition, isNull, reason: 'null=保留当前续播位');
    });

    test('切音轨：仅 audioTrackId 指定，其余保留当前', () {
      const intent = MediaSessionReloadIntent(audioTrackId: 'audio-2');
      expect(intent.audioTrackId, 'audio-2');
      expect(intent.subtitleTrackId, isNull);
      expect(intent.subtitleDisabled, isFalse);
      expect(intent.qualityIndex, isNull);
    });

    test('字幕三态：切到指定字幕轨', () {
      const intent = MediaSessionReloadIntent(subtitleTrackId: 'sub-3');
      expect(intent.subtitleTrackId, 'sub-3');
      expect(intent.subtitleDisabled, isFalse);
    });

    test('字幕三态：显式关闭字幕', () {
      const intent = MediaSessionReloadIntent(subtitleDisabled: true);
      expect(intent.subtitleDisabled, isTrue);
      expect(intent.subtitleTrackId, isNull);
    });

    test('字幕三态：保留当前字幕（默认）', () {
      const intent = MediaSessionReloadIntent();
      expect(intent.subtitleTrackId, isNull);
      expect(intent.subtitleDisabled, isFalse);
    });

    test('切画质 + 指定起播位', () {
      const intent = MediaSessionReloadIntent(
        qualityIndex: 2,
        startPosition: Duration(seconds: 90),
      );
      expect(intent.qualityIndex, 2);
      expect(intent.startPosition, const Duration(seconds: 90));
      expect(intent.audioTrackId, isNull, reason: '切画质保留当前音轨');
      expect(intent.subtitleTrackId, isNull, reason: '切画质保留当前字幕');
      expect(intent.subtitleDisabled, isFalse);
    });
  });
}
