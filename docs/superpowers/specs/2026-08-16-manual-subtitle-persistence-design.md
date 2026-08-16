# 手动外挂字幕持久化与回归设计

## 目标

补齐原生播放器手动导入外挂字幕后的完整生命周期：详情页立即显示导入结果；切集、切画质和重新进入播放器时恢复该集的字幕文件与上次选择；从原生播放器或详情页删除时同时清理文件、元数据和选择状态；使用 SRT、SUP、PGS 回归测试锁住这些流程。

本期只覆盖 Android 原生播放壳现有的 SAF 手动导入链路，不扩展远程字幕下载协议，也不重构服务端字幕模型。

## 已确认的问题

1. Kotlin 将 `flutter.manual_local_subtitles_v1` 写成 JSON 数组，Dart 按 `{entries: [...]}` 对象读取，导致详情页无法读取原生导入结果。
2. 详情页打开字幕面板时只异步触发刷新，却立即用旧缓存构建面板，首次打开仍可能缺少刚导入的字幕。
3. 原生壳把持久化字幕注入 `loadArgsMap` 后，初始化参数和 `playerSurface.load()` 仍使用注入前的 `loadArgs`，恢复结果没有真正进入播放内核。
4. 当前元数据只记录字幕条目，没有记录每集最后选择的手动字幕，无法在重进时自动选中。
5. 原生导入在文件复制完成后读取当前 `loadArgsMap`；若异步期间换集，条目可能归到错误媒体。
6. 删除链路先删元数据、后尝试删文件，文件删除失败时可能留下不可见的孤儿文件。
7. SUP/PGS 提交已包含扩展名白名单与 FFmpeg 的 `sup`/`hdmv_pgs_subtitle` 能力，但现有测试没有覆盖持久化恢复和清理流程。

## 方案选择

采用“原生与 Flutter 共享同一份版本化 SharedPreferences 数据”的方案。它保留现有 `FlutterSharedPreferences` 和 `flutter.manual_local_subtitles_v1` 键，不增加播放器运行时对 Flutter 的依赖，原生壳可在切集和重新进入时独立恢复。

未采用的方案：

- 原生独占存储、Flutter 经 MethodChannel 查询：边界更明确，但需要新增查询、删除、订阅协议，详情页生命周期更复杂。
- Flutter 独占存储、每次播放把字幕注入 `MpvMediaSource`：实现较简单，但原生壳切集时依赖 Flutter 回调及时提供状态，削弱原生播放宿主的自治性。

## 持久化模型

存储值统一为 JSON 对象：

```json
{
  "version": 2,
  "entries": [
    {
      "guid": "local:sub:<uuid>",
      "mediaGuid": "media-1",
      "itemGuid": "episode-1",
      "fileName": "episode.zh.sup",
      "path": "/private/subtitles/<uuid>.sup",
      "format": "sup",
      "importedAtMs": 1786800000000
    }
  ],
  "selectedByScope": {
    "item:episode-1": "local:sub:<uuid>"
  }
}
```

作用域优先使用稳定的 `itemGuid`，缺失时回退到 `mediaGuid`。读取时兼容当前 Kotlin 已写出的旧 JSON 数组，并在下次成功写入时升级为对象格式。未知字段保留，避免 Dart 与 Kotlin 任一端写入时抹掉另一端将来增加的字段。

## 导入与详情页刷新

导入开始时捕获 `itemGuid`、`mediaGuid`，文件复制完成后仍用捕获值归档。复制成功后写入条目并将该 guid 设为对应作用域的当前手动字幕；持久化失败则删除刚复制的文件，不向播放器或详情页报告成功。

只有播放器仍处于同一条目时，导入结果才注入当前 `loadArgsMap` 并立即选择；若期间已经切集，只持久化到原条目并通知 Flutter，不把字幕应用到新一集。

原生壳通过 `localSubtitleImported`/`localSubtitleRemoved` 回调通知详情页。详情页收到通知、恢复前台及打开字幕面板前都会重新读取存储；打开面板必须等待读取完成后再构建轨道列表。Dart 自身删除产生的 revision 继续用于本地刷新。

## 切集与重新进入恢复

所有进入播放内核的参数先经过同一个恢复函数：

1. 按 `itemGuid` 查找字幕；没有按条目匹配时再按 `mediaGuid` 回退。
2. 仅注入路径存在、guid 未重复的条目。
3. 为 SRT 等文本字幕设置外挂属性；SUP/PGS 同样作为本地外挂文件注入，同时保留 `isBitmap=1`。
4. 若 `selectedByScope` 指向本集仍存在的字幕，则覆盖 `subtitleTrackGuid`，清空内嵌字幕序号并设置外挂偏好。
5. 将恢复后的同一份参数用于 `NativePlayerSurface` 创建、`loadArgsMap`、当前选择初始化和 `playerSurface.load()`。

用户在播放器中选择手动字幕时更新 `selectedByScope`；选择内嵌字幕或关闭字幕时清除该作用域的手动选择。这样“上次使用”表达当前选择，而不是永久强制某个历史导入字幕。

## 删除语义

原生播放器和详情页遵循同一顺序：

1. 定位 guid 对应条目。
2. 文件不存在视为已清理；文件存在时先删除文件。
3. 文件删除成功后移除条目，并清除所有指向该 guid 的 `selectedByScope` 项。
4. 从当前 `loadArgsMap` 移除轨道与路径；若删除的是当前字幕，则关闭字幕。
5. 刷新面板并通知另一端。

文件删除失败时保留元数据并返回失败，避免界面声称删除成功却留下孤儿文件。若文件已被系统或外部原因移除，恢复时跳过它，删除操作仍可清掉残留元数据。

## SUP/PGS 复核

保留当前 FFmpeg 裁剪产物，不重新构建二进制。当前 `libavformat.so` 可见 PGS/SUP demuxer 相关符号，`libavcodec.so` 可见 `hdmv_pgs_subtitle`/`pgssub` 解码相关符号；本地 `local:sub:` 轨道优先走 `sub-add` 外挂路径，避免被“服务端位图字幕按内嵌轨处理”的规则误判。

同时修正两点：

- 格式支持提示补回白名单中已有的 TTML，保证提示与实现一致。
- 用测试区分服务端 PGS/SUP（按内嵌轨处理）和本地导入 PGS/SUP（按外挂文件处理）。

## 测试策略

### Kotlin 原生单元测试

- 读取旧数组并写回版本化对象，验证与 Dart 结构一致。
- SRT 导入快照按条目恢复为外挂轨，并自动恢复最后选择。
- SUP 与 PGS 恢复为 `isBitmap=1` 的本地外挂轨，且文件路径进入 `localSubtitleFiles`。
- 切到另一集不注入上一集字幕；同集切画质仍按 `itemGuid` 恢复。
- 恢复结果中的选择字段确实存在于最终交给播放内核的参数。
- 删除 SRT、SUP/PGS 临时文件后同步移除条目和选择；文件删除失败时不移除元数据。

### Flutter 单元与组件边界测试

- Dart 能读取 Kotlin 旧数组和新版对象，并按 `itemGuid` 优先、`mediaGuid` 回退查询。
- 原生导入回调被桥接到刷新回调。
- 面板轨道合并包含 SRT、SUP/PGS，位图标志正确且 guid 稳定。
- 详情页删除服务先删文件、再删元数据，并触发 revision。
- 删除后重新加载不再返回条目，选择映射不残留。

### 验证范围

运行新增 Flutter 测试、相关本地字幕测试、独立 Kotlin 字幕存储测试、Flutter 静态分析和 Android 编译。现有 `NativePlayerActivityPanelModelsTest` 在本地 JVM 环境有资源文案相关的既有 NPE，新增持久化测试放在不依赖 Android 资源的独立测试类中，避免把已知基线故障误归因于本功能。

## 成功标准

- 导入 SRT、SUP 或 PGS 后，返回详情页并首次打开字幕面板即可看到该轨道。
- 同一集切画质或重新进入播放器时，字幕文件仍在列表中，并自动选中最后使用的手动字幕。
- 切到其他集不会串入上一集字幕；切回原集可恢复。
- 从任一入口删除后，文件、元数据、选择映射和界面轨道均被清理。
- 新增回归测试通过，相关现有测试无新增失败，Android Kotlin 编译成功。
