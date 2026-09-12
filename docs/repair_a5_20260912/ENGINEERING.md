# 导航、测试与资源工程批次

基线 a5acbc3；仅修改独立 repair-a5-handoff-20260912 工作树。日志及最终矩阵位于仓外 `repair_a5acbc3_20260912`，不包含真实账号、媒体或数据库。本文不把构建、widget 或方法夹具写成真实播放验收。

## A5-UI-01

宿主改为通过 NavigatorObserver 记录真实 Route 实例的 push/pop/remove/replace。页面自行 push 的弹幕设置也进入同一记录；同名路由不再按名称移错条目。保留宿主同目标防抖、同路径替换、页内返回/关闭以及设置子页 await 返回后重读偏好。首层转场仍由 Shell 控制，build 阶段的记录更新延至帧后通知。

`ui_navigation_red` 真实 ExternalPlayerSettingsScreen 正确断言先失败（显示弹幕却记外部设置）；修后宽窗分屏、窄窗整页、重开/返回/关闭及偏好重读通过。`root_regressions_final` 还验证直接 push 同名路由、移除下层、同名替换及既有宿主测试。属于 Flutter widget 验证，不是 Windows 实际分屏播放验证。

影响为导航目标和层级恢复一致，不修改播放内核。回退宿主及这两组测试的补丁即可，无持久化迁移。

## A5-E03

只改 `external_player_media_proxy_test.dart`：测试 HTTP 客户端明确 DIRECT；仅本测试的 HttpOverrides 将合成 loopback 上游直连，保留非 loopback 的环境代理查找。关闭断言完成 getUrl/close/drain，并额外验证直接 Socket 拒连、上游请求数和惰性解析次数不增加。Range、HEAD、鉴权与跨源跳转断言保留。

基线全套唯一失败为旧 getUrl 断言。`proxy_without_env`、`proxy_with_env_fixture_v2` 和最终完整套件分别记录结果。强制拒绝代理时 Flutter 自身 WebSocket 控制连接也会使用代理，因此仓外验证器仅转发该 loopback WebSocket；所有媒体 HTTP 仍被拒绝代理拦截检测，最终媒体请求计数为0。初次控制连接受阻、一次 HttpOverrides getter 编译错误均保留原日志，不计产品 RED。

产品全局代理行为无变更；回退测试文件即可。

## A5-DESIGN-01

设计原稿增加本集取消标记，隐藏卡片不再重置取消意图；openPlayer 新播放会话重置。`tool/test_desktop_auto_next_cancel.cjs` 执行从实际 app.js 提取的函数和按钮回调，验证取消、后续20个tick、暂停恢复、seek、新集倒计时与Timer清理。`design_cancel_red` 正确断言失败，`design_cancel_green` 通过。仅设计原稿，不算 Flutter/原生播放通过。回退 app.js 和探针即可。

## 旧 R02 / 旧 R03

生成器改为显式输入视频与输出目录，可指定图集目录。所有候选产物统一写入指定输出目录；help/输入存在与SHA检查不依赖cv2，不触碰正式loading动画。依赖、帧范围、输入/输出与旧真实素材回归使用方式见 `tool/REFRESH_BUILD.md`。CLI 3项通过；原片与cv2条件不具备，真实素材重新生成 BLOCKED。临时占位文件仅用于检查路径，不用来生成或冒充原始素材。

资源声明从整个 refresh 目录收窄到原有正式 `shoujo_bird_loading.webp` 与 `shoujo_bird_loading_static.png`，不删除27个原稿/中间素材。真实 Windows bundle 对比见仓外 `refresh_bundle_result.json` 与对应测试日志；正式两文件校验哈希不变。减量只代表未压缩bundle资源字节，不能推论APK、内存、FPS或解码提升。

回退时分别反向应用生成器/文档/CLI测试，或恢复原pubspec目录声明；不覆盖素材、不从旧快照替换源码。本批无数据迁移，尚未应用到主工程。
