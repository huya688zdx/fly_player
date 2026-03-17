import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/models/remote_subtitle.dart';
import 'package:fly_player/models/stream_track_data.dart';
import 'package:fly_player/player/controllers/player_subtitle_controller.dart';

void main() {
  group('PlayerSubtitleController', () {
    test('resets source-scoped subtitle state and keeps file cache', () {
      final controller = PlayerSubtitleController()
        ..subtitleFileByGuid['sub-1'] = '/tmp/sub-1.srt'
        ..serverFallbackSubtitleGuids.add('fallback-1')
        ..subtitleFailureNoticeShownGuids.add('failed-1')
        ..subtitleExplicitlyDisabled = true
        ..pendingExternalSubtitlePath = '/tmp/pending.srt'
        ..subtitleDeletingGuid = 'sub-2'
        ..subtitleSearchLoadingLanguage = 'en'
        ..subtitleDownloadTrimId = 'trim-1'
        ..subtitleSearchResults = <RemoteSubtitleSearchItem>[
          const RemoteSubtitleSearchItem(
            filename: 'sub.srt',
            download: 1,
            sourceId: 'source-1',
            source: 'zimuku',
            trimId: 'trim-1',
            format: 'srt',
          ),
        ];

      controller.resetForSourceChange(pendingSelectionRefresh: true);

      expect(controller.subtitleFileByGuid, {'sub-1': '/tmp/sub-1.srt'});
      expect(controller.serverFallbackSubtitleGuids, isEmpty);
      expect(controller.subtitleFailureNoticeShownGuids, isEmpty);
      expect(controller.subtitleExplicitlyDisabled, isFalse);
      expect(controller.pendingSubtitleSelectionRefresh, isTrue);
      expect(controller.pendingExternalSubtitlePath, isNull);
      expect(controller.subtitleDeletingGuid, isNull);
      expect(controller.subtitleSearchLoadingLanguage, isNull);
      expect(controller.subtitleDownloadTrimId, isNull);
      expect(controller.subtitleSearchResults, isEmpty);
    });

    test('normalizes subtitle style values and track helpers', () {
      final controller = PlayerSubtitleController();

      final delay = controller.updateSubtitleDelaySeconds(12.34);
      final position = controller.updateSubtitlePositionFactor(0.25);
      final scale = controller.updateSubtitleScaleFactor(
        0.5,
        minScale: 0.8,
        maxScale: 2.0,
      );
      final track = controller.buildLocalSubtitleTrack(
        mediaGuid: 'media-1',
        guid: 'local:1',
        title: ' subtitle.ass ',
        format: 'ass',
      );
      final upserted = controller.upsertSubtitleTrack(
        const <SubtitleTrackOption>[],
        track,
        insertAtFront: true,
      );

      expect(delay, 10.0);
      expect(controller.subtitleDelaySeconds, 10.0);
      expect(position, 75);
      expect(controller.subtitlePositionFactor, 0.25);
      expect(scale, 1.4);
      expect(controller.subtitleScaleFactor, 0.5);
      expect(controller.subtitleSearchLanguageLabel('en'), '英文');
      expect(
        controller.subtitleFormatFromFileName('movie.SRT', '/tmp/fallback.ass'),
        'srt',
      );
      expect(track.isExternal, 1);
      expect(track.extraFile, 1);
      expect(upserted.single.guid, 'local:1');
      expect(
        controller.subtitleStreamTitle(track, subtitleLabel: 'ASS'),
        'subtitle.ass',
      );
      expect(
        controller.subtitleDrawerSwitchMessageForTrack(
          track,
          titleBuilder: (item) => item.title.trim(),
        ),
        '正在切换到subtitle.ass (ass) 字幕...',
      );

      controller.resetSubtitleStyle(minScale: 0.8, maxScale: 2.0);
      expect(controller.subtitleDelaySeconds, 0);
      expect(controller.subtitlePositionFactor, 0);
      expect(controller.subtitleScaleFactor, closeTo(1 / 6, 1e-9));
      expect(controller.removeSubtitleTrack(upserted, 'local:1'), isEmpty);
    });

    test('tracks subtitle selection, delete, and remote fetch state', () {
      final controller = PlayerSubtitleController()
        ..serverFallbackSubtitleGuids.add('server-guid')
        ..subtitleFailureNoticeShownGuids.add('server-guid');

      expect(controller.normalizeSelectionGuid('  sub-guid  '), 'sub-guid');
      expect(
        controller.isSelectionUnchanged(
          nextGuid: 'sub-guid',
          currentGuid: ' sub-guid ',
        ),
        isTrue,
      );
      expect(
        controller.selectionRequiresDirectFile(
          serverManagedPlayback: true,
          nextGuid: 'sub-guid',
          hasDirectFile: false,
        ),
        isTrue,
      );

      controller.beginSelectionChange('');
      expect(controller.subtitleExplicitlyDisabled, isTrue);

      controller.beginSelectionChange('server-guid');
      expect(controller.subtitleExplicitlyDisabled, isFalse);
      expect(controller.serverFallbackSubtitleGuids, isEmpty);
      expect(controller.subtitleFailureNoticeShownGuids, isEmpty);

      expect(controller.beginDeletingTrack('track-1'), isTrue);
      expect(controller.beginDeletingTrack('track-1'), isFalse);
      expect(controller.subtitleDeletingGuid, 'track-1');
      controller.finishDeletingTrack();
      expect(controller.subtitleDeletingGuid, isNull);

      expect(controller.beginRemoteSearch('zh-CN'), isTrue);
      expect(controller.beginRemoteSearch('zh-CN'), isFalse);
      expect(controller.subtitleSearchLoadingLanguage, 'zh-CN');
      expect(controller.updateSearchLanguage('en'), isTrue);
      expect(controller.updateSearchLanguage('en'), isFalse);
      expect(controller.subtitleSearchLanguage, 'en');

      controller.beginRemoteDownload('trim-1');
      expect(controller.subtitleDownloadTrimId, 'trim-1');
      controller.finishRemoteDownload();
      expect(controller.subtitleDownloadTrimId, isNull);

      const remoteResults = <RemoteSubtitleSearchItem>[
        RemoteSubtitleSearchItem(
          filename: 'remote.ass',
          download: 2,
          sourceId: 'source-2',
          source: 'zimuku',
          trimId: 'trim-2',
          format: 'ass',
        ),
      ];
      controller.completeRemoteSearch(remoteResults);
      expect(controller.subtitleSearchResults, remoteResults);
      expect(controller.subtitleSearchLoadingLanguage, isNull);

      controller.beginRemoteSearch('en');
      controller.failRemoteSearch();
      expect(controller.subtitleSearchResults, isEmpty);
      expect(controller.subtitleSearchLoadingLanguage, isNull);
    });

    test('builds selection and deletion plans for drawer orchestration', () {
      final controller = PlayerSubtitleController()
        ..subtitleExplicitlyDisabled = true
        ..subtitleStatusTipSuppressedUntil = DateTime(2026, 1, 2)
        ..subtitleFileByGuid['local:1'] = '/tmp/local-1.ass'
        ..serverFallbackSubtitleGuids.add('local:1')
        ..subtitleFailureNoticeShownGuids.add('local:1');
      final track = controller.buildLocalSubtitleTrack(
        mediaGuid: 'media-1',
        guid: 'local:1',
        title: 'local subtitle',
        format: 'ass',
      );

      final unchangedPlan = controller.planSelectionChange(
        guid: ' local:1 ',
        currentGuid: 'local:1',
        serverManagedPlayback: false,
        hasDirectFile: true,
      );
      expect(
        unchangedPlan.action,
        PlayerSubtitleSelectionAction.closeDrawer,
      );
      expect(unchangedPlan.normalizedGuid, 'local:1');

      final blockedPlan = controller.planSelectionChange(
        guid: 'server:1',
        currentGuid: 'local:1',
        serverManagedPlayback: true,
        hasDirectFile: false,
      );
      expect(
        blockedPlan.action,
        PlayerSubtitleSelectionAction.blockedByDirectFile,
      );

      final applyPlan = controller.planSelectionChange(
        guid: '',
        currentGuid: 'local:1',
        serverManagedPlayback: false,
        hasDirectFile: true,
      );
      expect(applyPlan.action, PlayerSubtitleSelectionAction.apply);
      expect(applyPlan.normalizedGuid, '');
      expect(applyPlan.subtitleExplicitlyDisabled, isTrue);
      expect(applyPlan.subtitleStatusTipSuppressedUntil, isNull);

      final deletion = controller.completeTrackDeletion(
        track: track,
        currentTracks: <SubtitleTrackOption>[track],
        currentGuid: ' local:1 ',
      );
      expect(deletion.remainingTracks, isEmpty);
      expect(deletion.nextCurrentGuid, '');
      expect(deletion.nextSubtitleExplicitlyDisabled, isFalse);
      expect(deletion.shouldApplySelection, isTrue);
      expect(deletion.removedCachedPath, '/tmp/local-1.ass');
      expect(deletion.subtitleStatusTipSuppressedUntil, isNull);
      expect(controller.serverFallbackSubtitleGuids, isEmpty);
      expect(controller.subtitleFailureNoticeShownGuids, isEmpty);
    });
  });
}
