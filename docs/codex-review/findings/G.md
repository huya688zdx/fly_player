<!-- CHECKPOINT
已审文件数: 29 / 29
最后完成: lib/screens/parallel_placeholder_screen.dart
下一个: 无
阶段: 已完成
更新时间: 2026-07-03 01:50
-->

# TASK G Findings

### [G-001] mpv 设置页单文件承载过多页面与组件
- 级别: P2
- 分类: 可维护性 / 约束违规(M1)
- 位置: lib/screens/mpv_player_settings_screen.dart:65
- 问题: `mpv_player_settings_screen.dart` 共 3181 行，远超单个 UI 文件 1500 行拆分阈值；同一文件同时承载入口页、目的地页、自定义预设管理、分类页、选项页、EQ、高级缓存、视频调节以及多个通用卡片组件。摘录：`class MpvPlayerSettingsScreen extends StatefulWidget {`、`class _MpvCustomManagementScreen extends StatefulWidget {`、`class _MpvSettingChoiceScreen extends StatefulWidget {`、`class _MpvCacheSizeScreen extends StatefulWidget {`、`class _VideoAdjustmentSliderCard extends StatelessWidget {`。
- 建议方向: 按入口/预设管理/分类与选项/缓存与视频调节/通用设置卡片组件拆成多个 part 或独立 screen/widget 文件，保留当前路由行为不变。
- 状态: 已确认

### [G-002] mpv 设置分类标题解析逻辑在同文件内重复
- 级别: P2
- 分类: 可维护性 / 约束违规(M2)
- 位置: lib/screens/mpv_player_settings_screen.dart:118
- 问题: 目的地页和主设置页各自维护一套 `_buildCategory`/`_buildDisplayCategory` 与 `_settingTitle`/`_displaySettingTitle`、`_settingSubtitle`/`_displaySettingSubtitle` switch，字段映射几乎相同，新增 mpv 设置时需要同步改两处。摘录：`title: _settingTitle(key), subtitle: _settingSubtitle(key)`；另一路为 `title: _displaySettingTitle(key), subtitle: _displaySettingSubtitle(key)`。
- 建议方向: 把 key 到本地化标题/副标题的映射收敛到 `MpvSettingsL10n.definitionByKey` 或单一 helper，两个页面只消费同一份 `MpvSettingCategoryEntry` 生成逻辑。
- 状态: 已确认

### [G-003] 缓存滑条端点文案硬编码英文
- 级别: P2
- 分类: 可维护性 / 约束违规(M3)
- 位置: lib/screens/mpv_player_settings_screen.dart:2380
- 问题: UI 展示文案绕过 `AppLocalizations`，直接硬编码英文 `MIN`/`MAX`。摘录：
  ```dart
  Text(
    'MIN ${MpvSettingsCatalog.formatCachePercentLabel(MpvSettingsCatalog.cachePercentSliderMin)}',
  )
  Text(
    'MAX ${MpvSettingsCatalog.formatCachePercentLabel(MpvSettingsCatalog.cachePercentSliderMax)}',
  )
  ```
- 建议方向: 增加对应 l10n getter 或复用已有“最小/最大”本地化文案，将格式化百分比作为参数传入。
- 状态: 已确认

### [G-004] 弹幕设置保存失败会留下错误的页面状态
- 级别: P2
- 分类: Bug / 错误处理
- 位置: lib/screens/danmaku_settings_screen.dart:58
- 问题: `_save` 先更新 `_settings` 再异步落盘，`await _store.save(next)` 没有失败处理、回滚或提示；一旦 SharedPreferences/存储写入失败，页面显示已经切换，但重进页面会恢复旧值。摘录：
  ```dart
  Future<void> _save(DanmakuSettings next) async {
    setState(() => _settings = next);
    await _store.save(next);
  }
  ```
- 建议方向: 保存失败时记录/上报错误并恢复上一份设置，或先落盘成功后再更新 UI，同时给用户明确失败提示。
- 状态: 已确认

### [G-005] 截图自定义目录平台异常没有用户反馈
- 级别: P2
- 分类: Bug / 错误处理
- 位置: lib/screens/screenshot_settings_screen.dart:973
- 问题: 选择/清除自定义截图目录只用 `try/finally` 复位按钮状态，没有 `catch` 上报或提示；而 `StorageAccessService.requestScreenshotCustomDirectory()` / `clearScreenshotCustomDirectory()` 直接调用 MethodChannel，`PlatformException` 会冒泡，用户只会看到操作中断。摘录：
  ```dart
  try {
    final info =
        await StorageAccessService.requestScreenshotCustomDirectory();
    ...
  } finally {
    if (mounted) {
      setState(() => _selecting = false);
    }
  }
  ```
- 建议方向: 在页面层捕获平台异常，调用现有错误上报/TopTip 提示，并确保清除失败时不更新本地目录状态。
- 状态: 已确认

### [G-006] 下载管理页单文件承载列表、详情和组件
- 级别: P2
- 分类: 可维护性 / 约束违规(M1)
- 位置: lib/screens/download_list_screen.dart:56
- 问题: `download_list_screen.dart` 共 2397 行，超过 UI 文件 1500 行拆分阈值；同一文件同时包含下载列表页、下载组详情页、版本分组、记录行、海报图、Tab 切换、按钮等多个职责。摘录：`class DownloadListScreen extends StatefulWidget {`、`class DownloadGroupDetailScreen extends StatefulWidget {`、`class _DownloadRecordVersionGroup extends StatelessWidget {`、`class _DownloadRecordRow extends StatelessWidget {`、`class _DownloadPosterImage extends StatelessWidget {`。
- 建议方向: 按列表宿主、详情宿主、记录/分组卡片、海报/徽标、顶部与 Tab 控件拆分文件，保留下载服务调用入口不变。
- 状态: 已确认

### [G-007] 下载速度/进度更新会重建整页下载界面
- 级别: P1
- 分类: 性能 / 约束违规(P4)
- 位置: lib/screens/download_list_screen.dart:287
- 问题: `DownloadTaskService` 会按下载速度发布间隔约 900ms、转码进度轮询 2s `notifyListeners()`；页面用一个 `AnimatedBuilder(animation: _service)` 包住 `PageView` 和两个列表，详情页也用同样方式包住整个 `Column`。下载中每次速度/进度变化都会重建头部、PageView、列表和所有可见行。摘录：
  ```dart
  Expanded(
    child: AnimatedBuilder(
      animation: _service,
      builder: (context, _) {
        final downloadedGroups = _service.groupsByStatus(...);
        final downloadingRecords = _service.activeRecords;
        return PageView(...);
      },
    ),
  )
  ```
- 建议方向: 将高频下载速度/进度拆到单条记录行或进度条的局部监听，列表结构只在记录增删/状态切换时刷新。
- 状态: 已确认

### [G-008] 下载暂停/恢复/取消任务没有等待与失败反馈
- 级别: P2
- 分类: Bug / 错误处理
- 位置: lib/screens/download_list_screen.dart:1698
- 问题: 下载行的暂停、恢复和取消操作直接调用返回 `Future` 的 service 方法，但没有 `await`、`unawaited` 标注、`catch` 或 TopTip；`pauseDownload` 至少会执行 `_persist()`，失败时页面不会提示，异常也可能成为未处理 Future。摘录：
  ```dart
  void handlePause() {
    final provider = Provider.of<NasProvider>(context, listen: false);
    DownloadTaskService.instance.pauseDownload(provider, record.id);
  }
  void handleResume() {
    final provider = Provider.of<NasProvider>(context, listen: false);
    DownloadTaskService.instance.resumeDownload(provider, record.id);
  }
  ```
- 建议方向: 将操作改成受控 async handler，等待结果并在失败时恢复/刷新记录状态，同时给用户提示并记录错误。
- 状态: 已确认

### [G-009] 存储管理页单文件过大且职责混杂
- 级别: P2
- 分类: 可维护性 / 约束违规(M1)
- 位置: lib/screens/storage_management_screen.dart:20
- 问题: `storage_management_screen.dart` 共 2911 行，超过 UI 文件 1500 行拆分阈值；同一文件包含主存储页、应用数据清理页、图表、分类卡片、分组树、播放缓存面板、下载面板、危险操作行和自绘 donut。摘录：`class StorageManagementScreen extends StatefulWidget {`、`class StorageAppDataScreen extends StatefulWidget {`、`class _StorageChartCard extends StatefulWidget {`、`class _GroupedStorageTree<T> extends StatelessWidget {`、`class _StorageDonutPainter extends CustomPainter {`。
- 建议方向: 按主页面/应用数据页面/图表与 legend/可展开分类/缓存与下载明细/通用行组件拆分，降低单文件维护成本。
- 状态: 已确认

### [G-010] 存储管理主页面加载和清理失败没有兜底状态
- 级别: P2
- 分类: Bug / 错误处理
- 位置: lib/screens/storage_management_screen.dart:56
- 问题: `_loadOverview()` 设置 `_loading = true` 后直接 await `loadOverview`，没有 `catch/finally`，平台通道或下载服务异常会让页面一直停在 loading；`_runSystemAction` 等清理路径也只有 `try/finally`，异常时不会显示失败原因。摘录：
  ```dart
  Future<void> _loadOverview() async {
    setState(() => _loading = true);
    final overview = await _service.loadOverview(l10n);
    if (!mounted) return;
    setState(() {
      _overview = overview;
      _loading = false;
    });
  }
  ```
- 建议方向: 加统一的加载/操作错误处理，失败时恢复 loading/working 状态、显示 TopTip，并记录异常供日志页追踪。
- 状态: 已确认

### [G-011] 存储明细 fallback 用 Column 一次性渲染不定长列表
- 级别: P2
- 分类: 性能 / 约束违规(P2)
- 位置: lib/screens/storage_management_screen.dart:2340
- 问题: 播放缓存和下载明细在无法分组时使用 `...entries.map(...)` 直接塞进父 `Column`，条目数来自真实缓存/下载记录，可能随用户长期使用增长；展开面板会一次性构建所有行。摘录：
  ```dart
  else
    ...entries.map((entry) {
      final checked = selectedKeys.contains(entry.resourceKey);
      return CheckboxListTile(...);
    }),
  ```
- 建议方向: 对明细列表使用 `ListView.builder`/`SliverList` 或沿用已有分页分组策略，确保未分组数据也有懒加载或分页上限。
- 状态: 已确认

### [G-012] 书签清空和删除操作没有确认或撤销
- 级别: P0
- 分类: Bug
- 位置: lib/screens/bookmark_manager_screen.dart:113
- 问题: 书签管理页顶部“清空”直接调用 `_store.clearAll()`，单条书签删除也直接 `_store.remove(entry.id)`，没有确认弹窗、撤销或二次防误触；误点会立即丢失全部或单条书签数据。摘录：
  ```dart
  Future<void> _clearAll() async {
    await _store.clearAll();
  }
  ...
  TextButton(onPressed: _clearAll, child: Text(l10n.commonClear)),
  ```
- 建议方向: 清空全部必须加确认弹窗并说明影响范围；单条删除至少加确认/撤销 snackbar，失败时提示并保留原状态。
- 状态: 已确认

### [G-013] 弹幕来源删除没有确认或撤销
- 级别: P1
- 分类: Bug
- 位置: lib/screens/danmaku_manager_screen.dart:505
- 问题: 弹幕管理页的删除按钮直接调用 `_store.removeSource`，没有确认弹窗、撤销入口或失败提示；误触会立即删除用户保存的本地/网络弹幕来源。摘录：
  ```dart
  Future<void> _deleteSource(DanmakuSavedSource source) async {
    await _store.removeSource(
      mediaKey: source.mediaKey,
      sourceKey: source.sourceKey,
    );
  }
  ...
  TextButton(onPressed: onDelete, child: Text(l10n.commonDelete))
  ```
- 建议方向: 删除前弹确认框，说明删除的是当前来源而不是弹幕文件本身；成功后可提供短暂撤销或至少 TopTip 反馈。
- 状态: 已确认

### [G-014] 截图预览页单文件过大且混合路由、图库和解码逻辑
- 级别: P2
- 分类: 可维护性 / 约束违规(M1)
- 位置: lib/screens/screenshot_preview_screen.dart:23
- 问题: `screenshot_preview_screen.dart` 共 2520 行，超过 UI 文件 1500 行拆分阈值；同一文件包含图库页、全屏路由、筛选/搜索/排序 sheet、Lightbox、图片 provider、元数据 loader 等多个职责。摘录：`class ScreenshotPreviewScreen extends StatefulWidget {`、`class ScreenshotLightboxRouteScreen extends StatelessWidget {`、`class _ScreenshotSortSheetState extends State<_ScreenshotSortSheet> {`、`class _ScreenshotLightboxState extends State<_ScreenshotLightbox>`、`class _ScreenshotImageProvider extends ImageProvider<_ScreenshotImageProvider> {`。
- 建议方向: 按图库宿主、筛选排序 sheet、lightbox、图片 provider/metadata loader、卡片组件拆分文件；通道路由部分交由桥接任务统一收敛。
- 状态: 已确认

### [G-015] 截图缩略图按原图字节解码，缺少尺寸约束
- 级别: P1
- 分类: 性能 / 约束违规(P3)
- 位置: lib/screens/screenshot_preview_screen.dart:2268
- 问题: `_ScreenshotImageProvider` 被缩略图卡片和全屏预览共用，加载时直接读取整张截图 `Uint8List` 并 `decode(buffer)`，没有根据卡片尺寸传 `targetWidth/targetHeight` 或独立缩略图 provider；图库网格中的每个小卡片也会按原始截图尺寸解码，高清/HDR 截图会造成内存和解码压力。摘录：
  ```dart
  Future<ui.Codec> _loadCodec(ImageDecoderCallback decode) async {
    Uint8List? bytes;
    ...
    bytes = await file.readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }
  ```
- 建议方向: 缩略图 provider 按布局尺寸计算目标解码宽高，或生成/复用缩略图缓存；全屏预览再使用原图 provider。
- 状态: 已确认

### [G-016] 按分辨率排序会并发读取并解码所有截图
- 级别: P1
- 分类: 性能 / 约束违规(P5)
- 位置: lib/screens/screenshot_preview_screen.dart:373
- 问题: `_warmSortMetadata` 对所有未缓存截图直接 `Future.wait(unresolved.map(...))`，而 `_ScreenshotMetadataLoader._read` 会读取整文件字节并 `decodeImageFromList(bytes)`；用户选择“分辨率”排序时，大量截图会同时进内存并触发解码。摘录：
  ```dart
  final entries = await Future.wait(
    unresolved.map((item) async {
      final metadata = await _ScreenshotMetadataLoader.instance.load(item);
      return MapEntry(item.id, metadata);
    }),
  );
  ```
- 建议方向: 限制并发、分页/按可见区域懒加载元数据，并优先走平台层图片尺寸 metadata，避免为排序读取整张图片字节。
- 状态: 已确认

### [G-017] 截图库 build 重复全量排序且 section 内一次性构建全部卡片
- 级别: P2
- 分类: 性能 / 约束违规(P2/P5)
- 位置: lib/screens/screenshot_preview_screen.dart:266
- 问题: `build()` 先取 `_visibleItems`，又取 `_visibleSections`，而 `_visibleSections` 内部再次调用 `_visibleItems`，导致每次 build 至少两次过滤/排序全量截图；每个 `_GallerySection` 再用 `Wrap(children: items.map(...).toList())` 一次性构建该 section 全部缩略图，截图多集中在同一天时不能懒加载。摘录：
  ```dart
  final visibleItems = _visibleItems;
  final visibleSections = _visibleSections;
  ...
  Wrap(
    children: items.map((item) { ... }).toList(growable: false),
  )
  ```
- 建议方向: 单次计算过滤/排序结果并传给 section builder；图库用 `SliverGrid` 或按 section 分页，避免单个 section 一次性构建所有缩略图。
- 状态: 已确认

### [G-018] 播放统计报表页直接依赖 FeiniuApi
- 级别: P1
- 分类: 耦合 / 可扩展性 / 约束违规(C2/C3)
- 位置: lib/screens/play_stats_report_screen.dart:6
- 问题: `PlayStatsReportScreen` 位于 `lib/screens/`，直接 import `../api/feiniu_api.dart` 并在默认元数据加载器中 new `FeiniuApi(provider)` 拉取标签/国家映射；统计页因此写死飞牛后端，后续 Emby/Jellyfin 无法复用这条元数据链路。摘录：
  ```dart
  import '../api/feiniu_api.dart';
  ...
  final api = FeiniuApi(provider);
  final results = await Future.wait<dynamic>([
    api.getTagGenresMap(lan: 'zh-CN'),
    api.getTagIso3166Map(lan: 'zh-CN'),
  ]);
  ```
- 建议方向: 把标签/国家 metadata 加载放到 media_backend 或 play_stats service 抽象中，screen 只依赖后端无关接口。
- 状态: 已确认

### [G-019] 播放统计报表主文件超过拆分阈值
- 级别: P2
- 分类: 可维护性 / 约束违规(M1)
- 位置: lib/screens/play_stats_report_screen.dart:30
- 问题: `play_stats_report_screen.dart` 共 1528 行，超过单个 UI 文件 1500 行拆分阈值；虽然已有 `play_stats_report_widgets.dart`，主文件仍承载加载状态、范围浮层、报表分段、筛选 metric、数据回填和若干局部组件。
- 建议方向: 继续按范围工具栏、数据加载/backfill、内容分布、行为分析、榜单分段拆分，让 screen 宿主只负责状态编排。
- 状态: 已确认

### [G-020] 播放统计元数据加载失败被静默吞掉
- 级别: P2
- 分类: 可维护性 / 错误处理 / 约束违规(M4)
- 位置: lib/screens/play_stats_report_screen.dart:208
- 问题: `_loadMetadataMaps` 捕获所有异常后空处理，网络/API/解析失败既不记录也不提示，报表会悄悄退回原始 genre/country id，后续无法追踪原因。摘录：
  ```dart
  try {
    final loader = widget.metadataLoader ?? _defaultMetadataLoader;
    final maps = await loader(provider);
    ...
  } catch (_) {}
  ```
- 建议方向: 至少用 AppErrorReporter/AppLogService 记录 source 和 action；必要时在报表页显示“元数据未加载”的非阻塞提示。
- 状态: 已确认

### [G-021] 播放统计组件文件过大
- 级别: P2
- 分类: 可维护性 / 约束违规(M1)
- 位置: lib/screens/play_stats_report/play_stats_report_widgets.dart:13
- 问题: `play_stats_report_widgets.dart` 共 2841 行，远超单个 UI 文件 1500 行阈值；一个文件内包含 hero、范围选择、折线/柱状/饼图/热力图、排行、时间线分页、继续观看横条、动画数字和大量私有 tile。
- 建议方向: 按 chart widgets、rank/timeline widgets、hero/metric widgets、range selector、shared tiles 拆分，降低报表组件维护成本。
- 状态: 已确认

### [G-022] 播放统计 compact 时长硬编码英文单位
- 级别: P2
- 分类: 可维护性 / 约束违规(M3)
- 位置: lib/screens/play_stats_report/play_stats_report_formatters.dart:22
- 问题: `PlayStatsReportFormatters.duration(compact: true)` 直接返回 `h`/`m`/`s` 英文单位，这些字符串用于报表 UI 的时长展示，绕过了 `AppLocalizations`。摘录：
  ```dart
  if (compact) {
    if (hours > 0) {
      return minutes > 0 ? '${hours}h ${minutes}m' : '${hours}h';
    }
    ...
    return '${value.inSeconds}s';
  }
  ```
- 建议方向: 为 compact 时长增加 l10n getter/formatter，或复用现有本地化时长格式并通过参数控制紧凑样式。
- 状态: 已确认

### [G-023] 播放统计调试页直接依赖 FeiniuApi 且失败静默
- 级别: P1
- 分类: 耦合 / 可扩展性 / 错误处理 / 约束违规(C2/C3/M4)
- 位置: lib/screens/play_stats_debug/play_stats_debug_screen.dart:6
- 问题: debug screen 位于 `lib/screens/`，直接 import `../../api/feiniu_api.dart` 并在 `_loadMetadataMaps` 中 new `FeiniuApi(provider)`；同时 `catch (_) {}` 静默吞掉元数据加载失败，既阻碍多后端，也无法追踪调试页标签/国家名缺失原因。摘录：
  ```dart
  import '../../api/feiniu_api.dart';
  ...
  final api = FeiniuApi(provider);
  final results = await Future.wait<dynamic>([
    api.getTagGenresMap(lan: 'zh-CN'),
    api.getTagIso3166Map(lan: 'zh-CN'),
  ]);
  ...
  } catch (_) {}
  ```
- 建议方向: 与报表页共用后端无关 metadata loader/service，并记录加载失败；debug UI 不直接触达具体 API。
- 状态: 已确认

### [G-024] 连接页直接持有 Feiniu/Emby API 登录逻辑
- 级别: P1
- 分类: 耦合 / 可扩展性 / 约束违规(C2/C3)
- 位置: lib/screens/connection_screen.dart:7
- 问题: `ConnectionScreen` 直接 import `EmbyApi`/`FeiniuApi`，并用私有枚举 `_ConnectionBackend { feiniu, emby }` 在 UI 内分支登录；飞牛登录直接调 `FeiniuApi.loginWithBaseUrl`，Emby 登录直接 new `EmbyApi`。新增 Jellyfin 或替换登录协议时必须改连接页 UI。摘录：
  ```dart
  import '../api/emby_api.dart';
  import '../api/feiniu_api.dart';
  enum _ConnectionBackend { feiniu, emby }
  ...
  final loginResult = await FeiniuApi.loginWithBaseUrl(...);
  ```
- 建议方向: 将登录表单配置与 authenticate 流程下沉到 media_backend/session 抽象，连接页只渲染当前 backend descriptor 暴露的字段和动作。
- 状态: 已确认

### [G-025] 连接页单文件超过拆分阈值
- 级别: P2
- 分类: 可维护性 / 约束违规(M1)
- 位置: lib/screens/connection_screen.dart:45
- 问题: `connection_screen.dart` 共 1527 行，超过单个 UI 文件 1500 行阈值；文件同时包含飞牛登录、Emby 登录、FN Connect fallback、历史记录选择、后端切换动画、表单控件和登录持久化。
- 建议方向: 至少拆出 backend selector、通用登录表单、飞牛登录 flow、Emby/FN Connect flow、历史记录填充逻辑；更理想是交给后端登录 descriptor。
- 状态: 已确认

### [G-026] 连接页保留未使用的旧 Emby 表单
- 级别: P2
- 分类: 可维护性 / 约束违规(M5)
- 位置: lib/screens/connection_screen.dart:1019
- 问题: `_buildEmbyFormLegacy` 带 `// ignore: unused_element`，全文件没有调用；它还依赖永远为空的 `_embyConnectionStatus`，形成一整段被忽略的旧 UI 分支。摘录：
  ```dart
  // ignore: unused_element
  Widget _buildEmbyFormLegacy(ThemeData theme, AppLocalizations l10n) {
    ...
    if (_embyConnectionStatus.isNotEmpty) ...[
      Text(_embyConnectionStatus),
    ],
  }
  ```
- 建议方向: 删除 legacy 表单，或若仍需要则接回真实入口并移除 ignore；不要保留未执行的 UI 分支。
- 状态: 已确认

### [G-027] 登录历史删除/清空没有确认和失败反馈
- 级别: P2
- 分类: Bug / 错误处理 / 可维护性 / 约束违规(M4)
- 位置: lib/screens/login_history_screen.dart:22
- 问题: 单条删除和清空全部历史会直接调用 `LoginHistoryStore.remove/clear`，页面没有确认、撤销，也没有 `catch` 处理 SharedPreferences 写入失败；用户误触清空或持久化失败时没有任何反馈。摘录：
  ```dart
  Future<void> _delete(LoginHistoryEntry entry) async {
    final entries = await LoginHistoryStore.remove(entry);
    ...
  }
  Future<void> _clear() async {
    await LoginHistoryStore.clear();
    ...
  }
  ```
- 建议方向: 清空全部至少加确认弹窗/撤销入口；删除和清空捕获异常并用现有错误提示或日志服务反馈，不要让失败静默中断。
- 状态: 已确认

### [G-028] FN Connect Web 登录页直接调用 FeiniuApi
- 级别: P1
- 分类: 耦合 / 可扩展性 / 约束违规(C2/C3)
- 位置: lib/screens/fn_connect_web_login_page.dart:7
- 问题: `FnConnectWebLoginPage` 位于 `lib/screens/`，直接 import `../api/feiniu_api.dart`，并在页面内调用 `FeiniuApi.fetchFnConnectOauthConfig` 与 `FeiniuApi.loginWithFnConnectOauthCode` 完成 OAuth；WebView 页面因此绑定飞牛协议，无法作为后端无关登录能力复用。摘录：
  ```dart
  import '../api/feiniu_api.dart';
  ...
  final config = await FeiniuApi.fetchFnConnectOauthConfig(...);
  ...
  final result = await FeiniuApi.loginWithFnConnectOauthCode(...);
  ```
- 建议方向: 将 FN Connect/OAuth 配置获取和 code 交换下沉到后端登录 service 或 `media_backend` descriptor，页面只负责承载 WebView 和回传后端无关结果。
- 状态: 已确认

### [G-029] WebView 登录无条件放行 SSL 证书错误
- 级别: P0
- 分类: Bug / 安全
- 位置: lib/screens/fn_connect_web_login_page.dart:173
- 问题: WebView 的 `onSslAuthError` 直接调用 `error.proceed()`，任何证书错误都会继续加载登录页；该页面还自动填充用户名/密码并交换 OAuth code，证书异常时继续提交会放大账号凭据泄露风险。摘录：
  ```dart
  onSslAuthError: (error) {
    error.proceed();
  },
  ```
- 建议方向: 默认取消 SSL 错误导航并提示用户；如确需支持自签证书，应通过明确设置/确认流程放行，并限制到用户配置的可信 NAS 主机。
- 状态: 已确认

### [G-030] FN Connect Web 登录失败路径大量静默吞异常
- 级别: P2
- 分类: Bug / 错误处理 / 约束违规(M4)
- 位置: lib/screens/fn_connect_web_login_page.dart:205
- 问题: OAuth 配置探测、JS 注入、桥消息解析、sys/config 解析等关键路径多处 `catch (_) {}`，失败后既不记录也不提示，用户可能只看到 WebView 停在中间状态，无法定位是 cookie、注入脚本还是配置接口失败。摘录：
  ```dart
  try {
    final config = await FeiniuApi.fetchFnConnectOauthConfig(...);
    ...
  } catch (_) {}
  ...
  try {
    await _controller.runJavaScript(_buildInjectionScript());
  } catch (_) {}
  ```
- 建议方向: 对可预期的降级分支记录 source/action；关键失败更新状态文案或返回明确错误，避免登录流程无声卡住。
- 状态: 已确认

### [G-031] FN Connect Web 登录页存在硬编码英文 UI 文案
- 级别: P2
- 分类: 可维护性 / 约束违规(M3)
- 位置: lib/screens/fn_connect_web_login_page.dart:116
- 问题: 多处展示文案直接写在页面里，未走 `AppLocalizations`，包括初始状态、授权状态、标题和按钮 tooltip。摘录：
  ```dart
  String _statusText = 'Opening FN Connect...';
  ...
  _statusText = 'Requesting FN Connect authorization...';
  ...
  title: Text('FN Connect: ${widget.fnConnectId}'),
  tooltip: 'Reload',
  ```
- 建议方向: 为这些状态/tooltip 增加 l10n getter；品牌名可作为参数保留，但完整 UI 文案不要硬编码。
- 状态: 已确认

### [G-032] Emby FN 入口登录页无条件放行 SSL 证书错误
- 级别: P0
- 分类: Bug / 安全
- 位置: lib/screens/emby_fn_entry_login_page.dart:100
- 问题: `EmbyFnEntryLoginPage` 的 WebView 遇到 SSL 证书错误时直接 `proceed()`；该页面会自动填充 FN 账号/密码并读取 `entry-token` cookie，证书异常时继续加载会带来凭据与入口令牌泄露风险。摘录：
  ```dart
  onSslAuthError: (error) => error.proceed(),
  ```
- 建议方向: 默认取消 SSL 错误并提示；如需支持自签证书，必须通过显式用户确认/可信主机白名单控制，且不能静默继续提交凭据。
- 状态: 已确认

### [G-033] Emby + FN Connect 入口协议细节泄漏到 screen
- 级别: P1
- 分类: 耦合 / 可扩展性 / 约束违规(C3)
- 位置: lib/screens/emby_fn_entry_login_page.dart:16
- 问题: 页面类和字段直接绑定 “Emby 服务 + FN Connect/fnos.net entry-token” 协议，screen 内硬编码 `fnos.net`/`5ddd.com` 域判断、`entry-token` cookie 提取和目标 Emby 主机校验；新增 Jellyfin 或调整入口网关协议时需要改 UI 页面。摘录：
  ```dart
  class EmbyFnEntryLoginPage extends StatefulWidget {
    final String serverUrl;
    final String userName;
    final String password;
  }
  ...
  pageHost == 'fnos.net' || pageHost == 'www.fnos.net' || pageHost == '5ddd.com';
  ```
- 建议方向: 将入口令牌获取策略下沉为后端登录 flow/adapter，screen 只承载通用 Web 登录容器和状态展示，后端差异由 adapter 提供 host/cookie/完成条件。
- 状态: 已确认

### [G-034] 两个 Web 登录页重复维护注入脚本和轮询逻辑
- 级别: P2
- 分类: 可维护性 / 约束违规(M2)
- 位置: lib/screens/emby_fn_entry_login_page.dart:115
- 问题: `EmbyFnEntryLoginPage` 与 `FnConnectWebLoginPage` 都内嵌一套 JS `autoLogin`、`autoAuthorize`、`setInterval` 轮询和 Flutter bridge post 逻辑；选择器、授权按钮文案、轮询间隔、失败吞异常策略需要双处同步，容易产生登录流程行为分叉。摘录：
  ```dart
  function autoLogin() { ... }
  function autoAuthorize() { ... }
  const timer = setInterval(() => {
    autoLogin();
    autoAuthorize();
    reportCookie();
  }, 750);
  ```
- 建议方向: 抽出共享 Web 登录 bridge/injection builder，由不同后端 flow 只配置完成条件、cookie 名和额外探测逻辑。
- 状态: 已确认

### [G-035] 播放宿主初始化在 async gap 后继续使用 context
- 级别: P1
- 分类: Bug / 约束违规(P7)
- 位置: lib/screens/player_host_screen.dart:105
- 问题: `_loadInitialArgs` 先 `await PlayerHostBridge.consumeInitialPlayerArgs()`，随后才调用 `_resolveRecoveredDownloadArgs`；后者在外部本地源恢复路径里直接 `context.read<NasProvider>()`。如果页面在第一次 await 后已卸载，仍可能用失效 context 读取 provider。摘录：
  ```dart
  final args = await _resolveRecoveredDownloadArgs(
    await PlayerHostBridge.consumeInitialPlayerArgs(),
  );
  ...
  provider: context.read<NasProvider>(),
  ```
- 建议方向: 拆开两次 await，在第一次 await 后先检查 `mounted`；或把 `NasProvider` 在 await 前取出并显式传入恢复函数。
- 状态: 已确认

### [G-036] 播放宿主初始参数加载失败会一直停留在转圈页
- 级别: P1
- 分类: Bug / 错误处理 / 约束违规(M4)
- 位置: lib/screens/player_host_screen.dart:105
- 问题: `_loadInitialArgs` 没有 `try/catch/finally`，`consumeInitialPlayerArgs`、下载记录恢复或续播位置解析任一步抛错时，`_loadingInitialArgs` 不会被置为 false，build 会一直显示 `CircularProgressIndicator`，也没有错误页或日志。摘录：
  ```dart
  Future<void> _loadInitialArgs() async {
    final args = await _resolveRecoveredDownloadArgs(
      await PlayerHostBridge.consumeInitialPlayerArgs(),
    );
    if (!mounted) return;
    setState(() {
      _loadingInitialArgs = false;
  ```
- 建议方向: 用 `try/catch/finally` 收敛初始化失败，至少落到 `_PlayerHostError` 并记录错误；`finally` 中保证 mounted 时退出 loading。
- 状态: 已确认

## 总结

- 本任务范围 29 个文件已完成第一轮逐文件评审与第二轮自复核，共记录 36 条，全部为已确认。
- 高优先级安全/数据风险：G-029、G-032 两个 WebView 登录页无条件放行 SSL 错误；G-012 书签删除/清空缺少确认或撤销。
- 高优先级性能风险：G-007 下载进度高频重建整页；G-015/G-016/G-017 截图图库存在原图解码、全量元数据读取和一次性构建问题。
- 多后端扩展阻塞集中在登录/统计：G-018/G-023/G-024/G-028/G-033 暴露 Feiniu/Emby/FN Connect 具体协议到 screen。
- 维护性重灾区：mpv 设置、下载管理、存储管理、截图预览、播放统计组件均超过拆分阈值，建议按页面宿主、flow、组件和 service adapter 分层拆分。
- 播放宿主需要优先处理 G-035/G-036，避免初始化 async gap 崩溃或首屏无限 loading。
