# 公共媒体前端抽象设计

## 目标

先不接入 Emby，先把当前深度绑定飞牛 API 的前端整理成可接入多媒体后端的公共前端。第一阶段必须保证现有飞牛体验不退化，同时为后续 Emby 适配留下清晰接口。

## 背景判断

当前页面大量直接调用 `FeiniuApi(context.read<NasProvider>())`，并直接消费飞牛字段：

- 首页和分类页依赖 `MediaItem`、`MediaLibraryItem`。
- 详情页依赖 `getItemDetail()` 返回的原始 `Map<String, dynamic>`。
- 播放入口依赖 `PlayInfoData`、`PlaybackStreamData`、`StreamTrackData`。
- 图片、下载、FN Connect、播放进度、片头片尾配置仍是飞牛专属能力。

所以不能把 Emby 分支散落进 UI。正确方向是建立 App 内部公共契约，让飞牛先作为第一个适配器接入。

## 架构

新增一层 `MediaBackend`：

```text
页面 / 播放入口
  -> MediaBackend
    -> FeiniuMediaBackend
      -> FeiniuApi
    -> 未来 EmbyMediaBackend
      -> EmbyApi
```

第一阶段只实现 `FeiniuMediaBackend`，不实现 Emby。页面迁移到公共接口后，飞牛表现必须保持一致。

## 公共模型边界

公共模型只表达前端真正需要的信息，不照搬飞牛或 Emby 字段。

- `MediaBackendKind`：`feiniu`、未来 `emby`。
- `MediaBackendSession`：当前后端类型、服务器地址、用户、token。
- `MediaCatalog`：首页媒体库入口，例如电影库、剧集库、目录库。
- `MediaItemSummary`：卡片/列表需要的最小条目信息。
- `MediaDetail`：详情页需要的统一信息。
- `MediaSeasonSummary`：剧集详情页季列表。
- `MediaEpisodeSummary`：选集列表和剧集卡片。
- `MediaPlaybackBundle`：播放入口需要的播放信息、轨道、清晰度、初始进度。
- `MediaImageRef`：图片 URL 与鉴权 header 的统一描述。
- `MediaBackendCapabilities`：声明后端支持哪些特性，比如下载、收藏、远程访问、片头片尾配置。

## 第一阶段范围

第一阶段只做“公共化飞牛”，不做 Emby API。

包含：

- 新增公共模型和接口。
- 新增 `FeiniuMediaBackend`，内部调用现有 `FeiniuApi`。
- 首页从直接调用 `FeiniuApi` 改为调用 `MediaBackend`。
- 增加 mapper 单测，保证飞牛字段到公共模型的转换稳定。
- 增加共享进度看板，方便 Codex 和 Claude 分工。

不包含：

- 不接 Emby API。
- 不重做播放器内部所有 FeiniuApi 调用。
- 不改下载任务逻辑。
- 不迁移 FN Connect。
- 不改变 UI 风格。

## 迁移顺序

1. 首页数据链路。
2. 分类页和搜索页。
3. 详情入口和电影详情。
4. 剧集详情和季/集列表。
5. 播放入口。
6. 播放器内部刷新、选集、字幕、音轨。
7. 后端能力声明和飞牛专属入口收口。

## 协作原则

- Codex 负责接口边界、第一刀样板、集成审查、最终提交。
- Claude 适合负责 mapper、调用点清单、字段映射表、页面迁移草案。
- 双方不要同时编辑同一个文件。
- 每个阶段完成后更新 `docs/superpowers/public-media-frontend-status.md`。
- 任何任务完成必须有测试命令或人工验证说明。

## 风险控制

- 第一阶段不改变数据来源，只改变调用边界。
- 公共模型必须小而稳定，避免把飞牛私有字段搬进去。
- 飞牛专属功能先通过 capabilities 暴露，不强塞进公共模型。
- 迁移播放器前必须先迁移详情和播放入口，否则播放器上下文会断裂。

