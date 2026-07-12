# TASK G —— 设置页 / 工具页 / 登录连接页评审

> 先完整阅读 `docs/codex-review/00-review-constraints.md`（约束标准 + 工作协议），再开工。
> findings 写入 `docs/codex-review/findings/G.md`，编号前缀 `G-`。

## 范围（约 2 万行）

`lib/screens/` 下除 TASK F 已列的浏览类之外的全部文件，按块推进：

1. **设置类**：`app_settings_screen.dart`、`mpv_player_settings_screen.dart`（~3.2k 行）、`danmaku_settings_screen.dart`、`screenshot_settings_screen.dart`、`theme_settings_screen.dart`、`theme_custom_recipe_screen.dart`、`parallel_window_settings_screen.dart`、`settings_search_screen.dart`、`settings_destination_routes.dart`
2. **工具/管理类**：`download_list_screen.dart`（~2.4k）、`storage_management_screen.dart`（~2.9k）、`bookmark_manager_screen.dart`、`danmaku_manager_screen.dart`、`app_log_screen.dart`、`screenshot_preview_screen.dart`（~2.5k，通道部分归 TASK C）
3. **统计类**：`play_stats_report_screen.dart`、`play_stats_report/`、`play_stats_debug_page.dart`、`play_stats_debug/`
4. **登录/连接类**：`connection_screen.dart`、`login_history_screen.dart`、`fn_connect_web_login_page.dart`、`emby_fn_entry_login_page.dart`
5. **宿主/占位**：`player_host_screen.dart`（通道部分归 TASK C）、`parallel_placeholder_screen.dart`

## 本区域重点检查项

1. **[M2] 设置页模式重复**：各设置页的"分组 + 开关/滑条/选择器"骨架有没有各写一套；列出可统一的设置项组件模板。`mpv_player_settings_screen.dart` 3.2k 行是重点解剖对象（[M1] 给拆分切面）。
2. **登录/连接类的 [C3] 后端耦合**：登录入口是否写死单一后端；`emby_fn_entry_login_page` 与 `fn_connect_web_login_page` / `connection_screen` 之间的平行重复；WebView 登录的 cookie/token 提取逻辑健壮性。
3. **download_list / storage_management**：
   - 列表刷新驱动方式（轮询？每秒 setState 整页？——[P4] 重灾区嫌疑）；
   - 文件操作（删除/移动）的确认与错误路径；
   - 大目录扫描是否在主 isolate（[P5]）。
4. **play_stats_report**：图表渲染的数据量控制；报表聚合计算是否在 build 里（[P5]）。
5. **设置项与生效链路**：设置写入后如何通知运行中的组件（播放器、弹幕）——有没有"改了设置要重启才生效"却无提示的坑。
6. **screenshot_preview**：大图字节的内存持有与释放；编辑/保存路径。
7. 通用项全查：[M3] i18n、[M4]、[M5]、[P2]、[P3]、[P6]、[P7]。

## 完成标准

第一轮逐文件 + 第二轮自复核（见 00 文档第 7 节协议），最后更新 PROGRESS.md 中 TASK G 状态为 DONE。
