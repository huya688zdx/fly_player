import 'package:flutter/foundation.dart';

import '../../models/stream_track_data.dart';
import 'mpv_player_controller.dart';

@immutable
class LocalRuntimeTrackSyncResult {
  final List<AudioTrackOption> audioTracks;
  final List<SubtitleTrackOption> subtitleTracks;
  final String selectedAudioGuid;
  final String selectedSubtitleGuid;

  const LocalRuntimeTrackSyncResult({
    required this.audioTracks,
    required this.subtitleTracks,
    required this.selectedAudioGuid,
    required this.selectedSubtitleGuid,
  });
}

class LocalRuntimeTrackController {
  const LocalRuntimeTrackController();

  bool isLocalPlaybackUrl(String? rawUrl) {
    final normalizedUrl = rawUrl?.trim() ?? '';
    if (normalizedUrl.isEmpty) return false;
    final parsed = Uri.tryParse(normalizedUrl);
    if (parsed?.scheme.toLowerCase() == 'file') {
      return true;
    }
    if (normalizedUrl.startsWith('/')) {
      return true;
    }
    return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(normalizedUrl);
  }

  bool shouldRefresh({
    required bool isLocalPlayback,
    required MpvPlayerValue value,
    required String? currentSubtitleGuid,
    required bool pendingSubtitleSelectionRefresh,
    required String? pendingExternalSubtitlePath,
    required int lastSnapshotLoadNonce,
    required String lastSnapshotStatus,
    bool force = false,
  }) {
    if (!isLocalPlayback) return false;
    if (!value.ready || !value.nativeLibLoaded) return false;
    final selectedLocalSubtitle = _isLocalSubtitleGuid(currentSubtitleGuid);
    if (!force &&
        selectedLocalSubtitle &&
        pendingSubtitleSelectionRefresh &&
        (pendingExternalSubtitlePath?.trim().isEmpty ?? true)) {
      return false;
    }
    if (force) return true;
    const refreshStatuses = <String>{
      'source loaded',
      'playback started',
      'audio track changed',
      'subtitle track changed',
      'external subtitle loaded',
    };
    final status = value.statusText.trim().toLowerCase();
    if (lastSnapshotLoadNonce != value.loadNonce) {
      return refreshStatuses.contains(status);
    }
    return refreshStatuses.contains(status) && lastSnapshotStatus != status;
  }

  LocalRuntimeTrackSyncResult applySnapshot({
    required MpvRuntimeTrackSnapshot snapshot,
    required List<AudioTrackOption> currentAudioTracks,
    required List<SubtitleTrackOption> currentSubtitleTracks,
    required String? currentAudioGuid,
    required String? currentSubtitleGuid,
  }) {
    final nextAudioTracks = snapshot.audioTracks.isNotEmpty
        ? snapshot.audioTracks
        : currentAudioTracks;
    final nextSubtitleTracks = _sanitizeLocalRuntimeSubtitleTracks(
      _mergeLocalSubtitleTracksForDisplay(
        runtimeTracks: snapshot.subtitleTracks,
        currentTracks: currentSubtitleTracks,
      ),
    );
    final nextAudioGuid = snapshot.selectedAudioGuid.trim();
    final nextSubtitleGuid = snapshot.selectedSubtitleGuid.trim();
    final normalizedCurrentSubtitleGuid = currentSubtitleGuid?.trim() ?? '';
    final hasLocalSubtitleTrack = nextSubtitleTracks.any(
      (track) => _isLocalSubtitleGuid(track.guid),
    );
    final runtimeHasExternalSubtitle = snapshot.subtitleTracks.any(
      _isExternalSubtitleTrack,
    );
    final selectedRuntimeSubtitle = _findSubtitleTrack(
      nextSubtitleTracks,
      nextSubtitleGuid,
    );
    final shouldSyncSubtitleSelection =
        (nextSubtitleGuid.isNotEmpty &&
            (!_isLocalSubtitleGuid(normalizedCurrentSubtitleGuid) ||
                runtimeHasExternalSubtitle)) ||
        normalizedCurrentSubtitleGuid.isEmpty;

    String resolvedSubtitleGuid = normalizedCurrentSubtitleGuid;
    if (shouldSyncSubtitleSelection) {
      if (_isExternalSubtitleTrack(selectedRuntimeSubtitle) ||
          (selectedRuntimeSubtitle == null &&
              hasLocalSubtitleTrack &&
              nextSubtitleGuid.isNotEmpty)) {
        resolvedSubtitleGuid =
            _pickLocalSubtitleForRuntimeSelection(
              currentTracks: nextSubtitleTracks,
              currentSubtitleGuid: normalizedCurrentSubtitleGuid,
              runtimeSubtitle: selectedRuntimeSubtitle,
            )?.guid ??
            '';
      } else {
        resolvedSubtitleGuid = nextSubtitleGuid;
      }
    }

    return LocalRuntimeTrackSyncResult(
      audioTracks: nextAudioTracks,
      subtitleTracks: nextSubtitleTracks,
      selectedAudioGuid: nextAudioGuid.isNotEmpty
          ? nextAudioGuid
          : (currentAudioGuid?.trim() ?? ''),
      selectedSubtitleGuid: resolvedSubtitleGuid,
    );
  }

  List<SubtitleTrackOption> _mergeLocalSubtitleTracksForDisplay({
    required List<SubtitleTrackOption> runtimeTracks,
    required List<SubtitleTrackOption> currentTracks,
  }) {
    final mergedTracks = <SubtitleTrackOption>[];
    final seenGuids = <String>{};
    final localTracks = currentTracks
        .where((track) => _isLocalSubtitleGuid(track.guid))
        .toList(growable: false);

    void addTrack(SubtitleTrackOption track) {
      final guid = track.guid.trim();
      if (guid.isEmpty || !seenGuids.add(guid)) {
        return;
      }
      mergedTracks.add(track);
    }

    for (final track in runtimeTracks.where(
      (track) => !_isExternalSubtitleTrack(track),
    )) {
      addTrack(track);
    }
    for (final track in localTracks) {
      addTrack(track);
    }
    if (localTracks.isEmpty) {
      for (final track in runtimeTracks.where(_isExternalSubtitleTrack)) {
        addTrack(track);
      }
    }
    return mergedTracks;
  }

  List<SubtitleTrackOption> _sanitizeLocalRuntimeSubtitleTracks(
    List<SubtitleTrackOption> tracks,
  ) {
    return tracks
        .where((track) {
          final guid = track.guid.trim();
          return guid.startsWith('mpv-subtitle:') || guid.startsWith('local:');
        })
        .toList(growable: false);
  }

  SubtitleTrackOption? _pickLocalSubtitleForRuntimeSelection({
    required List<SubtitleTrackOption> currentTracks,
    required String currentSubtitleGuid,
    required SubtitleTrackOption? runtimeSubtitle,
  }) {
    final localTracks = currentTracks
        .where((track) => _isLocalSubtitleGuid(track.guid))
        .toList(growable: false);
    if (localTracks.isEmpty) return null;

    final selectedLocalTrack = _findSubtitleTrack(
      localTracks,
      currentSubtitleGuid,
    );
    if (selectedLocalTrack != null) {
      return selectedLocalTrack;
    }

    final runtimeTitle = runtimeSubtitle?.title.trim() ?? '';
    if (runtimeTitle.isNotEmpty) {
      for (final track in localTracks) {
        if (track.title.trim() == runtimeTitle) {
          return track;
        }
      }
    }

    for (final track in localTracks) {
      if (track.isDefaultOption) return track;
    }
    return localTracks.first;
  }

  SubtitleTrackOption? _findSubtitleTrack(
    List<SubtitleTrackOption> tracks,
    String guid,
  ) {
    final normalizedGuid = guid.trim();
    if (normalizedGuid.isEmpty) return null;
    for (final track in tracks) {
      if (track.guid == normalizedGuid) {
        return track;
      }
    }
    return null;
  }

  bool _isLocalSubtitleGuid(String? guid) {
    return (guid?.trim() ?? '').startsWith('local:');
  }

  bool _isExternalSubtitleTrack(SubtitleTrackOption? track) {
    return track?.isExternal == 1 || track?.extraFile == 1;
  }
}
