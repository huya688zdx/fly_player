# TASK B —— 服务层与工具层评审

> 先完整阅读 `docs/codex-review/00-review-constraints.md`（约束标准 + 工作协议），再开工。
> findings 写入 `docs/codex-review/findings/B.md`，编号前缀 `B-`。

## 范围（约 1.7 万行）

1. `lib/services/` 全部文件，**除以下桥接文件归 TASK C**：
   - `gpu_profile_bridge.dart`、`main_host_bridge.dart`、`native_player_bridge.dart`、`parallel_host_bridge.dart`、`parallel_window_settings_bridge.dart`、`player_host_bridge.dart`、`player_system_session_bridge.dart`、`runtime_theme_session_bridge.dart`、`runtime_theme_sync_bridge.dart`、`session_exit_bridge.dart`、`embedded_detail_launcher.dart`、`detail_route_payload_store.dart`
   - `storage_access_service.dart`、`storage_management_service.dart`、`download_task_service.dart` 三个文件**你要审业务逻辑**，其中 MethodChannel 通道契约部分只记位置（归 TASK C）。
2. `lib/services/play_stats/`（SQLite 持久化）
3. `lib/utils/`（24 个文件）

## 本区域重点检查项

1. **[C6] 单一职责**：services 里有没有"上帝服务"（一个类干网络+缓存+持久化+格式化）；`download_task_service.dart` 是重点对象。
2. **`mpv_proxy_server.dart`（本地 HTTP 代理）**——播放链路上的性能关键件，报 P1 优先：
   - 转发是否流式（有没有把响应体整段读进内存）；
   - socket / 连接的关闭与异常路径；并发请求处理；
   - 主 isolate 上有没有阻塞操作。
3. **play_stats（SQLite）**：事务使用、批量写入是否逐条 await（性能）、数据库升级迁移路径、连接是否泄漏。
4. **持久化一致性**：SharedPreferences key 是否收敛定义（[M6]）；读写是否有 schema 版本概念。
5. **缓存策略**：各 service 内存缓存有没有上限/失效机制（无限增长 = 泄漏，[P6]）。
6. **[C1] 逆向依赖**：services import 了 widgets/pages 的一律上报。
7. **utils/**：死代码重灾区（[M5]）；和 Flutter SDK / 现成包重复造轮子的；被单一调用方使用却放在全局 utils 的（应内聚回调用方）。
8. 通用项全查：[M3] i18n、[M4] 错误处理、[P5] 昂贵同步操作、[P7] async gap。

## 完成标准

第一轮逐文件 + 第二轮自复核（见 00 文档第 7 节协议），最后更新 PROGRESS.md 中 TASK B 状态为 DONE。
