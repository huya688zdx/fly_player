# 手动外挂字幕持久化恢复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让手动导入的 SRT、SUP、PGS 字幕在详情页立即可见，按集恢复最后选择，并在删除时同步清理文件、元数据和选择状态。

**Architecture:** Kotlin 原生壳与 Dart 详情页继续共享 `FlutterSharedPreferences` 中的一个版本化 JSON 快照。原生侧负责导入、播放前注入和播放器内选择，Dart 侧负责详情展示与详情页删除；两端兼容旧数组并统一写回对象格式。

**Tech Stack:** Flutter/Dart、Kotlin、Android SharedPreferences、MethodChannel、JUnit 4、flutter_test

---

## 文件职责

- `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/NativeSubtitleImportStore.kt`：共享快照编解码、按集查询、选择状态、播放参数恢复、文件与元数据清理。
- `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/NativePlayerActivity.kt`：在所有加载入口使用恢复后的参数，捕获导入上下文，持久化选择，接线删除结果。
- `android/app/src/test/kotlin/com/geqian/flyplayer/fly_player/NativeSubtitleImportStoreTest.kt`：SRT/SUP/PGS 的旧数据迁移、按集恢复、自动选择和删除回归。
- `lib/services/manual_subtitle_store.dart`：Dart 侧兼容编解码、按条目读取、选择读取、文件优先删除和 revision 通知。
- `lib/pages/play_detail_page.dart`：等待刷新后再展示面板，合并手动轨，删除后更新选择与列表。
- `lib/services/native_player_bridge.dart`、`lib/services/native_playback_reentry.dart`：把原生导入/删除事件传给详情页刷新回调。
- `test/manual_subtitle_store_test.dart`：Dart 侧跨端载荷、查询、选择与清理回归。
- `test/mpv_local_file_subtitle_test.dart`：SRT/SUP/PGS 轨道映射与 bundle 合并回归。
- `android/app/src/main/res/values/strings.xml`、`lib/l10n/app_zh.arb`、`lib/l10n/app_zh_CN.arb`：支持格式提示补齐 TTML，增加删除失败提示（如实现路径需要）。

### Task 1: 用失败测试定义原生共享快照与恢复语义

**Files:**
- Create: `android/app/src/test/kotlin/com/geqian/flyplayer/fly_player/NativeSubtitleImportStoreTest.kt`
- Modify: `android/app/build.gradle.kts`
- Modify: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/NativeSubtitleImportStore.kt`

- [ ] **Step 1: 加入 JVM 可执行的 JSON 测试依赖**

在 `dependencies` 中增加：

```kotlin
testImplementation("org.json:json:20240303")
```

- [ ] **Step 2: 写旧数组迁移与新版对象失败测试**

创建独立测试类，断言旧数组可读、写回包含版本/entries/selectedByScope：

```kotlin
@Test
fun legacyArrayMigratesToVersionedObject() {
    val legacy = """[{"guid":"local:sub:srt","mediaGuid":"m1","itemGuid":"e1","fileName":"e1.srt","path":"/tmp/e1.srt","format":"srt","importedAtMs":1}]"""
    val state = decodeNativeSubtitleState(legacy)
    assertEquals("local:sub:srt", state.entries.single().guid)

    val encoded = JSONObject(encodeNativeSubtitleState(state))
    assertEquals(2, encoded.getInt("version"))
    assertEquals(1, encoded.getJSONArray("entries").length())
    assertEquals(0, encoded.getJSONObject("selectedByScope").length())
}
```

- [ ] **Step 3: 写 SRT、SUP、PGS 按集恢复失败测试**

用真实临时文件和纯函数 `restoreNativeSubtitleLoadArgs` 断言：

```kotlin
@Test
fun restoresSelectedSrtForSameItemAcrossMediaVariants() {
    val restored = restoreNativeSubtitleLoadArgs(
        loadArgs = mapOf("itemGuid" to "e1", "mediaGuid" to "m2", "subtitleTracks" to emptyList<Any>()),
        state = stateOf(entry("local:sub:srt", "m1", "e1", "e1.srt", "srt"), selected = "local:sub:srt"),
        fileExists = { true },
    )
    assertEquals("local:sub:srt", restored["subtitleTrackGuid"])
    assertEquals(true, restored["preferExternalSubtitle"])
    assertEquals("/tmp/e1.srt", (restored["localSubtitleFiles"] as Map<*, *>)["local:sub:srt"])
}

@Test
fun restoresSupAndPgsAsBitmapLocalFiles() {
    val restored = restoreNativeSubtitleLoadArgs(
        loadArgs = mapOf("itemGuid" to "e1", "mediaGuid" to "m1"),
        state = stateOf(
            entry("local:sub:sup", "m1", "e1", "e1.sup", "sup"),
            entry("local:sub:pgs", "m1", "e1", "e1.pgs", "pgs"),
            selected = "local:sub:sup",
        ),
        fileExists = { true },
    )
    val tracks = restored["subtitleTracks"] as List<Map<String, Any?>>
    assertEquals(listOf(1, 1), tracks.map { it["isBitmap"] })
    assertEquals(listOf(1, 1), tracks.map { it["isExternal"] })
}

@Test
fun doesNotLeakSubtitleIntoAnotherItem() {
    val restored = restoreNativeSubtitleLoadArgs(
        loadArgs = mapOf("itemGuid" to "e2", "mediaGuid" to "m2"),
        state = stateOf(entry("local:sub:srt", "m1", "e1", "e1.srt", "srt"), selected = "local:sub:srt"),
        fileExists = { true },
    )
    assertEquals(emptyList<Any>(), restored["subtitleTracks"])
    assertEquals(null, restored["subtitleTrackGuid"])
}
```

- [ ] **Step 4: 运行测试确认 RED**

Run:

```powershell
cd android
.\gradlew.bat :app:testFullDebugUnitTest --tests "com.geqian.flyplayer.fly_player.NativeSubtitleImportStoreTest"
```

Expected: FAIL，提示快照类型和恢复函数尚不存在。

- [ ] **Step 5: 实现最小快照模型、兼容编解码和纯恢复函数**

在 `NativeSubtitleImportStore.kt` 增加以下稳定接口，并让对象方法复用它们：

```kotlin
internal const val NATIVE_SUBTITLE_STATE_VERSION = 2

internal data class NativeSubtitleEntry(
    val guid: String,
    val mediaGuid: String,
    val itemGuid: String,
    val fileName: String,
    val path: String,
    val format: String,
    val importedAtMs: Long,
)

internal data class NativeSubtitleState(
    val entries: List<NativeSubtitleEntry> = emptyList(),
    val selectedByScope: Map<String, String> = emptyMap(),
    val root: JSONObject = JSONObject(),
)

internal fun nativeSubtitleScopeKey(itemGuid: String, mediaGuid: String): String =
    itemGuid.trim().takeIf { it.isNotEmpty() }?.let { "item:$it" }
        ?: mediaGuid.trim().takeIf { it.isNotEmpty() }?.let { "media:$it" }.orEmpty()

internal fun decodeNativeSubtitleState(raw: String): NativeSubtitleState
internal fun encodeNativeSubtitleState(state: NativeSubtitleState): String

internal fun restoreNativeSubtitleLoadArgs(
    loadArgs: Map<String, Any?>,
    state: NativeSubtitleState,
    fileExists: (String) -> Boolean,
): Map<String, Any?>
```

恢复函数按 `itemGuid` 优先匹配，只有没有条目匹配时才按 `mediaGuid` 回退；注入的轨道包含 `guid/title/format/codecName/language/index/isDefault/forced/isExternal/extraFile/isBitmap`。若选择映射有效，写入 `subtitleTrackGuid`、`preferExternalSubtitle=true`、`subtitleTrackIndex=null`。

- [ ] **Step 6: 运行原生存储测试确认 GREEN**

Run:

```powershell
cd android
.\gradlew.bat :app:testFullDebugUnitTest --tests "com.geqian.flyplayer.fly_player.NativeSubtitleImportStoreTest"
```

Expected: PASS。

### Task 2: 接通原生导入、选择、切集与重进

**Files:**
- Modify: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/NativeSubtitleImportStore.kt`
- Modify: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/NativePlayerActivity.kt`
- Modify: `android/app/src/test/kotlin/com/geqian/flyplayer/fly_player/NativeSubtitleImportStoreTest.kt`

- [ ] **Step 1: 写选择清除和文件删除失败测试**

```kotlin
@Test
fun removingSelectedSubtitleDropsEntryAndSelectionAfterFileDeletion() {
    val state = stateOf(entry("local:sub:sup", "m1", "e1", "e1.sup", "sup"), selected = "local:sub:sup")
    val result = removeNativeSubtitleFromState(state, "local:sub:sup")
    assertTrue(result.entries.isEmpty())
    assertTrue(result.selectedByScope.isEmpty())
}

@Test
fun stateIsNotRemovedWhenFileDeletionFails() {
    val state = stateOf(entry("local:sub:pgs", "m1", "e1", "e1.pgs", "pgs"), selected = "local:sub:pgs")
    val result = deleteNativeSubtitle(
        state = state,
        guid = "local:sub:pgs",
        deleteFile = { false },
    )
    assertFalse(result.deleted)
    assertEquals("local:sub:pgs", result.state.entries.single().guid)
}
```

- [ ] **Step 2: 运行测试确认 RED**

Run:

```powershell
cd android
.\gradlew.bat :app:testFullDebugUnitTest --tests "com.geqian.flyplayer.fly_player.NativeSubtitleImportStoreTest"
```

Expected: FAIL，缺少状态删除与文件删除编排函数。

- [ ] **Step 3: 实现原生持久化操作**

实现并由 Context 包装方法调用：

```kotlin
internal data class NativeSubtitleDeleteResult(
    val deleted: Boolean,
    val state: NativeSubtitleState,
    val removed: NativeSubtitleEntry? = null,
)

internal fun removeNativeSubtitleFromState(
    state: NativeSubtitleState,
    guid: String,
): NativeSubtitleState

internal fun deleteNativeSubtitle(
    state: NativeSubtitleState,
    guid: String,
    deleteFile: (String) -> Boolean,
): NativeSubtitleDeleteResult
```

`NativeSubtitleImportStore` 提供同步提交成功与否明确的 `saveEntryAndSelect`、`setSelectedGuid`、`deleteEntryAndFile`；所有写入使用同一锁串行化并用 `commit()` 确保反向通知发生在写入可见之后。

- [ ] **Step 4: 让所有播放器加载使用有效恢复参数**

在 `onCreate` 先得到：

```kotlin
val effectiveLoadArgs = NativeSubtitleImportStore.restoreLoadArgs(this, loadArgs)
loadArgsMap = effectiveLoadArgs
val creationParams = HashMap<String, Any?>(effectiveLoadArgs).apply {
    put("videoOutputBackend", "surface")
    put("enableNativeDanmakuRenderer", true)
}
```

在 `applyLoadArgs` 首行恢复并在后续统一使用：

```kotlin
val effectiveLoadArgs = NativeSubtitleImportStore.restoreLoadArgs(this, loadArgs)
mediaTitle = resolveTitle(effectiveLoadArgs)
loadArgsMap = effectiveLoadArgs
selectedAudioGuid = effectiveLoadArgs["audioTrackGuid"]?.toString().orEmpty()
selectedSubtitleGuid = effectiveLoadArgs["subtitleTrackGuid"]?.toString().orEmpty()
playerSurface.load(effectiveLoadArgs)
```

- [ ] **Step 5: 捕获导入作用域并持久化最后选择**

`importSubtitleFromUri` 在线程启动前捕获 `itemGuid/mediaGuid`。复制完成后先生成 guid 并调用 `saveEntryAndSelect`；失败时删除新文件。回到 UI 线程后只有当前 `itemGuid` 仍等于捕获值才调用 `addLocalSubtitleTrack` 和立即选择，否则只发送刷新通知。

`selectSubtitleFromPanel` 在本地 guid 时保存当前选择，在内嵌或关闭时清除当前作用域选择：

```kotlin
NativeSubtitleImportStore.setSelectedGuid(
    context = this,
    itemGuid = loadArgsMap["itemGuid"]?.toString().orEmpty(),
    mediaGuid = loadArgsMap["mediaGuid"]?.toString().orEmpty(),
    guid = guid.takeIf(::isLocalSubtitleGuid),
)
```

- [ ] **Step 6: 原生删除入口改用文件优先编排**

`removeLocalSubtitle` 只在 `deleteEntryAndFile` 成功后移除当前轨道、关闭已选字幕并发送 `localSubtitleRemoved`；失败则保留面板状态并显示失败提示。

- [ ] **Step 7: 运行原生测试和 Kotlin 编译**

Run:

```powershell
cd android
.\gradlew.bat :app:testFullDebugUnitTest --tests "com.geqian.flyplayer.fly_player.NativeSubtitleImportStoreTest"
.\gradlew.bat :app:compileFullDebugKotlin
```

Expected: 两条命令均 PASS。

### Task 3: 修正 Dart 共享存储、按集选择和文件清理

**Files:**
- Modify: `test/manual_subtitle_store_test.dart`
- Modify: `lib/services/manual_subtitle_store.dart`

- [ ] **Step 1: 写跨端载荷与按集选择失败测试**

```dart
test('读取 Kotlin 旧数组并按 itemGuid 优先匹配', () async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    ManualSubtitleStore.prefKey: jsonEncode(<Object?>[
      entry(guid: 'local:sub:srt', mediaGuid: 'm1', itemGuid: 'e1', format: 'srt').toJson(),
    ]),
  });
  final entries = await store.loadForItem('e1', mediaGuid: 'm2');
  expect(entries.single.guid, 'local:sub:srt');
});

test('读取 selectedByScope 中同一集最后选择', () async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    ManualSubtitleStore.prefKey: jsonEncode(<String, Object?>{
      'version': 2,
      'entries': <Object?>[entry(guid: 'local:sub:sup', itemGuid: 'e1').toJson()],
      'selectedByScope': <String, String>{'item:e1': 'local:sub:sup'},
    }),
  });
  expect(await store.selectedGuidForItem('e1', mediaGuid: 'm1'), 'local:sub:sup');
});
```

- [ ] **Step 2: 写 SRT/SUP 文件与元数据清理失败测试**

```dart
test('deleteByGuid 先删除文件再清理元数据和选择', () async {
  final dir = Directory.systemTemp.createTempSync('manual_subtitle_delete_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final path = '${dir.path}${Platform.pathSeparator}episode.sup';
  File(path).writeAsBytesSync(<int>[0x50, 0x47]);
  await store.add(entry(guid: 'local:sub:sup', itemGuid: 'e1', path: path));
  await store.setSelectedGuid(itemGuid: 'e1', mediaGuid: 'm1', guid: 'local:sub:sup');

  expect(await store.deleteByGuid('local:sub:sup'), isTrue);
  expect(File(path).existsSync(), isFalse);
  expect(await store.loadAll(), isEmpty);
  expect(await store.selectedGuidForItem('e1', mediaGuid: 'm1'), isNull);
});

test('文件删除失败时保留 PGS 元数据', () async {
  await store.add(entry(guid: 'local:sub:pgs', itemGuid: 'e1', format: 'pgs'));
  expect(
    await store.deleteByGuid('local:sub:pgs', deleteFile: (_) async => false),
    isFalse,
  );
  expect((await store.loadAll()).single.guid, 'local:sub:pgs');
});
```

- [ ] **Step 3: 运行测试确认 RED**

Run:

```powershell
flutter test test/manual_subtitle_store_test.dart --concurrency=1
```

Expected: FAIL，旧数组解析、选择 API 和 `deleteByGuid` 尚未实现。

- [ ] **Step 4: 实现 Dart 快照兼容与清理 API**

`_loadPayload` 同时接受 `List` 和 `Map`；旧数组包装为新版对象。增加：

```dart
static String scopeKey(String itemGuid, String mediaGuid) {
  final item = itemGuid.trim();
  if (item.isNotEmpty) return 'item:$item';
  final media = mediaGuid.trim();
  return media.isEmpty ? '' : 'media:$media';
}

Future<String?> selectedGuidForItem(String itemGuid, {String mediaGuid = ''});

Future<void> setSelectedGuid({
  required String itemGuid,
  required String mediaGuid,
  String? guid,
});

Future<bool> deleteByGuid(
  String guid, {
  Future<bool> Function(String path)? deleteFile,
});
```

`deleteByGuid` 在文件不存在时视为成功；文件存在时先删除，成功后在同一个串行 mutation 中移除 entry 和所有值等于 guid 的 `selectedByScope`，最后增加 revision。

- [ ] **Step 5: 修正 revision 测试监听器引用并确认 GREEN**

使用同一个闭包注册和移除：

```dart
void listener() => notified++;
store.revision.addListener(listener);
addTearDown(() => store.revision.removeListener(listener));
```

Run:

```powershell
flutter test test/manual_subtitle_store_test.dart --concurrency=1
```

Expected: PASS。

### Task 4: 让详情页首次打开即可看到导入字幕

**Files:**
- Modify: `lib/pages/play_detail_page.dart`
- Modify: `lib/services/native_player_bridge.dart`
- Modify: `lib/services/native_playback_reentry.dart`
- Create: `test/services/native_player_bridge_local_subtitle_test.dart`
- Modify: `test/mpv_local_file_subtitle_test.dart`

- [ ] **Step 1: 写原生回调刷新失败测试**

使用 `TestDefaultBinaryMessenger` 绑定 `NativePlayerBridge.bindReentry`，从平台侧发送：

```dart
const codec = StandardMethodCodec();
var imported = <String, dynamic>{};
final token = NativePlayerBridge.bindReentry(
  onResolvePlayback: (_, {qualityIndex, qualityMediaGuid, startPositionMs, subtitleGuid, audioGuid, audioTrackIndex, subtitleTrackIndex, preferredQualityResolution}) async => null,
  onRecordProgress: (_) async {},
  onLocalSubtitleImported: (args) async => imported = args,
);
addTearDown(() => NativePlayerBridge.unbindReentry(token));

await messenger.handlePlatformMessage(
  'fly_player/native_player',
  codec.encodeMethodCall(const MethodCall('localSubtitleImported', <String, Object?>{'guid': 'local:sub:srt'})),
  (_) {},
);
expect(imported['guid'], 'local:sub:srt');
```

- [ ] **Step 2: 运行桥接测试确认当前行为或暴露接线问题**

Run:

```powershell
flutter test test/services/native_player_bridge_local_subtitle_test.dart --concurrency=1
```

Expected: 若当前回调接线完整则 PASS；若平台消息测试暴露 handler/绑定竞态则先保持 RED 并修复最小桥接代码。

- [ ] **Step 3: 面板打开前等待存储刷新**

把 `_showSubtitleSheet` 开头改为：

```dart
await _refreshManualSubtitleEntries();
if (!mounted) return;
final tracks = _currentSubtitleTracks();
if (tracks.isEmpty) return;
```

`_refreshManualSubtitleEntries` 同时读取 `selectedGuidForItem`；有效手动选择存在时更新 `_selectedSubtitleGuid`，已删除的旧 `local:sub:` 选择则清空。

- [ ] **Step 4: 详情页删除改用文件优先 API**

```dart
Future<void> _deleteManualSubtitle(String guid) async {
  final deleted = await const ManualSubtitleStore().deleteByGuid(guid);
  if (!deleted || !mounted) return;
  if (_selectedSubtitleGuid == guid) {
    setState(() => _selectedSubtitleGuid = null);
  }
}
```

删除后刷新列表并重新打开面板的现有流程保留。

- [ ] **Step 5: 补齐 SRT/SUP/PGS 轨道映射测试**

在 `mpv_local_file_subtitle_test.dart` 用三个真实临时文件断言：SRT `isBitmap=0`，SUP/PGS `isBitmap=1`，三者均为 `isExternal=1/extraFile=1` 且路径映射完整。

- [ ] **Step 6: 运行 Flutter 相关测试确认 GREEN**

Run:

```powershell
flutter test test/manual_subtitle_store_test.dart test/mpv_local_file_subtitle_test.dart test/services/native_player_bridge_local_subtitle_test.dart --concurrency=1
```

Expected: PASS。

### Task 5: 完成 SUP/PGS 提交复核与提示一致性

**Files:**
- Modify: `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/NativePlayerActivity.kt`
- Modify: `android/app/src/test/kotlin/com/geqian/flyplayer/fly_player/NativeSubtitleImportStoreTest.kt`
- Modify: `android/app/src/main/res/values/strings.xml`
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_zh_CN.arb`

- [ ] **Step 1: 写格式白名单和路由测试**

```kotlin
@Test
fun supportedManualSubtitleFormatsIncludeTextAndPgsFiles() {
    assertTrue(nativeSubtitleImportFormatSupported("episode.srt"))
    assertTrue(nativeSubtitleImportFormatSupported("episode.ttml"))
    assertTrue(nativeSubtitleImportFormatSupported("episode.sup"))
    assertTrue(nativeSubtitleImportFormatSupported("episode.pgs"))
    assertFalse(nativeSubtitleImportFormatSupported("episode.xml"))
}

@Test
fun localPgsUsesExternalFileWhileServerPgsStaysEmbedded() {
    assertTrue(nativeSubtitleUsesExternalFile(mapOf("guid" to "local:sub:pgs", "format" to "pgs", "isBitmap" to 1)))
    assertFalse(nativeSubtitleUsesExternalFile(mapOf("guid" to "server:pgs", "format" to "pgs", "isBitmap" to 1, "isExternal" to 1)))
}
```

- [ ] **Step 2: 运行测试确认格式 helper 为 RED**

Run:

```powershell
cd android
.\gradlew.bat :app:testFullDebugUnitTest --tests "com.geqian.flyplayer.fly_player.NativeSubtitleImportStoreTest"
```

Expected: FAIL，`nativeSubtitleImportFormatSupported` 尚未抽取。

- [ ] **Step 3: 抽取格式判断并统一提示**

```kotlin
internal fun nativeSubtitleImportFormatSupported(fileName: String): Boolean {
    val ext = fileName.substringAfterLast('.', "").lowercase()
    return ext in NativePlayerActivity.SUBTITLE_IMPORT_EXTENSIONS
}
```

导入入口调用该 helper；三处中文提示统一为：

```text
仅支持 SRT / ASS / SSA / VTT / SUB / TTML / SUP / PGS 字幕
```

- [ ] **Step 4: 保留并核验现有裁剪库能力**

Run:

```powershell
rg -a -o -i "hdmv_pgs_subtitle|pgssub|pgs" android/app/src/main/jniLibs/arm64-v8a/libavcodec.so android/app/src/main/jniLibs/arm64-v8a/libavformat.so android/app/src/main/jniLibs/arm64-v8a/libmpv.so
```

Expected: `libavcodec.so` 包含 `hdmv_pgs_subtitle`/`pgssub`，`libavformat.so` 与 `libmpv.so` 包含 PGS 相关符号。不修改二进制文件。

### Task 6: 全面验证并审查范围

**Files:**
- Verify all modified subtitle files

- [ ] **Step 1: 格式化本次 Dart/Kotlin 文本改动**

Run:

```powershell
dart format lib/services/manual_subtitle_store.dart lib/utils/manual_subtitle_tracks.dart lib/pages/play_detail_page.dart lib/services/native_player_bridge.dart lib/services/native_playback_reentry.dart test/manual_subtitle_store_test.dart test/mpv_local_file_subtitle_test.dart test/services/native_player_bridge_local_subtitle_test.dart
```

Kotlin 使用项目现有四空格格式，不运行会改写无关文件的全仓格式化。

- [ ] **Step 2: 运行定向 Flutter 回归**

Run:

```powershell
flutter test test/manual_subtitle_store_test.dart test/mpv_local_file_subtitle_test.dart test/services/native_player_bridge_local_subtitle_test.dart --concurrency=1
```

Expected: PASS，0 failures。

- [ ] **Step 3: 运行独立 Kotlin 回归与编译**

Run:

```powershell
cd android
.\gradlew.bat :app:testFullDebugUnitTest --tests "com.geqian.flyplayer.fly_player.NativeSubtitleImportStoreTest"
.\gradlew.bat :app:compileFullDebugKotlin
```

Expected: PASS，0 failures。

- [ ] **Step 4: 运行静态分析**

Run:

```powershell
flutter analyze
```

Expected: 无本次改动引入的新 error；若仓库存在既有 warning，记录其文件和数量，不把它宣称为本功能通过。

- [ ] **Step 5: 检查 diff、空白错误和用户已有改动边界**

Run:

```powershell
git diff --check -- . ':(exclude)android/app/src/main/jniLibs/**'
git status --short
git diff -- android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/NativeSubtitleImportStore.kt android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/NativePlayerActivity.kt lib/services/manual_subtitle_store.dart lib/pages/play_detail_page.dart lib/services/native_player_bridge.dart lib/services/native_playback_reentry.dart test/manual_subtitle_store_test.dart test/mpv_local_file_subtitle_test.dart android/app/src/test/kotlin/com/geqian/flyplayer/fly_player/NativeSubtitleImportStoreTest.kt
```

Expected: 每一处新增改动都能追溯到导入刷新、按集恢复、删除清理或 SRT/SUP/PGS 回归；下载排序、手势、缓冲显示和现有 `.so` 改动保持不动。
