# Native Player UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 优化 Android 原生播放页 UI，按 Flutter 播放 UI 信息架构接入字幕、音轨、画质和二级分页抽屉。

**Architecture:** 第一轮仍集中在 `NativePlayerActivity.kt`，避免恢复期大规模拆文件；只把可测试的轨道/画质摘要逻辑做成同文件 top-level helper，并用 JVM 测试保护。UI 采用横屏右侧快捷轨道 + 统一分页抽屉；竖屏或窄屏保留底部入口。

**Tech Stack:** Android Kotlin View、现有 `NativePlayerActivity`、JUnit4、现有 Gradle full/lite flavor。

---

## Files

- Modify: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/NativePlayerActivity.kt`
- Create: `android/app/src/test/kotlin/com/geqian/flyplayer/fly_player/NativePlayerActivityPanelModelsTest.kt`
- Verify: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/mpv/NativePlayerSurface.kt` only if compile reveals method mismatch; do not proactively edit.

## Task 1: 可测试的轨道/画质摘要模型

**Files:**
- Modify: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/NativePlayerActivity.kt`
- Create: `android/app/src/test/kotlin/com/geqian/flyplayer/fly_player/NativePlayerActivityPanelModelsTest.kt`

- [ ] **Step 1: Write failing tests**

Create `NativePlayerActivityPanelModelsTest.kt`:

```kotlin
package com.geqian.flyplayer.fly_player

import org.junit.Assert.assertEquals
import org.junit.Test

class NativePlayerActivityPanelModelsTest {
    @Test
    fun audioSummaryUsesSelectedGuid() {
        val tracks = listOf(
            mapOf<String, Any?>("guid" to "a1", "title" to "AAC", "language" to "zh"),
            mapOf<String, Any?>("guid" to "a2", "title" to "DTS", "language" to "ja"),
        )

        assertEquals("DTS · ja", nativePanelAudioSummary(tracks, "a2"))
    }

    @Test
    fun subtitleSummaryTreatsEmptyGuidAsOff() {
        val tracks = listOf(
            mapOf<String, Any?>("guid" to "s1", "title" to "简体中文", "language" to "zh"),
        )

        assertEquals("关闭", nativePanelSubtitleSummary(tracks, ""))
    }

    @Test
    fun subtitleSummaryFallsBackToTrackLabel() {
        val tracks = listOf(
            mapOf<String, Any?>("guid" to "s1", "title" to "简体中文", "language" to "zh"),
        )

        assertEquals("简体中文 · zh", nativePanelSubtitleSummary(tracks, "s1"))
    }

    @Test
    fun qualitySummaryShowsOriginalWhenOriginalMode() {
        assertEquals(
            "原画",
            nativePanelQualitySummary(
                playbackMode = "originalQuality",
                currentResolution = "3840x2160",
            ),
        )
    }

    @Test
    fun qualitySummaryExtractsVerticalResolution() {
        assertEquals(
            "1080P",
            nativePanelQualitySummary(
                playbackMode = "transcode",
                currentResolution = "1920x1080",
            ),
        )
    }
}
```

- [ ] **Step 2: Run tests and verify red**

Run:

```powershell
cd F:\fly_play_recovered\android
.\gradlew :app:testFullDebugUnitTest --tests "*NativePlayerActivityPanelModelsTest"
```

Expected: compilation fails because `nativePanelAudioSummary`, `nativePanelSubtitleSummary`, and `nativePanelQualitySummary` do not exist.

- [ ] **Step 3: Add minimal helper implementation**

Add top-level helpers near the top of `NativePlayerActivity.kt`, outside the class:

```kotlin
internal fun nativePanelTrackLabel(track: Map<String, Any?>): String {
    val title = track["title"]?.toString()?.trim().orEmpty()
    val language = track["language"]?.toString()?.trim().orEmpty()
    val fallback = track["index"]?.toString()?.trim().orEmpty()
    return when {
        title.isNotEmpty() && language.isNotEmpty() -> "$title · $language"
        title.isNotEmpty() -> title
        language.isNotEmpty() -> language
        fallback.isNotEmpty() -> "轨道 $fallback"
        else -> "轨道"
    }
}

internal fun nativePanelAudioSummary(
    tracks: List<Map<String, Any?>>,
    selectedGuid: String,
): String {
    val selected = tracks.firstOrNull { it["guid"]?.toString().orEmpty() == selectedGuid }
    return selected?.let(::nativePanelTrackLabel) ?: "默认"
}

internal fun nativePanelSubtitleSummary(
    tracks: List<Map<String, Any?>>,
    selectedGuid: String,
): String {
    if (selectedGuid.isEmpty()) return "关闭"
    val selected = tracks.firstOrNull { it["guid"]?.toString().orEmpty() == selectedGuid }
    return selected?.let(::nativePanelTrackLabel) ?: "未选择"
}

internal fun nativePanelQualitySummary(
    playbackMode: String?,
    currentResolution: String?,
): String {
    if (playbackMode == "originalQuality") return "原画"
    val resolution = currentResolution?.trim().orEmpty()
    val vertical = Regex("""(?:^|x)(\d{3,4})(?:p)?$""", RegexOption.IGNORE_CASE)
        .find(resolution)
        ?.groupValues
        ?.getOrNull(1)
        ?.toIntOrNull()
    return if (vertical != null && vertical > 0) "${vertical}P" else "原画"
}
```

- [ ] **Step 4: Run tests and verify green**

Run:

```powershell
cd F:\fly_play_recovered\android
.\gradlew :app:testFullDebugUnitTest --tests "*NativePlayerActivityPanelModelsTest"
```

Expected: `BUILD SUCCESSFUL`.

## Task 2: 统一二级抽屉组件样式

**Files:**
- Modify: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/NativePlayerActivity.kt`

- [ ] **Step 1: Replace rough panel rows with polished primitives**

Add helper methods:

```kotlin
private fun panelPrimaryTile(
    title: String,
    subtitle: String = "",
    trailing: String = "",
    selected: Boolean = false,
    onClick: () -> Unit,
): View

private fun panelOptionTile(
    title: String,
    subtitle: String = "",
    selected: Boolean = false,
    onClick: () -> Unit,
): View

private fun panelActionChip(
    label: String,
    onClick: () -> Unit,
): TextView
```

Implementation rules:

- Tile background uses dark translucent fill.
- Selected tile uses `ACCENT` stroke and soft blue fill.
- Title maxLines = 1, ellipsize = END.
- Subtitle maxLines = 1, ellipsize = END.
- Keep radius <= 8dp unless existing `glassBackground()` forces larger.

- [ ] **Step 2: Update existing settings root to use new tiles**

Replace rows in `buildSettingsRoot()` with `panelPrimaryTile`, preserving all existing destinations:

```kotlin
addPanelRow(panelPrimaryTile("画面调整", "亮度、对比度、饱和度") {
    pushPanel(PanelPage("画面调整") { buildVideoAdjustPage() })
})
```

- [ ] **Step 3: Compile check**

Run:

```powershell
cd F:\fly_play_recovered\android
.\gradlew :app:compileFullProfileKotlin
```

Expected: `BUILD SUCCESSFUL`.

## Task 3: 横屏右侧快捷轨道和播放控制根页

**Files:**
- Modify: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/NativePlayerActivity.kt`

- [ ] **Step 1: Add quick rail**

Add a right-side quick rail to the root overlay layout for landscape/wide screens. Buttons:

```text
字幕
音轨
画质
弹幕
设置
```

Each button opens a `PanelPage`:

```kotlin
panelQuickRailButton("字幕") { showSubtitlePanel() }
panelQuickRailButton("音轨") { showAudioPanel() }
panelQuickRailButton("画质") { showQualityPanel() }
panelQuickRailButton("弹幕") { togglePanel(PanelPage("弹幕设置") { buildDanmakuSettingsPage() }) }
panelQuickRailButton("设置") { showSettingsRoot() }
```

- [ ] **Step 2: Add playback control root panel**

Create `showPlaybackControlPanel()` and `buildPlaybackControlRoot()`:

```kotlin
private fun showPlaybackControlPanel() {
    togglePanel(PanelPage("播放控制") { buildPlaybackControlRoot() })
}
```

Root rows:

- 字幕：`nativePanelSubtitleSummary(trackList("subtitleTracks"), selectedSubtitleGuid)`
- 音轨：`nativePanelAudioSummary(trackList("audioTracks"), selectedAudioGuid)`
- 画质：`nativePanelQualitySummary(loadArgsMap["playbackMode"]?.toString(), loadArgsMap["resolution"]?.toString())`
- 弹幕：开/关
- 设置：播放设置
- 选集：当前集摘要

- [ ] **Step 3: Wire more/settings button**

Change the top “更多” button to open `showPlaybackControlPanel()` instead of dumping every setting directly.

- [ ] **Step 4: Compile check**

Run:

```powershell
cd F:\fly_play_recovered\android
.\gradlew :app:compileFullProfileKotlin
```

Expected: `BUILD SUCCESSFUL`.

## Task 4: 字幕、音轨、画质二级页接入

**Files:**
- Modify: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/NativePlayerActivity.kt`

- [ ] **Step 1: Implement subtitle panel**

Create:

```kotlin
private fun showSubtitlePanel() {
    togglePanel(PanelPage("字幕") { buildSubtitlePanelPage() })
}
```

Rows:

- “关闭字幕”：selected when `selectedSubtitleGuid.isEmpty()`
- Each `subtitleTracks` item with `panelOptionTile`
- “字幕调整” chip opens `buildSubtitleStylePage()`

Selection behavior:

```kotlin
private fun selectSubtitleFromPanel(guid: String) {
    selectedSubtitleGuid = guid
    if (isServerManagedPlayback()) {
        requestServerReload(selectedAudioGuid, selectedSubtitleGuid, null, "正在切换字幕…")
    } else {
        applySubtitleByGuid(guid)
    }
    hidePanel()
}
```

- [ ] **Step 2: Implement audio panel**

Create:

```kotlin
private fun showAudioPanel() {
    togglePanel(PanelPage("音轨") { buildAudioPanelPage() })
}
```

Selection behavior:

```kotlin
private fun selectAudioFromPanel(guid: String) {
    selectedAudioGuid = guid
    if (isServerManagedPlayback()) {
        requestServerReload(selectedAudioGuid, selectedSubtitleGuid, null, "正在切换音轨…")
    } else {
        val index = trackList("audioTracks").indexOfFirst { it["guid"]?.toString() == guid }
        playerSurface.setAudioTrack(if (index >= 0) index + 1 else null, guid)
    }
    hidePanel()
}
```

- [ ] **Step 3: Implement quality panel**

Create:

```kotlin
private fun showQualityPanel() {
    togglePanel(PanelPage("画质") { buildQualityPanelPage() })
}
```

Each row calls `requestQuality(index)` and hides the panel.

- [ ] **Step 4: Replace bottom button handlers**

Change existing bottom buttons:

```kotlin
makeEntryButton("音轨") { showAudioPanel() }
makeEntryButton("字幕") { showSubtitlePanel() }
makeEntryButton(currentQualityLabel()) { showQualityPanel() }
```

- [ ] **Step 5: Compile check**

Run:

```powershell
cd F:\fly_play_recovered\android
.\gradlew :app:compileFullProfileKotlin
```

Expected: `BUILD SUCCESSFUL`.

## Task 5: Final verification

**Files:**
- No planned edits.

- [ ] **Step 1: Run focused tests**

```powershell
cd F:\fly_play_recovered\android
.\gradlew :app:testFullDebugUnitTest --tests "*NativePlayerActivityPanelModelsTest"
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 2: Run full/lite Kotlin compile**

```powershell
cd F:\fly_play_recovered\android
.\gradlew :app:compileFullProfileKotlin
.\gradlew :app:compileLiteProfileKotlin
```

Expected: both `BUILD SUCCESSFUL`.

- [ ] **Step 3: Build profile APK**

```powershell
cd F:\fly_play_recovered
F:\software\flutter_Sdk\flutter\bin\flutter.bat build apk --profile --flavor full
```

Expected: `build\app\outputs\flutter-apk\app-full-profile.apk`.

- [ ] **Step 4: Manual smoke checklist**

On device:

- Top/bottom controls show readable Chinese labels.
- Right-side quick rail appears in landscape.
- 字幕 opens subtitle panel; off and track selection work.
- 音轨 opens audio panel; selection updates current audio.
- 画质 opens quality panel; selection reloads source.
- 弹幕 settings still opens and danmaku still renders.
