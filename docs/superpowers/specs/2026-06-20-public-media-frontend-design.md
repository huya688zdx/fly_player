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

本项目后续采用 “Claude 主实现，Codex 审查收口” 的协作方式。

- Claude 负责主实现：公共模型、`MediaBackend` 接口、`FeiniuMediaBackend`、Provider、页面迁移框架和主要业务代码。
- Codex 负责审查和补小逻辑：架构漏洞排查、测试缺口、小范围修复、边界条件、`flutter analyze`、最终验证和提交检查。
- Claude 可以完成计划中的完整 Task，但每个 Task 完成后必须更新状态看板，写明测试命令和提交 hash。
- Codex 优先审查 Claude 已完成的 Task，不抢主实现文件；只有发现明确问题时才做小范围修复。
- 双方不要同时编辑同一个文件；如果必须编辑同一文件，先在状态看板标记当前负责人和原因。
- 每个阶段完成后更新 `docs/superpowers/public-media-frontend-status.md`。
- 任何任务完成必须有测试命令或人工验证说明。
- 每完成一个小任务，只要对应测试通过，就必须立刻单独提交；不要把多个小任务攒到同一个 commit。
- 提交前只暂存当前小任务相关文件，不能夹带工作区里的其它改动。
- 如果测试没通过，不允许提交成功状态；应先修复，或者在状态看板标记阻塞和失败命令。

## Claude 上下文管理

Claude Code 不会自动压缩上下文。Claude 在以下情况必须停止继续执行，并提示用户压缩上下文：

- 完成一个完整 Task 后，上下文明显偏长。
- 已经进行了大范围扫描并输出过大量结果。
- 即将进入另一个阶段或另一个文件群。
- 对当前状态的记忆开始依赖长上下文而不是文档和 commit。

提示格式：

```text
建议现在压缩上下文。以下是可用于压缩后的继续摘要：
1. 当前目标：
2. 已阅读文档：
3. 已完成任务：
4. 修改过的文件：
5. 提交状态：
6. 测试结果：
7. 下一步：
8. 明确不要做：
```

## 风险控制

- 第一阶段不改变数据来源，只改变调用边界。
- 公共模型必须小而稳定，避免把飞牛私有字段搬进去。
- 飞牛专属功能先通过 capabilities 暴露，不强塞进公共模型。
- 迁移播放器前必须先迁移详情和播放入口，否则播放器上下文会断裂。
