import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/models/stream_track_data.dart';
import 'package:fly_player/playback/playback_source.dart';
import 'package:fly_player/utils/local_subtitle_bundle.dart';

void main() {
  group('MpvMediaSource.localFile subtitle selection', () {
    test('discovers sidecar subtitles through async entrypoint', () async {
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
        '${tempDir.path}${Platform.pathSeparator}demo.zh-Hans.ass',
      ).writeAsStringSync('subtitle');

      final bundle = await discoverLocalSubtitleBundleAsync(
        mediaGuid: 'media-1',
        videoFilePath: videoFile.path,
      );

      expect(bundle.tracks, hasLength(1));
      expect(bundle.tracks.single.guid, startsWith('local:'));
      expect(bundle.tracks.single.language, 'zho');
      expect(bundle.fileByGuid[bundle.tracks.single.guid], contains('demo'));
    });

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

  group('bundleFromLocalFiles', () {
    test('maps SRT as text and SUP/PGS as bitmap external tracks', () {
      final tempDir = Directory.systemTemp.createTempSync(
        'fly_player_manual_subtitle_formats_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final paths = <String>[
        for (final format in <String>['srt', 'sup', 'pgs'])
          '${tempDir.path}${Platform.pathSeparator}episode.$format',
      ];
      for (final path in paths) {
        File(path).writeAsBytesSync(<int>[0x50, 0x47]);
      }

      final bundle = bundleFromLocalFiles(
        mediaGuid: 'media-1',
        filePaths: paths,
      );

      expect(bundle.tracks, hasLength(3));
      expect(bundle.fileByGuid.values.toSet(), paths.toSet());
      final byFormat = <String, SubtitleTrackOption>{
        for (final track in bundle.tracks) track.format: track,
      };
      expect(byFormat['srt']!.isBitmap, 0);
      expect(byFormat['sup']!.isBitmap, 1);
      expect(byFormat['pgs']!.isBitmap, 1);
      for (final track in bundle.tracks) {
        expect(track.isExternal, 1);
        expect(track.extraFile, 1);
      }
    });

    test('builds tracks and file map from explicit file paths', () {
      final tempDir = Directory.systemTemp.createTempSync(
        'fly_player_bundle_from_files_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final supPath = '${tempDir.path}${Platform.pathSeparator}demo.sup';
      final assPath = '${tempDir.path}${Platform.pathSeparator}demo.ass';
      File(supPath).writeAsStringSync('sup');
      File(assPath).writeAsStringSync('ass');

      final bundle = bundleFromLocalFiles(
        mediaGuid: 'media-1',
        filePaths: <String>[supPath, assPath],
      );

      expect(bundle.tracks, hasLength(2));
      expect(bundle.fileByGuid, hasLength(2));
      // 位图字幕按扩展名推导 isBitmap。
      final supTrack = bundle.tracks.firstWhere((t) => t.format == 'sup');
      expect(supTrack.isBitmap, 1);
      expect(supTrack.isExternal, 1);
      expect(supTrack.extraFile, 1);
      expect(bundle.fileByGuid[supTrack.guid], supPath);
      final assTrack = bundle.tracks.firstWhere((t) => t.format == 'ass');
      expect(assTrack.isBitmap, 0);
    });

    test('skips nonexistent files', () {
      final bundle = bundleFromLocalFiles(
        mediaGuid: 'media-1',
        filePaths: <String>['C:/does/not/exist.sup', 'C:/also/missing.srt'],
      );
      expect(bundle.tracks, isEmpty);
      expect(bundle.fileByGuid, isEmpty);
    });

    test('merge combines two bundles deduping by guid', () {
      final tempDir = Directory.systemTemp.createTempSync(
        'fly_player_bundle_merge_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final aPath = '${tempDir.path}${Platform.pathSeparator}demo.a.sup';
      final bPath = '${tempDir.path}${Platform.pathSeparator}demo.b.ass';
      File(aPath).writeAsStringSync('a');
      File(bPath).writeAsStringSync('b');

      final bundleA = bundleFromLocalFiles(
        mediaGuid: 'media-1',
        filePaths: <String>[aPath],
      );
      final bundleB = bundleFromLocalFiles(
        mediaGuid: 'media-1',
        filePaths: <String>[bPath, aPath],
      );
      final merged = LocalSubtitleBundle.merge(bundleA, bundleB);

      expect(merged.tracks, hasLength(2));
      expect(merged.fileByGuid, hasLength(2));
    });
  });
}
