# 已下载视频播放时选集网络封面修复设计

## 背景与根因

从下载列表播放已下载剧集时，选集面板同时包含本地已下载集和 NAS 返回的未下载集。已下载集优先使用 `file://` 本地封面，未下载集使用飞牛 NAS 网络图片。

当前 Flutter 选集映射只给原生壳传递 `imageAuth`。原生 Glide 因而只能补充 `Authorization` 和 `Trim-MC-token`，无法携带 FN Connect 中转地址所需的 `Cookie: mode=relay`。整季列表接口能够成功返回，但未下载集的图片请求被中转层拒绝，最终显示为黑色背景。本地封面不经过网络，因此可以正常显示。

## 目标与边界

- 在线连接 NAS 时，从已下载视频进入播放器，未下载集也能显示网络封面。
- 已下载集继续优先显示本地封面，断网时不回退网络请求。
- 图片鉴权规则继续由 Flutter 飞牛传输层生成，Android 原生壳不重复判断 FN Connect 域名。
- 保留 `imageAuth` 读取兼容，避免旧 payload 或其它尚未迁移入口失效。
- 本修复不改变完全断网时未缓存网络封面不可用的事实，也不新增整季封面预下载。

## 数据流设计

Flutter 在组装每集原生 payload 时先确定最终 `poster`：

1. 存在有效本地封面时，使用本地 `file://` URL，`imageHeaders` 为空。
2. 否则使用 NAS 图片 URL，并通过现有飞牛图片头策略生成完整 `imageHeaders`。FN Connect URL 将包含 `Authorization`、`Trim-MC-token` 和 `Cookie: mode=relay`；普通直连 NAS 不会额外带 relay Cookie。

`item_playback_launcher.dart` 的初始整季列表和 `native_reentry_support.dart` 的刷新、切季列表必须使用同一规则。payload 暂时同时保留：

- `imageHeaders`：新的完整请求头映射，作为权威来源。
- `imageAuth`：旧 token 字段，仅用于兼容旧原生壳或旧 payload。

Android 原生壳把图片地址与请求头组装集中到可测试的辅助函数中。读取 `imageHeaders` 时只接受字符串键和值；若映射为空，再从 `imageAuth` 构造旧的两个 token 请求头。选集缩略图、听视频封面以及其它消费同一集封面的 Glide 入口共用该模型，避免入口行为漂移。

## 安全与错误处理

- Flutter 只为飞牛 NAS 同源图片生成 NAS 鉴权头；本地文件和第三方图片不附加 NAS 凭据。
- Android 不记录请求头内容，也不把请求头拼进 URL。
- 图片加载失败继续保留现有深色占位背景，不影响播放和切集。
- Kotlin 解析异常或非字符串头值时忽略无效项，并回退旧 `imageAuth`。

## 测试与验收

先添加失败测试，再实施最小修复：

- Dart 测试：FN Connect 未下载集 payload 带 `Cookie: mode=relay`，普通直连不带；本地封面头映射为空。
- Kotlin 测试：优先消费 `imageHeaders`，并验证缺失时兼容 `imageAuth`；无效头值不会进入 Glide 模型。
- 运行相关 Flutter 测试、Android JVM 单测和涉及文件的静态分析。
- 真机验收：从下载列表播放一集，打开卡片式选集；本地已下载集显示本地封面，未下载集在联网时显示 NAS 封面，播放和切集行为不变。
