import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

enum ImdbLaunchResult { success, empty, failed }

class ImdbLauncher {
  static Future<ImdbLaunchResult> openExternal(String imdbId) async {
    return _openByPathSegment(imdbId, segment: 'title');
  }

  static Future<ImdbLaunchResult> openPersonExternal(String imdbId) async {
    return _openByPathSegment(imdbId, segment: 'name');
  }

  static Future<ImdbLaunchResult> openTmdbExternal(String trimId) async {
    final normalized = _normalizeTmdbTrimId(trimId);
    if (normalized == null) return ImdbLaunchResult.empty;
    final (segment, id) = normalized;
    try {
      final uri = Uri.parse('https://www.themoviedb.org/$segment/$id');
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      return ok ? ImdbLaunchResult.success : ImdbLaunchResult.failed;
    } on PlatformException {
      return ImdbLaunchResult.failed;
    } catch (_) {
      return ImdbLaunchResult.failed;
    }
  }

  static Future<ImdbLaunchResult> _openByPathSegment(
    String imdbId, {
    required String segment,
  }) async {
    final id = imdbId.trim();
    if (id.isEmpty) return ImdbLaunchResult.empty;
    try {
      final uri = Uri.parse('https://www.imdb.com/$segment/$id/');
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      return ok ? ImdbLaunchResult.success : ImdbLaunchResult.failed;
    } on PlatformException {
      return ImdbLaunchResult.failed;
    } catch (_) {
      return ImdbLaunchResult.failed;
    }
  }

  static (String, String)? _normalizeTmdbTrimId(String trimId) {
    final raw = trimId.trim();
    if (raw.length < 3) return null;
    final prefix = raw.substring(0, 2).toLowerCase();
    final id = raw.substring(2).trim();
    if (id.isEmpty) return null;
    switch (prefix) {
      case 'tm':
        return ('movie', id);
      case 'tt':
        return ('tv', id);
      case 'tp':
        return ('person', id);
      default:
        return null;
    }
  }
}
