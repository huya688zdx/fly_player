import 'dart:io';

/// Keeps network URIs intact and encodes native paths using the host's syntax.
String playbackFileUri(String path, {bool? windows}) {
  final useWindows = windows ?? Platform.isWindows;
  final windowsPath =
      useWindows &&
      (RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path) || path.startsWith(r'\\'));
  if (!windowsPath && Uri.tryParse(path)?.hasScheme == true) return path;
  return Uri.file(path, windows: useWindows).toString();
}

String playbackFilePath(String path, {bool? windows}) {
  final uri = Uri.tryParse(path);
  return uri?.scheme == 'file'
      ? uri!.toFilePath(windows: windows ?? Platform.isWindows)
      : path;
}
