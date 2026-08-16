# 详情页音轨语言中文显示实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让详情页音轨摘要和选择面板把常见媒体语言码显示为中文，并与已完成的手动外挂字幕持久化改动一起安全提交。

**Architecture:** 保持 `AudioTrackOption` 和播放器数据中的原始语言码不变，由 `MediaLanguageMapper` 维护代码与中文名称映射，由 `PlayDetailTrackSelector` 提供详情页专用展示标题。控制器和当前音轨摘要共用该标题入口；未知非空代码原样显示，明确未知标记保持空白。

**Tech Stack:** Flutter、Dart、flutter_test、Kotlin/JUnit、Git

---

### Task 1: 补齐常见语言映射

**Files:**
- Modify: `test/media_language_mapper_test.dart`
- Modify: `lib/utils/media_language_mapper.dart`

- [ ] **Step 1: 写映射失败测试**

在 `MediaLanguageMapper` 测试组中增加表驱动用例：

```dart
test('maps common ISO 639 language aliases to Chinese names', () {
  const cases = <String, String>{
    'afr': '南非荷兰语',
    'sq': '阿尔巴尼亚语',
    'arm': '亚美尼亚语',
    'az': '阿塞拜疆语',
    'baq': '巴斯克语',
    'bn': '孟加拉语',
    'bs': '波斯尼亚语',
    'bur': '缅甸语',
    'fil': '菲律宾语',
    'geo': '格鲁吉亚语',
    'is': '冰岛语',
    'ga': '爱尔兰语',
    'kn': '卡纳达语',
    'kk': '哈萨克语',
    'km': '高棉语',
    'lo': '老挝语',
    'mac': '马其顿语',
    'ml': '马拉雅拉姆语',
    'mn': '蒙古语',
    'ne': '尼泊尔语',
    'per': '波斯语',
    'pa': '旁遮普语',
    'ta': '泰米尔语',
    'te': '泰卢固语',
    'ur': '乌尔都语',
    'wel': '威尔士语',
    'be': '白俄罗斯语',
    'sw': '斯瓦希里语',
    'uz': '乌兹别克语',
    'si': '僧伽罗语',
    'mr': '马拉地语',
    'gu': '古吉拉特语',
    'ku': '库尔德语',
    'am': '阿姆哈拉语',
    'la': '拉丁语',
    'gl': '加利西亚语',
  };

  for (final entry in cases.entries) {
    expect(
      MediaLanguageMapper.languageName(entry.key),
      entry.value,
      reason: entry.key,
    );
  }
});
```

- [ ] **Step 2: 运行测试并确认因缺少映射失败**

Run: `flutter test test/media_language_mapper_test.dart`

Expected: FAIL，首个尚未收录的代码返回空字符串。

- [ ] **Step 3: 添加最小映射实现**

在 `_languageNameMap` 和 `_languageAliasToCode` 中为测试列出的语言加入 ISO 639-1、639-2/T、639-2/B（存在时）、英文名称和中文名称别名。每个别名归一到术语三字母代码，例如：

```dart
// _languageNameMap
'fas': '波斯语',
'per': '波斯语',
'fa': '波斯语',
'mya': '缅甸语',
'bur': '缅甸语',
'my': '缅甸语',
'cym': '威尔士语',
'wel': '威尔士语',
'cy': '威尔士语',

// _languageAliasToCode
'persian': 'fas',
'fas': 'fas',
'per': 'fas',
'fa': 'fas',
'波斯语': 'fas',
'burmese': 'mya',
'mya': 'mya',
'bur': 'mya',
'my': 'mya',
'缅甸语': 'mya',
'welsh': 'cym',
'cym': 'cym',
'wel': 'cym',
'cy': 'cym',
'威尔士语': 'cym',
```

其余测试语言按同一规则加入：`afr/af`、`sqi/alb/sq`、`hye/arm/hy`、`aze/az`、`eus/baq/eu`、`ben/bn`、`bos/bs`、`fil/tl`、`kat/geo/ka`、`isl/ice/is`、`gle/ga`、`kan/kn`、`kaz/kk`、`khm/km`、`lao/lo`、`mkd/mac/mk`、`mal/ml`、`mon/mn`、`nep/ne`、`pan/pa`、`tam/ta`、`tel/te`、`urd/ur`、`bel/be`、`swa/sw`、`uzb/uz`、`sin/si`、`mar/mr`、`guj/gu`、`kur/ku`、`amh/am`、`lat/la`、`glg/gl`。

- [ ] **Step 4: 运行映射测试并确认通过**

Run: `flutter test test/media_language_mapper_test.dart`

Expected: PASS。

### Task 2: 统一详情页音轨标题

**Files:**
- Create: `test/play_detail_track_selector_test.dart`
- Modify: `lib/utils/play_detail_track_selector.dart`
- Modify: `lib/controllers/play_detail_sheet_controller.dart`

- [ ] **Step 1: 写展示标题失败测试**

新增最小音轨构造器，并覆盖已知代码、B/T 别名、未知自定义代码和明确未知标记：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/models/stream_track_data.dart';
import 'package:fly_player/utils/play_detail_track_selector.dart';

AudioTrackOption audio(String language) => AudioTrackOption(
  mediaGuid: 'media-1',
  guid: 'audio-$language',
  title: '',
  codecName: 'aac',
  profile: '',
  language: language,
  audioType: '',
  channelLayout: 'stereo',
  channels: 2,
  sampleRate: 48000,
  bps: 0,
  index: 0,
  isDefault: 0,
);

void main() {
  test('localizes audio language codes for detail page display', () {
    expect(PlayDetailTrackSelector.audioOptionTitle(audio('jpn')), '日语');
    expect(PlayDetailTrackSelector.audioOptionTitle(audio('eng')), '英语');
    expect(PlayDetailTrackSelector.audioOptionTitle(audio('fre')), '法语');
    expect(PlayDetailTrackSelector.audioOptionTitle(audio('per')), '波斯语');
  });

  test('keeps custom language codes but hides explicit unknown markers', () {
    expect(PlayDetailTrackSelector.audioOptionTitle(audio('qaa')), 'qaa');
    expect(PlayDetailTrackSelector.audioOptionTitle(audio('und')), '');
    expect(PlayDetailTrackSelector.audioOptionTitle(audio('unknown')), '');
  });
}
```

- [ ] **Step 2: 运行测试并确认因缺少方法失败**

Run: `flutter test test/play_detail_track_selector_test.dart`

Expected: FAIL，提示 `audioOptionTitle` 未定义。

- [ ] **Step 3: 实现最小展示标题方法**

在 `PlayDetailTrackSelector` 中加入：

```dart
static String audioOptionTitle(AudioTrackOption track) {
  final mapped = MediaLanguageMapper.languageName(track.language).trim();
  if (mapped.isNotEmpty) return mapped;
  final raw = track.language.trim();
  final normalized = raw.toLowerCase();
  if (normalized.isEmpty ||
      normalized == 'und' ||
      normalized == 'unknown' ||
      normalized == 'zz-unknow') {
    return '';
  }
  return raw;
}
```

把 `audioLabelForCurrentMedia` 中两处 `track.displayLabel` 改为 `audioOptionTitle(track)`，把 `PlayDetailSheetController.showAudioSheet` 的 `title: e.displayLabel` 改为 `title: PlayDetailTrackSelector.audioOptionTitle(e)`。

- [ ] **Step 4: 运行展示标题与既有本地化测试**

Run: `flutter test test/play_detail_track_selector_test.dart test/media_language_mapper_test.dart test/ui/audio_track_label_localizer_test.dart`

Expected: 全部 PASS。

### Task 3: 回归验证并提交功能改动

**Files:**
- Verify: `test/manual_subtitle_store_test.dart`
- Verify: `test/services/native_player_bridge_local_subtitle_test.dart`
- Verify: `test/mpv_local_file_subtitle_test.dart`
- Verify: `android/app/src/test/kotlin/com/geqian/flyplayer/fly_player/NativeSubtitleImportStoreTest.kt`
- Stage: 仅手动外挂字幕、SUP/PGS 文档修正及音轨语言显示相关文件/代码块

- [ ] **Step 1: 运行 Flutter 字幕和音轨回归测试**

Run: `flutter test test/manual_subtitle_store_test.dart test/services/native_player_bridge_local_subtitle_test.dart test/mpv_local_file_subtitle_test.dart test/media_language_mapper_test.dart test/play_detail_track_selector_test.dart test/ui/audio_track_label_localizer_test.dart`

Expected: 全部 PASS，SRT、SUP/PGS 导入、恢复和删除流程无回归。

- [ ] **Step 2: 运行 Kotlin 字幕存储回归测试**

Run: `./gradlew :app:testFullDebugUnitTest --tests com.geqian.flyplayer.fly_player.NativeSubtitleImportStoreTest`

Workdir: `android`

Expected: `BUILD SUCCESSFUL`。

- [ ] **Step 3: 运行静态分析和差异检查**

Run: `flutter analyze`

Expected: `No issues found!`

Run: `git diff --check`

Expected: 无输出，退出码为 0。

- [ ] **Step 4: 精确暂存相关改动**

先用 `git diff -- <file>` 审核混合文件；完整属于本功能的新文件直接 `git add -- <file>`，混合文件使用 `git add -p -- <file>`，只选择手动字幕、SUP/PGS 修正和音轨中文显示代码块。不得暂存 `jniLibs/*.so`、下载模型/服务/测试、播放器手势或其他既有工作区改动。

- [ ] **Step 5: 检查暂存结果并提交**

Run: `git diff --cached --check && git diff --cached --stat`

Expected: 仅出现本功能相关文件，无 `.so` 和下载模块。

Run: `git commit -m "feat(player): 完善手动字幕持久化与轨道显示"`

- [ ] **Step 6: 检查提交和剩余工作区**

Run: `git show --stat --oneline HEAD && git status --short`

Expected: 新提交包含手动字幕持久化、SRT/SUP/PGS 回归和音轨语言显示；无关改动仍留在工作区且未被提交。
