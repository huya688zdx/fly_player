import '../models/stream_track_data.dart';
import '../services/manual_subtitle_store.dart';
import 'media_language_mapper.dart';

/// 从持久化的手动导入字幕元数据构造 [SubtitleTrackOption] 列表。
///
/// 与 `local_subtitle_bundle.dart` 的轨道构造语义保持一致：负 index 表达外挂轨、
/// isExternal/extraFile=1、位图按扩展名推导。guid 直接用持久化 entry 的 `local:sub:<uuid>`
/// （跨会话稳定），原生壳据此识别为外挂本地字幕轨。
List<SubtitleTrackOption> manualSubtitleTracksForMedia(
  String mediaGuid,
  List<ManualSubtitleEntry> entries,
) {
  if (entries.isEmpty) return const <SubtitleTrackOption>[];
  final normalized = mediaGuid.trim();

  final tracks = <SubtitleTrackOption>[];
  for (int index = 0; index < entries.length; index++) {
    final entry = entries[index];
    final format = entry.format.toLowerCase();
    final isBitmap = format == 'sup' || format == 'pgs';
    tracks.add(
      SubtitleTrackOption(
        mediaGuid: normalized,
        guid: entry.guid,
        title: entry.fileName,
        codecName: format,
        format: format,
        language:
            MediaLanguageMapper.inferLanguageCodeFromText(entry.fileName) ??
            'und',
        index: -1 - index,
        isDefault: 0,
        forced: 0,
        isExternal: 1,
        extraFile: 1,
        isBitmap: isBitmap ? 1 : 0,
      ),
    );
  }
  return tracks;
}

/// 判断一个字幕轨 guid 是否为持久化的手动导入本地字幕（`local:sub:` 前缀）。
bool isManualSubtitleGuid(String guid) {
  return guid.trim().startsWith('local:sub:');
}
