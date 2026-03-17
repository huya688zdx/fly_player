import '../models/play_info.dart';

String resolvePlayerArtworkPathForPlayItem(PlayItem item) {
  final type = item.type.trim().toLowerCase();
  if (type == 'episode') {
    if (item.posters.isNotEmpty) return item.posters;
    if (item.stillPath.isNotEmpty) return item.stillPath;
    return item.backdrops;
  }
  if (item.backdrops.isNotEmpty) return item.backdrops;
  if (item.stillPath.isNotEmpty) return item.stillPath;
  return item.posters;
}
