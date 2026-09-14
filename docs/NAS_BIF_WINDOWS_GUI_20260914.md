# Windows NAS BIF GUI verification

This report covers the independent portable Release client built from `4b0e747` and the NAS preview at `http://192.168.6.120:8796`. The application was launched with `scripts/run-bif-integration.ps1 -ShowWindow`, using `.runtime/bif-integration` on E as its separate profile. Runtime screenshots, timestamps, input helpers, and resource samples are in `.runtime/bif-integration/evidence`.

## Method and boundaries

The test used the visible Fly login, source selection, media detail, playback, pause, back, and timeline controls. Windows UI Automation exposed only the Flutter view, so input used real OS mouse events and `SendInput`, guarded by the exact executable path and foreground process. The helper restored the test window before input. Screenshots were actual `PrintWindow` captures from that process. No preferences, playback state, Dart internals, or media were injected to imitate user interaction.

Credentials came from the authorized private initial-access file without printing the password. The login form kept the password masked, unchecked remember-password, and registered an independent test device. The test did not close another player's window, terminate another process, alter the workspace-root launchers, or copy a different user's profile.

The build includes the committed clean OPED/mask baseline. It does not include the B worktree's dirty later OPED/mask/settings changes or the original main worktree's dirty edits. This report therefore does not validate that unmerged work. The ADB device listing was empty; Android playback on a physical device remains unverified. Audio was not independently auditioned through these screenshot tools.

## Login and original preview fallback

Fly login against the preview service succeeded. The app synchronized two media sources, switched to Emby, populated the catalog, and opened the Violet Evergarden series detail page. Its main play button explicitly selected Season 1 Episode 7. Evidence: `03-system-input.png`, `04-login-result.png`, `05-source-emby.png`, and `06-violet-detail.png`. The earlier `02-login-prepared.png` was an unsuccessful window-message input attempt and is not evidence of a filled form.

At 00:56:12.354 (+08:00), the test invoked the real click on the episode's play button. At 00:56:16.032, `08-play-start.png` showed the actual episode image and `00:01 / 23:41`, with a pause control. At 00:56:51.406, `10-fallback-mid-preview.png` showed a timeline hover image for 11:49 while playback was at 00:37. At that time no full-episode NAS asset had been published and this profile had no NAS BIF cache, demonstrating that the existing preview fallback still worked.

Operation timestamps are recorded immediately before the guarded input helper runs; they are not millisecond-precise measurements of the physical click. The helper's restore/focus checks run before input.

## Playback lease and worker handoff

The parent service test observed the running full-episode task move to `waiting / FLY_PLAYBACK_ACTIVE`, retaining 2 of 24 completed segments and 12 frames. Its job update timestamp was 00:56:13.708, about 1.35 seconds after the client click command began. No partial asset was published.

The test invoked the pause control at 00:57:03.636. Both `11-paused.png` (00:57:06.995) and `13-paused-retained.png` (00:57:51.215) showed `00:50 / 23:41` and a play icon. The parent independently observed an active paused lease beyond 30 seconds. A second worker invocation returned `attempted=false` and `waiting / FLY_PLAYBACK_ACTIVE` in 0.677 seconds, without decoding or advancing the retained checkpoint.

The test invoked the playback back control at 00:58:56.525. `14-stopped-detail.png` at 00:59:00.139 showed the series detail page again. The parent subsequently confirmed that the original session was `stopped` and that the worker resumed from its retained checkpoint.

At 01:05:15.489, a read-only screenshot requested by the parent showed that the same test window had been independently switched to K-On Season 1 Episode 3 and was actually playing at `12:00 / 24:11`. The parent observed a distinct new playback session on the same test device and another correct worker handoff. This was not an automated test action: the last test input remained the 00:58:56 back control. The test sent no further input and did not interrupt that playback. Evidence: `15-unexpected-lease-check.png`.

## Resource samples

These are bounded process samples, not guarantees about the maximum over an entire episode. CPU values are average cores used during each interval; GPU values are the process-specific Windows engine counter snapshot at the end.

| State | Interval | Average CPU cores | Working set | GPU snapshot |
| --- | ---: | ---: | ---: | --- |
| Detail idle | 10.01 s | 0.000 | 185.6 MiB | Not captured |
| Playing | 10.02 s | 0.145 | 401.5 MiB | 3D 6%, Video Codec 22%; other listed engines 0% |
| Paused | 10.01 s | 0.000 | 427.9 MiB | All listed engines 0% |

The process remained responsive. Evidence: `07-idle-resources.json`, `09-playing-resources.json`, and `12-paused-resources.json`. The worker's independent 0.75-core/512-MiB/no-GPU limits and NAS observations belong to the service report.

## Published NAS BIF

The Emby observations above are auxiliary lease and fallback checks. Because Emby already supplies its own preview, they are not acceptance evidence for NAS BIF consumption. Final acceptance uses the FNOS source for Violet Evergarden Season 1 Episode 7, after exact-file proof and full-episode publication, with a local cache SHA match and real first/middle/final timeline hovers.

Root subsequently took over the same independent window, selected the FNOS source, opened the target episode, and actually started playback. The evidence chain includes `root-02-source-home.png`, `root-07-violet-fnos.png`, and `root-08-fnos-play.png`. No mock media, altered application state, or external-player substitute was used.

The published full-episode NAS asset was `5ca1b707-0e63-5e9b-a66e-9d65935e3675`, with 143 frames and 1,143,901 bytes. The SHA256 of the actual profile cache matched the generated NAS asset: `26f6ce53442479e56ee37fa4a16244d74179931f4c79c06b44be13437d6308fd`. Evidence: `root-fnos-cache-audit.json`. The cache file is `.runtime/bif-integration/cache/fly_bif/19fb3956396b4356baf7dbd95001ca03a4804439d711a00d43d4f735f4499513.bif`.

Actual visible timeline hovers establish the user-facing result:

- `root-11-fnos-middle.png`: 11:57 hover with the umbrella character image, while the main video is paused at 15:34.
- `root-15-fnos-start.png`: 00:00 hover with a full black image panel. The generated first JPEG is also black; this is not a missing thumbnail.
- `root-13-fnos-tail.png`: 23:27 hover with the ending sky/figure image.
- `root-14-fnos-final.png`: 23:38 hover with a forest image.
- `root-18-after-zero-preview.png`: a preview remains available after a real seek to zero.

The final BIF index is at 1,420,002 ms. Floor lookup at 1,420,000 ms selects index 141, not the final black index 142. The `root-16-fnos-end.png` artifact has no visible hover panel when independently inspected, so that file is not evidence that the exact final black index was displayed. The directly evidenced acceptance is visible zero, middle and late-episode NAS previews, plus preview survival after seek-zero. The final-index binary audit and the visible late-episode hover checks are kept distinct.

Root exited playback before deploying the production service (`root-19-exit-before-deploy.png`). The window played and was inspected for several minutes; it was not watched continuously through the entire episode. These observations establish actual FNOS playback and NAS preview consumption on Windows, not complete end-to-end viewing or Android-device acceptance.

## Retained local watching facts

A read-only SQLite audit after the user exited found one Emby test record with 50,000 ms watched and one FNOS K-On record with 71,000 ms watched. The latter's maximum position was 760,000 ms; seek position was not counted as watched time. Both separate source databases retained their history/provenance and had successful preview-service receipts with no pending JSON packet. Evidence: `17-local-stats-audit.json`.

The local facts survive preview-service cleanup. `FlyDataSession.accountKey` uses service instance and user, and the statistics scope additionally includes the binding. A public identity read confirmed that preview and production have the same service instance. Complete snapshots include already acknowledged local history, so a new production login/device/stream can re-upload these facts while retaining the original dataset and record identities. This requires the same user/bindings and no unresolved packet belonging to the previous device. Reusing a preview token/stream through a bare address switch is not equivalent to a fresh production login; those preview-only server objects may not exist in production. No migration, login change, or preference edit was performed by this audit.

## Real production login and complete snapshot upload

Root subsequently used the real login form for production `http://192.168.6.120:8787`, then selected FNOS and entered its home page. Evidence: `root-32-production-login-success.png` and `root-33-production-fnos-home.png`. This normal navigation triggered automatic synchronization of both previously used source scopes.

The independent read-only audit at 2026-09-14 02:49:20 (+08:00), `E:/fly_play_recovere/nas-branches/bif-integration/runtime/evidence/nas/player-production-sync.json`, confirmed the new production device `9913fd15-9254-4df4-ad55-f67dae5e2282`. FNOS stream `443bdafc-c2aa-4f8d-9d01-d9f57a481f37` and Emby stream `e71b26c3-4351-4e3a-ba5a-6b41d88f0f6d` each received an applied sequence-1 snapshot: seven FNOS records and one Emby record, eight inserted, zero updated or ignored. Both local scopes advanced to next sequence 2 with zero pending bytes.

Three key records each had exactly one production match, identical provenance, and unchanged watched/maximum-position values: FNOS K-On 71,000/760,000 ms, Emby Violet Evergarden 50,000/50,000 ms, and the final FNOS Violet Evergarden test 239,000/934,000 ms. These watching counters measure accepted continuous media-position advance, not a separately timed wall-clock viewing duration. The audit did not read authentication tables, create an authentication session, or write the database. Local history and the original profile remain retained.
