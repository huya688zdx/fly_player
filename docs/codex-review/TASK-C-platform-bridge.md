# TASK C —— Flutter ↔ Android 平台桥接层评审（含通道契约核对）

> 先完整阅读 `docs/codex-review/00-review-constraints.md`（约束标准 + 工作协议），再开工。
> findings 写入 `docs/codex-review/findings/C.md`，编号前缀 `C-`。

## 范围

这是唯一允许**阅读** Kotlin 代码的任务，但只为核对通道契约，**不评审 Kotlin 内部实现质量**（原生层暂不在评审范围）。

### Dart 侧（逐文件全审）

1. `lib/services/` 下全部桥接文件：
   `gpu_profile_bridge.dart`、`main_host_bridge.dart`、`native_player_bridge.dart`、`parallel_host_bridge.dart`、`parallel_window_settings_bridge.dart`、`player_host_bridge.dart`、`player_system_session_bridge.dart`、`runtime_theme_session_bridge.dart`、`runtime_theme_sync_bridge.dart`、`session_exit_bridge.dart`、`embedded_detail_launcher.dart`、`detail_route_payload_store.dart`
2. `lib/player/services/native_player_bridge.dart`、`lib/player/services/native_panel_bridge.dart`
3. 以下文件中**与通道相关的代码段**（其余部分归各自任务）：
   `lib/services/storage_access_service.dart`、`lib/services/storage_management_service.dart`、`lib/services/download_task_service.dart`、`lib/providers/nas_provider.dart`、`lib/screens/detail_host_screen.dart`、`lib/screens/player_host_screen.dart`、`lib/screens/screenshot_preview_screen.dart`、`lib/theme/dynamic_theme_seed_extractor.dart`、`lib/player/controllers/mpv_player_controller.dart`、`lib/player/mpv_player_page.dart`、`lib/player/widgets/player_system_controls.dart`、`lib/danmaku/api/dandanplay_config.dart`

### Kotlin 侧（只读对照，不评审）

`android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/` 下注册 MethodChannel/EventChannel 的位置（grep `MethodChannel(` / `setMethodCallHandler`）。

## 本区域重点检查项

1. **通道契约一致性（本任务核心，双向核对）**：
   - Dart 侧 invoke 的每个方法名，Kotlin 侧是否真有 handler；Kotlin 侧主动 invoke 的回调，Dart 侧是否注册了 handler；
   - 参数名/类型两侧是否一致（Map key 拼错、int/long/bool 不匹配）；
   - 单侧存在的孤儿方法 = 死契约，上报 [M5]。
2. **疑似重复桥**：`lib/services/native_player_bridge.dart` 与 `lib/player/services/native_player_bridge.dart` 同名并存——查清两者关系（重复实现？新旧版本？），若为平行重复报 P1 [M2]。
3. **[C5] 通道收敛**：通道名/方法名裸字符串散落情况；页面/widget 内直接建通道的违规点。
4. **错误路径**：每个 `invokeMethod` 的 `PlatformException` / `MissingPluginException` 处理；原生侧未 attach 时（引擎未就绪、Activity 已销毁）调用会怎样。
5. **生命周期**：handler 注册后是否有对应卸载；多引擎场景（ParallelFlutterEngineRegistry 双 Flutter 引擎）下通道会不会串（两个引擎注册同名通道、消息投错引擎）。
6. **数据编解码**：大对象（截图字节、列表）过通道的方式——有没有在主线程做大体积序列化（[P5]）；应传路径/句柄却传了整个字节数组的。
7. **[P7] async gap**：桥回调里用 context/setState 未查 mounted。
8. 每个桥接文件产出一张**契约小结表**（方法名 | 方向 | Kotlin 对应点 | 状态 OK/孤儿/不一致）附在 findings 里，方便后续修复。

## 完成标准

第一轮逐文件（含契约表）+ 第二轮自复核（见 00 文档第 7 节协议），最后更新 PROGRESS.md 中 TASK C 状态为 DONE。
