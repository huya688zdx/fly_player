# 公共播放桥接 + 单条目 launcher 灰度迁移设计（Phase 6 第二子阶段）

> 前置：`docs/superpowers/specs/2026-06-21-public-media-playback-design.md`（公共播放 bundle 骨架）
> 第一阶段骨架已交付：`MediaBackend.getPlayback` 返回 `MediaPlaybackBundle`（Task 1~4，Codex 深审通过 `b0b37ae`/`0eb9484`）

## 目标

把 `ItemPlaybackLauncher`（**仅单条目，先不动 TV**）的播放解析从「内联飞牛取数 + 选择 + mpv 装配」改成「经 `MediaBackend.getPlayback` 拿后端中立 bundle + 经桥接器装配 `MpvMediaSource`」，让单条目播放入口不再直接出现飞牛选择规则。TV、本地下载优先、原生壳反向重载、弹幕预取、进度写回**全部留后续子阶段**。

## 核心张力：桥接器要 raw facts，公共 bundle 故意不带

`PlayerSourceController.buildInitialPlaybackResult` 的签名（已审计）要求**飞牛私有原始结构**：

```dart
Future<PlayerInitialPlaybackResult> buildInitialPlaybackResult({
  required FeiniuApi api,
  required String directUrl,
  required String mediaGuid,
  required String videoGuid,
  required PlaybackStreamData playbackStream,        // 原始流
  required PlaybackQualityOption? quality,           // 原始画质档
  required AudioTrackOption? selectedAudio,          // 原始音轨
  required SubtitleTrackOption? selectedSubtitle,    // 原始字幕
  required Duration startPosition,
});
```

而公共 `MediaPlaybackBundle` 只带中立事实（`MediaPlaybackSource`/`Quality`/`Track`，`id`/`sourceId`/`videoTrackId` 命名），**故意不带** `PlaybackStreamData`、raw `PlaybackQualityOption`、raw 音轨/字幕 option。Codex 明确警告：桥接器不能直接信任 `MediaPlaybackSource.url` 是最终可播 URL，必须用 raw facts 重新调 `buildInitialPlaybackResult`（直链 target、代理会话、headers override、seek 探测都在里面）。

所以本子阶段的设计焦点不是「写个 mapper」，而是：**桥接器如何同时拿到（a）后端中立 bundle 的选择结果 和（b）飞牛 raw facts，且不让 raw facts 污染中立层、不重复网络请求。**

## 方案选项

### 方案 A：selection-only（launcher 仍自取 raw，只借 bundle 做选择）

launcher 保留现有飞牛取数（getPlayInfo/getPlaybackStream/getStreamTrackData），但把内联的画质/音轨/字幕/续播选择换成「调 `getPlayback` 拿 bundle，再把 bundle 选中的中立 id 映射回 raw option」喂桥接器。

- 优点：中立层零改动；桥接器只在 launcher 内。
- 缺点：`getPlayback` 内部又各拉一遍 getPlayInfo/getPlaybackStream/getStreamTrackData → **双倍网络**。且「中立 id → raw option」回映射本身要再写一套匹配，没真正简化。**不推荐**。

### 方案 B：bundle + 不透明后端上下文（推荐）

`getPlayback` 既返回中立 bundle，又**附带一个后端私有、对中立层不透明的 raw 上下文句柄**。中立 launcher 只消费 bundle；一个**飞牛专属桥接器**（住 `lib/player/controllers/` 或 `lib/controllers/`，不住 `lib/media_backend/`）downcast 该上下文，用 raw facts + bundle 选择结果调 `buildInitialPlaybackResult` 装配 `MpvMediaSource`。

- 单次网络（getPlayback 内已取的 raw facts 直接装进上下文）。
- 中立层不出现飞牛字段：上下文在公共签名里是 `Object`（或 `sealed MediaPlaybackBackendContext` 标记接口），只有飞牛桥接器知道真实类型。
- 将来 Emby：`EmbyMediaBackend.getPlayback` 附 Emby 上下文，`EmbyPlaybackSourceBridge` 装配；launcher 仍中立。
- 代价：公共 `getPlayback` 返回类型要扩展成 `(bundle, context)`（或在 bundle 上加 `backendContext` 字段，类型 `Object?`）。需评估这算不算「中立层泄漏」——上下文不透明、无飞牛命名，可接受。

### 方案 C：只交付可测桥接器，暂不翻 launcher

本子阶段只产出桥接器纯函数 + 单测（输入 raw facts + bundle 选择，输出 `MpvMediaSource` 等价物），**不动 launcher 调用链**。下一子阶段再翻。

- 最低风险、纯增量、可单测；不需要实机验证。
- 但 Codex 要的是「桥接器 + 单条目 launcher 灰度迁移」，方案 C 没完成「灰度迁移」那半。

## 推荐

**方案 B**，但分两步交付以控风险：

1. **B-1（可单测，不碰播放链路）**：定义 `MediaPlaybackBackendContext` 标记类型 + 飞牛 `FeiniuPlaybackContext`（持 `api`/`playbackStream`/raw selected quality/audio/subtitle/directUrl）；`getPlayback` 附上下文；新增 `FeiniuPlaybackSourceBridge.assemble(bundle, context) → MpvMediaSource`，复刻 launcher 现有 `buildInitialPlaybackResult` + `MpvMediaSource` 装配逻辑。全程单测（fake api seam + 现成 MpvMediaSource 字段断言），**不改 launcher**。
2. **B-2（灰度翻单条目 launcher，需实机）**：把 `ItemPlaybackLauncher._resolve()` 改成 `getPlayback` + `FeiniuPlaybackSourceBridge`，`open()` / `resolveForNative()` 两条出口都走桥接器产物。`flutter run` 实机验证单条目：默认播放、续播、画质切换、音轨切换、字幕关闭/切换、外部字幕、原生壳重载。TV launcher 不动。

B-1 失败/不满意可随时停在桥接器，不影响线上 launcher；B-2 才碰播放链路。

## 不做（本子阶段）

- 不动 `TvSeasonPlaybackLauncher`。
- 不迁本地下载优先（`local_download_source_resolver`）——设备本地能力仍留 launcher。
- 不改原生壳反向重载、弹幕预取、播放进度写回 / play stats。
- 不接 Emby、不写 `EmbyPlaybackSourceBridge`。
- 不把 `MpvMediaSource` / `FeiniuApi` 放进 `lib/media_backend/`（桥接器住 player/controller 层）。

## 验收口径

- B-1：`flutter test test/media_backend/ test/<bridge_test>` 全 PASS；`flutter analyze` No issues；桥接器装出的 `MpvMediaSource` 关键字段（url/headers/mediaGuid/videoGuid/directLinkQualityIndex/proxySessionId/playLink/serverSessionHlsTimeSeconds/startPosition/轨道 index/guid）与迁移前 launcher 一致（用单测锁）。
- B-2：单条目 `flutter run` 实机验证上述全部播放路径与迁移前一致，方可收口。

## 待用户确认

1. 选 **方案 B（B-1 + B-2 分步）**，还是先只做 **方案 C**（纯桥接器、暂不翻 launcher）？
2. 方案 B 的上下文承载：扩 `getPlayback` 返回 `(bundle, context)`，还是给 `MediaPlaybackBundle` 加 `Object? backendContext` 字段？（前者更干净，后者改动小。）
