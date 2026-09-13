# NAS BIF preview client

This isolated client branch consumes published NAS BIF previews on Android and Windows. It does not change segmentation/mask processing, launch an existing player, replace a running bundle, or change workspace-root launch scripts.

## Preserved baseline

- Started from clean `0ff973b` (verified file OPED and assistant, parent `dbd2112`).
- Merged clean account/login/address/UI branch `0039d91` as `a2a6bce`, preserving the assistant action alongside the newer overview component.
- Applied only the `e43cdc8` NAS danmaku consumption delta as `5fef6da`; did not merge the old repository history.
- Applied committed `edc732a` locale infrastructure as `652b891`, retaining the OPED bridge import. Inherited compatible catalog labels from `fa42892` using the existing localization keys. The newer account and catalog structures from `0039d91` remain in place.
- The dirty original `fly_player` worktree and the dirty OPED-settings changes in `fly-player-b-oped` were not copied or reset. In particular, B's uncommitted OPED settings classes, native settings, timeline controls, and their tests are not part of this build. Full account UI string migration remains outside this bounded integration because the original `fa42892` files predate the newer account components.

## Protocol and lifecycle

`POST /api/v1/bif/resolve` uses the active Fly session and exact binding/item/media-source reference. Only `ready` assets with a verified `FileContext`, complete `[0,duration_ms]` coverage, and matching duration are eligible. Asset URLs must be relative paths under `/api/v1/bif/assets/<id>/content` with exactly one query value for each expected source field. Disabled, missing, stale, malformed, or failed requests silently retain the original preview behavior.

The Fly API uses an isolated strict TLS client; it does not inherit the media client's private-certificate policy. Redirects are disabled. Streamed data is bounded by the declared size and 128 MiB maximum, and checked against SHA256 and the complete BIF index before publication. Validation runs in a worker isolate. The private `fly_bif` application cache hashes service instance, user, exact source, file revision, coordinate, asset id and digest; cached bytes are reverified before reuse. Temporary files are renamed after verification and at most 16 assets are retained.

Only a local cache path reaches a playback host. Windows tries the local BIF first, then the original Emby BIF with its original headers, then chapter images. Android keeps independent NAS-local and Emby stores and prefers the NAS store when ready. The Android bridge accepts canonical paths only below its own `cacheDir/fly_bif`. Fly bearer credentials never enter media headers, chapter images, playback load arguments or a media URL.

Resolution is asynchronous and does not delay media loading. Account/binding epoch, playback generation, native channel ownership, and context identity reject stale results. Desktop identity uses stable scope/item/media-source/load nonce fields so subtitle import, audio-track changes and signed-URL refresh do not invalidate a still-playing file. Source replacement and disposal clear the old preview and stop the old lease.

`POST /api/v1/playback/activity` uses a UUID per active playback context. Playing and paused states refresh every 15 seconds. Stop is serialized after any in-flight update, cancels local timers, and uses the original captured account. Network errors are silent; server expiration remains the final cleanup. No activity is reported without a verified Fly session/binding.

## Independent Windows launcher

After the portable build, run `scripts/run-bif-integration.ps1 -ShowWindow`. It uses this branch's `build/windows/x64-mask-p0-integrated/bundle/fly_player.exe` and an isolated `.runtime/bif-integration` E-drive profile. The underlying launcher sets `FLY_PLAYER_DATA_HOME`, `TEMP`, `TMP`, `APPDATA` and `LOCALAPPDATA` for the child process and restores the calling environment. A new profile needs its own login; existing credentials are not copied.

The old NAS-danmaku launcher inherited with its patch is retained as historical material; use the BIF launcher above for this build.

## Verification boundaries

Automated checks cover manifest/source rejection, SHA and damaged-cache behavior, late-download invalidation, strict TLS despite permissive global media policy, no redirects or credential forwarding, byte limits, paused heartbeats, terminal ordering, stable same-file metadata changes, Windows fallback, and the native local-file generation gate. Existing account/login, OPED, NAS danmaku and desktop playback regressions are also included.

Android validation compiles all native source against the existing E-drive cached dependencies and generated resource/API artifacts, then runs Kotlin BIF JUnit tests. It does not produce or install a newly verified APK. The Windows portable Release build is independent of the existing running players. Subsequent real Windows GUI observations are recorded in [NAS_BIF_WINDOWS_GUI_20260914.md](NAS_BIF_WINDOWS_GUI_20260914.md); Android-device playback remains unverified.

The real Windows FNOS test subsequently demonstrated visible zero, middle and late-episode timeline previews for Violet Evergarden S01E07, with the private cache SHA matching the NAS-generated 143-frame full-episode asset. Preview also remained available after a real seek to zero. Earlier Emby hovers only established fallback and lease behavior; they are not the NAS acceptance result. The GUI report records screenshots, the exact final-index timestamp boundary, and the remaining verification limits.

Build dependencies and caches are on E. The existing locked `pubspec.lock` was retained. An initial mirror-based `pub get` hit the Windows symlink limitation; its dependency resolution was discarded and the matching clean mem2 `package_config`, `package_graph`, and plugin metadata were used with the portable junction-based builder.

Evidence logs are under `E:/fly_play_recovere/.tmp/`: `bif-client-flutter-final.log`, `bif-client-windows-final.log`, and `bif-client-android/{compile.log,junit.log}`.

Final automated checks: 139 Flutter tests across 18 files passed; full `flutter analyze --no-pub` reported no issues; all Android native source compiled with existing deprecation warnings; 10 Kotlin BIF JUnit tests passed; the final portable Windows Release build completed successfully. The launcher passed PowerShell syntax parsing and was subsequently used for the separate real GUI verification report.

Final Windows SHA256:

- `fly_player.exe`: `435C4B1786ECA15A249C8FBE29C856AA85F929E16C2EAE5963579FC7E3C7939E`
- `data/app.so`: `306DCE4573DC075B34552A85B742B5C5AC612DCD6A74588850F75D24AA79B4F7`
