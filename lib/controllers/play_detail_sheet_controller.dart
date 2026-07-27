import 'package:flutter/material.dart';

import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/media_backend/feiniu/feiniu_media_detail_variant_mapper.dart';
import 'package:fly_player/models/stream_list_option.dart';
import 'package:fly_player/models/stream_track_data.dart';
import 'package:fly_player/pages/media_detail_overlay_page.dart';
import 'package:fly_player/utils/play_detail_track_selector.dart';
import 'package:fly_player/widgets/common/track_option_sheet.dart';

/// 提供详情页轨道选择与媒体信息面板的展示入口。
class PlayDetailSheetController {
  const PlayDetailSheetController._();

  /// 展示字幕轨选择面板并返回新的字幕标识。
  static Future<String?> showSubtitleSheet(
    BuildContext context, {
    required List<SubtitleTrackOption> subtitleTracks,
    required String? selectedSubtitleGuid,
  }) async {
    if (subtitleTracks.isEmpty) return null;

    final l10n = AppLocalizations.of(context);
    const offId = '__subtitle_off__';
    final items = <TrackOptionSheetItem>[
      TrackOptionSheetItem(id: offId, title: l10n.playerSubtitleOffAction),
      ...subtitleTracks.map(
        (e) => TrackOptionSheetItem(
          id: e.guid,
          title: PlayDetailTrackSelector.subtitleOptionTitle(e, l10n: l10n),
          subtitle: PlayDetailTrackSelector.subtitleOptionSubtitle(
            e,
            l10n: l10n,
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
      title: l10n.playerSubtitleSelectTitle,
      items: items,
      selectedId: selectedId,
    );
    if (result == null) return null;
    return result == offId ? '' : result;
  }

  /// 展示音轨选择面板并返回新的音轨标识。
  static Future<String?> showAudioSheet(
    BuildContext context, {
    required List<AudioTrackOption> audioTracks,
    required String? selectedAudioGuid,
  }) async {
    if (audioTracks.isEmpty) return null;

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
      title: AppLocalizations.of(context).playerAudioSelectTitle,
      items: items,
      selectedId: selectedId,
    );
  }

  /// 展示当前媒体变体的详细信息面板。
  static Future<void> showMediaInfoDetail(
    BuildContext context, {
    required List<StreamListOption> streamOptions,
    required StreamTrackData? streamTrackData,
    required int? selectedStreamIndex,
    required ValueChanged<int> onVariantChanged,
  }) async {
    final l10n = AppLocalizations.of(context);
    final variants = <MediaDetailVariant>[];
    for (final option in streamOptions) {
      final mediaGuid = option.mediaGuid;
      variants.add(
        mapFeiniuMediaDetailVariant(
          key: mediaGuid,
          title: option.label,
          l10n: l10n,
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
