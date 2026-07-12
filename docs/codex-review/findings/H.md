<!-- CHECKPOINT
已审文件数: 75 / 75
最后完成: H-031
下一个: 无
阶段: 已完成
更新时间: 2026-07-02 23:05
-->

# TASK H findings

### [H-001] 底部面板仍保留真实模糊路径
- 级别: P1
- 分类: 性能 / 约束违规(P1)
- 位置: lib/widgets/detail/bottom_glass_panel.dart:29
- 问题: TASK H 明确要求清剿 `BackdropFilter` / `ImageFilter.blur`，但该公共底部面板仍在 `enableBlur && !isAndroid` 时启用大面积实时背景模糊：
  ```dart
  if (useBlur)
    Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: const SizedBox.expand(),
      ),
    ),
  ```
- 建议方向: 删除真实模糊路径，统一退回纯色/半透明实色面板；若调用方仍传 `enableBlur`，保留兼容参数但不再触发 `BackdropFilter`。
- 状态: 已确认

### [H-002] 简介组件仍有硬编码中文展示文案
- 级别: P2
- 分类: 可维护性 / 约束违规(M3)
- 位置: lib/widgets/detail/description_section.dart:24
- 问题: UI 展示文案没有走 `AppLocalizations` getter，而是在公共组件中硬编码中文 fallback 与操作文案：
  ```dart
  final content = text.trim().isEmpty ? '\u6682\u65E0\u7B80\u4ECB' : text;
  ...
  const suffix = '... ';
  const more = '\u66F4\u591A';
  ```
- 建议方向: 将“暂无简介”“更多”等展示文本迁入 arb，并由调用方或组件内通过 `AppLocalizations` 获取；省略号也应统一到本地化/排版策略中。
- 状态: 已确认

### [H-003] RichText 手势识别器在 build 中创建且未释放
- 级别: P0
- 分类: Bug / 性能 / 约束违规(P6)
- 位置: lib/widgets/detail/description_section.dart:101
- 问题: `TapGestureRecognizer` 是需要 `dispose()` 的对象，但这里在 `StatelessWidget.build` 中直接创建并挂到 `TextSpan`，组件没有任何释放路径，反复重建简介区域会持续分配识别器：
  ```dart
  TextSpan(
    text: more,
    style: moreStyle,
    recognizer: TapGestureRecognizer()..onTap = onMoreTap,
  ),
  ```
- 建议方向: 改为 `WidgetSpan` + `GestureDetector/InkWell`，或将组件改成 `StatefulWidget`，在 state 中持有并 dispose 识别器。
- 状态: 已确认

### [H-004] 演职员头像组件内泄漏后端鉴权差异
- 级别: P2
- 分类: 可扩展性 / 约束违规(C3)
- 位置: lib/widgets/detail/credits_section.dart:187
- 问题: UI 组件直接理解“NAS token”和 Emby `api_key` 自鉴权规则，并调用 `nasImageHeaders` 拼 header；后端鉴权差异没有收敛在 `media_backend`/解析层，后续新增 Jellyfin 等后端会继续把 URL 规则写进组件：
  ```dart
  final selfAuthenticated =
      hasUrl && widget.urls[_index].contains('api_key=');
  if (!hasUrl || (widget.token.trim().isEmpty && !selfAuthenticated)) {
  ...
  headers: nasImageHeaders(widget.token, url: widget.urls[_index]),
  ```
- 建议方向: 将头像 URL、headers、是否可匿名加载封装成中立图片引用/展示模型，组件只接收已解析好的 `ImageProvider` 或 `{url, headers}` 候选。
- 状态: 已确认

### [H-005] Hero logo 组件内重复判断后端鉴权规则
- 级别: P2
- 分类: 可扩展性 / 约束违规(C3)
- 位置: lib/widgets/detail/detail_hero_overlay.dart:156
- 问题: `DetailHeroLogoTitle` 直接把“飞牛 token”和 Emby `api_key` URL 规则写进 UI 组件，和头像组件形成重复的后端特判：
  ```dart
  final selfAuthenticated =
      hasUrl && widget.urls[_index].contains('api_key=');
  if (!hasUrl || (widget.token.trim().isEmpty && !selfAuthenticated)) {
    return _fallbackTitle(context);
  }
  ...
  headers: nasImageHeaders(widget.token, url: url),
  ```
- 建议方向: 在数据/适配层产出统一的 logo 图片候选及 headers，UI 只负责渲染候选和 fallback 标题，不解析后端认证语义。
- 状态: 已确认

### [H-006] Hero logo 网络图缺少解码尺寸约束
- 级别: P2
- 分类: 性能 / 约束违规(P3)
- 位置: lib/widgets/detail/detail_hero_overlay.dart:170
- 问题: logo 渲染虽然用 `ConstrainedBox` 限制显示尺寸，但 `Image.network` 未传 `cacheWidth/cacheHeight`，遇到较大的远端 logo 仍可能按原图解码：
  ```dart
  child: Image.network(
    url,
    fit: BoxFit.contain,
    alignment: Alignment.centerLeft,
    filterQuality: FilterQuality.medium,
    headers: nasImageHeaders(widget.token, url: url),
  ```
- 建议方向: 按 `maxWidth/maxHeight * devicePixelRatio` 计算受控 `cacheWidth/cacheHeight`，或改用统一图片引用构造器负责 resize。
- 状态: 已确认

### [H-007] 文件信息组件内写死飞牛 `/vol` 路径语义
- 级别: P2
- 分类: 可扩展性 / 约束违规(C3)
- 位置: lib/widgets/detail/file_info_section.dart:20
- 问题: 公共 UI 组件直接暴露 `/vol` toggle，并在 `_friendlyPath` 中解析飞牛路径格式；后端路径差异没有收敛在数据/适配层：
  ```dart
  /// 是否显示「/vol ↔ 友好路径」切换按钮。飞牛恒为 true；Emby 等公共后端路径无 /vol 概念，
  final bool showPathToggle;
  ...
  if (normalized.isEmpty || !normalized.startsWith('/vol')) {
    return normalized;
  }
  final rootMatch = RegExp(r'^/vol(\d+)/\d+').firstMatch(normalized);
  ```
- 建议方向: 将 raw/friendly path 的生成移到后端适配或 presenter，组件只渲染传入的文件信息行和可选切换项。
- 状态: 已确认

### [H-008] 链接区标题硬编码中文
- 级别: P2
- 分类: 可维护性 / 约束违规(M3)
- 位置: lib/widgets/detail/link_section.dart:29
- 问题: UI 展示文案没有走 `AppLocalizations`，公共详情组件中直接硬编码中文标题：
  ```dart
  Text(
    '\u94fe\u63a5',
    style: TextStyle(
      color: colors.textPrimary,
      fontSize: 20,
  ```
- 建议方向: 增加 `AppLocalizations.detailLinksTitle` 之类的 getter，或由调用方传入已本地化标题。
- 状态: 已确认

### [H-009] 沉浸式详情背景仍保留实时模糊渲染
- 级别: P1
- 分类: 性能 / 约束违规(P1)
- 位置: lib/widgets/detail/immersive_detail_background.dart:136
- 问题: TASK H 明确要求清剿 `BackdropFilter` / `ImageFilter.blur`，但该背景组件在 `enableRealtimeBlur` 且非 Android 时仍会启用 `ImageFiltered.blur` 和滚动联动 `BackdropFilter`：
  ```dart
  _blurImageLayer = enableGapBlur
      ? Opacity(
          opacity: 0.72,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
  ...
  if (effectiveSigma > 0.01)
    BackdropFilter(
      filter: ImageFilter.blur(
  ```
- 建议方向: 删除实时模糊分支，使用静态实色/渐变遮罩填补空隙和滚动状态；保留 `enableRealtimeBlur` 时也不应创建 blur layer。
- 状态: 已确认

### [H-010] 背景图组件内泄漏后端鉴权规则
- 级别: P2
- 分类: 可扩展性 / 约束违规(C3)
- 位置: lib/widgets/detail/immersive_detail_background.dart:379
- 问题: 背景图 UI 组件直接判断 Emby `api_key` 并调用 NAS header 工具，和 logo/头像组件重复同一套后端鉴权分支：
  ```dart
  final selfAuthenticated = currentUrl.contains('api_key=');
  if (!hasUrl || (token.trim().isEmpty && !selfAuthenticated)) {
    return Container(color: context.appColors.surface);
  }
  ...
  headers: nasImageHeaders(token, url: currentUrl),
  ```
- 建议方向: 将背景图候选与 headers 在后端适配/图片 resolver 中统一解析，UI 组件只消费中立图片引用。
- 状态: 已确认

### [H-011] 背景图错误回调可能在 dispose 后 setState
- 级别: P0
- 分类: Bug / 约束违规(P7)
- 位置: lib/widgets/detail/immersive_detail_background.dart:415
- 问题: `Image.network.errorBuilder` 注册 post-frame 回调后直接调用 `onErrorNext()`，而 `_nextFallbackImage()` 内部无 `mounted` 检查；如果图片错误和页面退出交叠，下一帧可能对已 dispose 的 State 调 `setState`：
  ```dart
  errorBuilder: (_, error, ___) {
    ...
    WidgetsBinding.instance.addPostFrameCallback((_) => onErrorNext());
    return Container(color: context.appColors.surface);
  }
  ...
  void _nextFallbackImage() {
    if (_index + 1 < widget.urls.length) {
      setState(() => _index += 1);
  ```
- 建议方向: 在 post-frame 回调或 `_nextFallbackImage()` 中检查 `mounted`，并在 URL/index 仍匹配当前请求时再推进 fallback。
- 状态: 已确认

### [H-012] 剧集简介“详情”识别器在 build 中创建且未释放
- 级别: P0
- 分类: Bug / 性能 / 约束违规(P6)
- 位置: lib/widgets/detail/tv_episode_browser_section.dart:784
- 问题: `_EpisodeSummaryLine` 是 `StatelessWidget`，但在 `RichText` 的 `TextSpan` 中直接创建 `TapGestureRecognizer`，没有 dispose 路径；剧集列表滚动/切换范围时会反复分配识别器：
  ```dart
  TextSpan(
    text: detailText,
    style: detailStyle,
    recognizer: TapGestureRecognizer()..onTap = onDetailTap,
  ),
  ```
- 建议方向: 使用 `WidgetSpan` 包一个可点击文本，或改为 stateful 持有并释放 recognizer。
- 状态: 已确认

### [H-013] 季详情面板构造参数过多
- 级别: P2
- 分类: 可维护性 / 组件 API 设计
- 位置: lib/widgets/detail/tv_season_detail_panel.dart:9
- 问题: `TvSeasonDetailPanel` 是详情公共组件，但构造器暴露 30 多个布局、状态、文案和回调参数，超过 TASK H “参数超过 ~8 个应改配置对象或拆分”的阈值，后续新增场景会继续扩大参数面：
  ```dart
  class TvSeasonDetailPanel extends StatelessWidget {
    final String title;
    final double titleFontSize;
    final String token;
    final Color? ambientTint;
    final List<String> posterUrls;
    final double posterWidth;
    final double posterCardHeight;
    final double posterBridgeOverlap;
  ```
- 建议方向: 拆成 `TvSeasonHeaderData`、`TvSeasonActions`、`TvSeasonLayoutMetrics` 等配置对象，或按 header/actions/content 分成更小组件。
- 状态: 已确认

### [H-014] 下载面板状态文案硬编码英文默认值
- 级别: P2
- 分类: 可维护性 / 约束违规(M3)
- 位置: lib/widgets/detail/tv_season_download_sheet.dart:61
- 问题: 下载状态文案作为 UI 展示文本，却在 payload/组件参数中提供英文默认值；调用方漏传时会绕过 `AppLocalizations` 直接显示英文：
  ```dart
  required this.downloadLabel,
  this.downloadingLabel = 'Downloading',
  this.downloadedLabel = 'Downloaded',
  this.pausedLabel = 'Paused',
  ...
  this.downloadingLabel = 'Downloading',
  this.downloadedLabel = 'Downloaded',
  this.pausedLabel = 'Paused',
  ```
- 建议方向: 移除英文默认值，要求调用方传入本地化文案，或在组件内部通过 `AppLocalizations` 解析默认状态标签。
- 状态: 已确认

### [H-015] 视频信息 UI 文件内包含飞牛 DTO 格式化逻辑
- 级别: P2
- 分类: 可扩展性 / 约束违规(C3)
- 位置: lib/widgets/detail/video_info_section.dart:27
- 问题: widgets/detail 公共 UI 文件直接暴露 `fromFeiniu` 工厂、依赖 `VideoStreamInfo/AudioTrackOption/SubtitleTrackOption`，并在同文件中实现飞牛字段格式化；公共组件出现后端专名和后端 DTO 假设：
  ```dart
  factory VideoInfoLines.fromFeiniu(
    VideoStreamInfo? video,
    AudioTrackOption? audio,
    SubtitleTrackOption? subtitle,
  ) {
    return VideoInfoLines(
      video: _feiniuVideoLine(video),
      audio: _feiniuAudioLine(audio),
  ```
- 建议方向: 将飞牛 DTO 到 `VideoInfoLines` 的转换迁到飞牛适配/presenter 层，UI 文件只保留中立 `VideoInfoLines` 与渲染组件。
- 状态: 已确认

### [H-016] 集合列表缩略图缺少解码尺寸约束
- 级别: P2
- 分类: 性能 / 约束违规(P3)
- 位置: lib/widgets/library/media_collection_browser.dart:213
- 问题: `_ListThumb` 显示尺寸只有 72x46，但 `Image.network` 没有传 `cacheWidth/cacheHeight`，列表滚动时可能按原图解码缩略图：
  ```dart
  return Image.network(
    urls.first,
    fit: BoxFit.cover,
    headers: nasImageHeaders(token, url: urls.first),
    errorBuilder: (_, __, ___) {
  ```
- 建议方向: 像 `media_library_list_tile.dart` 一样用 `LayoutBuilder + devicePixelRatio` 计算 `cacheWidth/cacheHeight`，或复用同一个缩略图组件。
- 状态: 已确认

### [H-017] 集合浏览组件内拼接后端图片 URL 与 NAS header
- 级别: P2
- 分类: 可扩展性 / 约束违规(C3)
- 位置: lib/widgets/library/media_collection_browser.dart:231
- 问题: `MediaCollectionBrowserSliver` 作为公共列表/网格组件，直接接收 `baseUrl/token`，用 `ApiUrlHelper.imageCandidates` 拼图片候选，并在缩略图里调用 `nasImageHeaders`；图片 URL 与鉴权规则泄漏到 UI 层：
  ```dart
  List<String> _posterCandidates(
    String baseUrl,
    MediaLibraryItem item, {
  ...
  (path) => ApiUrlHelper.imageCandidates(
    baseUrl,
    path,
    width: width,
  ```
- 建议方向: 在媒体后端/展示模型层预先生成中立图片候选和 headers，集合组件只接收可直接渲染的图片引用。
- 状态: 已确认

### [H-018] 媒体列表 tile 以空 token 判定图片不可加载
- 级别: P2
- 分类: 可扩展性 / 约束违规(C3)
- 位置: lib/widgets/library/media_library_list_tile.dart:139
- 问题: 独立列表 tile 只要 `token` 为空就直接显示占位，即使传入的是自鉴权直链也不会加载；公共组件把 NAS token 作为图片可用性的前置条件：
  ```dart
  if (urls.isEmpty || token.trim().isEmpty) {
    return Container(
      color: colors.surfaceStrong,
      alignment: Alignment.center,
  ...
  headers: nasImageHeaders(token, url: urls.first),
  ```
- 建议方向: 组件改为接收已解析的图片请求对象，或至少按 URL/header 是否可用判断，不把 NAS token 作为公共组件前置条件。
- 状态: 已确认

### [H-019] 自适应详情导航预取逻辑直接绑定 NasProvider
- 级别: P2
- 分类: 可扩展性 / 约束违规(C3)
- 位置: lib/ui/adaptive_detail_navigator.dart:223
- 问题: `lib/ui/` 的导航基建在 push 前预取 hero 图时直接读取 `NasProvider.baseUrl/token`，并把 NAS 参数传给 `DetailHeroImage`；多后端详情页无法在不改公共 UI 基建的情况下替换图片预取来源：
  ```dart
  final nas = context.read<NasProvider>();
  ...
  final provider = DetailHeroImage.fullPagePrecacheProvider(
    baseUrl: nas.baseUrl,
    backdropPath: backdrop,
    token: nas.token,
  ```
- 建议方向: 将预取所需的 `ImageProvider` 或中立图片引用放进 `AdaptiveDetailRequest`，由各后端/详情入口构造，导航层只负责触发预取。
- 状态: 已确认

### [H-020] 详情图源 resolver 放在 UI 层并内置飞牛/Emby 分支
- 级别: P2
- 分类: 可扩展性 / 约束违规(C3)
- 位置: lib/ui/detail_artwork_resolver.dart:21
- 问题: `lib/ui/` 下的图源解析器直接接收 NAS `baseUrl/token`，判断 http 直链与飞牛相对路径，并调用 `ApiUrlHelper.imageCandidates`/`nasImageHeaders`；后端图片差异没有收敛在 `media_backend`：
  ```dart
  class DetailArtworkResolver {
    /// 飞牛 NAS 基址,用于把相对路径拼成绝对 URL。Emby 直链不依赖它。
    final String baseUrl;
    /// 飞牛 NAS token,用于相对路径图的鉴权 header。Emby 直链不依赖它。
    final String token;
  ...
  final urls = ApiUrlHelper.imageCandidates(
  ```
- 建议方向: 将该 resolver 移到媒体后端/图片服务层，或让后端适配直接产出 `DetailArtwork`，UI 只渲染解析结果。
- 状态: 已确认

### [H-021] Hero 预取 helper 以 NAS token 作为可预取前提
- 级别: P2
- 分类: 可扩展性 / 约束违规(C3)
- 位置: lib/ui/detail_hero_image.dart:36
- 问题: `DetailHeroImage.provider/fullPagePrecacheProvider` 需要 `token` 且内部调用 `nasImageHeaders`，即使后端提供自鉴权直链也会因 token 为空跳过预取：
  ```dart
  static ImageProvider? provider({
    required String url,
    required String token,
    required int cacheWidth,
  }) {
    if (url.trim().isEmpty || token.trim().isEmpty) return null;
    return ResizeImage(
      NetworkImage(url, headers: nasImageHeaders(token, url: url)),
  ```
- 建议方向: 让调用方传入已构造好的 `ImageProvider`/headers，或把 token 判断替换为中立图片请求对象的可加载性判断。
- 状态: 已确认

### [H-022] MediaPosterCard 构造参数过多
- 级别: P2
- 分类: 可维护性 / 组件 API 设计
- 位置: lib/ui/media_poster_card.dart:9
- 问题: `MediaPosterCard` 是全 app 列表/网格基础件，但构造器混合图片、文本、评分、状态、布局、Hero、交互和 decode 参数，参数数已远超 TASK H 建议的 ~8 个阈值：
  ```dart
  class MediaPosterCard extends StatelessWidget {
    final List<String> urls;
    final String token;
    final String title;
    final String subtitle;
    final double? imageAspectRatioHint;
    final double? rating;
    final List<String> resolutions;
    final bool watched;
  ```
- 建议方向: 拆为 `MediaPosterCardData`、`MediaPosterImageConfig`、`MediaPosterActions` 等配置对象，降低调用方扩展新场景时继续加 flag/参数的压力。
- 状态: 已确认

### [H-023] MediaPosterCard 图片加载内置 NAS token/api_key 规则
- 级别: P2
- 分类: 可扩展性 / 约束违规(C3)
- 位置: lib/ui/media_poster_card.dart:322
- 问题: 基础海报卡内部直接判断 Emby `api_key`、NAS token，并用 `nasImageHeaders` 构造请求；后端图片鉴权规则泄漏进全 app 基础组件：
  ```dart
  final selfAuthenticated = activeUrl.contains('api_key=');
  if (!hasUrl || (widget.token.trim().isEmpty && !selfAuthenticated)) {
    return widget.fallback;
  }
  ...
  provider = NetworkImage(
    url,
    headers: nasImageHeaders(widget.token, url: url),
  );
  ```
- 建议方向: 让 `MediaPosterCard` 接收中立图片请求对象/`ImageProvider` 列表，后端适配层负责 URL 与 headers。
- 状态: 已确认

### [H-024] DetailHeroImage 组件内置 NAS token/api_key 规则
- 级别: P2
- 分类: 可扩展性 / 约束违规(C3)
- 位置: lib/ui/media_detail_components.dart:47
- 问题: 详情通用图片组件直接判断 `api_key=`、NAS token，并调用 `nasImageHeaders`；所有复用它的详情、剧集、下载缩略图都会继承这套后端假设：
  ```dart
  final selfAuthenticated = url.contains('api_key=');
  if (!isLocal && widget.token.trim().isEmpty && !selfAuthenticated) {
    return _buildPlaceholder();
  }
  ...
  headers: nasImageHeaders(widget.token, url: url),
  ```
- 建议方向: 将 `DetailHeroImage` 的入参改为图片请求/候选对象，后端适配层负责 headers 与自鉴权判断。
- 状态: 已确认

### [H-025] EQ 预设命名弹窗的 TextEditingController 未释放
- 级别: P0
- 分类: Bug / 约束违规(P6)
- 位置: lib/ui/mpv_audio_eq_advanced_panel.dart:201
- 问题: `_showPresetNameDialog` 中创建了 `TextEditingController`，但函数没有 `try/finally` 或 state dispose 释放它；每次保存预设弹窗都会泄漏 controller：
  ```dart
  Future<String?> _showPresetNameDialog(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
  ...
            controller: controller,
  ```
- 建议方向: 用 `try/finally` 包住 `await showDialog` 并在 finally 中 `controller.dispose()`，或抽成 stateful dialog 管理生命周期。
- 状态: 已确认

### [H-026] 主题预设标题仍通过英文 getter 展示
- 级别: P2
- 分类: 可维护性 / 约束违规(M3)
- 位置: lib/theme/app_theme.dart:16
- 问题: `AppThemePresetX.title` 和多处 provider/UI 调用链会把英文硬编码标题展示出来，绕过 arb；例如 `AppThemeL10n.currentThemeTitle` 仍返回 `provider.preset.title`：
  ```dart
  String get title => switch (this) {
    AppThemePreset.midnight => 'Midnight',
    AppThemePreset.ocean => 'Ocean',
    AppThemePreset.forest => 'Forest',
  ...
  AppThemeSourceType.preset => provider.preset.title,
  ```
- 建议方向: 为主题预设标题补齐 `AppLocalizations` getter，并让设置页、provider 展示名、recipe 文案统一走 `AppThemeL10n`。
- 状态: 已确认

### [H-027] DetailTokens 保留未引用的模糊/玻璃渐变常量
- 级别: P2
- 分类: 可维护性 / 约束违规(M5)
- 位置: lib/theme/detail_tokens.dart:36
- 问题: `headerMaxBlur`、`glassPanelGradient`、`glassPanelGradientOf` 仍保留在详情 token 中，但全库引用搜索只命中定义；这是玻璃/模糊回退后的死 token，容易让后续改动误以为仍可启用模糊方案：
  ```dart
  static const double headerMaxBlur = 30;
  ...
  static const LinearGradient glassPanelGradient = LinearGradient(
  ...
  static LinearGradient glassPanelGradientOf(BuildContext context) {
  ```
- 建议方向: 删除未引用的 blur/glass gradient token，或迁移为纯色面板 token 并重命名，避免继续暴露旧方案入口。
- 状态: 已确认

### [H-028] 玻璃质量配置仍声明可启用真实 BackdropFilter
- 级别: P1
- 分类: 性能 / 可维护性 / 约束违规(P1)
- 位置: lib/theme/glass_quality.dart:5
- 问题: 玻璃质量枚举仍公开 `liquid` 挡位和 `usesRealBlur`，注释说明会启用真实 `BackdropFilter`；但当前 `LiquidGlass` 已纯色化且全库未使用 `usesRealBlur`，该配置成为误导性的模糊回潮入口：
  ```dart
  /// - [liquid] 液态：关键面（导航/详情按钮/版本chip/弹层）启用真实 [BackdropFilter]
  ...
  enum LiquidGlassLevel { off, frosted, liquid }
  ...
  bool get usesRealBlur => this == LiquidGlassLevel.liquid;
  ```
- 建议方向: 移除 `liquid` 真模糊语义，或将其改名/降级为纯色视觉强度；设置项和存储迁移也应同步避免用户选到无效或危险模式。
- 状态: 已确认

### [H-029] 页级动态主题缓存持久化失败被静默吞掉
- 级别: P2
- 分类: 可维护性 / 约束违规(M4)
- 位置: lib/theme/dynamic_theme_runtime_controller.dart:267
- 问题: 页级 seed 缓存的读取和写入异常都只 `catch (_)` 后注释降级，没有日志、指标或可追踪信号；一旦 SharedPreferences 数据损坏或写入失败，动态主题会长期退回实时取色/内存缓存，用户只能感知到首帧抖动或缓存失效，开发侧无证据：
  ```dart
  } catch (_) {
    // Runtime cache restore failure should only fall back to live sampling.
  } finally {
    _persistentCacheLoaded = true;
  ...
  } catch (_) {
    // Keep the in-memory cache even if persistence is unavailable.
  }
  ```
- 建议方向: 至少通过统一日志/诊断通道记录 cache restore/persist 失败原因，并保留降级行为；必要时对损坏 payload 做清理，避免每次启动重复失败。
- 状态: 已确认

### [H-030] 动态取色层直接依赖 NAS 图片鉴权 helper
- 级别: P2
- 分类: 可扩展性 / 约束违规(C3)
- 位置: lib/theme/dynamic_theme_seed_extractor.dart:224
- 问题: 主题取色属于公共 theme 基建，但 extractor 直接接收 `token` 并调用 `nasImageHeaders` 拼图片请求头；这把飞牛/NAS 鉴权语义泄漏进主题层，后续 Emby/Jellyfin 或本地图片取色都要继续在 theme 文件里兼容后端差异：
  ```dart
  final palette = await PaletteGenerator.fromImageProvider(
    NetworkImage(imageUrl, headers: nasImageHeaders(token, url: imageUrl)),
    maximumColorCount: 24,
    size: const Size(220, 140),
  );
  ```
- 建议方向: 让调用方或 media backend 提供中立的图片取色请求对象（URL + headers/本地 provider），theme 层只负责从已解析的 `ImageProvider` 或抽象输入中提取颜色。
- 状态: 已确认

### [H-031] 动态取色失败被整体静默吞掉
- 级别: P2
- 分类: 可维护性 / 约束违规(M4)
- 位置: lib/theme/dynamic_theme_seed_extractor.dart:293
- 问题: `_extractUncached` 包住了原生取色、网络图片加载、PaletteGenerator 解析和 seed 计算，任何异常都直接返回 `null`，调用侧只能看到主题取色消失，无法区分网络失败、平台通道异常、图片解码失败还是算法异常：
  ```dart
  try {
    ...
    return DynamicThemeSeed(
      backgroundSeed: _backgroundSeedForHsl(...),
      ...
    );
  } catch (_) {
    return null;
  }
  ```
- 建议方向: 保留取色失败回退，但记录失败类型和图片 identity；原生通道失败、网络图片失败、palette 为空应拆成可观测的分支，便于定位动态主题失效。
- 状态: 已确认

## 总结

TASK H 共审完 75 个文件，记录 31 条问题，第二轮全部复核为已确认，无撤回项。
最优先处理的是 P0 资源/生命周期问题：H-003、H-011、H-012、H-025。
玻璃/模糊回潮仍有实际渲染路径与死配置入口：H-001、H-009、H-027、H-028。
多后端抽象泄漏集中在图片 URL/header/token/api_key 规则：H-004、H-005、H-010、H-017、H-018、H-019、H-020、H-021、H-023、H-024、H-030。
i18n 与公共组件 API 维护成本问题包括 H-002、H-008、H-013、H-014、H-022、H-026。
主题动态取色链路主要缺可观测性与后端中立输入：H-029、H-030、H-031。
