import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:fly_player/models/stream_list_option.dart';
import 'package:fly_player/models/stream_track_data.dart';
import 'package:fly_player/pages/media_detail_overlay_page.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/utils/media_locale_store.dart';
import 'package:fly_player/utils/play_detail_track_selector.dart';
import 'package:fly_player/widgets/common/track_option_sheet.dart';

class PlayDetailSheetController {
  const PlayDetailSheetController._();

  static String _t(
    Map<String, dynamic> localeMap,
    String path,
    String fallback, {
    Map<String, Object?> params = const <String, Object?>{},
  }) {
    return MediaLocaleStore.text(
      localeMap,
      path,
      fallback: fallback,
      params: params,
    );
  }

  static Future<String?> showSubtitleSheet(
    BuildContext context, {
    required List<SubtitleTrackOption> subtitleTracks,
    required String? selectedSubtitleGuid,
  }) async {
    if (subtitleTracks.isEmpty) return null;

    final localeMap = await MediaLocaleStore.load(context.read<NasProvider>());
    if (!context.mounted) return null;
    const offId = '__subtitle_off__';
    final items = <TrackOptionSheetItem>[
      TrackOptionSheetItem(
        id: offId,
        title: _t(localeMap, 'stream.subtitle.hiddenSubtitle', '关闭字幕'),
      ),
      ...subtitleTracks.map(
        (e) => TrackOptionSheetItem(
          id: e.guid,
          title: PlayDetailTrackSelector.subtitleOptionTitle(
            e,
            localeMap: localeMap,
          ),
          subtitle: PlayDetailTrackSelector.subtitleOptionSubtitle(
            e,
            localeMap: localeMap,
          ),
        ),
      ),
    ];
    final selectedId =
        (selectedSubtitleGuid == null || selectedSubtitleGuid.isEmpty)
        ? offId
        : selectedSubtitleGuid;

    final result = await TrackOptionSheet.show(
      context,
      title: _t(localeMap, 'player.subtitle.select', '选择字幕'),
      items: items,
      selectedId: selectedId,
    );
    if (result == null) return null;
    return result == offId ? '' : result;
  }

  static Future<String?> showAudioSheet(
    BuildContext context, {
    required List<AudioTrackOption> audioTracks,
    required String? selectedAudioGuid,
  }) async {
    if (audioTracks.isEmpty) return null;

    final localeMap = await MediaLocaleStore.load(context.read<NasProvider>());
    if (!context.mounted) return null;
    final items = audioTracks
        .map(
          (e) => TrackOptionSheetItem(
            id: e.guid,
            title: e.displayLabel,
            subtitle: e.detailLabel,
          ),
        )
        .toList();
    final selectedId = (selectedAudioGuid == null || selectedAudioGuid.isEmpty)
        ? items.first.id
        : selectedAudioGuid;
    return TrackOptionSheet.show(
      context,
      title: _t(localeMap, 'player.audio.select', '选择音频'),
      items: items,
      selectedId: selectedId,
    );
  }

  static Future<void> showMediaInfoDetail(
    BuildContext context, {
    required List<StreamListOption> streamOptions,
    required StreamTrackData? streamTrackData,
    required int? selectedStreamIndex,
    required ValueChanged<int> onVariantChanged,
  }) async {
    final variants = <MediaDetailVariant>[];
    for (final option in streamOptions) {
      final mediaGuid = option.mediaGuid;
      variants.add(
        MediaDetailVariant(
          mediaGuid: mediaGuid,
          title: option.label,
          video: streamTrackData?.videoForMedia(mediaGuid),
          audios: streamTrackData?.audiosForMedia(mediaGuid) ?? const [],
          subtitles: streamTrackData?.subtitlesForMedia(mediaGuid) ?? const [],
        ),
      );
    }
    if (variants.isEmpty) return;

    final initialIndex = (selectedStreamIndex ?? 0).clamp(
      0,
      variants.length - 1,
    );
    await MediaDetailOverlayPage.show(
      context,
      variants: variants,
      initialIndex: initialIndex,
      onVariantChanged: onVariantChanged,
    );
  }
}
