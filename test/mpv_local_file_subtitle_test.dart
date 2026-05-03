import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/models/stream_track_data.dart';
import 'package:fly_player/player/controllers/mpv_player_controller.dart';

void main() {
  group('MpvMediaSource.localFile subtitle selection', () {
    test('keeps explicit embedded subtitle instead of sidecar default', () {
      final tempDir = Directory.systemTemp.createTempSync(
        'fly_player_local_source_test_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final videoFile = File('${tempDir.path}${Platform.pathSeparator}demo.mkv')
        ..writeAsStringSync('video');
      File(
        '${tempDir.path}${Platform.pathSeparator}demo.ass',
      ).writeAsStringSync('subtitle');

      final source = MpvMediaSource.localFile(
        filePath: videoFile.path,
        itemGuid: 'item-1',
        mediaGuid: 'media-1',
        videoGuid: 'video-1',
        title: 'Demo',
        subtitleTrackIndex: 2,
        subtitleTrackGuid: 'server-subtitle-guid',
      );

      expect(source.subtitleTrackIndex, 2);
      expect(source.subtitleTrackGuid, 'server-subtitle-guid');
      expect(source.preferExternalSubtitle, isFalse);
      expect(source.localSubtitleFiles, isNotEmpty);
    });

    test(
      'inherits downloaded subtitle language and title for sidecar track',
      () {
        final tempDir = Directory.systemTemp.createTempSync(
          'fly_player_local_source_test_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });

        final videoFile = File(
          '${tempDir.path}${Platform.pathSeparator}demo.mkv',
        )..writeAsStringSync('video');
        File(
          '${tempDir.path}${Platform.pathSeparator}demo.ass',
        ).writeAsStringSync('subtitle');

        final source = MpvMediaSource.localFile(
          filePath: videoFile.path,
          itemGuid: 'item-1',
          mediaGuid: 'media-1',
          videoGuid: 'video-1',
          title: 'Demo',
          subtitleTrackGuid: 'remote-subtitle-guid',
          subtitleTracks: const <SubtitleTrackOption>[
            SubtitleTrackOption(
              mediaGuid: 'media-1',
              guid: 'remote-subtitle-guid',
              title: 'DSNP',
              codecName: 'ass',
              format: 'ass',
              language: 'fra',
              index: 1,
              isDefault: 1,
              forced: 0,
              isExternal: 1,
              extraFile: 1,
              isBitmap: 0,
            ),
          ],
        );

        final localTrack = source.subtitleTracks.firstWhere(
          (track) => track.guid.startsWith('local:'),
        );
        expect(localTrack.language, 'fra');
        expect(localTrack.title, 'DSNP');
        expect(source.subtitleTrackGuid, startsWith('local:'));
        expect(source.preferExternalSubtitle, isTrue);
      },
    );
  });
}
