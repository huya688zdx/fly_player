import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/desktop/playback/desktop_playback_host.dart';
import 'package:fly_player/playback/native_playback_host.dart';
import 'package:fly_player/playback/playback_host.dart';
import 'package:fly_player/playback/playback_platform.dart';
import 'package:fly_player/playback/playback_source.dart';
import 'package:fly_player/playback/platform_playback_host.dart';
import 'package:fly_player/playback/unsupported_playback_host.dart';

void main() {
  for (final platform in <TargetPlatform>[
    TargetPlatform.iOS,
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.android,
    TargetPlatform.linux,
    TargetPlatform.fuchsia,
  ]) {
    testWidgets('$platform selects its explicit playback host', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      late PlaybackHost host;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                host = playbackHostFor(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
      expect(
        host,
        platform == TargetPlatform.android
            ? isA<NativePlaybackHost>()
            : PlaybackPlatform.supportsMediaKit(platform)
            ? isA<DesktopPlaybackHost>()
            : isA<UnsupportedPlaybackHost>(),
      );
      if (host is UnsupportedPlaybackHost) {
        expect(await host.resume(itemGuid: 'item'), isFalse);
        expect(
          await host.launch(
            source: const MpvMediaSource(
              itemGuid: 'item',
              mediaGuid: 'media',
              videoGuid: 'video',
              url: 'https://example.test/video.mp4',
              headers: {},
              title: 'Video',
            ),
          ),
          isFalse,
        );
      }
    });
  }
}
