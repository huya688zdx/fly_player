# 公共播放入口抽象（Phase 6） Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立后端中立的公共播放 bundle，让飞牛播放解析先从入口控制器中抽到 `MediaBackend` 适配层，但暂不迁移播放器深层逻辑。

**Architecture:** 第一阶段新增 `lib/media_backend/playback/` 纯模型和 selector，再新增飞牛 playback mapper，最后给 `MediaBackend` 增加 `getPlayback` 接口。`FeiniuMediaBackend` 只编排飞牛 API 和返回公共 bundle，不构造 `MpvMediaSource`，不碰 `Navigator` / `MpvPlayerPage` / `NativePlayerBridge`。

**Tech Stack:** Flutter / Dart，现有 `FeiniuApi`、`PlayInfoData`、`PlaybackStreamData`、`StreamTrackData`、`PlaybackResumePositionResolver`，测试使用 `flutter_test`。

---

## File Structure

- Create: `lib/media_backend/playback/media_playback.dart`
  - 公共播放请求、播放 bundle、播放源、画质、轨道、会话模型。
- Create: `lib/media_backend/playback/media_playback_selectors.dart`
  - 纯函数选择 quality / audio / subtitle，复刻当前入口控制器规则。
- Create: `lib/media_backend/feiniu/feiniu_playback_mappers.dart`
  - 飞牛 `PlayInfoData` / `PlaybackStreamData` / `StreamTrackData` 到公共播放模型的映射。
- Modify: `lib/media_backend/media_backend.dart`
  - 新增 `getPlayback(MediaPlaybackRequest request)`。
- Modify: `lib/media_backend/feiniu/feiniu_media_backend.dart`
  - 实现 `getPlayback`，薄适配层编排飞牛 API。
- Test: `test/media_backend/media_playback_models_test.dart`
- Test: `test/media_backend/media_playback_selectors_test.dart`
- Test: `test/media_backend/feiniu_playback_mappers_test.dart`
- Test: `test/media_backend/feiniu_playback_backend_test.dart`
- Modify: `docs/superpowers/public-media-frontend-status.md`
  - 每个 Task 完成后记录 commit hash 和验证命令。

---

### Task 1: 公共播放模型

**Files:**
- Create: `lib/media_backend/playback/media_playback.dart`
- Test: `test/media_backend/media_playback_models_test.dart`

- [ ] **Step 1: Write the failing model test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/playback/media_playback.dart';

void main() {
  test('MediaPlaybackBundle exposes neutral playback facts', () {
    const source = MediaPlaybackSource(
      id: 'source-1',
      videoTrackId: 'video-1',
      delivery: MediaPlaybackDeliveryKind.directLink,
      url: 'https://example.test/video.m3u8',
      headers: {'User-Agent': 'FlyPlayer'},
      width: 1920,
      height: 1080,
      videoCodec: 'h264',
      videoProfile: 'High',
      colorSpace: 'bt709',
      colorTransfer: 'bt709',
      colorPrimaries: 'bt709',
      bitDepth: 8,
      reliableSeek: true,
      forceNativeProxy: false,
    );
    const quality = MediaPlaybackQuality(
      id: 'quality-1',
      sourceId: 'source-1',
      videoTrackId: 'video-1',
      label: '1080p',
      resolution: '1080p',
      bitrate: 8000000,
      isDefault: true,
      delivery: MediaPlaybackDeliveryKind.directLink,
      directLinkIndex: 0,
    );
    const audio = MediaPlaybackTrack(
      id: 'audio-1',
      kind: MediaPlaybackTrackKind.audio,
      index: 1,
      label: '日语 AAC',
      language: 'jpn',
      codec: 'aac',
      title: 'Main',
      isDefault: true,
    );
    const session = MediaPlaybackSession(
      id: 'session-1',
      serverManaged: true,
      requiresStop: true,
      hlsTimeSeconds: 30,
    );
    const bundle = MediaPlaybackBundle(
      itemId: 'item-1',
      title: 'Episode 1',
      itemType: 'Episode',
      seriesId: 'series-1',
      seasonId: 'season-1',
      seriesTitle: 'Series',
      seasonNumber: 1,
      episodeNumber: 1,
      posterUrl: '/poster.jpg',
      tmdbId: '123',
      durationSeconds: 1500,
      startPosition: Duration(seconds: 42),
      selectedSource: source,
      selectedQuality: quality,
      selectedAudioTrack: audio,
      selectedSubtitleTrack: null,
      qualities: [quality],
      audioTracks: [audio],
      subtitleTracks: [],
      session: session,
    );

    expect(bundle.selectedSource.headers['User-Agent'], 'FlyPlayer');
    expect(bundle.startPosition, const Duration(seconds: 42));
    expect(bundle.selectedQuality?.sourceId, 'source-1');
    expect(bundle.session.requiresStop, isTrue);
  });

  test('MediaPlaybackRequest distinguishes default subtitle from off', () {
    const request = MediaPlaybackRequest(
      itemId: 'item-1',
      subtitleTrackId: null,
      subtitleTrackExplicitlyDisabled: true,
    );

    expect(request.itemId, 'item-1');
    expect(request.subtitleTrackId, isNull);
    expect(request.subtitleTrackExplicitlyDisabled, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test\media_backend\media_playback_models_test.dart`

Expected: FAIL with missing `media_backend/playback/media_playback.dart` or missing model classes.

- [ ] **Step 3: Implement the minimal public models**

Create `lib/media_backend/playback/media_playback.dart` with the model shapes from the design document. Keep constructors `const`, default string fields empty where useful, and do not use `guid`, `Feiniu`, or `Emby` in public field names.

- [ ] **Step 4: Run model test**

Run: `flutter test test\media_backend\media_playback_models_test.dart`

Expected: PASS.

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib\media_backend\playback test\media_backend\media_playback_models_test.dart`

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git status --short
git add lib/media_backend/playback/media_playback.dart test/media_backend/media_playback_models_test.dart
git diff --cached --name-only
git commit -m "feat: add public media playback models"
```

---

### Task 2: 公共播放选择器

**Files:**
- Create: `lib/media_backend/playback/media_playback_selectors.dart`
- Test: `test/media_backend/media_playback_selectors_test.dart`

- [ ] **Step 1: Write the failing selector tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/playback/media_playback.dart';
import 'package:fly_player/media_backend/playback/media_playback_selectors.dart';

void main() {
  const original = MediaPlaybackQuality(
    id: 'original',
    sourceId: 'source-a',
    videoTrackId: 'video-a',
    label: '原画',
    resolution: '4K',
    bitrate: 20000000,
    isDefault: true,
    delivery: MediaPlaybackDeliveryKind.original,
  );
  const transcoded = MediaPlaybackQuality(
    id: 'transcoded',
    sourceId: 'source-b',
    videoTrackId: 'video-b',
    label: '1080p',
    resolution: '1080p',
    bitrate: 8000000,
    isDefault: false,
    delivery: MediaPlaybackDeliveryKind.serverSession,
  );

  test('quality id wins over index', () {
    final selected = selectPlaybackQuality(
      qualities: const [original, transcoded],
      qualityId: 'transcoded',
      qualityIndex: 0,
    );

    expect(selected, transcoded);
  });

  test('quality index is used when id is absent', () {
    final selected = selectPlaybackQuality(
      qualities: const [original, transcoded],
      qualityIndex: 1,
    );

    expect(selected, transcoded);
  });

  test('default quality is used as fallback', () {
    final selected = selectPlaybackQuality(
      qualities: const [transcoded, original],
    );

    expect(selected, original);
  });

  test('subtitle can be explicitly disabled', () {
    const subtitle = MediaPlaybackTrack(
      id: 'subtitle-1',
      kind: MediaPlaybackTrackKind.subtitle,
      label: '中文',
      language: 'chi',
      codec: 'ass',
      title: '',
      isDefault: true,
      subtitleLocation: MediaSubtitleLocation.embedded,
    );

    final selected = selectPlaybackTrack(
      tracks: const [subtitle],
      preferredTrackId: null,
      explicitlyDisabled: true,
    );

    expect(selected, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test\media_backend\media_playback_selectors_test.dart`

Expected: FAIL with missing selector file or functions.

- [ ] **Step 3: Implement selector functions**

Implement:

```dart
MediaPlaybackQuality? selectPlaybackQuality({
  required List<MediaPlaybackQuality> qualities,
  String? qualityId,
  int? qualityIndex,
});

MediaPlaybackTrack? selectPlaybackTrack({
  required List<MediaPlaybackTrack> tracks,
  String? preferredTrackId,
  bool explicitlyDisabled = false,
});
```

Rules:

- `qualityId` wins over `qualityIndex`.
- `qualityIndex` is used only when in range.
- fallback is first `isDefault == true`, otherwise first item, otherwise null.
- track `preferredTrackId` wins when non-empty.
- `explicitlyDisabled == true` returns null, used for subtitles.
- fallback track is first `isDefault == true`, otherwise first item, otherwise null.

- [ ] **Step 4: Run selector tests**

Run: `flutter test test\media_backend\media_playback_selectors_test.dart`

Expected: PASS.

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib\media_backend\playback test\media_backend\media_playback_selectors_test.dart`

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git status --short
git add lib/media_backend/playback/media_playback_selectors.dart test/media_backend/media_playback_selectors_test.dart
git diff --cached --name-only
git commit -m "feat: add media playback selectors"
```

---

### Task 3: 飞牛播放 mapper

**Files:**
- Create: `lib/media_backend/feiniu/feiniu_playback_mappers.dart`
- Test: `test/media_backend/feiniu_playback_mappers_test.dart`

- [ ] **Step 1: Write mapper tests against real constructors**

Before writing fixtures, inspect these files and match their current constructors:

```bash
Get-Content lib\models\play_info.dart
Get-Content lib\models\playback_stream.dart
Get-Content lib\models\stream_track_data.dart
```

Write tests covering:

- `PlayInfoData.mediaGuid` maps to `MediaPlaybackSource.id`.
- `PlayInfoData.videoGuid` or selected quality video id maps to `videoTrackId`.
- `PlaybackStreamData.responseHeaders` maps to `MediaPlaybackSource.headers`.
- Audio and subtitle options map to `MediaPlaybackTrack` without leaking `audioGuid` / `subtitleGuid` field names.
- `PlaybackQualityOption` maps to `MediaPlaybackQuality`.
- External subtitle maps to `MediaSubtitleLocation.external`; local subtitle maps to `MediaSubtitleLocation.local`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test\media_backend\feiniu_playback_mappers_test.dart`

Expected: FAIL with missing `feiniu_playback_mappers.dart`.

- [ ] **Step 3: Implement mapper functions**

Implement functions with neutral return types:

```dart
List<MediaPlaybackQuality> mapFeiniuPlaybackQualities(
  List<PlaybackQualityOption> qualities,
);

List<MediaPlaybackTrack> mapFeiniuAudioTracks(
  List<AudioTrackOption> tracks,
);

List<MediaPlaybackTrack> mapFeiniuSubtitleTracks(
  List<SubtitleTrackOption> tracks,
);

MediaPlaybackSource mapFeiniuPlaybackSource({
  required String sourceId,
  required String videoTrackId,
  required PlaybackStreamData playbackStream,
  required PlaybackQualityOption? selectedQuality,
  required String candidateUrl,
  required Map<String, String> headers,
});
```

Do not import Flutter widgets, provider, navigator, or player pages. `media_backend/feiniu` may import existing data models from `lib/models/`.

- [ ] **Step 4: Run mapper tests**

Run: `flutter test test\media_backend\feiniu_playback_mappers_test.dart`

Expected: PASS.

- [ ] **Step 5: Run focused media backend tests**

Run: `flutter test test\media_backend\ --concurrency=1`

Expected: all media backend tests PASS.

- [ ] **Step 6: Analyze**

Run: `flutter analyze lib\media_backend test\media_backend`

Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git status --short
git add lib/media_backend/feiniu/feiniu_playback_mappers.dart test/media_backend/feiniu_playback_mappers_test.dart
git diff --cached --name-only
git commit -m "feat: map Feiniu playback to public bundle parts"
```

---

### Task 4: MediaBackend 播放接口与飞牛编排

**Files:**
- Modify: `lib/media_backend/media_backend.dart`
- Modify: `lib/media_backend/feiniu/feiniu_media_backend.dart`
- Test: `test/media_backend/feiniu_playback_backend_test.dart`

- [ ] **Step 1: Write failing backend orchestration tests**

Use the existing `test/media_backend/feiniu_detail_backend_test.dart` fake seam style as reference. Add a fake `FeiniuApi` that records calls and returns deterministic playback fixtures.

Test cases:

- `getPlayback` calls `getPlayInfo`, `getPlaybackStream`, and best-effort `getStreamTrackData`.
- `startFromBeginning` calls `resetPlaybackRecord` with the selected source id.
- `getStreamTrackData` failure still returns a bundle.
- `qualityId` overrides default source id.
- subtitle disabled request returns `selectedSubtitleTrack == null`.
- resume uses `playInfo.ts > 0 ? playInfo.ts : playInfo.item.watchedTs`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test\media_backend\feiniu_playback_backend_test.dart`

Expected: FAIL with missing `MediaBackend.getPlayback`.

- [ ] **Step 3: Add backend interface**

In `lib/media_backend/media_backend.dart`:

```dart
import 'playback/media_playback.dart';

abstract class MediaBackend {
  // existing methods...

  /// 解析播放所需的后端中立 bundle；不构造 MpvMediaSource。
  Future<MediaPlaybackBundle> getPlayback(MediaPlaybackRequest request);
}
```

- [ ] **Step 4: Implement FeiniuMediaBackend.getPlayback**

Implementation rules:

- `final playInfo = await api.getPlayInfo(request.itemId);`
- `effectiveSourceId = request.qualityId?.trim().isNotEmpty == true ? request.qualityId!.trim() : playInfo.mediaGuid;`
- If `request.startFromBeginning`, call `api.resetPlaybackRecord(itemGuid: playInfo.item.guid, mediaGuid: effectiveSourceId);`
- Load `StreamTrackData?` best-effort; catch errors and report warning using the same pattern as launchers if practical.
- `final playbackStream = await api.getPlaybackStream(effectiveSourceId);`
- `final mergedQualities = mergePlaybackQualitiesWithStreamTrackData(playbackStream.qualities, trackData);`
- Use `selectPlaybackQuality`, `selectPlaybackTrack`, and `PlaybackResumePositionResolver.resolve`.
- Return `MediaPlaybackBundle`.

- [ ] **Step 5: Run backend test**

Run: `flutter test test\media_backend\feiniu_playback_backend_test.dart`

Expected: PASS.

- [ ] **Step 6: Run all media backend tests**

Run: `flutter test test\media_backend\ --concurrency=1`

Expected: all media backend tests PASS.

- [ ] **Step 7: Analyze**

Run: `flutter analyze lib\media_backend test\media_backend`

Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git status --short
git add lib/media_backend/media_backend.dart lib/media_backend/feiniu/feiniu_media_backend.dart test/media_backend/feiniu_playback_backend_test.dart
git diff --cached --name-only
git commit -m "feat: add media playback backend interface"
```

---

### Task 5: 状态看板与 Phase 6 第一阶段收口

**Files:**
- Modify: `docs/superpowers/public-media-frontend-status.md`

- [ ] **Step 1: Update status board**

Record:

- Task 1 commit hash and verification.
- Task 2 commit hash and verification.
- Task 3 commit hash and verification.
- Task 4 commit hash and verification.
- Remaining scope: launcher migration deferred to the next Phase 6 sub-phase.

- [ ] **Step 2: Verify docs diff**

Run: `git diff -- docs/superpowers/public-media-frontend-status.md`

Expected: status update only, no unrelated content churn.

- [ ] **Step 3: Commit status**

```bash
git status --short
git add docs/superpowers/public-media-frontend-status.md
git diff --cached --name-only
git commit -m "docs: record Phase 6 playback backend skeleton progress"
```

---

## Self-Review Checklist

- [ ] Public playback models do not contain `mediaGuid`, `videoGuid`, `audioGuid`, `subtitleGuid`, `Feiniu`, or `Emby` field names.
- [ ] `FeiniuMediaBackend` does not import `package:flutter/material.dart`, `Navigator`, `BuildContext`, `MpvPlayerPage`, or `NativePlayerBridge`.
- [ ] `lib/media_backend` does not construct `MpvMediaSource`.
- [ ] No UI file gains `if (isEmby)`.
- [ ] Existing Feiniu playback launchers still compile and behave unchanged.
- [ ] `flutter test test/media_backend/ --concurrency=1` passes.
- [ ] `flutter analyze lib/media_backend test/media_backend` reports no issues.
- [ ] `HANDOFF.md` remains untracked and unstaged.
