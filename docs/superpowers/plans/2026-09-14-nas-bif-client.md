# NAS BIF client implementation plan

**Goal:** Consume published whole-file NAS BIF assets on Android and Windows without delaying playback; maintain a separate playing/paused activity lease.

**Architecture:** Resolve with the existing Fly account and binding identity. Download with an isolated strict TLS Fly API into an account/file/asset scoped private cache, verify SHA256 and BIF index, and deliver only a local path to playback hosts. Keep Emby BIF and chapter images as fallbacks. Source/account generation changes invalidate async work. Activity owns a UUID per playback source and sends 15-second heartbeats plus terminal stopped.

**Tech stack:** Dart/Flutter, Dio, crypto, path_provider, existing Kotlin and Dart BIF parsers.

- [x] Integrate clean account chain and preserved NAS danmaku patch without rewriting existing worktrees.
- [x] Inherit compatible committed locale infrastructure; preserve newer account behavior.
- [ ] Add failing behavioral tests for asset validation, strict download/cache integrity, account/source late callback rejection, lease ordering and disposal.
- [ ] Add FlyBifService and FlyPlaybackActivity; use injectable I/O and timers for deterministic lifecycle tests.
- [ ] Add desktop local BIF support with Emby fallback and tests; resolve off the playback loading path.
- [ ] Add Android reverse bridge local BIF delivery and local-file parsing with context invalidation and lease lifecycle.
- [ ] Run focused Flutter tests, full analyze and portable Windows Release build entirely on E.
- [ ] Deliver an independent E-profile launcher, report inherited/unmerged scope and platform validation limits, commit final changes.

Checks: `flutter test test/services/fly_bif_service_test.dart test/services/fly_playback_activity_test.dart test/desktop/desktop_seek_thumbnails_test.dart`; `flutter analyze`; `E:/fly_play_recovere/.tools/portable-build/build-mask-p0-integrated.ps1 -ProjectDir E:/fly_play_recovere/.worktrees/fly-player-bif-integration`.
