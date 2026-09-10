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

  /// 合并两个本地字幕 bundle（按 guid 去重），保留先者的 preferredGuid。
  /// 用于把自动发现的同目录字幕与持久化的手动导入字幕合并成一个 bundle。
  static LocalSubtitleBundle merge(
    LocalSubtitleBundle a,
    LocalSubtitleBundle b,
  ) {
    final tracks = <SubtitleTrackOption>[];
    final fileByGuid = <String, String>{};
    final seenGuids = <String>{};

    void append(LocalSubtitleBundle source) {
      for (final track in source.tracks) {
        final guid = track.guid.trim();
        if (guid.isEmpty || !seenGuids.add(guid)) continue;
        tracks.add(track);
      }
      fileByGuid.addAll(source.fileByGuid);
    }

    append(a);
    append(b);
    return LocalSubtitleBundle(
      tracks: tracks,
      fileByGuid: fileByGuid,
      preferredGuid: a.preferredGuid ?? b.preferredGuid,
    );
  }
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

/// 从一组本地字幕文件路径构造字幕 bundle（供持久化手动导入的字幕复用）。
///
/// 与 [discoverLocalSubtitleBundle] 的轨道构造语义一致：guid 用 `local:<file://path>`、
/// 负 index 表达外挂轨、isExternal/extraFile=1、位图按扩展名推导。
LocalSubtitleBundle bundleFromLocalFiles({
  required String mediaGuid,
  required List<String> filePaths,
}) {
  final files = filePaths
      .map((path) => File(path))
      .where((file) => file.existsSync())
      .toList(growable: false);
  if (files.isEmpty) return LocalSubtitleBundle.empty;
  return _bundleFromCandidates(mediaGuid: mediaGuid, candidates: files);
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
