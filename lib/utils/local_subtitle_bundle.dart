import 'dart:io';

import '../models/stream_track_data.dart';
import 'media_language_mapper.dart';

class LocalSubtitleBundle {
  final List<SubtitleTrackOption> tracks;
  final Map<String, String> fileByGuid;
  final String? preferredGuid;

  const LocalSubtitleBundle({
    required this.tracks,
    required this.fileByGuid,
    required this.preferredGuid,
  });

  static const empty = LocalSubtitleBundle(
    tracks: <SubtitleTrackOption>[],
    fileByGuid: <String, String>{},
    preferredGuid: null,
  );
}

LocalSubtitleBundle discoverLocalSubtitleBundle({
  required String mediaGuid,
  required String videoFilePath,
}) {
  final normalizedVideoPath = videoFilePath.trim();
  if (normalizedVideoPath.isEmpty) return LocalSubtitleBundle.empty;
  final videoFile = File(normalizedVideoPath);
  if (!videoFile.existsSync()) return LocalSubtitleBundle.empty;

  final directory = videoFile.parent;
  if (!directory.existsSync()) return LocalSubtitleBundle.empty;
  final videoName = videoFile.uri.pathSegments.isNotEmpty
      ? videoFile.uri.pathSegments.last
      : normalizedVideoPath;
  final baseName = _fileNameBase(videoName);
  final candidates = <File>[];

  for (final entity in directory.listSync(followLinks: false)) {
    if (entity is! File) continue;
    final fileName = entity.uri.pathSegments.isNotEmpty
        ? entity.uri.pathSegments.last
        : entity.path;
    final lowerName = fileName.toLowerCase();
    if (!lowerName.startsWith('${baseName.toLowerCase()}.')) continue;
    final extension = _subtitleExtension(fileName);
    if (!_supportedSubtitleExtensions.contains(extension)) continue;
    candidates.add(entity);
  }

  return _bundleFromCandidates(mediaGuid: mediaGuid, candidates: candidates);
}

Future<LocalSubtitleBundle> discoverLocalSubtitleBundleAsync({
  required String mediaGuid,
  required String videoFilePath,
}) async {
  final normalizedVideoPath = videoFilePath.trim();
  if (normalizedVideoPath.isEmpty) return LocalSubtitleBundle.empty;
  final videoFile = File(normalizedVideoPath);
  if (!await videoFile.exists()) return LocalSubtitleBundle.empty;

  final directory = videoFile.parent;
  if (!await directory.exists()) return LocalSubtitleBundle.empty;
  final videoName = videoFile.uri.pathSegments.isNotEmpty
      ? videoFile.uri.pathSegments.last
      : normalizedVideoPath;
  final baseName = _fileNameBase(videoName);
  final candidates = <File>[];

  await for (final entity in directory.list(followLinks: false)) {
    if (entity is! File) continue;
    final fileName = entity.uri.pathSegments.isNotEmpty
        ? entity.uri.pathSegments.last
        : entity.path;
    final lowerName = fileName.toLowerCase();
    if (!lowerName.startsWith('${baseName.toLowerCase()}.')) continue;
    final extension = _subtitleExtension(fileName);
    if (!_supportedSubtitleExtensions.contains(extension)) continue;
    candidates.add(entity);
  }

  return _bundleFromCandidates(mediaGuid: mediaGuid, candidates: candidates);
}

const Set<String> _supportedSubtitleExtensions = <String>{
  'ass',
  'ssa',
  'srt',
  'vtt',
  'sub',
  'idx',
  'lrc',
  'sup',
  'pgs',
};

String _fileNameBase(String fileName) {
  final lastDot = fileName.lastIndexOf('.');
  if (lastDot <= 0) return fileName;
  return fileName.substring(0, lastDot);
}

String _subtitleExtension(String fileName) {
  final lastDot = fileName.lastIndexOf('.');
  if (lastDot < 0 || lastDot == fileName.length - 1) return '';
  return fileName.substring(lastDot + 1).toLowerCase();
}

LocalSubtitleBundle _bundleFromCandidates({
  required String mediaGuid,
  required List<File> candidates,
}) {
  if (candidates.isEmpty) return LocalSubtitleBundle.empty;
  candidates.sort((lhs, rhs) => lhs.path.compareTo(rhs.path));

  final tracks = <SubtitleTrackOption>[];
  final fileByGuid = <String, String>{};
  String? preferredGuid;

  for (int index = 0; index < candidates.length; index++) {
    final file = candidates[index];
    final fileName = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : file.path;
    final extension = _subtitleExtension(fileName);
    final guid = 'local:${Uri.file(file.path, windows: Platform.isWindows)}';
    final track = SubtitleTrackOption(
      mediaGuid: mediaGuid.trim(),
      guid: guid,
      title: fileName,
      codecName: extension,
      format: extension,
      language:
          MediaLanguageMapper.inferLanguageCodeFromText(fileName) ?? 'und',
      index: -1 - index,
      isDefault: index == 0 ? 1 : 0,
      forced: 0,
      isExternal: 1,
      extraFile: 1,
      isBitmap: extension == 'sup' || extension == 'pgs' ? 1 : 0,
    );
    tracks.add(track);
    fileByGuid[guid] = file.path;
    preferredGuid ??= guid;
  }

  return LocalSubtitleBundle(
    tracks: tracks,
    fileByGuid: fileByGuid,
    preferredGuid: preferredGuid,
  );
}
