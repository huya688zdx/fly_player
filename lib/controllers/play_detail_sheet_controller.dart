import 'package:flutter/material.dart';

import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/media_backend/detail/media_detail_variant.dart';
import 'package:fly_player/media_backend/feiniu/feiniu_media_detail_variant_mapper.dart';
import 'package:fly_player/models/stream_list_option.dart';
import 'package:fly_player/models/stream_track_data.dart';
import 'package:fly_player/pages/media_detail_overlay_page.dart';
import 'package:fly_player/ui/app_sheet_transitions.dart';
import 'package:fly_player/utils/play_detail_track_selector.dart';
import 'package:fly_player/widgets/common/track_option_sheet.dart';

/// 提供详情页轨道选择与媒体信息面板的展示入口。
class PlayDetailSheetController {
  const PlayDetailSheetController._();

  /// 字幕「关闭」项的公共 id：sheet 与桌面悬停弹窗共用同一映射语义。
  static const String subtitleOffItemId = '__subtitle_off__';

  /// 构建字幕轨选项条目（含首项「关闭」；`local:sub:` 手动导入轨带删除按钮）。
  ///
  /// [onLocalSubtitleDelete] 非空时本地导入轨渲染删除按钮，点击回调被删轨 guid；
  /// sheet 传「pop 删除标记」，桌面悬停弹窗传「原地删除并刷新」。
  static List<TrackOptionSheetItem> subtitleItems({
    required List<SubtitleTrackOption> subtitleTracks,
    required AppLocalizations l10n,
    void Function(String guid)? onLocalSubtitleDelete,
  }) {
    return <TrackOptionSheetItem>[
      TrackOptionSheetItem(
        id: subtitleOffItemId,
        title: l10n.playerSubtitleOffAction,
      ),
      ...subtitleTracks.map(
        (e) => TrackOptionSheetItem(
          id: e.guid,
          title: PlayDetailTrackSelector.subtitleOptionTitle(e, l10n: l10n),
          subtitle: PlayDetailTrackSelector.subtitleOptionSubtitle(
            e,
            l10n: l10n,
          ),
          onDelete:
              onLocalSubtitleDelete == null || !e.guid.startsWith('local:sub:')
              ? null
              : () => onLocalSubtitleDelete(e.guid),
        ),
      ),
    ];
  }

  /// 当前选中项对应的条目 id（未选/关闭态映射到「关闭」项）。
  static String subtitleSelectedIdOf(String? selectedSubtitleGuid) {
    return (selectedSubtitleGuid == null || selectedSubtitleGuid.isEmpty)
        ? subtitleOffItemId
        : selectedSubtitleGuid;
  }

  /// 把条目 id 还原为 sheet 结果语义（「关闭」项 → ''，其余原样）。
  static String subtitleResultOf(String itemId) {
    return itemId == subtitleOffItemId ? '' : itemId;
  }

  /// 构建音轨选项条目。
  static List<TrackOptionSheetItem> audioItems({
    required List<AudioTrackOption> audioTracks,
  }) {
    return audioTracks
        .map(
          (e) => TrackOptionSheetItem(
            id: e.guid,
            title: PlayDetailTrackSelector.audioOptionTitle(e),
            subtitle: e.detailLabel,
          ),
        )
        .toList();
  }

  /// 当前选中音轨对应的条目 id（未选时回退首项）。
  static String audioSelectedIdOf({
    required String? selectedAudioGuid,
    required List<TrackOptionSheetItem> items,
  }) {
    return (selectedAudioGuid == null || selectedAudioGuid.isEmpty)
        ? items.first.id
        : selectedAudioGuid;
  }

  /// 展示字幕轨选择面板并返回新的字幕标识。
  ///
  /// 对 `local:sub:` 手动导入轨渲染删除按钮；点击后面板关闭并返回删除标记
  /// `[subtitleDeleteMarkerPrefix]<guid>`，调用方据此删除并重新打开面板。
  static Future<String?> showSubtitleSheet(
    BuildContext context, {
    required List<SubtitleTrackOption> subtitleTracks,
    required String? selectedSubtitleGuid,
  }) async {
    if (subtitleTracks.isEmpty) return null;

    final l10n = AppLocalizations.of(context);
    final items = subtitleItems(
      subtitleTracks: subtitleTracks,
      l10n: l10n,
      onLocalSubtitleDelete: (guid) {
        final marker = '$subtitleDeleteMarkerPrefix$guid';
        if (AppSheetTransitions.maybeClose<String>(context, marker)) {
          return;
        }
        Navigator.of(context).pop(marker);
      },
    );
    final selectedId = subtitleSelectedIdOf(selectedSubtitleGuid);

    final result = await TrackOptionSheet.show(
      context,
      title: l10n.playerSubtitleSelectTitle,
      items: items,
      selectedId: selectedId,
    );
    if (result == null) return null;
    return subtitleResultOf(result);
  }

  /// 删除标记前缀：返回 `'<前缀><guid>'` 表示删除该本地字幕轨。
  static const String subtitleDeleteMarkerPrefix = '__subtitle_delete__:';

  /// 判断 [result] 是否为删除请求，是则返回被删字幕 guid，否则返回 null。
  static String? subtitleDeleteGuidOf(String? result) {
    if (result == null) return null;
    if (!result.startsWith(subtitleDeleteMarkerPrefix)) return null;
    return result.substring(subtitleDeleteMarkerPrefix.length);
  }

  /// 展示音轨选择面板并返回新的音轨标识。
  static Future<String?> showAudioSheet(
    BuildContext context, {
    required List<AudioTrackOption> audioTracks,
    required String? selectedAudioGuid,
  }) async {
    if (audioTracks.isEmpty) return null;

    final items = audioItems(audioTracks: audioTracks);
    return TrackOptionSheet.show(
      context,
      title: AppLocalizations.of(context).playerAudioSelectTitle,
      items: items,
      selectedId: audioSelectedIdOf(
        selectedAudioGuid: selectedAudioGuid,
        items: items,
      ),
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
