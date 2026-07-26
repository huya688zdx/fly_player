# 多后端前端抽象改造方案（面向 Jellyfin 快速接入）

> 执行者注意：本文档是完整改造计划，按阶段执行，每阶段独立可验收、可提交。
> 执行前先读一遍全文，理解"两族路径"的核心语义再动手。
> 全程约束：**不改任何页面的渲染 UI**（复用现成页面，只在数据层分流）；**UI 文案一律走
> l10n（arb / AppLocalizations getter），禁止硬编码中文、禁止 `_t(path, fallback)` 间接层**；
> 每阶段结束跑 `flutter analyze` + `flutter test` 必须全绿。

---

## 1. 背景与目标

项目最初是飞牛影视（fnOS NAS）的前端，后来加入 Emby 适配并复用了前端组件。现在希望
未来接入 Jellyfin（以及更多媒体服务器）时能**快速接入**：主要功能（首页 / 列表 / 详情 /
搜索 / 收藏 / 播放 / 原生播放器壳 / 进度回写）零 UI 改动、零原生改动，只写一个后端适配目录。

**验收总目标（改造完成的判定标准）**：接入 Jellyfin 时，改动面收敛为——

1. 新增 `lib/media_backend/jellyfin/` 一个目录（适配器 + mappers + 播放桥接）；
2. 在唯一的注册点登记一个"后端描述符"（种类 + 登录表单 + 工厂）；
3. `MediaBackendKind` 枚举加一个值；
4. **不改**任何 `lib/pages/`、`lib/screens/`、`lib/controllers/` 下的播放 launcher、
   任何 Kotlin 原生代码。

---

## 2. 现状盘点（已有的资产，不要推翻重做）

抽象层已有相当完整的骨架，本次改造是**收口和纠偏**，不是重写：

| 资产 | 位置 | 状态 |
|---|---|---|
| 后端中立接口 `MediaBackend`（约 20 个方法） | `lib/media_backend/media_backend.dart` | ✅ 已覆盖首页/列表/详情/季集/播放解析/进度回写/收藏已看 |
| 能力声明 `MediaBackendCapabilities` | `lib/media_backend/media_backend_capabilities.dart` | ✅ 已有，但只有飞牛 preset |
| 中立播放模型（bundle + 不透明 context） | `lib/media_backend/playback/media_playback*.dart` | ✅ 设计良好，字段名已强制中立 |
| 飞牛 / Emby 两个适配器 | `lib/media_backend/feiniu/`、`lib/media_backend/emby/` | ✅ |
| 后端实例路由 | `lib/providers/media_backend_provider.dart` | ⚠️ 硬编码两后端 |
| 会话连接模型 + 存储 | `lib/media_backend/session/media_backend_connection.dart`、`lib/services/media_backend_connection_store.dart` | ⚠️ 字段基本中立，路由逻辑硬编码 |
| 原生壳反向通道统一接线 | `lib/services/native_playback_reentry.dart` | ⚠️ 单一接线点已收口，但内部按 kind 二元分支 |
| 原生播放壳（Kotlin） | `android/.../NativePlayerActivity.kt` 等 | ✅ **已经后端中立**：只消费 `loadArgs` JSON，无任何后端判断（注释里提 Emby 只是说明数据来源） |

**核心认知：原生播放器层不需要改。** Kotlin 侧的边界就是 `loadArgs`（`MpvMediaSource.toMap()`
产出）+ 一组反向通道回调（重解析 / 进度 / 选集 / 外挂字幕 / 服务端会话重载）。这个边界已经是
中立的，本次只需要把它**文档化成契约**并把 Flutter 侧的接线收干净。

---

## 3. 问题清单（阻碍第三个后端快速接入的具体病灶）

### P1. 公共逻辑顶着 "Emby" 的名字（最大病灶）

Emby 作为第一个"公共路径"后端接入时，很多**本质上后端中立**的逻辑被命名/放置成了 Emby 专属。
第三个后端来了要么复制一份 `Jellyfin*`，要么尴尬地调用 `Emby*` 类——两者都错。

| 现有命名 | 位置 | 实际本质 |
|---|---|---|
| `EmbyNativePickerSupport` | `lib/services/emby_native_picker_support.dart` | 纯靠 `MediaBackend` 接口实现的原生壳选集数据装配，无一行 Emby 私有调用 |
| `EmbyPlaybackReporter` | `lib/services/native_playback_reentry.dart:119` | 纯靠 `backend.reportPlayback*` 中立方法实现的进度上报状态机 |
| `_resolveEmbyForNative` / `_embyNativeEpisodes` | `lib/controllers/item_playback_launcher.dart:173,221` | 走 `backend.getPlayback` + `backend.getSeasonEpisodes` 的通用重解析，无 Emby 私有调用 |
| `tv_season_playback_launcher.dart` 内的 `_embyNativeEpisodes` 等对应物 | `lib/controllers/tv_season_playback_launcher.dart` | 同上 |

### P2. 二元分支的语义漂移

代码里约 30+ 处 `kind == feiniu` / `kind == emby` 分支，其中混着**两种不同语义**：

- **正确语义（保留，但要收敛写法）**：`kind != feiniu` → 走公共路径。这类分支的真实含义是
  "飞牛遗留路径 vs 公共路径"，第三个后端自动落入公共分支，方向是对的。
  典型：`play_detail_page.dart:1307`、`tv_detail_page.dart:208,261`、`person_detail_screen.dart:183`、
  `play_detail_screen.dart:73`、`media_list_screen.dart:260,273,354…`、
  `favorite_items_screen.dart:137`、`category_items_screen.dart:84`。
- **错误语义（必须消灭）**：`kind == emby` → 做某事。第三个后端会漏掉这些行为。
  典型：`lib/main.dart:626`、`lib/screens/media_list_screen.dart:147,594`、
  `lib/providers/media_backend_provider.dart:36`、`media_list_screen_widgets.dart:86`。
  这些判断的真实意图都是"当前是**服务器族**后端会话"，不是"是 Emby"。

### P3. 播放桥接器靠调用方 downcast 硬分发

`item_playback_launcher.dart:370-386` 与 `tv_season_playback_launcher.dart` 里：

```dart
if (context is FeiniuPlaybackContext) { …FeiniuPlaybackSourceBridge… }
if (context is EmbyPlaybackContext)   { …EmbyPlaybackSourceBridge… }
```

每加一个后端，要改每个分发点。桥接器选择应该由后端自己提供。

### P4. 登录 / 会话层写死两个后端

- `connection_screen.dart`：`_ConnectionBackend` 二值枚举 + `isEmby` 三元表达式驱动整个
  表单（controller 成对出现：`_baseUrlController` / `_embyBaseUrlController`…）。加 Jellyfin
  要在十几处三元里插第三路。
- `media_backend_provider.dart`：`if (kind == emby) … else feiniu` 硬编码工厂。
- `login_history_screen.dart:110-207`：`isEmby ? 'E' : 'FN'` 式的两值展示逻辑。

### P5. `MediaBackend` 接口的默认实现是"飞牛形状"

大量方法默认实现的文档写着"默认返回空（飞牛走自有路径，不经本接口）；Emby override"。
这意味着新后端作者**必须去读 `EmbyMediaBackend` 才知道哪些方法必须 override**，忘了
override 的表现是页面静默空白（如 `queryFavoriteItems` 默认返回空页）。契约模糊是接入慢的
直接原因之一。

### P6. `MediaBackendCapabilities` 没有服务器族 preset

构造函数把飞牛专属 flag（`supportsDownloadTasks` / `supportsFnConnect` /
`supportsIntroOutroConfig`）设为 required，新后端要逐个显式传 false。

### P7. `getHomeSummary` 返回 `Map<String, dynamic>`

接口注释自己承认"仍为飞牛原始结构"。Emby 实现被迫拼一个飞牛形状的 Map。第三个后端还要
再拼一次。

### P8. Jellyfin 与 Emby 的 API 高度同源，但当前 `EmbyApi` 不可参数化

Jellyfin 是 Emby 3.5 的 fork，REST 形状 90% 一致（`/Users/AuthenticateByName`、`/Items`、
`/Sessions/Playing/*`、`/Videos/{id}/stream`…）。差异集中在：鉴权头（Jellyfin 10.8+ 推荐
`Authorization: MediaBrowser Token="…"`，也兼容 `X-Emby-Authorization`）、个别端点
（Jellyfin 无 `/emby/` 前缀习惯、章节图/Trickplay 端点不同、QuickConnect 为 Jellyfin 特有）、
个别字段。如果 `EmbyApi`（797 行）不抽出可复用内核，Jellyfin 就要复制粘贴 700 行。
**这是"快速接入"最大的杠杆点。**

---

## 4. 目标架构

### 4.1 两族路径的正式语义

全代码库统一为两族路径，并给它们正式命名：

- **遗留族（legacy）**：飞牛专属的完整路径（自有收藏页 / 下载 / FN Connect / PlayInfo /
  NativeReentrySupport 进度通道）。**永远只有飞牛一个成员**，不为它做任何进一步抽象。
- **公共族（server family）**：走 `MediaBackend` 中立接口的路径。Emby 是首个成员，
  Jellyfin 及以后的所有后端**只加入公共族**。

分支判据从"`kind == xxx`"改为语义 getter（加在 `MediaBackendCapabilities` 上）：

```dart
/// 是否走飞牛遗留路径（自有收藏页/下载/PlayInfo/NAS 进度通道）。
/// 永远只有飞牛为 true；新后端一律 false，自动落入公共族路径。
bool get usesLegacyFeiniuFlow => kind == MediaBackendKind.feiniu;
```

会话层（不经 backend 实例的地方，如 `main.dart` / `media_list_screen` 顶部）用
`MediaBackendKind` 上的扩展 getter：

```dart
extension MediaBackendKindX on MediaBackendKind {
  /// 是否服务器族后端（走 MediaBackend 公共路径；飞牛为遗留族）。
  bool get isServerFamily => this != MediaBackendKind.feiniu;
}
```

### 4.2 后端描述符 + 注册表（唯一注册点）

新建 `lib/media_backend/media_backend_registry.dart`：

```dart
/// 一个后端种类的静态描述：登录表单形状、展示元数据、实例工厂。
/// 接入新后端 = 在 [MediaBackendRegistry.all] 里登记一条。
class MediaBackendDescriptor {
  final MediaBackendKind kind;
  final String displayName;          // 'Emby' / 'Jellyfin'（品牌名不走 l10n）
  final String badgeText;            // 登录历史页角标：'E' / 'JF' / 'FN'
  final ServerLoginForm loginForm;   // 表单形状：地址+用户名+密码（服务器族通用）
  final MediaBackend Function(MediaBackendConnection, {String Function()? entryTokenProvider}) createBackend;
  final Future<MediaBackendConnection> Function(ServerLoginInput) authenticate;
}
```

改造消费方：

- `MediaBackendProvider.backend`：按 `session.currentKind` 查注册表拿工厂，删除
  `if (kind == emby)` 硬编码（飞牛遗留族保持现状旁路，不进注册表也可以——注册表只管服务器族）。
- `connection_screen.dart`：后端切换 tab 由注册表驱动渲染（飞牛 tab 保留现状特殊处理，
  服务器族 tab 循环生成）；服务器族登录表单收敛为**一套** controller + 描述符驱动的
  label/hint，删除 `_embyXxxController` 成对字段。
- `login_history_screen.dart`：角标 / 名称从描述符取，删除 `isEmby ? … : …`。

### 4.3 播放桥接器由后端自供

新建中立桥接接口，替代 launcher 里的 downcast 分发：

```dart
/// 把中立播放事实装配成 mpv 最终 source 的后端桥接器。
abstract interface class MediaPlaybackSourceBridge {
  Future<MpvMediaSource> assemble({
    required MediaPlaybackRequest request,
    required MediaPlaybackBundle bundle,
    required MediaPlaybackBackendContext? context,
    required AppLocalizations l10n,
  });
}
```

`MediaBackend` 增加：

```dart
/// 本后端的播放桥接器。launcher 统一经此装配，不再 downcast backendContext。
MediaPlaybackSourceBridge get playbackSourceBridge;
```

`FeiniuPlaybackSourceBridge` / `EmbyPlaybackSourceBridge` 实现该接口（内部自行 downcast
自己的 context 类型，downcast 从"调用方职责"变成"后端私事"）。飞牛桥接器额外产出的
`PlayInfoData` 通过桥接结果的可选 sidecar 字段带出（只有遗留族消费）。

改造点：`item_playback_launcher.dart::_resolve`、`tv_season_playback_launcher.dart` 对应
分发处——删除 `context is FeiniuPlaybackContext / is EmbyPlaybackContext` 判断。

### 4.4 "Emby 命名的公共件"改名搬家

| 现名 | 新名 | 新位置 |
|---|---|---|
| `EmbyNativePickerSupport` | `ServerNativePickerSupport` | `lib/services/server_native_picker_support.dart` |
| `EmbyPlaybackReporter` | `ServerPlaybackReporter` | 留在 `native_playback_reentry.dart` |
| `_resolveEmbyForNative` | `_resolveServerForNative` | 原文件内改名 |
| `_embyNativeEpisodes` | `_serverNativeEpisodes` | 原文件内改名 |
| `emby_playback_source_bridge.dart` | **不改名**（它真是 Emby 私有） | 移入 `lib/media_backend/emby/`（桥接器归后端目录所有） |
| `feiniu_playback_source_bridge.dart` | 不改名 | 移入 `lib/media_backend/feiniu/` |

判定标准：一个类/函数**只调用 `MediaBackend` 中立接口**就属于公共族，改中立名；
调用了 `EmbyApi` / Emby DTO 的才配叫 `Emby*`，并归入 `lib/media_backend/emby/`。

`NativePlaybackReentry.bind` 改造后：飞牛分支保持不动（遗留族）；else 分支即公共族分支，
所有服务器族后端共享，其中 `onReloadServerSession` 是否绑定改由能力位
`capabilities.supportsServerTranscodeSession` 决定（Emby/Jellyfin 直链阶段为 false，
未来接转码时打开），不再靠"是 Emby 所以不绑"的隐式知识。

### 4.5 `MediaBackend` 契约重新定基线

接口方法分成三档，并在接口文件顶部文档表格化（新后端作者只读这一个文件就知道要实现什么）：

1. **必须实现（abstract，无默认）**：`capabilities`、`getCatalogs`、`getHomeSummary`、
   `getContinueWatching`、`getCatalogPreviewItems`、`searchItems`、`getCatalogFilterSchema`、
   `queryCatalogItems`、`getItemDetail`、`getItemSeasons`、`getSeasonEpisodes`、`getPlayback`、
   `playbackSourceBridge`。
2. **服务器族必须 override（默认实现 = 遗留族行为，文档标注 ⚠️SERVER-MUST）**：
   `queryFavoriteItems`、`getPersonItems`、`getItemSourceVersions`、
   `resolveSeriesPlaybackTarget`、`resolveSeriesNextUpEpisode`、`reportPlaybackStart/Progress/Stopped`、
   `setItemFavorite`、`setItemWatched`、`resolveExternalSubtitleFile`。
3. **可选增强**：`getItemSourceInfo`、seek 缩略图等。

为防"忘 override 静默空页"，新增一个**契约单测模板** `test/media_backend/backend_contract_test.dart`：
对每个注册的服务器族后端断言 ⚠️SERVER-MUST 方法均已 override（用反射不可行，改为：注册表
描述符里加 `Set<ServerBackendCapabilityCheck>` 自检清单，或最简单——为 Emby/Jellyfin 各写一组
契约用例，模板化复制）。

`MediaBackendCapabilities` 增加服务器族 preset：

```dart
/// 服务器族后端（Emby / Jellyfin…）能力预设：飞牛专属能力全关，收藏/已看开。
const MediaBackendCapabilities.server({required MediaBackendKind kind, …})
```

### 4.6 MediaBrowser 家族共享客户端（Jellyfin 提速的最大杠杆）

把 `lib/api/emby_api.dart` 重构为家族共享内核 + 风味参数：

```
lib/api/mediabrowser/
  mediabrowser_api.dart       // 原 EmbyApi 主体：auth / items / sessions / stream URL
  mediabrowser_flavor.dart    // 风味参数
lib/api/emby_api.dart         // EmbyApi = MediaBrowserApi(flavor: .emby)，保留导出兼容
```

```dart
class MediaBrowserFlavor {
  final String authorizationScheme;   // Emby: 'X-Emby-Authorization' 头；Jellyfin: 'Authorization: MediaBrowser …'
  final String clientName;            // Authorization 头里的 Client 字段
  final bool supportsQuickConnect;    // Jellyfin 特有，第一阶段可不实现
  // 端点差异走方法级 override，不塞 flavor：JellyfinApi extends MediaBrowserApi 只覆写差异端点。
}
```

重构方式：**纯移动 + 参数化，不改任何请求行为**。`EmbyApi` 名字保留（typedef 或薄子类），
现有调用点零改动。fnos `entry-token` 注入机制原样保留在内核（Jellyfin 也可能被反代）。

`EmbyMediaBackend` 同步评估：其中多数方法只依赖 API 返回的 MediaBrowser 通用 DTO 形状，
可上提为 `MediaBrowserMediaBackend` 基类，`EmbyMediaBackend` / `JellyfinMediaBackend`
继承并只覆写差异（图片 URL 拼法、章节图、播放 URL 构造）。mappers 同理评估上提。
**注意：这一步做到"Jellyfin 接入时自然发现差异再下沉"即可，不要预先猜测差异过度设计。**

### 4.7 原生壳契约文档化（不改 Kotlin 代码）

新建 `docs/native-shell-contract.md`，把现在散落在注释里的边界固化：

1. **loadArgs 字段表**：`MpvMediaSource.toMap()` 全字段 + 语义 + 哪些可空 + `episodes`
   载荷形状 + `danmakuFile` + `seekThumbnails` + `startPositionMs`。标注哪些字段是
   飞牛遗留字段（如 `imageAuth` 走 NAS token）、哪些是中立字段。
2. **反向通道回调表**：`NativePlayerBridge.bindReentry` 的全部回调签名、每个回调
   遗留族/公共族各自的实现来源、可缺省行为（缺省时壳侧如何回退）。
3. **弹幕预取输入**：`NativeDanmakuPrefetch.resolveToFile` 的入参约定
   （seriesTitle/seasonNumber/episodeNumber/tmdbId + item/media/season guid），声明这些
   入参对所有后端都从 loadArgs 取，本身已中立。

新后端接入原生壳 = 让自己的桥接器产出符合契约的 `MpvMediaSource`，其余免费获得。

### 4.8 `getHomeSummary` 类型化（低优先级，可最后做）

定义 `MediaHomeSummary`（电影数 / 剧集数 / 其他数…字段按 `media_list_screen` 实际消费面
反推，先 grep 消费点再定字段，不要照抄飞牛响应），两个后端实现改返回类型化模型。

---

## 5. 分阶段执行计划

每阶段一个独立 commit（或小 commit 组），阶段间无交叉依赖的可并行，但推荐按序执行。

### 阶段 0：契约文档（纯文档，零代码风险）

- [ ] 写 `docs/native-shell-contract.md`（见 4.7；从 `MpvMediaSource.toMap()`、
      `NativePlayerBridge.bindReentry`、`NativePlayerActivity` 的 loadArgs 消费处反推）。
- [ ] 在 `lib/media_backend/media_backend.dart` 顶部补三档方法分类表（见 4.5）。

**验收**：文档评审通过；`flutter analyze` 无新增告警。

### 阶段 1：命名与分支收敛（机械重构，行为零变化）

- [ ] `MediaBackendCapabilities` 加 `usesLegacyFeiniuFlow` getter；
      `MediaBackendKind` 加 `isServerFamily` 扩展。
- [ ] 全库替换：`kind == MediaBackendKind.feiniu` → `capabilities.usesLegacyFeiniuFlow`
      （backend 可得处）；`kind == MediaBackendKind.emby`（会话层）→ `kind.isServerFamily`。
      逐处核对语义：**判断意图是"服务器族"的才换 isServerFamily**，真是 Emby 私有的
      （目前应当为零处，若发现则记录并单独评估）保留并加注释说明为何私有。
      重点清单：`main.dart:626`、`media_list_screen.dart:147,594`、
      `media_list_screen_widgets.dart:86`、`media_backend_provider.dart:36`、
      `connection_screen.dart`（阶段 3 一并处理，此阶段跳过）。
- [ ] 改名搬家（见 4.4 表格）：`EmbyNativePickerSupport` → `ServerNativePickerSupport`、
      `EmbyPlaybackReporter` → `ServerPlaybackReporter`、`_resolveEmbyForNative` →
      `_resolveServerForNative`、`_embyNativeEpisodes` → `_serverNativeEpisodes`。
      同步改注释里的"Emby xxx"表述为"服务器族后端 xxx（Emby/Jellyfin…）"。
- [ ] 两个 playback source bridge 文件移入各自后端目录。
- [ ] `MediaBackendCapabilities` 加 `.server()` preset + `supportsServerTranscodeSession`
      能力位；`NativePlaybackReentry.bind` 的公共族分支按该能力位决定是否绑
      `onReloadServerSession`。

**验收**：`flutter analyze` + `flutter test` 全绿；`grep -rn "isEmby\|== MediaBackendKind.emby" lib/`
仅剩连接/登录相关文件（阶段 3 处理）与 `MediaBackendKind` 定义本身；实机冒烟：飞牛与 Emby
各起播一次（单集 + 剧集切集 + 进度回写）确认零行为变化。

### 阶段 2：播放桥接自注册

- [ ] 新建 `lib/media_backend/playback/media_playback_source_bridge.dart` 中立接口（见 4.3）。
- [ ] 两个 bridge 实现接口；`MediaBackend` 加 `playbackSourceBridge` getter（abstract，必须档）。
- [ ] `item_playback_launcher.dart::_resolve`、`tv_season_playback_launcher.dart` 分发处
      改为 `backend.playbackSourceBridge.assemble(…)`，删除 context 类型判断。
      飞牛 `PlayInfoData` sidecar：桥接返回值改为
      `({MpvMediaSource source, Object? legacySidecar})` 形状，遗留族调用点 downcast
      `PlayInfoData`，公共族恒 null——sidecar 语义在接口注释写明"仅遗留族使用，新后端禁用"。
- [ ] launcher 顶部对 `FeiniuPlaybackContext` / `EmbyPlaybackContext` /
      `feiniu_media_backend.dart` 的 import 应随之消失（`item_playback_launcher.dart:298`
      处直接 `FeiniuMediaBackend(FeiniuApi(nas))` 的原生壳画质切换反向通道属遗留族专线，保留）。

**验收**：analyze/test 全绿；launcher 文件中 `grep "is FeiniuPlaybackContext\|is EmbyPlaybackContext"`
为零；实机冒烟同阶段 1。

### 阶段 3：登录 / 会话注册表化

- [x] 新建 `MediaBackendDescriptor` + `MediaBackendRegistry`（见 4.2），先只登记 Emby 一条。
- [x] `MediaBackendProvider` 改为查注册表构造（飞牛遗留族旁路保持现状）。
- [x] `connection_screen.dart` 重构：服务器族表单收敛为一套 `_ServerLoginFormState`（按注册表
      按 kind 各持一份），label/hint 由描述符（displayName / serverUrlExample）+参数化 l10n
      （`connectionServerAddress*`）提供；后端切换 tab 由"飞牛 + 注册表列表"生成，滑动高亮 /
      表单滑切方向按选项下标计算。**UI 布局与动效不变**。
- [x] `login_history_screen.dart`：角标/名称/配色从描述符取。
- [x] `login_history_store.dart` / `media_backend_connection_store.dart`：确认反序列化对未知
      kind 的容错（老版本降级默认飞牛的现状保留；新增 kind 值不破坏旧数据）。单测已用
      确实不存在的 kind（`plex`）钉住"未知条目被忽略"语义。

**验收**：analyze/test 全绿；连接页三条路径实测：飞牛登录、Emby 直连登录、Emby fnos 中转
（entry-token）登录均正常；登录历史正确显示与回填。

### 阶段 4：MediaBrowser 家族客户端抽取

- [x] **以更小改动面达成同等效果**：未做文件搬家，改为把 `EmbyApi` 就地声明为 MediaBrowser
      家族内核，鉴权头构造抽成 `@protected` 可覆写缝隙（`authorizationHeaderValue` /
      `sessionAuthorizationHeaderValue`），Emby 请求行为零变化（有单测钉住不带引号的历史头）。
      `JellyfinApi extends EmbyApi` 只覆写鉴权头风味。若未来差异扩大再升级为目录级抽取。
- [x] `EmbyMediaBackend` 即家族共享实现：`JellyfinMediaBackend extends EmbyMediaBackend`，
      只覆写 `capabilities`（kind）。BIF 端点 Jellyfin 404 → 原生壳回退章节图，无需覆写。

**验收**：analyze/test 全绿；Emby 实机全功能冒烟（登录/首页/列表筛选/详情/收藏/播放/切集/
进度回写/外挂字幕/seek 缩略图）。

### 阶段 5：Jellyfin 试点接入（对前四阶段的真实验证）

- [x] `MediaBackendKind` 加 `jellyfin`；grep 确认 `jellyfin` 字面量只出现在 api / jellyfin
      目录 / 注册表 / 枚举，页面层零分支。
- [x] `lib/api/jellyfin_api.dart`：`JellyfinApi extends EmbyApi`（家族内核），仅覆写认证
      鉴权头为带引号规范形状（头名沿用 `X-Emby-Authorization` 兼容名）；items / 直链 /
      进度 / 收藏已看 / 外挂字幕端点与 Emby 同形直用。BIF 缩略图 Jellyfin 404 → 原生壳
      自动回退章节图（章节图走通用 `/Items/{id}/Images/Chapter/{index}` 路由）。
- [x] `lib/media_backend/jellyfin/jellyfin_media_backend.dart`：继承 `EmbyMediaBackend`，
      只覆写 capabilities；播放桥接器复用 Emby 直链桥接（同形）。
- [x] 注册表登记 Jellyfin 描述符（badge 'JF'、logo、示例地址、API 工厂、后端工厂）；
      连接页第三 tab 由注册表自动生成并启用（含 fnos 中转 entry-token 流程复用）。
- [x] 契约单测：`test/api/jellyfin_api_test.dart`（鉴权头两家形状、会话头同形、描述符与
      后端工厂、isServerFamily）。
- [ ] **实机验收（待做）**：Jellyfin 实机走通登录 → 首页 → 列表 → 详情 → 原生壳播放 →
      切集 → 进度回写 → 收藏/已看。

**验收（即本方案总验收）**：Jellyfin 实机走通：登录 → 首页 → 列表 → 详情 → 原生壳播放 →
切集 → 进度回写 → 收藏/已看。并复核改动面：`git diff --stat` 确认 `lib/pages/`、
`lib/screens/`（除连接页注册表登记外）、`lib/controllers/*launcher*`、`android/` 零改动。
若出现不得不改这些目录的情况，说明前四阶段有漏收口——**回头补抽象，不许在页面里加
`if (jellyfin)`**。

### 阶段 6（可选，独立排期）：`getHomeSummary` 类型化

见 4.8。与前五阶段无依赖，任何时候可做。

---

## 6. 风险与红线

1. **飞牛主路径零回归是硬约束**。飞牛是遗留族，所有重构对它必须逐像素等价；阶段 1/2 的
   实机冒烟不能省。
2. **不要为遗留族做抽象**。飞牛专属逻辑（下载 / FN Connect / PlayInfo / 自有收藏页）
   保持原样直连，抽象只服务公共族。把飞牛也塞进新抽象是本方案明确反对的过度工程。
3. **不要预先为 Jellyfin 猜差异**。阶段 4 只上提"确定同形"的代码；差异在阶段 5 接触真实
   Jellyfin 服务器时按实际情况下沉。
4. **复用现成页面 UI，数据层分流**。任何后端差异都不允许催生"平行简陋页面"。
5. **文案全走 l10n**。改名/新增过程中出现的任何用户可见文案进 arb；品牌名（Emby/Jellyfin）
   例外，不翻译。
6. 弹幕匹配依赖 `seriesTitle/seasonNumber/episodeNumber/tmdbId`——Jellyfin 桥接器必须把
   这些填进 `MpvMediaSource`，否则原生壳弹幕静默失效（契约文档里要加粗标注）。
