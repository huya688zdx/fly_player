import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../../api/feiniu_api.dart';
import '../../models/remote_subtitle.dart';
import '../../models/stream_track_data.dart';

typedef SubtitleBytesWriter =
    Future<String> Function({required String path, required Uint8List bytes});

class PlayerSubtitleService {
  const PlayerSubtitleService();

  Future<List<RemoteSubtitleSearchItem>> searchRemoteSubtitles({
    required FeiniuApi api,
    required String mediaGuid,
    required String language,
  }) async {
    final result = await api.searchRemoteSubtitles(
      mediaGuid: mediaGuid,
      language: language,
    );
    return result.subtitles;
  }

  Future<SubtitleTrackOption> downloadRemoteSubtitleTrack({
    required FeiniuApi api,
    required String mediaGuid,
    required String trimId,
  }) async {
    final result = await api.downloadRemoteSubtitle(
      mediaGuid: mediaGuid,
      trimId: trimId,
    );
    return result.toTrack(fallbackMediaGuid: mediaGuid);
  }

  Future<String?> materializePickedSubtitle({
    required PlatformFile file,
    required String Function(String fileName, String fallbackPath)
    formatResolver,
    required SubtitleBytesWriter writeBytesToTempFile,
  }) async {
    final rawPath = file.path?.trim() ?? '';
    if (rawPath.isNotEmpty) {
      final source = File(rawPath);
      if (source.existsSync()) {
        return source.path;
      }
    }
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) return null;
    final extension = formatResolver(file.name, rawPath);
    final path =
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'fly_player_local_sub_${DateTime.now().microsecondsSinceEpoch}.$extension';
    return writeBytesToTempFile(path: path, bytes: Uint8List.fromList(bytes));
  }
}
