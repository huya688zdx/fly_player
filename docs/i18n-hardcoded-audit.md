# 未 i18n 化文案审计（lib/ Flutter 侧）

> 生成于 2026-10-11，扫描工具：`out/i18n-scan.mjs`（Dart 字符串字面量分词，保留插值原文，排除注释与 lib/l10n/）。
> 现状：l10n 体系已建成（`flutter_localizations` + 模板 `app_zh_CN.arb`，en/ja/zh/zh_CN 四语各 2468 键完全同步），
> 但仍有 **544 处**用户可见硬编码中文散落在 50 个文件中未走 ARB。安卓原生层已有集中 `strings.xml`（含文案规范），不在本清单范围。

## 总览

| 分类 | 处数 | 说明 |
|---|---|---|
| 需 i18n 的用户可见文案 | 544 | 本清单主体 |
| 语言码→中文名映射表 | 119 | `media_language_mapper.dart`，见特殊情形 A |
| mpv 设置选项描述 | 69 | `mpv_settings_store.dart`，见特殊情形 B |
| 服务器错误匹配关键词 | 47 | `login_error_resolver.dart`：**不需要 i18n**，中文串是匹配入参，输出已走 `strings.loginErrorXxx` |
| 弹幕/章节/季集解析正则 | ~20 | dandanplay_resolver、desktop_playback_chapters、external_player_playlist 等：**不需要 i18n** |
| 开发者消息（断言/Deprecated/logSwallowedError） | ~15 | route_transition_gate 及各页面 RouteGateAnchor 回退日志：**不需要 i18n** |
| 日志文案 | 9 | debugPrint 等：**不需要 i18n** |

## 特殊情形（需先做设计决策）

### A. 语言码→语言名映射表（`lib/utils/media_language_mapper.dart`，119 条）

轨道语言显示名（如 `afr`→南非荷兰语）目前只有中文表。en/ja 用户会看到中文语言名。
建议：改用 locale 感知方案——优先 intl 的语言显示名 API，或为 en/ja 增补平行表；zh 沿用现有表。工作量集中但机械。

### B. mpv 画质/音频设置选项（`lib/playback/settings/mpv_settings_store.dart`，69 条 + 英文 label）

`MpvSettingOption` 的 `description` 全部为硬编码中文，`label` 为硬编码英文（Off/Low/Default/Anime Clear…）。
建议：按选项 value 外置到 ARB（如 `mpvDebandOffDesc`），label 一并处理；store 退化为 value+图标枚举，展示文案走 l10n。

### C. 截图保存位置预设（`lib/playback/screenshots/screenshot_settings_store.dart`，4 条英文 label）

Pictures/DCIM/App pictures/Custom folder 为 ASCII 文案，CJK 扫描抓不到，但同样用户可见，建议与 B 一并外置。

### D. 无 context 场景的取词通道

StateError/FormatException 携带中文消息（约 60 条），部分经 catch 后透出（如 external_playback_screen 的 `_run` 通用 failure、`showExternalPlaybackNotice`），部分只进日志。
建议：会透出的改为经 `lookupAppLocalizations`（main.dart:366 已有先例）就地取词或抛错误码枚举；纯内部的保持现状并加注释。

## 实施约定

- 模板：`app_zh_CN.arb`，四语（zh_CN/en/ja/zh）同步增键，键名 snake_case 按模块前缀分组（沿用现有风格）。
- Widget 内：`AppLocalizations.of(context).xxx`（现有 96 个文件、568 处调用是现成范例）。
- 非 Widget 层：仿 `external_playback_host.dart:598` 在入口取一次 `l10n` 传递；无 context 的启动路径用 `lookupAppLocalizations`。
- 带插值的改用带占位符的 ARB 消息（`placeholders`），不要拼接翻译。
- 建议按下面模块分批落地，每批后跑 `flutter gen-l10n` + 对应页面冒烟。

## 媒体后端与 API（12 处）

### `lib/api/feiniu_api.dart`（1 处，建议键前缀 `api_feiniu_api`）

| 行 | 现文案 |
|---|---|
| 2408 | 字幕资源不属于当前飞牛播放会话 |

### `lib/media_backend/emby/emby_media_backend.dart`（6 处，建议键前缀 `media_backend_emby_emby_media_backend`）

| 行 | 现文案 |
|---|---|
| 104 | 直播 |
| 855 | Emby 条目 ${request.itemId} 无 MediaSources，无法播放 |
| 1023 | 直播频道 ${request.itemId} 无可用播放源 |
| 1031 | 直播频道 ${request.itemId} 找不到播放源 $requestedSourceId |
| 1043 | 直播频道 ${request.itemId} 缺少 OpenToken |
| 1057 | 直播频道 ${request.itemId} 的播放源缺少 Id |

### `lib/media_backend/feiniu/feiniu_media_backend.dart`（5 处，建议键前缀 `media_backend_feiniu_feiniu_media_backend`）

| 行 | 现文案 |
|---|---|
| 698 | 指定的直播线路不存在 |
| 700 | 指定的直播线路不可用 |
| 704 | 指定的直播线路不存在 |
| 707 | 指定的直播线路不可用 |
| 722 | 没有可用的直播线路 |

## 服务与控制器（22 处）

### `lib/controllers/item_playback_launcher.dart`（2 处，建议键前缀 `controllers_item_playback_launcher`）

| 行 | 现文案 |
|---|---|
| 39 | 当前平台暂不支持播放 |
| 483 | 媒体账号已切换，请重新播放。 |

### `lib/controllers/local_download_source_resolver.dart`（2 处，建议键前缀 `controllers_local_download_source_resolver`）

| 行 | 现文案 |
|---|---|
| 67 | 本地播放的在线元数据查询超时 |
| 187 | 媒体账号已切换，请重新播放。 |

### `lib/controllers/tv_season_playback_launcher.dart`（2 处，建议键前缀 `controllers_tv_season_playback_launcher`）

| 行 | 现文案 |
|---|---|
| 33 | 当前平台暂不支持播放 |
| 362 | 媒体账号已切换，请重新播放。 |

### `lib/providers/startup_preferences_provider.dart`（1 处，建议键前缀 `providers_startup_preferences_provider`）

| 行 | 现文案 |
|---|---|
| 54 | 启动目的地偏好保存失败 |

### `lib/services/download_task_service.dart`（10 处，建议键前缀 `services_download_task_service`）

| 行 | 现文案 |
|---|---|
| 57 | 下载接口返回了错误信息，而非媒体文件 |
| 67 | 服务器返回的续传范围不正确 |
| 71 | 下载响应状态不正确 |
| 792 | 请连接创建该下载任务的服务器和账号后继续 |
| 1243 | 下载任务进度响应为空 |
| 1255 | 服务端下载任务失败：${progress.status} |
| 1714 | 下载未完整接收，请继续下载 |
| 5467 | 随片弹幕未下载：弹弹play凭据未配置 |
| 5512 | 随片弹幕未下载：未匹配到可用弹幕 |
| 5602 | 随片弹幕已保存 |

### `lib/services/parallel_window_settings_bridge.dart`（1 处，建议键前缀 `services_parallel_window_settings_bridge`）

| 行 | 现文案 |
|---|---|
| 176 | 无法保存平行窗口设置 |

### `lib/services/play_stats/play_stats_database.dart`（2 处，建议键前缀 `services_play_stats_play_stats_database`）

| 行 | 现文案 |
|---|---|
| 131 | Fly 本机新记录 |
| 241 | 升级前历史（需要关联或确认未导入） |

### `lib/services/storage_access_host.dart`（1 处，建议键前缀 `services_storage_access_host`）

| 行 | 现文案 |
|---|---|
| 131 | 保存下载目录失败 |

### `lib/services/storage_management_service.dart`（1 处，建议键前缀 `services_storage_management_service`）

| 行 | 现文案 |
|---|---|
| 638 | 设置项重置失败: $key |

## 桌面框架（desktop）（9 处）

### `lib/desktop/desktop_detail_pane_host.dart`（2 处，建议键前缀 `desktop_desktop_detail_pane_host`）

| 行 | 现文案 |
|---|---|
| 276 | 选择内容查看详情 |
| 285 | 在浏览区点击海报或卡片，详情将在这里打开 |

### `lib/desktop/desktop_hover_scroll_arrows.dart`（2 处，建议键前缀 `desktop_desktop_hover_scroll_arrows`）

| 行 | 现文案 |
|---|---|
| 232 | 向左翻页 |
| 233 | 已到最左侧 |

### `lib/desktop/desktop_shell.dart`（1 处，建议键前缀 `desktop_desktop_shell`）

| 行 | 现文案 |
|---|---|
| 814 | 分屏详情宿主待接入（desktop-detail-pane） |

### `lib/desktop/desktop_side_bar.dart`（1 处，建议键前缀 `desktop_desktop_side_bar`）

| 行 | 现文案 |
|---|---|
| 131 | 外部播放 |

### `lib/desktop/desktop_window_frame.dart`（3 处，建议键前缀 `desktop_desktop_window_frame`）

| 行 | 现文案 |
|---|---|
| 100 | 最小化 |
| 105 | 还原 |
| 112 | 关闭 |

## 桌面播放器（desktop/playback）（428 处）

### `lib/desktop/playback/desktop_danmaku_overlay.dart`（1 处，建议键前缀 `desktop_playback_desktop_danmaku_overlay`）

| 行 | 现文案 |
|---|---|
| 105 | 弹弹play |

### `lib/desktop/playback/desktop_mpv_runtime.dart`（2 处，建议键前缀 `desktop_playback_desktop_mpv_runtime`）

| 行 | 现文案 |
|---|---|
| 204 | 直播线路 |
| 298 | 直播 |

### `lib/desktop/playback/desktop_playback_host.dart`（2 处，建议键前缀 `desktop_playback_desktop_playback_host`）

| 行 | 现文案 |
|---|---|
| 304 | 加载该季剧集失败，请重试 |
| 327 | 未找到所属剧集，请重试 |

### `lib/desktop/playback/desktop_playback_launch_guard.dart`（3 处，建议键前缀 `desktop_playback_desktop_playback_launch_guard`）

| 行 | 现文案 |
|---|---|
| 76 | 正在取消，等待清理… |
| 87 | 取消加载 |
| 126 | 所选影片 |

### `lib/desktop/playback/desktop_playback_screen.dart`（33 处，建议键前缀 `desktop_playback_desktop_playback_screen`）

| 行 | 现文案 |
|---|---|
| 582 | 已导入本地字幕 |
| 838 | 导入弹幕文件 |
| 859 | 弹幕文件无法识别 |
| 868 | 已导入 ${_danmakuComments.length} 条弹幕 |
| 907 | 弹幕源加载失败 |
| 916 | 已切换弹幕源 |
| 942 | 在线弹幕加载失败 |
| 952 | 已加载在线弹幕 |
| 967 | 已删除弹幕源 |
| 1840 | 直播已中断，请重试或切换线路 |
| 2805 | 样式 |
| 2811 | 导入 |
| 2827 | 调节 |
| 2999 | 暂无可用选项 |
| 3263 | 第$numberLabel集 |
| 3265 | 第$numberLabel集 · $title |
| 3653 | 再按一次 Esc 解锁 |
| 4070 | 弹幕设置 · 已开启 |
| 4071 | 弹幕设置 · 已关闭 |
| 4089 | 关闭 A-B 循环 |
| 4091 | 设置 B 点 |
| 4092 | 设置 A 点 |
| 4238 | 解锁（连按两次 Esc） |
| 4463 | 章节识别 |
| 4465 | 编号章节推测 |
| 4466 | 固定时长 |
| 4468 | 片头 · $basis |
| 4471 | 片尾 · $basis |
| 4507 | 跳到 ${_formatDuration(bounds.introEnd ?? Duration.zero)} |
| 4509 | 跳到 ${_formatDuration(bounds.outroEnd!)} |
| 4511 | 播放下一集 |
| 4512 | 跳到视频结束 |
| 4559 |  · ${remaining}s 后自动跳过 |

### `lib/desktop/playback/desktop_player_controls.dart`（2 处，建议键前缀 `desktop_playback_desktop_player_controls`）

| 行 | 现文案 |
|---|---|
| 425 | 音量 |
| 455 | 直播 |

### `lib/desktop/playback/desktop_player_hover_overlays.dart`（2 处，建议键前缀 `desktop_playback_desktop_player_hover_overlays`）

| 行 | 现文案 |
|---|---|
| 382 | 直播线路 |
| 383 | 暂无可用线路 |

### `lib/desktop/playback/desktop_player_panels.dart`（172 处，建议键前缀 `desktop_playback_desktop_player_panels`）

| 行 | 现文案 |
|---|---|
| 50 | 选择要输出的轨道 |
| 142 | 季列表加载失败，点击重试 |
| 168 | 剧集加载失败，点击重试 |
| 244 | 特别篇 |
| 245 | 第${season.seasonNumber}季 |
| 498 | 弹幕设置 |
| 506 | 滚动弹幕 |
| 507 | 从右向左滚动显示 |
| 514 | 顶部弹幕 |
| 515 | 固定在画面顶部显示 |
| 522 | 底部弹幕 |
| 523 | 固定在弹幕显示区域底部 |
| 530 | 保留弹幕颜色 |
| 531 | 关闭后统一使用白色 |
| 538 | 隐藏重复弹幕 |
| 539 | 同一时间窗口只显示一次相同内容 |
| 546 | 避让字幕区域 |
| 547 | 减少弹幕与底部字幕重叠 |
| 556 | 主体穿透遮挡 |
| 558 | 用本地 AI 蒙版扣除人物区域内的弹幕 |
| 559 | 优先把弹幕限制在画面上部 |
| 566 | 不透明度 |
| 580 | 显示密度 |
| 594 | 字体大小 |
| 608 | 字体粗细 |
| 623 | 滚动速度 |
| 637 | 显示区域 |
| 654 | 刷新率 |
| 829 | 正在加载 |
| 831 | ${widget.commentCount} 条 |
| 832 | 暂无弹幕 |
| 842 | 弹幕源 |
| 850 | 当前弹幕源 |
| 851 | 未选择 |
| 856 | 导入本地弹幕 |
| 857 | 支持 XML 与 JSON 文件 |
| 862 | 在线搜索 |
| 872 | 作品名或 TMDB:编号（如 TMDB:100049） |
| 881 | 搜索 |
| 903 | 填入当前片名 |
| 908 | 填入当前 TMDB |
| 916 | ${result['title'] ?? '弹弹play'} |
| 919 | 当前集 |
| 929 | 已保存弹幕源 |
| 940 | 来源库 |
| 941 | 暂无已保存来源 |
| 942 | 在线匹配、随片下载和本地导入的来源会显示在这里。 |
| 951 | 使用中 |
| 970 | 弹弹play |
| 971 | 随片下载 |
| 972 | 本地 |
| 978 | $count 条 |
| 1042 | 删除来源 |
| 1340 | 播放行为 |
| 1341 | 片头片尾跳过 |
| 1342 | 章节 |
| 1343 | 字幕样式 |
| 1346 | 音频调整 |
| 1347 | 自定义均衡器 |
| 1348 | 已保存画面预设 |
| 1349 | 已保存音频预设 |
| 1350 | 弹幕设置 |
| 1351 | 弹幕源 |
| 1398 | 画面 |
| 1420 | 弹幕 |
| 1422 | 弹幕设置 |
| 1423 | 显示区域、透明度、密度、字号与弹幕类型 |
| 1424 | 已开启 |
| 1429 | 弹幕源 |
| 1431 | 在线搜索、本地导入与已保存来源 |
| 1434 | ${widget.danmakuCommentCount} 条 |
| 1439 | 播放 |
| 1441 | 播放行为 |
| 1442 | 自动连播、下一级预加载 |
| 1443 | 已开启 |
| 1448 | 片头片尾跳过 |
| 1449 | 按时长窗口提示跳过片头片尾 |
| 1450 | 已开启 |
| 1455 | 章节 |
| 1456 | 跳转到当前视频的章节时间点 |
| 1457 | 暂无 |
| 1471 | 视频/轨道信息 |
| 1480 | 预设 |
| 1482 | 选择已保存预设 |
| 1483 | 应用已保存的画面与解码预设 |
| 1487 | 解码与画面 |
| 1509 | 画质增强 |
| 1520 | 同步与缓存 |
| 1563 | 片头 |
| 1577 | 章节识别与固定时长跳过均已关闭。 |
| 1579 | 正在等待视频时长和章节信息。 |
| 1582 | 当前未读取到章节；未启用固定时长跳过。 |
| 1583 | 未识别到$label章节；未启用固定时长跳过。 |
| 1585 | 当前跳过范围无效或片头片尾范围重叠。 |
| 1588 | 当前$label |
| 1589 | 不提示跳过 |
| 1594 | 章节识别 |
| 1596 | 编号章节推测 |
| 1597 | 固定时长 |
| 1599 | 跳到 ${_duration(end)} |
| 1601 | 跳到 ${_duration(end)} |
| 1603 | 播放下一集 |
| 1604 | 跳到视频结束 |
| 1606 | 当前$label |
| 1609 | 点击后$target。 |
| 1611 | 点击后$target，继续播放片尾后的内容。 |
| 1612 | 点击后$target，片尾起点之后的内容会一并跳过。 |
| 1618 | 按章节识别 |
| 1619 | 匹配 OP、ED、片头、片尾等章节名称，进入范围后提示跳过 |
| 1624 | 固定时长跳过 |
| 1625 | 按设定的前后时长提示；同时开启章节识别时，优先使用章节 |
| 1633 | 固定片头时长 |
| 1634 | 从视频开头到设定时间，点击跳过会跳到该时间点 |
| 1647 | 固定片尾时长 |
| 1648 | 在视频最后这段时间内提示跳过 |
| 1664 | 倒计时结束自动跳过 |
| 1665 | 开启后提前弹出并倒计时，归零自动跳过；关闭仅提示 |
| 1673 | 跳过倒计时 |
| 1674 | 提示提前弹出的秒数，倒计时归零自动跳过 |
| 1675 | ${widget.skipCountdownSeconds} 秒 |
| 1694 | 关闭 |
| 1697 | $seconds 秒 |
| 1698 | $minutes 分钟 |
| 1699 | $minutes 分 $rest 秒 |
| 1726 | 字幕延迟 |
| 1727 | 正值让字幕更晚出现 |
| 1729 | ${widget.subtitleDelaySeconds > 0 ? '+' : ''}${widget.subtitleDelaySeconds.toStringAsFixed(1)} 秒 |
| 1744 | 字幕位置 |
| 1745 | 数值越小字幕越靠上 |
| 1759 | 字幕缩放 |
| 1760 | 整体放大或缩小字幕 |
| 1793 | 章节 |
| 1794 | 当前视频没有章节信息 |
| 1795 | 片源带内嵌章节时这里会列出可跳转的时间点。 |
| 1819 | 章节 ${index + 1} |
| 1841 | 音频延迟 |
| 1842 | 正值让声音更晚，负值让声音更早 |
| 1844 | ${_audioDelaySeconds > 0 ? '+' : ''}${_audioDelaySeconds.toStringAsFixed(1)} 秒 |
| 1852 | 预设 |
| 1854 | 选择已保存预设 |
| 1855 | 应用已保存的音频预设 |
| 1859 | 输出 |
| 1863 | 音频直通 |
| 1864 | 已开启 |
| 1865 | 位流直通由功放解码，音效与均衡器暂时不生效。 |
| 1867 | 增益与音效 |
| 1878 | 均衡器 |
| 1885 | 自定义均衡器 |
| 1886 | 五个频段增益微调 |
| 1902 | 自定义均衡器频段 |
| 1948 | ${definition.title} · 插帧期间自动同步 |
| 1991 | 标题 |
| 1992 | 位置 |
| 1993 | 时长 |
| 1994 | 分辨率 |
| 1995 | 视频编码 |
| 1996 | 编码配置 |
| 1997 | 位深 |
| 1998 | 色彩空间 |
| 1999 | 传输特性 |
| 2001 | 码率 |
| 2006 | 播放模式 |
| 2179 | 已保存预设 |
| 2180 | 暂无已保存预设 |
| 2181 | 在全局设置的 MPV 播放器设置里保存过预设后，这里可以直接应用。 |
| 2688 | 点击跳转到此时间点 |
| 2884 | 当前视图 |
| 2915 | 第$numberLabel集 |
| 2947 | 第$numberLabel集 · $title |
| 2969 | 第$numberLabel集 · $title |
| 2998 | 已下载 |
| 3103 | 已观看 |

### `lib/desktop/playback/external_playback_controls.dart`（12 处，建议键前缀 `desktop_playback_external_playback_controls`）

| 行 | 现文案 |
|---|---|
| 29 | ${status.player.displayName} 暂不支持由 Fly Player 编辑字幕或弹幕。 |
| 44 | 播放内容已切换，请重新选择当前影片的弹幕 |
| 51 | 弹幕源加载失败，请重试或选择其他来源 |
| 65 | 弹幕已应用到 ${status.player.displayName} |
| 66 | 弹幕未能应用，请确认当前影片和字幕选项 |
| 71 | 弹幕源加载失败，请重试 |
| 79 | 导入弹幕文件 |
| 101 | 弹幕文件无法读取，请重新选择 |
| 109 | 关闭弹幕源 |
| 110 | 关闭 |
| 134 | 未找到弹幕，请检查关键词或网络后重试 |
| 178 | 弹幕源删除失败，请重试 |

### `lib/desktop/playback/external_playback_host.dart`（39 处，建议键前缀 `desktop_playback_external_playback_host`）

| 行 | 现文案 |
|---|---|
| 59 | 等待进度回报 |
| 273 | 所选剧集 |
| 341 | 所选片源 |
| 486 | 当前影片 |
| 564 | 外部播放器正在启动，请稍候 |
| 584 | 外部播放启动已取消 |
| 658 | 等待播放器就绪 |
| 699 | 播放页面或账号已切换，请重新播放 |
| 729 | 播放账号已切换 |
| 772 | 播放会话已结束 |
| 786 | 未能解析这一集 |
| 796 | 播放会话已结束 |
| 819 | 播放会话已结束 |
| 831 | 这一集的播放信息或字幕未能加载，请从 Fly Player 重试 |
| 859 | 播放页面或账号已切换，请重新播放 |
| 866 | 本地文件，无需回报服务器 |
| 867 | 等待进度回报 |
| 883 | 进度已同步 |
| 884 | 进度已保存，等待同步 |
| 885 | 进度回报失败，可重试 |
| 936 | 自动匹配 |
| 975 | 正在同步进度 |
| 1073 | 已加载弹幕 |
| 1084 | 等待当前集进度回报 |
| 1097 | 字幕或弹幕未能载入，请在 ${adapter.displayName} 检查字幕选项 |
| 1186 | 外部播放启动已取消 |
| 1197 | ${adapter.displayName} 正在解析文件，较大的蓝光原盘可能需要一分钟左右 |
| 1208 | 字幕或弹幕未能载入，请在 ${adapter.displayName} 检查字幕选项 |
| 1316 | 弹幕未能应用，请重试 |
| 1322 | 已在 ${adapter.displayName} 播放；请保持 Fly Player 运行以同步进度 |
| 1407 | 所选本地字幕不存在或为空，视频将继续播放 |
| 1413 | 当前字幕不能从控制页载入，请在 ${player.displayName} 中切换 |
| 1422 | 所选 SUP 位图字幕暂不能接入，视频将继续播放 |
| 1442 | 所选外挂字幕未能获取，视频将继续播放 |
| 1452 | 所选内封字幕暂不能与弹幕合并，本次保留内封字幕播放 |
| 1456 | 所选字幕未能获取，已保留当前字幕 |
| 1472 | 未生成可用弹幕，请搜索或导入弹幕源 |
| 1479 | 字幕与弹幕未能合并，已保留原字幕继续播放 |
| 1480 | 弹幕未能加载，视频将继续播放 |

### `lib/desktop/playback/external_playback_mini_player.dart`（22 处，建议键前缀 `desktop_playback_external_playback_mini_player`）

| 行 | 现文案 |
|---|---|
| 50 | 操作未完成，请在完整页面检查连接 |
| 53 | 操作失败，请重试 |
| 65 | 窗口调整失败，请重试 |
| 82 | 当前播放已结束 |
| 87 | 已暂停 |
| 88 | 正在连接 |
| 89 | 连接已断开 |
| 90 | 播放已结束 |
| 130 | 拖动悬浮条 |
| 195 | 暂停 |
| 203 | 取消置顶 |
| 214 | 收起操作 |
| 219 | 返回完整界面 |
| 303 | 上一集 |
| 309 | 后退 10 秒 |
| 320 | 前进 10 秒 |
| 331 | 下一集 |
| 373 | 弹幕已开 |
| 374 | 弹幕已关 |
| 380 | 弹幕与字幕调节 |
| 406 | 回到 ${status?.player.displayName ?? '外部播放器'} |
| 415 | 返回完整界面选择影片 |

### `lib/desktop/playback/external_playback_mini_settings.dart`（15 处，建议键前缀 `desktop_playback_external_playback_mini_settings`）

| 行 | 现文案 |
|---|---|
| 81 | 已应用 |
| 84 | 应用失败，请重试 |
| 100 | $playerName 暂不支持由 Fly Player 编辑字幕或弹幕。 |
| 110 | 由 $playerName 选择 |
| 130 | 弹幕与字幕 |
| 139 | 字号 |
| 147 | 不透明度 |
| 155 | 密度 |
| 163 | 速度 |
| 176 | 影片字幕 |
| 215 | 内封字幕（由 $playerName 管理） |
| 237 | 内封 / 位图字幕请在 $playerName 中切换 |
| 245 | 调节后点击应用 |
| 257 | 还原 |
| 266 | 应用中… |

### `lib/desktop/playback/external_playback_notice.dart`（2 处，建议键前缀 `desktop_playback_external_playback_notice`）

| 行 | 现文案 |
|---|---|
| 69 | 关闭提示 |
| 116 | 操作未能完成，请稍后重试 |

### `lib/desktop/playback/external_playback_screen.dart`（79 处，建议键前缀 `desktop_playback_external_playback_screen`）

| 行 | 现文案 |
|---|---|
| 142 | 操作未能完成，请确认外部播放器会话仍然有效 |
| 177 | 设置已应用到 ${status.player.displayName} |
| 316 | 当前没有外部播放 |
| 328 | 从媒体详情页使用外部播放器播放，\n即可在这里管理进度、弹幕、字幕与剧集。 |
| 355 | 返回媒体库 |
| 374 | 外部播放器设置 |
| 392 | 返回 |
| 401 | 外部播放 |
| 410 | ${status.player.displayName} 会话控制与片源设置 |
| 451 | 外部播放器设置 |
| 477 | 无法打开极简模式，请重试 |
| 487 | 极简模式已开启 |
| 493 | 极简模式中 |
| 545 | 正在播放 |
| 571 | 第 ${source.seasonNumber} 季 |
| 573 | 第 ${source.episodeNumber} 集 |
| 577 | 本地文件 |
| 601 | 继续 |
| 607 | 上一集 |
| 614 | 下一集 |
| 626 | 回到 ${status.player.displayName} |
| 677 | 最近一次服务器同步：${_clock(status.lastSyncedAt!)} |
| 738 | 重新连接外部播放器失败 |
| 740 | 重新连接 |
| 750 | 重试进度回报失败 |
| 752 | 重试回报 |
| 788 | 弹幕 |
| 795 | 片源与字幕 |
| 825 | 启用弹幕前，请关闭内封/位图字幕或改选外挂文本字幕 |
| 826 | 有尚未应用的更改 |
| 837 | 撤销 |
| 850 | 应用到 ${status.player.displayName} |
| 866 | ${status.player.displayName} 暂不支持由 Fly Player 编辑字幕或弹幕。 |
| 883 | 未选择弹幕源 |
| 893 | ${status.danmakuCount} 条弹幕 |
| 894 | 没有已加载的弹幕 |
| 903 | 搜索或导入 |
| 923 | 字号 |
| 932 | 不透明度 |
| 941 | 密度 |
| 950 | 速度 |
| 983 | 显示区域 ${(draft.displayAreaRatio * 100).round()}% |
| 1000 | 滚动 |
| 1006 | 顶部 |
| 1012 | 底部 |
| 1019 | 避让字幕区域 |
| 1061 | 这一幕的配乐太棒了 |
| 1068 | 前方高能 |
| 1077 | 细节满分 |
| 1081 | 弹幕已关闭 |
| 1087 | 样式预览 |
| 1096 | 字幕避让区 |
| 1122 | 由 ${status.player.displayName} 选择 |
| 1141 | 当前位图字幕（在 ${status.player.displayName} 中切换） |
| 1142 | 当前内封字幕（在 ${status.player.displayName} 中切换） |
| 1147 | 视频质量 |
| 1156 | 当前媒体没有其他可切换片源 |
| 1163 | 选择视频质量 |
| 1177 | 画质切换失败，请稍后重试 |
| 1187 | ${status.player.displayName} 暂不支持由 Fly Player 编辑字幕或弹幕。 |
| 1193 | 外挂字幕 |
| 1201 | 启用弹幕时，Fly Player 会将外挂 ASS、SRT、VTT 与弹幕合成为一条临时 ASS；关闭字幕只关闭影片字幕。 |
| 1230 | 当前是位图字幕，请在 ${status.player.displayName} 菜单中切换；这里可关闭或改用外挂文本字幕。 |
| 1231 | 当前是内封字幕，请在 ${status.player.displayName} 菜单中切换；这里可关闭或改用外挂文本字幕。 |
| 1258 | 音轨和内封字幕由 ${status.player.displayName} 管理，请在播放器菜单中切换。 |
| 1333 | 播放列表 |
| 1341 | ${episodes.length} 集 |
| 1352 | 特别篇 |
| 1355 | 选择季 |
| 1361 | 特别篇 |
| 1376 | 当前会话没有剧集目录 |
| 1434 | 切集后会重新解析该集的片源、字幕和弹幕；连续播放由 ${status.player.displayName} 的播放列表设置控制。 |
| 1435 | 切集后会重新解析该集的片源、字幕和弹幕。 |
| 1453 | 剧集切换失败，请稍后重试 |
| 1458 | 正在连接 |
| 1459 | 已暂停 |
| 1460 | 连接已断开 |
| 1461 | 播放已结束 |
| 1486 | 原画 |

### `lib/desktop/playback/external_player_adapters.dart`（1 处，建议键前缀 `desktop_playback_external_player_adapters`）

| 行 | 现文案 |
|---|---|
| 14 | 不支持的外部播放器：$id |

### `lib/desktop/playback/external_player_media_proxy.dart`（3 处，建议键前缀 `desktop_playback_external_player_media_proxy`）

| 行 | 现文案 |
|---|---|
| 132 | 媒体重定向无效 |
| 136 | 媒体重定向协议无效 |
| 209 | 不支持的播放清单资源地址 |

### `lib/desktop/playback/external_player_playlist.dart`（8 处，建议键前缀 `desktop_playback_external_player_playlist`）

| 行 | 现文案 |
|---|---|
| 40 | 第 $episodeNumber 集 |
| 110 | 第$seasonNumber季 第${episode['episodeNumber'] ?? ''}集  |
| 134 | 本地播放的在线目录查询超时 |
| 159 | 特别篇 |
| 160 | 第${season.seasonNumber}季 |
| 165 | $label 第${episode.episodeNumber}集 ${episode.title} |
| 180 | 部分季的播放列表未能加载，本次保留已获取的剧集 |
| 247 | 第${record.seasonNumber}季 第${record.episodeNumber}集  |

### `lib/desktop/playback/external_player_settings.dart`（1 处，建议键前缀 `desktop_playback_external_player_settings`）

| 行 | 现文案 |
|---|---|
| 62 | 无法保存外部播放器设置，请重试。 |

### `lib/desktop/playback/external_player_subtitles.dart`（8 处，建议键前缀 `desktop_playback_external_player_subtitles`）

| 行 | 现文案 |
|---|---|
| 94 | 暂不支持将 .$extension 字幕与弹幕合并，请选择 ASS、SRT 或 VTT 字幕，或关闭弹幕。 |
| 124 | UTF-16 字幕内容不完整。 |
| 136 | 合并字幕需要 UTF-8 或 UTF-16 编码，请先转换字幕编码。 |
| 247 | 字幕包含无法读取的时间轴。 |
| 265 | 未能读取 SRT/VTT 字幕时间轴，无法合并弹幕。 |
| 325 | 弹幕合并仅支持 ASS v4+ 字幕，不支持旧 SSA 或不完整的 ASS 文件。 |
| 332 | ASS 字幕格式字段不完整，无法安全合并弹幕。 |
| 366 | ASS 字幕缺少 Format 字段。 |

### `lib/desktop/playback/potplayer_adapter.dart`（8 处，建议键前缀 `desktop_playback_potplayer_adapter`）

| 行 | 现文案 |
|---|---|
| 32 | 播放时请保持 Fly Player 运行，用于向 NAS 回报进度。影片详情页和外部播放控制页可暂停、跳转、更换片源、搜索弹幕和选择外挂字幕。\n\n |
| 33 | 飞牛原画剧集会带入各季播放列表；切集时会同步对应字幕、弹幕和进度。连续播放由 PotPlayer 的播放列表设置控制。\n\n |
| 34 | 弹幕与外挂 ASS、SRT、VTT 会合成为临时 ASS。音轨、内封字幕和位图字幕请在 PotPlayer 菜单中切换；AI 人物遮挡暂不支持。 |
| 47 | 外部播放器接入目前仅支持 Windows。 |
| 49 | 请先选择或自动查找 PotPlayer 程序。 |
| 52 | 请选择 PotPlayerMini64.exe 或 PotPlayerMini.exe。 |
| 54 | 程序文件不存在，请重新选择 PotPlayer。 |
| 155 | 未能启动 PotPlayer |

### `lib/desktop/playback/potplayer_session.dart`（13 处，建议键前缀 `desktop_playback_potplayer_session`）

| 行 | 现文案 |
|---|---|
| 69 | PotPlayer 未接受控制命令：$method |
| 77 | 播放会话已结束或账号已切换 |
| 100 | 播放账号已切换，请重新播放 |
| 112 | PotPlayer 已关闭 |
| 125 | PotPlayer 已切换到列表外的媒体，请重新打开播放 |
| 193 | 未能确认 PotPlayer 正在播放此媒体，请检查播放地址或播放器权限 |
| 252 | PotPlayer 已切换到其他媒体，已结束原影片的进度回报 |
| 273 | 切换列表影片失败，已停止进度回报，请重新打开播放 |
| 283 | PotPlayer 已切换到列表外的媒体，已结束进度回报 |
| 337 | 未能确认切集后的续播位置，已停止进度回报，请重新打开播放 |
| 349 | 暂时无法读取 PotPlayer 进度，正在重试；不会推算播放位置 |
| 450 | 未能将 PotPlayer 窗口切到前台 |
| 500 | 未能确认 PotPlayer 已关闭，请检查播放器窗口 |

## 其他（playback / utils / ui / main）（7 处）

### `lib/main.dart`（2 处，建议键前缀 `main`）

| 行 | 现文案 |
|---|---|
| 76 | 飞翔播放器 |
| 416 | 飞翔播放器 |

### `lib/playback/emby_playback_source_bridge.dart`（1 处，建议键前缀 `playback_emby_playback_source_bridge`）

| 行 | 现文案 |
|---|---|
| 33 | Emby 播放桥接器收到不匹配的后端上下文 |

### `lib/playback/feiniu_playback_source_bridge.dart`（3 处，建议键前缀 `playback_feiniu_playback_source_bridge`）

| 行 | 现文案 |
|---|---|
| 33 | 当前直链档位已不可用 |
| 36 | 未返回有效直链 |
| 73 | 飞牛播放桥接器收到不匹配的后端上下文 |

### `lib/ui/catalog_filter_localizer.dart`（1 处，建议键前缀 `ui_catalog_filter_localizer`）

| 行 | 现文案 |
|---|---|
| 86 | 频道顺序 |

## 手机/平板页面（screens）（66 处）

### `lib/screens/app_settings_screen.dart`（8 处，建议键前缀 `screens_app_settings_screen`）

| 行 | 现文案 |
|---|---|
| 195 | 外部播放器接入 |
| 196 | 使用外部播放器播放并回报进度 |
| 202 | 外部播放器 |
| 203 | 字幕 |
| 204 | 弹幕 |
| 205 | 进度回报 |
| 575 | 外部播放器接入 |
| 576 | 使用外部播放器播放并回报进度 |

### `lib/screens/download_list_screen.dart`（10 处，建议键前缀 `screens_download_list_screen`）

| 行 | 现文案 |
|---|---|
| 53 | 无法打开文件夹 |
| 59 | 无法打开文件夹，请检查保存路径是否存在 |
| 151 | 读取下载目录失败 |
| 163 | 选择下载位置（将在其中创建 FlyPlayer 文件夹） |
| 174 | 新下载将保存到此处，已有任务位置不变 |
| 181 | 无法保存到该目录，请选择可写入的文件夹 |
| 418 | 下载目录：${_downloadDirectory ?? '正在读取…'} |
| 431 | 更改目录 |
| 434 | 打开下载文件夹 |
| 2339 | 打开文件夹：${p.dirname(record.filePath)} |

### `lib/screens/external_player_settings_screen.dart`（33 处，建议键前缀 `screens_external_player_settings_screen`）

| 行 | 现文案 |
|---|---|
| 59 | 读取外部播放器设置失败，请重新打开此页面。 |
| 71 | 读取弹幕设置失败，请重新打开此页面。 |
| 114 | 已启用 ${_player.displayName}，下一次播放时生效。 |
| 118 | 保存失败，请重试。 |
| 130 | 选择 ${_player.displayName} 程序 |
| 140 | 无法选择程序，请手动填写 ${_player.displayName} 路径。 |
| 152 | 未找到 ${_player.displayName}，请选择程序或填写安装路径。 |
| 158 | 自动查找失败，请手动选择 ${_player.displayName} 程序。 |
| 188 | 外部播放器接入 |
| 224 | ${_player.displayName} 接入 |
| 233 | 由 Fly Player 管理片源、弹幕与播放进度 |
| 256 | 已启用 |
| 308 | 播放器 |
| 318 | 使用 ${_player.displayName} 播放 |
| 326 | 启用后，此电脑上的视频将交给 ${_player.displayName}。 |
| 359 | 程序路径 |
| 427 | 选择 |
| 436 | 自动查找 |
| 451 | 保存 |
| 493 | 常用操作 |
| 521 | 弹幕设置 |
| 531 | 已开启，匹配后会带入 ${_player.displayName} |
| 532 | 已关闭，开启后才会显示弹幕 |
| 533 | 暂未读取到弹幕状态 |
| 535 | ${_player.displayName} 不支持由 Fly Player 注入弹幕 |
| 583 | 使用说明 |
| 591 | 进度同步、播放列表与字幕限制 |
| 655 | 极简模式已开启 |
| 669 | 开始外部播放后可用 |
| 672 | 顶部居中显示，可拖动并保持置顶 |
| 673 | ${status.player.displayName} 不支持极简模式 |
| 674 | 当前窗口暂不可用 |
| 688 | 无法打开极简模式，请重试 |

### `lib/screens/home/home_view_data.dart`（1 处，建议键前缀 `screens_home_home_view_data`）

| 行 | 现文案 |
|---|---|
| 18 | 失败的首页区块结果没有值 |

### `lib/screens/home/widgets/home_catalog_section.dart`（1 处，建议键前缀 `screens_home_widgets_home_catalog_section`）

| 行 | 现文案 |
|---|---|
| 82 | 媒体库 |

### `lib/screens/home/widgets/home_continue_watching_section.dart`（2 处，建议键前缀 `screens_home_widgets_home_continue_watching_section`）

| 行 | 现文案 |
|---|---|
| 42 | 继续观看 |
| 181 | 继续播放 |

### `lib/screens/live_channel_screen.dart`（10 处，建议键前缀 `screens_live_channel_screen`）

| 行 | 现文案 |
|---|---|
| 58 | 加载直播频道 |
| 69 | 直播 |
| 74 | 播放直播 |
| 95 | 收藏直播频道 |
| 111 | 直播频道 |
| 144 | 直播线路 |
| 146 | 服务器默认线路 |
| 154 | 线路 ${i + 1} |
| 167 | 正在处理… |
| 181 | 取消收藏 |

### `lib/screens/login_history_screen.dart`（1 处，建议键前缀 `screens_login_history_screen`）

| 行 | 现文案 |
|---|---|
| 283 | 飞牛影视 |

---

## 修复进度（2026-10-11 第二轮更新）

**已完成（约 450 处 → 34 文件清零）：**

- 桌面播放器全模块：external_playback_screen / desktop_player_panels / external_playback_host / potplayer_session+adapter（接口注入 l10n）/ mini_player / mini_settings / controls / desktop_playback_screen / launch_guard / notice / playlist / mpv_runtime 等
- 外部播放器设置页（screens/external_player_settings_screen）+ 适配器接口（usageNotes/validateExecutable/launch 增加 l10n 参数）
- screens：live_channel / download_list / app_settings / home 区块
- 服务层（无 context）：新增 AppLocaleProvider.effectiveLocale 同步取词通道（含绑定未就绪兜底），download_task_service / launchers / storage / bridges / emby+feiniu backend / feiniu_api / startup_preferences
- main.dart 桌面窗口标题（runApp 前经 loadStoredLocale 取词）
- ARB 四语同步增至 2897 键；flutter analyze 全项目 0 问题；全量测试 1425 过 / 10 失败（经 stash 对照全部为 HEAD 既有失败）；相关测试 harness 已补 localizationsDelegates + zh_CN locale

**有意保留（确认不需要 i18n，共约 140 处）：**

- login_error_resolver 47 条服务器错误匹配关键词、dandanplay_resolver 15 条解析正则、弹幕/章节/季集正则、debugPrint 日志、RouteGateAnchor 开发者消息
- external_player_subtitles 8 条 isolate 内部诊断（异常被 host catch 后仅显示通用本地化消息，不透出）
- 品牌名（弹弹play/飞牛影视/飞翔播放器 MaterialApp.title）、play_stats_database 2 条存量数据 label、media_proxy 3 条协议内部异常

**待下一批（约 188 处，见特殊情形 A/B）：**

- mpv_settings_store 69 条 option.description：设计方案=加 mpv option description ARB 键 + MpvSettingsL10n.optionDescriptionForSetting()（仿现有 optionLabelForSetting），choice page 与 optionText() 两处消费点改走 l10n
- media_language_mapper 119 条语言码→中文名表：需 locale 感知方案（intl 语言显示名或 en/ja 平行表）
- screenshot_settings_store 4 条英文 label 随 B 一并处理

## 修复进度（2026-10-12 第三轮：剩余两块已完成）

**mpv 选项描述（特殊情形 B，68 键）：**

- 从 store 提取 21 个设置项 × 68 个选项的中文描述，外置为 ARB 键 `mpv<Key><Value>Desc`（四语同步，ARB 总数 2965）。
- `MpvSettingsL10n` 新增 `optionDescriptionForSetting()`（按设置项+取值 switch，未覆盖组合回退 catalog 原文），`optionText()` 接线后 choice page / 桌面设置面板自动生效。
- store 里的中文描述保留为 fallback（与 catalog 英文 title 同架构，不再对 en/ja 用户透出）。

**语言映射表（特殊情形 A，119 条）：**

- `MediaLanguageMapper` 新增 en/ja 平行显示名表（74 个规范语言码），`languageName/subtitleLabel` 增加 `uiLocaleName` 可选参数：持有 l10n 的调用方传 `l10n.localeName`，其余走 `AppLocaleProvider.effectiveLocale`，zh 或缺项回退原中文表。
- 已接线：DesktopMpvRuntime 轨道标题、play_detail_track_selector、audio_track_label_localizer、feiniu_video_info_lines（新增可选 l10n 参数）、feiniu_media_detail_variant_mapper。运行时 `mergeLanguageMap` 合入的自定义名仅入中文表，en/ja 缺项回退中文（可接受）。

**截图位置预设（特殊情形 C）：核实后无需处理** —— 设置屏早已通过屏内 helper 走 ARB（`settingsScreenshotSavePath*`），store 里的英文 label 是无调用方的 fallback。

**最终验证：** `flutter analyze` 全项目 0 问题；全量测试 1425 过 / 10 失败（与 HEAD 既有基线逐一对照一致）。
