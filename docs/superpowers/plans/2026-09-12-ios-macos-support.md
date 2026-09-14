# iOS / macOS adaptation implementation plan

**Goal:** Add Apple application projects and working Apple playback, credential persistence and file access to Fly Player.

**Architecture:** Build on committed `main` at `e2c478f` in the isolated `feat/ios-macos-support` branch. Apple uses the existing Flutter media_kit host and playback/reporting pipeline. Android retains its native host. Each platform implements the existing storage/credential contracts.

**Toolchain:** Flutter 3.41.9, Dart 3.11, Swift, CocoaPods; iOS 13 and macOS 10.15 minimums, subject to native dependency validation on Xcode.

## Work packages

- [x] Generate `ios/` and `macos/` using the installed Flutter templates without rewriting shared application code. Add bundle branding, Apple Keychain channel handlers, native contract tests, local network descriptions, HTTP NAS support and macOS sandbox entitlements.
- [x] Add the two Apple media_kit native library packages to `pubspec.yaml` and retain existing locked dependency versions.
- [x] Centralize playback capabilities in `lib/playback/`; test Windows/macOS/iOS, Android native and unsupported platform routing. Update all online, episode, manual and downloaded playback launchers before native reverse-channel registration. Adapt file URIs and touch/fullscreen behavior in the existing media_kit player.
- [x] Add iOS sandbox storage through `StorageAccessHost` and `StorageManagementHost`; test download paths and no Android method-channel calls. Use the system file picker for Apple file selection and remove unreachable Android-only settings there.
- [x] Provide macOS command shortcuts and Apple DanDanPlay build-time configuration, retaining Windows developer configuration lookup and Android native credentials.
- [x] Run focused regression tests, static analysis and the complete Flutter suite. Review all changed files and generated project references. Record pre-existing failures separately from introduced failures.
- [x] Document build commands and remaining Xcode/device checks in `docs/apple-platform-support.md`. Do not claim Apple binaries or native tests are verified on this Windows host.

## Verification

Run `flutter test --no-pub` after focused tests and `flutter analyze --no-pub`; use `git diff --check` and parse Apple plist/project configuration. On a Mac with Flutter 3.41.9 and Xcode, run `flutter pub get`, `flutter build ios --simulator --debug`, `flutter build macos --debug`, and both RunnerTests targets. Device checks cover login restart, HTTP/HTTPS NAS playback, local playback, seek, subtitle selection, episode changes, progress persistence, downloads, safe areas and fullscreen transitions.

## Review boundaries

Original work directories contain in-progress review changes and must remain untouched. No automatic merge, push or signing identity changes. iOS background downloads, PiP and Android AI danmaku occlusion are outside this first Apple implementation; unsupported entry points must not invoke Android channels.
