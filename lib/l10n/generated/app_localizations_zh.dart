// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Fly Player';

  @override
  String get globalLoadFailed => '加载失败';

  @override
  String get navMovies => '影视';

  @override
  String get navSettings => '设置';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsSearchTooltip => '搜索设置项';

  @override
  String get settingsLanguageTitle => '应用语言';

  @override
  String get settingsLanguageSubtitleSystem => '跟随系统';

  @override
  String get settingsLanguageSubtitleZhCN => '简体中文';

  @override
  String get languageSheetTitle => '应用语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get languageSystemSubtitle => '使用系统语言偏好';

  @override
  String get languageZhCN => '简体中文';

  @override
  String get languageZhCNSubtitle => '固定使用简体中文';

  @override
  String get commonCancel => '取消';

  @override
  String get commonConfirm => '确认';

  @override
  String get commonSave => '保存';

  @override
  String get commonRefreshRetry => '刷新重试';

  @override
  String get commonNone => '无';

  @override
  String get commonEmpty => '没有内容';

  @override
  String get commonNoData => '暂无数据';

  @override
  String get commonNoAccessLibrary => '没有可访问的媒体库，请联系管理员';

  @override
  String get authExitTitle => '退出登录';

  @override
  String get authExitContent => '确认退出当前帐号？';

  @override
  String get mediaAllItemsTitle => '全部影视';

  @override
  String get mediaLibraryFallbackName => '媒体库';

  @override
  String get collectionLayoutTitle => '布局方式';

  @override
  String get collectionLayoutSubtitle => '切换合集详情中的列表布局';

  @override
  String get collectionLayoutViewSection => '视图';

  @override
  String get collectionLayoutPosterWall => '海报墙';

  @override
  String get collectionLayoutList => '列表';

  @override
  String get collectionLayoutPosterSection => '海报';

  @override
  String get collectionLayoutHorizontalPoster => '横幅';

  @override
  String get collectionLayoutVerticalPoster => '竖幅';

  @override
  String collectionItemCount(int count) {
    return '共 $count 项';
  }

  @override
  String get localFileAuthorizeFirst => '请先授权一个文件夹，然后在应用内选择本地文件';

  @override
  String get localFileNoAuthorizedFolder => '还没有授权本地文件夹，先授权一个目录后才能在应用内浏览';

  @override
  String get localFileAuthorizationCanceled => '没有完成文件夹授权，无法读取本地文件';

  @override
  String get localFileAuthorizedFolderUnavailable => '已授权的目录当前不可访问，请重新授权文件夹';

  @override
  String get localFileReadDirectoryFailedRetry => '读取目录失败，请重新授权后重试';

  @override
  String localFileReadDirectoryFailed(Object error) {
    return '读取目录失败: $error';
  }

  @override
  String get localFileAuthorizeFolder => '授权文件夹';

  @override
  String get localFileChangeFolder => '更换文件夹';

  @override
  String get localFileParentDirectory => '返回上一级';

  @override
  String get localFileFolder => '文件夹';

  @override
  String get detailMoreActionsTitle => '更多操作';

  @override
  String get detailCurrentPage => '当前详情页';

  @override
  String get detailSaveCurrentTheme => '保存当前主题';

  @override
  String get detailSaveCurrentThemeSubtitle => '把当前取色保存成一套可复用的自定义主题';

  @override
  String get detailSaveCurrentThemeUnavailable => '当前页面还没有可保存的动态取色结果';

  @override
  String detailThemeSaved(Object name) {
    return '已保存主题：$name';
  }

  @override
  String get detailThemeNameLabel => '主题名称';

  @override
  String get detailThemeDescriptionLabel => '说明（可选）';

  @override
  String get detailThemeNameDuplicate => '主题名称不能重复';

  @override
  String get presetNameLabel => '名称';

  @override
  String get presetDescriptionLabel => '描述';

  @override
  String get presetNameRequired => '请输入名称';

  @override
  String get presetAutoFill => '自动填入';

  @override
  String get presetDescriptionHint => '可选，简单写一下这个预设的用途';

  @override
  String get audioSpecDolbySurround => '杜比环绕';

  @override
  String get audioSpecDolbyAtmos => '杜比全景声';

  @override
  String get audioSpecDts => 'DTS';

  @override
  String get audioSpecStereo => '立体声';

  @override
  String get resourceTypeDirectory => '目录';

  @override
  String get resourceTypeVideo => '视频';

  @override
  String get listFilterButton => '筛选';

  @override
  String get listFilterAll => '全部';

  @override
  String get listFilterResetButton => '重置';

  @override
  String get listFilterDecadeRecent => '今年';

  @override
  String get listTypeMovie => '电影';

  @override
  String get listTypeTv => '电视剧';

  @override
  String get listRecognitionUnmatched => '未匹配';

  @override
  String get listRecognitionMatched => '已匹配';

  @override
  String get listRecognitionNfo => 'NFO匹配';

  @override
  String get listWatched => '已观看';

  @override
  String get listUnwatched => '未观看';

  @override
  String get listFilterType => '影视分类';

  @override
  String get listFilterGenres => '类型';

  @override
  String get listFilterLocate => '国家和地区';

  @override
  String get listFilterDecade => '发行年份';

  @override
  String get listFilterResolution => '分辨率';

  @override
  String get listFilterColorRange => '视频动态范围';

  @override
  String get listFilterAudioType => '音频规格';

  @override
  String get listFilterRecognitionStatus => '匹配状态';

  @override
  String get listFilterWatched => '是否观看';

  @override
  String get listSortTitle => '排序';

  @override
  String get listSortCreateTime => '按添加日期';

  @override
  String get listSortReleaseDate => '按发行年份';

  @override
  String get listSortTitleField => '按标题';

  @override
  String get listSortVoteAverage => '按评分';

  @override
  String get listSortAsc => '升序';

  @override
  String get listSortDesc => '降序';

  @override
  String get searchHistory => '搜索历史';

  @override
  String searchResultCount(int count) {
    return '$count个搜索结果';
  }

  @override
  String get searchPlaceholder => '搜索';

  @override
  String personItemCount(int count) {
    return '共 $count 个作品';
  }

  @override
  String get personJobActor => '演员';

  @override
  String get personJobDirector => '导演';

  @override
  String get personJobScreenplay => '编剧';

  @override
  String get personJobWriter => '编剧';

  @override
  String get personJobProducer => '制片人';

  @override
  String personAsJob(Object job) {
    return '作为$job';
  }

  @override
  String get personBiographyTitle => '演员简介';

  @override
  String get routeErrorMissingDetail => '缺少详情参数';

  @override
  String get routeErrorMissingSeason => '缺少季详情参数';

  @override
  String get routeErrorMissingPerson => '缺少人物详情参数';

  @override
  String get routeErrorMissingDownload => '缺少下载详情参数';

  @override
  String get connectionAppName => '飞牛播放器';

  @override
  String get connectionUserNameHint => '用户名';

  @override
  String get connectionPasswordHint => '密码';

  @override
  String get connectionRememberLogin => '保持登录';

  @override
  String get connectionHttpsAccess => 'HTTPS 安全访问';

  @override
  String get connectionLogin => '登录';

  @override
  String get connectionOpenDownloads => '查看已下载数据';

  @override
  String get connectionLoginHistory => '登录历史';

  @override
  String get connectionClear => '清空';

  @override
  String get connectionNoLoginHistory => '暂无登录历史';

  @override
  String get connectionOperationFailedRetryLater => '操作失败，请稍后重试';

  @override
  String get connectionOperationFailedRetry => '操作失败，请重试';

  @override
  String get connectionServerRequired => '请输入服务器地址';

  @override
  String get connectionUserNameRequired => '请输入用户名';

  @override
  String get connectionPasswordRequired => '请输入密码';

  @override
  String get connectionInvalidCredential => '用户名或密码错误';

  @override
  String get connectionNetworkError => '网络异常，请检查后重试';

  @override
  String get connectionValidationFailed => '验证失败';

  @override
  String get settingsThemeTitle => '主题设置';

  @override
  String settingsThemeSubtitle(Object title, Object subtitle) {
    return '$title · $subtitle';
  }

  @override
  String get settingsThemeKeywords => '主题|配色|颜色|外观';

  @override
  String get settingsCustomThemeTitle => '自定义主题';

  @override
  String get settingsCustomThemeSubtitle => '已保存主题管理';

  @override
  String get settingsCustomThemeKeywords => '自定义主题|保存主题|主题管理';

  @override
  String get settingsCustomRecipeTitle => '颜色分类控制';

  @override
  String get settingsCustomRecipeSubtitle => '自定义主题配色编辑';

  @override
  String get settingsCustomRecipeLocation => '设置 > 主题设置 > 当前自定义';

  @override
  String get settingsCustomRecipeKeywords => '颜色分类|当前自定义|调色';

  @override
  String get settingsMpvTitle => 'MPV播放器设置';

  @override
  String get settingsMpvSubtitle => '播放器参数设置';

  @override
  String get settingsMpvKeywords => 'mpv|播放器|外部播放';

  @override
  String get settingsParallelWindowTitle => '并行窗口设置';

  @override
  String get settingsParallelWindowKeywords => '并行窗口|双屏|分屏';

  @override
  String get settingsParallelSummaryEnabledLeft => '已开启 · 左侧主屏';

  @override
  String get settingsParallelSummaryEnabledRight => '已开启 · 右侧主屏';

  @override
  String get settingsParallelSummaryDisabled => '已关闭 · 当前使用单屏模式';

  @override
  String get settingsDownloadTitle => '下载管理';

  @override
  String get settingsDownloadSubtitle => '已下载与下载中内容管理';

  @override
  String get settingsDownloadKeywords => '下载|下载管理|已下载|下载中|离线视频';

  @override
  String get settingsStorageTitle => '储存管理';

  @override
  String get settingsStorageSubtitle => '缓存、截图、日志与应用数据';

  @override
  String get settingsStorageKeywords => '储存管理|缓存|播放缓存|截图文件|应用数据|清理缓存';

  @override
  String get settingsPlayStatsTitle => '全局播放数据统计';

  @override
  String get settingsPlayStatsSubtitle => '本地播放统计与历史记录';

  @override
  String get settingsPlayStatsKeywords => '播放统计|播放历史|本地统计|sqlite';

  @override
  String get settingsOtherTitle => '其他';

  @override
  String get settingsOtherSubtitle => '书签、弹幕与截图设置';

  @override
  String get settingsOtherKeywords => '其他|辅助设置';

  @override
  String get settingsLogTitle => '日志信息';

  @override
  String get settingsLogSubtitle => '应用日志与导出';

  @override
  String get settingsLogKeywords => '日志|报错|txt|导出';

  @override
  String get settingsBookmarkTitle => '书签管理';

  @override
  String get settingsBookmarkSubtitle => '书签列表与定位';

  @override
  String get settingsBookmarkKeywords => '书签|bookmark';

  @override
  String get settingsDanmakuTitle => '弹幕设置';

  @override
  String get settingsDanmakuSubtitle => '默认样式与来源策略';

  @override
  String get settingsDanmakuKeywords => '弹幕|danmaku';

  @override
  String get settingsScreenshotTitle => '截图设置';

  @override
  String get settingsScreenshotSubtitle => '字幕携带和保存路径';

  @override
  String get settingsScreenshotKeywords => '截图|相册目录|保存路径';

  @override
  String get settingsScreenshotIncludeSubtitlesTitle => '截图是否携带字幕';

  @override
  String get settingsScreenshotIncludeSubtitlesSubtitle => '字幕携带选项';

  @override
  String get settingsScreenshotIncludeSubtitlesKeywords => '截图|字幕|携带字幕';

  @override
  String get settingsScreenshotSavePathTitle => '截图保存路径设置';

  @override
  String get settingsScreenshotSavePathSubtitle => '保存路径选项';

  @override
  String get settingsScreenshotSavePathKeywords => '截图|保存路径|相册目录';

  @override
  String get settingsScreenshotCustomDirectoryTitle => '截图自定义目录';

  @override
  String get settingsScreenshotCustomDirectorySubtitle => '自定义目录管理';

  @override
  String get settingsScreenshotCustomDirectoryKeywords => '截图|自定义目录|文件夹';

  @override
  String get settingsScreenshotPreviewTitle => '截图预览';

  @override
  String get settingsScreenshotPreviewSubtitle => '已保存截图管理';

  @override
  String get settingsScreenshotPreviewKeywords => '截图|预览|删除截图|管理截图';

  @override
  String get settingsMpvQuickModeTitle => 'MPV 快速模式';

  @override
  String get settingsMpvQuickModeSubtitle => '快捷预设与模式切换';

  @override
  String get settingsMpvQuickModeKeywords => 'mpv|快速模式|高保真|极速模式';

  @override
  String get settingsMpvPictureTitle => 'MPV 画面调节';

  @override
  String get settingsMpvPictureSubtitle => '滤镜、HDR、插帧与即时调节';

  @override
  String get settingsMpvPictureKeywords => 'mpv|画面|hdr|插帧|滤镜';

  @override
  String get settingsMpvAudioTitle => 'MPV 音频调节';

  @override
  String get settingsMpvAudioSubtitle => 'EQ、限幅、低音增强与人声增强';

  @override
  String get settingsMpvAudioKeywords => 'mpv|音频|eq|高保真|限幅';

  @override
  String get settingsMpvPlaybackTitle => 'MPV 播放与缓存';

  @override
  String get settingsMpvPlaybackSubtitle => '同步模式、缓存策略与缓存大小';

  @override
  String get settingsMpvPlaybackKeywords => 'mpv|缓存|缓冲|同步';

  @override
  String get settingsMpvCompatibilityTitle => 'MPV 兼容与诊断';

  @override
  String get settingsMpvCompatibilitySubtitle => '兼容模式和播放器诊断信息';

  @override
  String get settingsMpvCompatibilityKeywords => 'mpv|兼容|诊断|播放信息';

  @override
  String get settingsLocationRoot => '设置';

  @override
  String get settingsLocationTheme => '设置 > 主题设置';

  @override
  String get settingsLocationOther => '设置 > 其他';

  @override
  String get settingsLocationScreenshot => '设置 > 其他 > 截图设置';

  @override
  String get settingsLocationMpv => '设置 > MPV播放器设置';

  @override
  String settingsLocationMpvWithSection(Object section) {
    return '设置 > MPV播放器设置 > $section';
  }

  @override
  String get settingsMpvPictureSection => '画面调节';

  @override
  String get settingsMpvAudioSection => '音频调节';

  @override
  String get settingsMpvPlaybackSection => '播放与缓存';

  @override
  String get settingsMpvCompatibilitySection => '兼容与诊断';

  @override
  String get settingsSearchResults => '搜索结果';

  @override
  String get settingsSearchFrequent => '常用入口';

  @override
  String get settingsSearchHint => '搜索设置项';

  @override
  String get settingsSearchEmptyResults => '没有找到相关设置项。';

  @override
  String get settingsSearchEmptyPrompt => '先输入关键字，或从常用入口开始。';

  @override
  String get mpvContinueEnable => '继续开启';

  @override
  String get mpvGenericSettingTitle => '调节项';

  @override
  String get mpvPictureCategorySubtitle => '滤镜、渲染、HDR 与插帧';

  @override
  String get mpvPictureCategoryDescription => '围绕画面观感的细项调节，适合按片源逐步细调。';

  @override
  String get mpvAudioCategorySubtitle => '音量、EQ、增强与声道混合';

  @override
  String get mpvAudioCategoryDescription => '音频处理、高保真模式与声道输出设置。';

  @override
  String get mpvPlaybackCategorySubtitle => '同步模式、缓存策略与缓存大小';

  @override
  String get mpvPlaybackCategoryDescription => '主要影响拖动响应、缓存强度和播放稳定性。';

  @override
  String get mpvCompatibilityCategorySubtitle => '兼容模式与诊断';

  @override
  String get mpvCompatibilityCategoryDescription => '兼容性回退与播放诊断。';

  @override
  String get mpvSettingDebandTitle => '去色带';

  @override
  String get mpvSettingDebandSubtitle => '处理渐变断层和暗部条带。';

  @override
  String get mpvSettingSharpenTitle => '锐化';

  @override
  String get mpvSettingSharpenSubtitle => '提升线条和边缘清晰度。';

  @override
  String get mpvSettingDenoiseTitle => '降噪';

  @override
  String get mpvSettingDenoiseSubtitle => '压制噪点和颗粒感。';

  @override
  String get mpvSettingDeinterlaceTitle => '反交错';

  @override
  String get mpvSettingDeinterlaceSubtitle => '适配隔行扫描片源。';

  @override
  String get mpvSettingScaleProfileTitle => '缩放算法';

  @override
  String get mpvSettingScaleProfileSubtitle => '控制放大和缩小时的取向。';

  @override
  String get mpvSettingHdrModeTitle => 'HDR 处理';

  @override
  String get mpvSettingHdrModeSubtitle => '调整 HDR 映射和整体亮度取向。';

  @override
  String get mpvSettingFrameInterpolationTitle => '插帧';

  @override
  String get mpvSettingFrameInterpolationSubtitle => '提升运动流畅度，性能开销更高。';

  @override
  String get mpvSettingVideoSyncTitle => '同步模式';

  @override
  String get mpvSettingVideoSyncSubtitle => '控制音画同步与刷新率优先级。';

  @override
  String get mpvSettingCacheProfileTitle => '缓存策略';

  @override
  String get mpvSettingCacheProfileSubtitle => '按片源和网络环境切换缓存风格。';

  @override
  String get mpvSettingCacheSizeTitle => '缓存大小';

  @override
  String get mpvSettingCacheSizeSubtitle => '单独调整最大预读缓存上限。';

  @override
  String get mpvSettingVolumeGainTitle => '音量放大';

  @override
  String get mpvSettingVolumeGainSubtitle => '提高偏小声音源的输出上限。';

  @override
  String get mpvSettingAudioHighFidelityTitle => '高保真模式';

  @override
  String get mpvSettingAudioHighFidelitySubtitle => '优先保持干净解码输出，旁路大部分后处理。';

  @override
  String get mpvSettingDynamicRangeTitle => '动态范围压缩';

  @override
  String get mpvSettingDynamicRangeSubtitle => '让对白更靠前，夜间播放更稳。';

  @override
  String get mpvSettingAudioEqTitle => 'EQ 均衡器';

  @override
  String get mpvSettingAudioEqSubtitle => '调整低频、中频和高频的听感平衡。';

  @override
  String get mpvSettingAudioLimiterTitle => '峰值限幅';

  @override
  String get mpvSettingAudioLimiterSubtitle => '抑制突发峰值，避免爆音。';

  @override
  String get mpvSettingAudioBassBoostTitle => '低音增强';

  @override
  String get mpvSettingAudioBassBoostSubtitle => '增强低频氛围和下潜感。';

  @override
  String get mpvSettingAudioVoiceEnhanceTitle => '人声增强';

  @override
  String get mpvSettingAudioVoiceEnhanceSubtitle => '提升对白和人声清晰度。';

  @override
  String get mpvSettingChannelMixTitle => '声道混合';

  @override
  String get mpvSettingChannelMixSubtitle => '控制多声道输出的下混方式。';

  @override
  String get mpvSettingCompatibilityTitle => '兼容模式';

  @override
  String get mpvSettingCompatibilitySubtitle => '遇到异常时优先回退到更稳妥方案。';

  @override
  String get mpvCurrentSchemeTitle => '当前方案';

  @override
  String get mpvSmartRecommendationTitle => '智能推荐';

  @override
  String get mpvSmartRecommendationSubtitle =>
      '根据当前片源的分辨率、码率、HDR 和音轨信息推荐更合适的场景预设';

  @override
  String get mpvNoRecommendationTitle => '当前没有推荐';

  @override
  String get mpvNoRecommendationDescription => '当前片源信息还不完整，先保留手动选择。';

  @override
  String get mpvPictureQuickPresetTitle => '画质快速预设';

  @override
  String get mpvPictureQuickPresetSubtitle => '快速套用动画、影院、流畅等画质方案';

  @override
  String get mpvPictureQuickPresetDescription =>
      '这里只放画面相关方案，音频增强已经拆到独立的音频快速预设。';

  @override
  String get mpvAudioQuickPresetTitle => '音频快速预设';

  @override
  String get mpvAudioQuickPresetSubtitle => '高保真、EQ、低音增强、人声增强一键切换';

  @override
  String get mpvAudioQuickPresetDescription =>
      '一键切换高保真、对白增强、低频氛围和夜间压缩，不再和画质预设混在一起。';

  @override
  String get mpvCustomManagementTitle => '自定义管理';

  @override
  String get mpvCustomManagementSubtitle => '把画质自定义、音频自定义和即时调节统一收进三级页面管理';

  @override
  String get mpvCustomManagementDescription =>
      '首页只保留快速预设；即时调节、分类细调和保存当前预设都统一收进这里。';

  @override
  String get mpvPictureCustomTitle => '画质自定义';

  @override
  String get mpvPictureCustomSubtitle => '即时调节、滤镜、渲染、HDR、插帧、同步、缓存和兼容项';

  @override
  String get mpvPictureCustomDescription =>
      '即时调节和所有画质相关细项都统一放在这里管理，保存后会生成独立画质预设。';

  @override
  String get mpvAudioCustomTitle => '音频自定义';

  @override
  String get mpvAudioCustomSubtitle => '高保真、音量增强、EQ、限幅、低音增强、人声增强和声道混合';

  @override
  String get mpvAudioCustomDescription =>
      '把高保真、EQ、音量增强和所有音频后处理统一放在这里管理，保存后会生成独立音频预设。';

  @override
  String get mpvSaveCurrentPictureTitle => '保存当前画质';

  @override
  String get mpvSaveCurrentPictureSubtitle => '把当前即时调节和画质增强另存为独立预设';

  @override
  String get mpvSaveCurrentAudioTitle => '保存当前音频';

  @override
  String get mpvSaveCurrentAudioSubtitle => '把当前音频增强和 EQ 另存为独立预设';

  @override
  String get mpvInstantAdjustTitle => '即时调节';

  @override
  String get mpvInstantAdjustSubtitle => '亮度、对比度、饱和度、Gamma、色相';

  @override
  String get mpvSavedPicturePreset => '已保存画质预设';

  @override
  String get mpvSavedAudioPreset => '已保存音频预设';

  @override
  String get mpvCurrentCustom => '当前自定义';

  @override
  String get mpvNotUsed => '未使用';

  @override
  String get mpvDefault => '默认';

  @override
  String get mpvAllDefault => '全部默认';

  @override
  String mpvChangedCount(int count) {
    return '已调整 $count 项';
  }

  @override
  String get mpvSavedPresetKindPicture => '画质';

  @override
  String get mpvSavedPresetKindAudio => '音频';

  @override
  String mpvPresetNameLabel(Object kind) {
    return '$kind预设名称';
  }

  @override
  String mpvPresetDuplicateName(Object kind) {
    return '$kind预设名称不能重复';
  }

  @override
  String mpvPresetSavedMessage(Object kind, Object name) {
    return '已保存$kind预设：$name';
  }

  @override
  String mpvPresetDefaultBaseName(Object kind) {
    return '$kind预设';
  }

  @override
  String mpvPresetRenameTitle(Object kind) {
    return '重命名$kind预设';
  }

  @override
  String get commonRemarkOptional => '备注（可选）';

  @override
  String get commonDescriptionOptional => '说明（可选）';

  @override
  String get mpvPicturePresetOffLabel => '默认';

  @override
  String get mpvPicturePresetOffDescription => '关闭额外画质增强，优先保证兼容性和稳定性。';

  @override
  String get mpvPicturePresetAnimeLabel => '动画清晰';

  @override
  String get mpvPicturePresetAnimeDescription =>
      '通过轻微对比度和饱和度调整突出线条感，不再默认带入重滤镜。';

  @override
  String get mpvPicturePresetCinemaLabel => '影院柔和';

  @override
  String get mpvPicturePresetCinemaDescription => '用较轻的亮暗和饱和调整偏向影院观感，避免额外画面计算。';

  @override
  String get mpvPicturePresetSmoothLabel => '流畅优先';

  @override
  String get mpvPicturePresetSmoothDescription => '偏向稳定和响应的轻量流畅方案，不再默认带入插帧。';

  @override
  String get mpvAudioPresetOffLabel => '默认';

  @override
  String get mpvAudioPresetOffDescription => '关闭额外音频增强，保留基础播放参数。';

  @override
  String get mpvAudioPresetHiFiLabel => '原声保真';

  @override
  String get mpvAudioPresetHiFiDescription => '打开高保真，旁路 EQ 和增强，适合耳机和高质量片源。';

  @override
  String get mpvAudioPresetBalancedLabel => '通用增强';

  @override
  String get mpvAudioPresetBalancedDescription =>
      '轻度提亮人声和低频，适合大多数普通剧集、综艺和日常看片。';

  @override
  String get mpvAudioPresetDialogueLabel => '人声清晰';

  @override
  String get mpvAudioPresetDialogueDescription => '抬前对白和中高频细节，适合台词偏轻的片源。';

  @override
  String get mpvAudioPresetSpeakerClearLabel => '外放清晰';

  @override
  String get mpvAudioPresetSpeakerClearDescription =>
      '针对手机和平板外放，压住爆点、把对白往前推，减少糊成一团。';

  @override
  String get mpvAudioPresetCinemaBassLabel => '影院低频';

  @override
  String get mpvAudioPresetCinemaBassDescription => '增强低频氛围和厚度，适合动作片、配乐片和外放。';

  @override
  String get mpvAudioPresetHeadphoneImmersiveLabel => '耳机沉浸';

  @override
  String get mpvAudioPresetHeadphoneImmersiveDescription =>
      '保留动态感，补一点氛围和厚度，适合耳机听电影和演唱会现场。';

  @override
  String get mpvAudioPresetNightLabel => '夜间均衡';

  @override
  String get mpvAudioPresetNightDescription => '压低爆点、抬前对白，适合深夜外放和追剧。';

  @override
  String get mpvScenePresetStableClearLabel => '省电稳定';

  @override
  String get mpvScenePresetStableClearDescription =>
      '优先照顾解码稳定和系统流畅度，适合 4K、HDR、HEVC 和高码率片源。';

  @override
  String get mpvScenePresetBalancedMovieLabel => '通用观影';

  @override
  String get mpvScenePresetBalancedMovieDescription =>
      '用轻量画质和通用增强音频组成的日常观影片方案，适合大多数普通片源。';

  @override
  String get mpvScenePresetAnimeDialogueLabel => '追番对白';

  @override
  String get mpvScenePresetAnimeDialogueDescription =>
      '保留动画线条感并把对白往前提，适合动画、综艺和日常追番。';

  @override
  String get mpvScenePresetSpeakerClearLabel => '外放清晰';

  @override
  String get mpvScenePresetSpeakerClearDescription =>
      '优先照顾手机和平板外放，把爆点压住并把对白往前推。';

  @override
  String get mpvScenePresetNightBingeLabel => '夜间追剧';

  @override
  String get mpvScenePresetNightBingeDescription =>
      '偏向稳定和夜间聆听，压低爆点并减少长时间观看的刺耳感。';

  @override
  String get mpvScenePresetHeadphoneImmersiveLabel => '耳机沉浸';

  @override
  String get mpvScenePresetHeadphoneImmersiveDescription =>
      '画面保持轻柔层次，耳机下保留氛围感和低频厚度。';

  @override
  String get mpvSceneRecommendationStableTitle => '推荐稳定优先';

  @override
  String get mpvSceneRecommendationStableReason =>
      '当前片源负载偏高，建议先用更稳的轻量场景，避免播放器和系统一起掉帧。';

  @override
  String get mpvSceneRecommendationImmersiveTitle => '推荐电影沉浸';

  @override
  String get mpvSceneRecommendationImmersiveReason =>
      '当前音轨更适合保留氛围感和低频厚度的电影向组合。';

  @override
  String get mpvSceneRecommendationSpeakerTitle => '推荐清晰外放';

  @override
  String get mpvSceneRecommendationSpeakerReason =>
      '当前音轨偏轻，优先把对白和主体声推前，普通剧集和外放更省心。';

  @override
  String get mpvSceneRecommendationBalancedTitle => '推荐通用观影';

  @override
  String get mpvSceneRecommendationBalancedReason =>
      '当前片源负载正常，先用平衡一些的画质和音频组合最稳妥。';

  @override
  String get mpvVideoAdjustGenericTitle => '画面参数';

  @override
  String get mpvVideoAdjustBrightnessTitle => '亮度';

  @override
  String get mpvVideoAdjustBrightnessSubtitle => '提亮暗场或压暗过曝画面。';

  @override
  String get mpvVideoAdjustContrastTitle => '对比度';

  @override
  String get mpvVideoAdjustContrastSubtitle => '拉开明暗层次，数值过高会让高光和阴影更硬。';

  @override
  String get mpvVideoAdjustSaturationTitle => '饱和度';

  @override
  String get mpvVideoAdjustSaturationSubtitle => '控制整体颜色浓度。';

  @override
  String get mpvVideoAdjustGammaTitle => 'Gamma';

  @override
  String get mpvVideoAdjustGammaSubtitle => '偏向中间调修正，适合微调灰雾感和暗部层次。';

  @override
  String get mpvVideoAdjustHueTitle => '色相';

  @override
  String get mpvVideoAdjustHueSubtitle => '整体色调偏移，建议小幅调整，用来修正偏色片源。';

  @override
  String get mpvVideoAdjustStatusTitle => '画面参数';

  @override
  String get mpvVideoAdjustDescription =>
      '这些值会直接写入 mpv 的亮度、对比度、饱和度、Gamma 和色相参数，并会一起保存到画质预设中。';

  @override
  String get mpvVideoAdjustDrawerDescription =>
      '这些参数直接对应 mpv 原生视频均衡项，适合播放中微调，不会像 HDR 或插帧那样频繁触发重载。';

  @override
  String get mpvVideoAdjustAllDefaultSummary => '亮度、对比度、饱和度、Gamma 和色相都保持在默认值。';

  @override
  String get mpvOptionOff => '关闭';

  @override
  String get mpvOptionOn => '开启';

  @override
  String get mpvOptionAuto => '自动';

  @override
  String get mpvOptionLow => '轻度';

  @override
  String get mpvOptionMedium => '标准';

  @override
  String get mpvOptionStrong => '标准';

  @override
  String get mpvOptionFast => '快速';

  @override
  String get mpvOptionBalanced => '标准';

  @override
  String get mpvOptionQuality => '高质量';

  @override
  String get mpvOptionForce => '强制开启';

  @override
  String get mpvOptionSdrMap => 'SDR 映射';

  @override
  String get mpvOptionConservative => '保守映射';

  @override
  String get mpvOptionEnhanced => '增强映射';

  @override
  String get mpvOptionAudio => '音频优先';

  @override
  String get mpvOptionDisplay => '显示优先';

  @override
  String get mpvOptionSmooth => '平滑同步';

  @override
  String get mpvOptionDefault => '智能分配';

  @override
  String get mpvOptionLowLatency => '极速响应';

  @override
  String get mpvOptionStable => '稳定缓冲';

  @override
  String get mpvOptionNetwork => '网盘 / STRM / NAS';

  @override
  String get mpvOptionLight => '轻度';

  @override
  String get mpvOptionSoft => '柔和';

  @override
  String get mpvOptionClarity => '清晰';

  @override
  String get mpvOptionCinema => '影院';

  @override
  String get mpvOptionCustom => '高级自定义';

  @override
  String get mpvOptionStereo => '立体声优先';

  @override
  String get mpvOptionSurround => '环绕优先';

  @override
  String get mpvOptionSoftwareFallback => '软件优先';

  @override
  String get commonOk => '知道了';

  @override
  String get commonEnter => '进入';

  @override
  String get commonView => '查看';

  @override
  String get commonRename => '重命名';

  @override
  String get commonDelete => '删除';

  @override
  String get commonClear => '清空';

  @override
  String get commonJump => '跳转';

  @override
  String get playerAbLoopPoint => 'A点';

  @override
  String get playerAbLoopUnavailable => '当前时长不足，无法设置 A-B 循环';

  @override
  String playerAbLoopPointSet(Object position) {
    return 'A 点已设置到 $position';
  }

  @override
  String get playerAbLoopMinimumSpan => 'A-B 间隔至少需要 0.8 秒';

  @override
  String playerAbLoopSet(Object start, Object end) {
    return 'A-B 循环已设置 $start - $end';
  }

  @override
  String get playerAbLoopCleared => 'A-B 循环已清除';

  @override
  String get playerBookmarkNone => '无书签';

  @override
  String playerBookmarkCount(int count) {
    return '$count 个';
  }

  @override
  String get playerBookmarkEmptySummary => '为当前片段记录关键时间点，之后可以快速跳回。';

  @override
  String playerBookmarkRecentSummary(Object position, int count) {
    return '最近书签 $position，共 $count 个。';
  }

  @override
  String get playerBookmarkNoteDialogTitle => '添加书签备注';

  @override
  String playerBookmarkAdded(Object position) {
    return '已添加书签 $position';
  }

  @override
  String get playerBookmarkDeleted => '已删除书签';

  @override
  String get playerBookmarkCleared => '当前片段书签已清空';

  @override
  String playerBookmarkJumped(Object position) {
    return '已跳转到 $position';
  }

  @override
  String get playerBookmarkTitle => '书签';

  @override
  String get playerBookmarkAddCurrent => '添加当前';

  @override
  String get playerBookmarkCurrentSegment => '当前片段';

  @override
  String get playerBookmarkEmptyPrompt => '还没有书签，点击右上角“添加当前”即可记录当前时间点。';

  @override
  String playerBookmarkCreatedAt(Object time) {
    return '创建于 $time';
  }

  @override
  String get playerEpisodeList => '剧集列表';

  @override
  String get playerEpisodeSpecialSeason => '特别篇';

  @override
  String playerEpisodeSeasonTemplate(Object season) {
    return '第$season季';
  }

  @override
  String get playerEpisodePlaying => '播放中..';

  @override
  String get playerEpisodeWatched => '已观看';

  @override
  String playerEpisodeWatchedPercent(Object percent) {
    return '已观看$percent%';
  }

  @override
  String get playerEpisodeUnwatched => '未观看';

  @override
  String get playerEpisodePickerTitle => '选集';

  @override
  String get playerEpisodeLast => '已经是最后一集了';

  @override
  String get playerEpisodeFirst => '已经是第一集了';

  @override
  String get playerEpisodeViewSaveFailed => '选集视图保存失败';

  @override
  String get playerEpisodeNoAvailableList => '当前片源没有可用选集列表';

  @override
  String playerEpisodeLoadListFailed(Object error) {
    return '加载选集列表失败: $error';
  }

  @override
  String playerEpisodeLoadSeasonFailed(Object error) {
    return '加载该季选集失败: $error';
  }

  @override
  String playerEpisodeNumberLabel(int episode) {
    return '第 $episode 集';
  }

  @override
  String get playerEpisodePreparingPlayback => '正在准备播放...';

  @override
  String playerEpisodeSwitchingTo(Object episode) {
    return '正在切换到 $episode...';
  }

  @override
  String get playerSubtitleLanguageEnglish => '英文';

  @override
  String get playerSubtitleLanguageChinese => '中文';

  @override
  String get playerSubtitleClosing => '正在关闭字幕...';

  @override
  String playerSubtitleSwitching(Object title, Object suffix) {
    return '正在切换到$title$suffix 字幕...';
  }

  @override
  String get playerSubtitleClosingPleaseWait => '正在为您关闭字幕，请稍等...';

  @override
  String playerSubtitleSwitchingPleaseWait(Object title, Object suffix) {
    return '正在为您切换至$title$suffix 字幕，请稍等...';
  }

  @override
  String get playerSubtitleUnknownTrack => '未知字幕';

  @override
  String get playerSubtitleExternal => '外挂';

  @override
  String get playerSubtitleFileFallbackApplied => '当前字幕文件不可直接获取，已切换兼容方案';

  @override
  String playerSubtitleLoadFailed(Object error) {
    return '字幕加载失败: $error';
  }

  @override
  String get playerAudioUnknownTrack => '未知音轨';

  @override
  String get playerQualityOriginal => '原画';

  @override
  String get playerQualityGeneric => '清晰度';

  @override
  String get playerLoadingPreparingEnvironment => '正在准备播放环境...';

  @override
  String get playerLoadingInitializingPlayer => '正在初始化播放器...';

  @override
  String get playerLoadingPreparingSource => '正在准备播放源...';

  @override
  String get playerLoadingBuffering => '视频缓冲中...';

  @override
  String get playerLoadingSeeking => '正在定位播放进度...';

  @override
  String get playerLoadingOpeningSource => '正在打开播放源...';

  @override
  String get playerLoadingPreparingVideo => '正在准备画面...';

  @override
  String get playerLoadingVideo => '视频加载中...';

  @override
  String get mpvNoSavedPicturePresetTitle => '暂无已保存画质预设';

  @override
  String get mpvNoSavedPicturePresetContent => '可在“画质自定义”中保存预设。';

  @override
  String get mpvNoSavedAudioPresetTitle => '暂无已保存音频预设';

  @override
  String get mpvNoSavedAudioPresetContent => '可在“音频自定义”中保存预设。';

  @override
  String get mpvPresetManagementStatus => '预设管理';

  @override
  String get mpvPresetManagementSummary => '画质自定义、音频自定义与已保存预设管理。';

  @override
  String get mpvSavedPresetDefaultDescription => '已保存的独立预设，可随时再次应用。';

  @override
  String get mpvPresetApplied => '当前已应用';

  @override
  String get mpvTapToApply => '点按应用';

  @override
  String get mpvVideoFiltersCategoryTitle => '视频滤镜';

  @override
  String get mpvVideoFiltersCategorySubtitle => '去色带、锐化、降噪、反交错、缩放算法';

  @override
  String get mpvVideoFiltersCategoryDescription => '主要针对画面净化、边缘锐度和缩放观感。';

  @override
  String get mpvPlayerDiagnosticsTitle => '播放器诊断信息';

  @override
  String get mpvPlayerDiagnosticsSubtitle => '查看当前 codec、输出、色彩和源信息';

  @override
  String get mpvCacheSettingStatusTitle => '缓存设定';

  @override
  String get mpvCacheSettingAutoDescription =>
      '当前由缓存策略自动分配上限。关闭自动后，可直接拖动滑杆控制缓存百分比。';

  @override
  String get mpvCacheSettingManualDescription =>
      '缓存百分比越高，越有利于高码率和不稳定网络，但也会占用更多内存和存储。';

  @override
  String get mpvCacheAutoSwitchTitle => '自动缓存';

  @override
  String get mpvCacheAutoSwitchAutoSubtitle => '当前由缓存策略自动分配缓冲上限';

  @override
  String get mpvCacheAutoSwitchManualSubtitle => '关闭后可手动指定缓存百分比';

  @override
  String get mpvCacheSliderTitle => '滑动设定';

  @override
  String get mpvCacheSliderSubtitle => '拖动滑杆调整缓存百分比，修改后会立即应用到当前播放器。';

  @override
  String mpvCachePercentSettingLabel(Object value) {
    return '缓存设定：$value';
  }

  @override
  String get mpvCacheHelpDefaultContent =>
      '自动档。播放器会根据片源类型决定更合适的缓冲强度，本地文件更偏常规，较重的网络片源会自动偏向更稳的缓冲。';

  @override
  String get mpvCacheHelpLowLatencyContent =>
      '预读最轻，拖动、切换和回填最快，但抗抖动最弱。更适合本地视频，或者局域网很稳时追求跟手感。';

  @override
  String get mpvCacheHelpStableContent =>
      '中等偏重缓冲，优先减少抖动导致的卡顿。拖动响应会比极速慢一点，但更适合大多数 NAS、网盘和 STRM 观看。';

  @override
  String get mpvCacheHelpNetworkContent =>
      '最重的一档，给高码率网盘、STRM 和 NAS 片源更多预读空间。起播和拖动后的回填更重，但最抗波动。';

  @override
  String get mpvCacheHelpGenericContent => '当前选项用于控制预读力度和缓冲风格。';

  @override
  String get mpvCacheHelpDefaultExtra => '适合：不想自己判断时直接用。';

  @override
  String get mpvCacheHelpLowLatencyExtra => '适合：本地硬盘视频、局域网很稳时的 NAS。';

  @override
  String get mpvCacheHelpStableExtra => '适合：大多数 NAS、网盘和普通 STRM。';

  @override
  String get mpvCacheHelpNetworkExtra => '适合：高码率、大体积、跨网络访问的片源。';

  @override
  String get mpvPerformanceWarningTitle => '性能提醒';

  @override
  String get mpvPerformanceWarningDebandMedium =>
      '中档去色带会增加额外画面处理开销，部分设备可能出现掉帧、发热或系统卡顿。';

  @override
  String get mpvPerformanceWarningSharpen =>
      '锐化会增加滤镜计算量，片源较重或设备较弱时可能导致播放掉帧和界面不流畅。';

  @override
  String get mpvPerformanceWarningDenoise =>
      '降噪属于较重的视频滤镜，移动设备上很容易带来明显掉帧、发热甚至系统卡顿。';

  @override
  String get mpvPerformanceWarningDeinterlaceForce =>
      '强制反交错会让所有片源都走额外处理链路，普通逐行片源通常没有必要，且可能拖慢播放。';

  @override
  String get mpvPerformanceWarningScaleQuality =>
      '高质量缩放会增加 GPU 和渲染压力，高分辨率或高码率片源上更容易出现掉帧。';

  @override
  String get mpvPerformanceWarningHdr =>
      '这个 HDR 模式会增加色调映射压力，HDR、10-bit 或高分辨率片源上可能导致明显卡顿。';

  @override
  String get mpvPerformanceWarningFrameInterpolation =>
      '插帧是最容易拖慢播放和系统流畅度的选项之一，开启后可能出现视频掉帧、UI 掉帧和系统卡顿。';

  @override
  String get mpvPerformanceWarningVideoSyncSmooth =>
      '平滑同步会更积极地贴合屏幕刷新率，部分设备上会增加合成与同步压力。';

  @override
  String get mpvPerformanceWarningCacheNetwork =>
      '网络重缓存会占用更多内存，并让拖动回填更重，只建议在高码率远程片源上使用。';

  @override
  String get mpvPerformanceWarningCacheSize =>
      '较大的缓冲会占用更多内存，并让起播、拖动后的回填更重；低内存设备上可能影响系统流畅度。';

  @override
  String get mpvPerformanceWarningGeneric => '当前选项可能增加播放器负载，请根据设备性能谨慎开启。';

  @override
  String get mpvAudioEqAdvancedTitle => '高级频段调整';

  @override
  String get mpvAudioEqAdvancedSubtitle => '进入上下滑动频谱页，自定义每个频段并保存多套预设。';

  @override
  String get mpvAudioEqAdvancedHeader => '高级均衡';

  @override
  String get mpvCurrentlyUsed => '当前使用';

  @override
  String get commonReset => '重置';

  @override
  String get commonRestoreDefault => '恢复默认';

  @override
  String playerQualitySwitching(Object quality, Object suffix) {
    return '正在为您切换至 $quality$suffix 画质，请稍等...';
  }

  @override
  String playerQualitySwitchFailed(Object error) {
    return '切换清晰度失败: $error';
  }

  @override
  String get playerQualityNoAvailableOptions => '当前没有可切换清晰度';

  @override
  String get playerQualitySheetTitle => '清晰度';

  @override
  String get playerQualitySheetSection => '清晰度列表';

  @override
  String get playerQualityRecommendedExpired => '推荐清晰度已失效';

  @override
  String get playerQualityDownloaded => '已下载';

  @override
  String playerWeakNetworkSuggestionTitle(Object quality) {
    return '网络较慢，建议切换到 $quality';
  }

  @override
  String playerWeakNetworkSwitching(Object quality) {
    return '网络较慢，正在切换到 $quality，请稍候...';
  }

  @override
  String get playerAutoFilterFallbackApplied => '检测到帧率不稳定，已自动关闭滤镜';

  @override
  String get playerAdvancedSettingsTitle => '高级设置';

  @override
  String get playerDecoderTitle => '解码方式';

  @override
  String get playerDecoderSubtitle => '切换当前播放器使用的解码方式';

  @override
  String get playerCacheSettingsTitle => '缓存设置';

  @override
  String get playerCacheSettingsSubtitle => '直接按百分比调节播放器缓存策略强度。';

  @override
  String get playerMonitorTitle => '播放监测';

  @override
  String get playerMonitorSubtitle => '设置左上角悬浮信息显示的性能占用和实时帧率';

  @override
  String get playerExtremePlaybackTitle => '极限播放';

  @override
  String get playerExtremePlaybackEnabledSubtitle =>
      '边下边播已开启，退出播放器后会清理本次播放缓存。切换时会重新加载当前播放源。';

  @override
  String get playerExtremePlaybackDisabledSubtitle =>
      '边下边播开启后，退出播放器会自动删除已下载缓存，但会增加内存和存储空间消耗。';

  @override
  String get playerVideoInfoTitle => '视频信息';

  @override
  String get playerVideoInfoSubtitle => '查看当前播放链路、渲染输出和片源信息';

  @override
  String get playerMonitorStatusTitle => '播放监控';

  @override
  String get playerMonitorStatusDescription =>
      '显示在左上角，可拖动并记住位置。GPU 占用取决于设备是否开放系统节点。';

  @override
  String get playerPerformanceMonitorTitle => '性能监控';

  @override
  String get playerPerformanceMonitorSubtitle => '显示 CPU / GPU 占用百分比';

  @override
  String get playerFpsMonitorTitle => '实时帧率';

  @override
  String get playerFpsMonitorSubtitle => '显示当前视频输出 FPS，默认关闭';

  @override
  String get playerHardwareDecoderTitle => '硬件解码';

  @override
  String get playerHardwareDecoderSubtitle => '性能高，优先选择';

  @override
  String get playerSoftwareDecoderTitle => '软件解码';

  @override
  String get playerSoftwareDecoderSubtitle => '兼容性更高，适合硬解异常时切换';

  @override
  String playerDecoderSwitching(Object mode) {
    return '正在切换为 $mode，请稍等...';
  }

  @override
  String get playerMonitorPartiallyEnabled => '部分开启';

  @override
  String get playerMonitorOff => '已关闭';

  @override
  String get playerAspectFit => '适应';

  @override
  String get playerAspectFill => '填充';

  @override
  String get playerAspectRatioTitle => '画面比例';

  @override
  String get playerPreparingPlayback => '正在准备播放';

  @override
  String get playerRefreshingPlaybackSession => '正在刷新播放会话...';

  @override
  String get playerPlaybackSessionExpiredRecovering => '播放会话已过期，正在恢复播放...';

  @override
  String get playerRefreshPlaybackSessionFailed => '刷新播放会话失败';

  @override
  String get playerRecoverPlaybackSessionFailed => '恢复播放会话失败';

  @override
  String playerGenericError(Object title, Object error) {
    return '$title: $error';
  }

  @override
  String get playerIntroSkipped => '已跳过片头';

  @override
  String get playerOutroSkipped => '已跳过片尾';

  @override
  String get playerChapterSkipPromptDismissed =>
      '本次播放已忽略跳过提示，如需关闭可在设置中禁用片头片尾跳过。';

  @override
  String get playerCacheFullyAvailable => '当前视频已全部缓存';

  @override
  String get playerCacheNotReadyForDownload => '当前缓存尚未完整，暂时不能转为下载';

  @override
  String get playerCurrentVideo => '当前视频';

  @override
  String get playerCacheImportFailed => '缓存转下载失败';

  @override
  String get playerCacheImportedToDownload => '已转为下载';

  @override
  String get playerAlreadyInDownloadList => '已在下载列表中';

  @override
  String get playerAddingToDownloadList => '正在加入下载列表';

  @override
  String get playerLayoutSwitchFailed => '切换播放布局失败';

  @override
  String get playerUiLocked => '界面已锁定';

  @override
  String get playerUiUnlocked => '界面已解锁';

  @override
  String get playerReloadRequiredRecovering => '当前播放需要重新加载，正在为您恢复播放，请稍候...';

  @override
  String get playerErrorHintFailed => '失败';

  @override
  String get playerErrorHintError => '错误';

  @override
  String get playerErrorHintUnavailable => '不可';

  @override
  String get playerErrorHintMissing => '缺少';

  @override
  String get playerErrorHintNone => '暂无';

  @override
  String get playerErrorHintNotLoaded => '未加载';

  @override
  String get playerErrorHintNotExtracted => '未提取';

  @override
  String get playerSettingsTitle => '设置';

  @override
  String get playerAutoRotateTitle => '自动旋转';

  @override
  String get playerAutoRotateSystemSubtitle => '跟随系统方向自动切换';

  @override
  String get playerAutoRotateLockedSubtitle => '锁定当前播放方向';

  @override
  String get playerAutoPlayTitle => '自动连播';

  @override
  String get playerAutoPlayEnabledSubtitle => '当前集播放完成后自动播放下一集';

  @override
  String get playerAutoPlayDisabledSubtitle => '关闭后播放完成停留当前集';

  @override
  String get playerNextEpisodePreloadTitle => '下一级预加载';

  @override
  String get playerNextEpisodePreloadEnabledSubtitle =>
      '片尾倒计时开始时预加载下一集，尽量减少黑屏和等待';

  @override
  String get playerNextEpisodePreloadDisabledSubtitle => '关闭后保持原本的自动连播切集方式';

  @override
  String get playerNextEpisodePreloadRequiresAutoPlay => '需先开启自动连播';

  @override
  String playerCurrentValue(Object value) {
    return '当前：$value';
  }

  @override
  String get playerIntroOutroSettingsTitle => '片头片尾设置';

  @override
  String get playerBookmarkSettingsSubtitle => '记录当前片段关键时间点并快速跳转';

  @override
  String get playerSelectIntroChapterTitle => '选择片头章节';

  @override
  String get playerSelectOutroChapterTitle => '选择片尾章节';

  @override
  String get playerIntroOutroStatusTitle => 'OP/ED 跳过';

  @override
  String get playerEnabled => '已开启';

  @override
  String get playerIntroOutroAutoSkipToggleTitle => '启用自动跳过';

  @override
  String get playerIntroOutroAutoSkipToggleSubtitle => '开启后按官方配置跳过片头片尾';

  @override
  String get playerAdvancedAdjustmentLabel => '高级调整';

  @override
  String get playerIntroOutroDefaultDurationHint => '默认 1-2 分钟，必要时再微调';

  @override
  String get playerIntroOutroOffTitle => '关闭';

  @override
  String get playerIntroOutroOffSubtitle => '不自动跳过片头片尾';

  @override
  String get playerIntroOutroOfficialTitle => '自动跳过官方片头片尾';

  @override
  String get playerIntroOutroOfficialSubtitle => '使用飞牛官方片头片尾时长配置';

  @override
  String get playerIntroOutroOfficialSettingsTitle => '飞牛官方设置';

  @override
  String get playerIntroOutroOfficialSettingsSubtitle => '设置官方片头片尾跳过时长';

  @override
  String get playerIntroOutroChapterModeTitle => '章节判断跳过';

  @override
  String get playerIntroOutroChapterModeSubtitle => '根据章节自动判断，或手动选择章节作为 OP/ED';

  @override
  String get playerIntroOutroChapterSettingsTitle => '章节跳过设置';

  @override
  String get playerSkipIntroTitle => '跳过片头';

  @override
  String get playerSkipOutroTitle => '跳过片尾';

  @override
  String get playerIntroDurationTitle => '片头时长';

  @override
  String get playerOutroDurationTitle => '片尾时长';

  @override
  String get playerOfficialIntroDescription => '设置官方片头跳过时长';

  @override
  String get playerOfficialOutroDescription => '设置官方片尾跳过时长';

  @override
  String get playerCurrentPlaybackTime => '当前播放时间';

  @override
  String get playerSetAsIntro => '设为片头';

  @override
  String get playerSetAsOutro => '设为片尾';

  @override
  String get playerCustomDurationTitle => '自定义';

  @override
  String get playerCustomDurationSubtitle => '距离片头/片尾多少秒时开始跳过';

  @override
  String get playerResetToZeroSeconds => '恢复为 0 秒';

  @override
  String get playerIntroOutroAutoModeTitle => '自动判断';

  @override
  String get playerIntroOutroAutoModeSubtitle => '根据章节位置和短章节时长自动识别 OP/ED';

  @override
  String get playerIntroOutroManualModeTitle => '手动选择章节';

  @override
  String get playerIntroOutroManualModeSubtitle => '手动指定章节作为片头片尾';

  @override
  String get playerIntroOutroAutoRangeLabel => '自动判断范围';

  @override
  String get playerIntroMaxChapterDurationTitle => '片头最大章节时长';

  @override
  String get playerIntroMaxChapterDurationSubtitle => '前段短章节小于该时长时，优先判定为片头';

  @override
  String get playerOutroMaxChapterDurationTitle => '片尾最大章节时长';

  @override
  String get playerOutroMaxChapterDurationSubtitle => '尾段短章节小于该时长时，优先判定为片尾';

  @override
  String get playerIntroChapterTitle => '片头章节';

  @override
  String get playerIntroChapterSubtitle => '手动指定片头章节';

  @override
  String get playerOutroChapterTitle => '片尾章节';

  @override
  String get playerOutroChapterSubtitle => '手动指定片尾章节';

  @override
  String get playerUnset => '未设置';

  @override
  String playerChapterNumber(int chapter) {
    return '第 $chapter 章';
  }

  @override
  String playerChapterLoadFailed(Object error) {
    return '读取章节失败: $error';
  }

  @override
  String get playerNoAvailableChapters => '当前视频没有可用章节';

  @override
  String get playerNoChapter => '不使用章节';

  @override
  String get playerIntroOutroSourceChapterLabel => '章节判断';

  @override
  String get playerIntroOutroSourceOffLabel => '已关闭';

  @override
  String get playerIntroOutroManualLabel => '手动选择';

  @override
  String get playerIntroOutroAutoLabel => '自动判断';

  @override
  String playerIntroOutroManualSummary(Object intro, Object outro) {
    return '片头：$intro，片尾：$outro';
  }

  @override
  String get playerUnrecognized => '未识别';

  @override
  String playerIntroOutroAutoSummary(Object intro, Object outro) {
    return '自动判断结果，片头：$intro，片尾：$outro';
  }

  @override
  String get playerIntroOutroOffSummary => '关闭后不会自动跳过片头片尾';

  @override
  String playerIntroOutroOfficialSummary(Object intro, Object outro) {
    return '官方片头 $intro，片尾 $outro';
  }

  @override
  String playerEpisodeSwitchFailed(Object error) {
    return '切换剧集失败: $error';
  }

  @override
  String get playerNotReady => '播放器未就绪';

  @override
  String get playerListenVideoEnabled => '已开启听视频模式';

  @override
  String get playerListenVideoRestored => '已恢复视频画面';

  @override
  String get playerListenVideoSwitchFailed => '听视频模式切换失败';

  @override
  String get playerVideoRestoreFailed => '视频画面恢复失败';

  @override
  String get playerScreenshotModuleMissing => '截图模块未加载，请重启应用';

  @override
  String get playerScreenshotFailed => '截图失败';

  @override
  String get playerScreenshotSaved => '截图已保存';

  @override
  String get playerScreenshotCustomDirectoryRequired => '请先在截图设置里选择自定义目录';

  @override
  String get playerScreenshotCustomDirectoryUnavailable => '自定义目录不可用，请重新选择';

  @override
  String get playerScreenshotUnavailable => '当前还不能截图';

  @override
  String get playerScreenshotSaveFailed => '截图保存失败';

  @override
  String get playerDiagnosticsTitle => '播放诊断';

  @override
  String playerDiagnosticsLoadFailed(Object error) {
    return '读取播放诊断失败：$error';
  }

  @override
  String get playerDiagnosticsEmpty => '暂时没有可显示的播放信息';

  @override
  String get playerDiagnosticsPlaybackSection => '播放信息';

  @override
  String get playerDiagnosticsStatus => '状态';

  @override
  String get playerDiagnosticsPosition => '当前位置';

  @override
  String get playerDiagnosticsDuration => '总时长';

  @override
  String get playerDiagnosticsSpeed => '播放速度';

  @override
  String get playerDiagnosticsPaused => '已暂停';

  @override
  String get playerDiagnosticsError => '错误';

  @override
  String get playerDiagnosticsVideoSection => '视频';

  @override
  String get playerDiagnosticsVideoCodec => '视频编码';

  @override
  String get playerDiagnosticsDolbyVision => '杜比视界';

  @override
  String get playerDiagnosticsResolution => '分辨率';

  @override
  String get playerDiagnosticsVideoOutput => '视频输出';

  @override
  String get playerDiagnosticsDecoder => '解码方式';

  @override
  String get playerDiagnosticsAudioSection => '音频';

  @override
  String get playerDiagnosticsCurrentAudioTrack => '当前音轨';

  @override
  String get playerDiagnosticsAudioCodec => '音频编码';

  @override
  String get playerDiagnosticsAudioChain => '音频链路';

  @override
  String get playerDiagnosticsOutputParams => '输出参数';

  @override
  String get playerDiagnosticsOutputDevice => '输出设备';

  @override
  String get playerDiagnosticsExternalAudio => '已接入外接音频';

  @override
  String get playerDiagnosticsUsbAudio => 'USB / 小尾巴';

  @override
  String get playerDiagnosticsSystemDefaultOutput => '系统默认输出';

  @override
  String get playerDiagnosticsCurrentSubtitle => '当前字幕';

  @override
  String get playerDiagnosticsOutputDisplaySection => '输出与显示';

  @override
  String get playerDiagnosticsHdrDolbyPipeline => 'HDR / 杜比链路';

  @override
  String get playerDiagnosticsColorMode => '色彩模式';

  @override
  String get playerDiagnosticsDeviceInfo => '设备信息';

  @override
  String get playerDiagnosticsSourceSection => '片源';

  @override
  String get playerDiagnosticsTitleLabel => '标题';

  @override
  String get playerDiagnosticsMediaId => '媒体标识';

  @override
  String get playerDiagnosticsVideoStream => '视频流';

  @override
  String get playerDiagnosticsAudioStream => '音频流';

  @override
  String get playerDiagnosticsSubtitleStream => '字幕流';

  @override
  String get commonYes => '是';

  @override
  String get commonNo => '否';

  @override
  String get playerDolbyVisionSource => '杜比视界片源';

  @override
  String get playerHdrSource => 'HDR片源';

  @override
  String get playerSdrSource => 'SDR片源';

  @override
  String get playerHdrDirect => 'HDR直出';

  @override
  String get playerSdrTonemap => 'SDR映射';

  @override
  String get playerSdrPipeline => 'SDR链路';

  @override
  String get playerAudioPassthrough => '直通输出';

  @override
  String get playerAudioDecodedNonPassthrough => '解码播放（非直通）';

  @override
  String get playerAudioDecoded => '解码播放';

  @override
  String get playerRecognized => '已识别';

  @override
  String get playerConnected => '已接入';

  @override
  String get playerNotDetected => '未检测到';

  @override
  String get danmakuSettingsTitle => '弹幕设置';

  @override
  String get danmakuDisplaySection => '显示调节';

  @override
  String get danmakuDisplayArea => '显示区域';

  @override
  String get danmakuOpacity => '不透明度';

  @override
  String get danmakuDensity => '弹幕密度';

  @override
  String get danmakuFontSize => '字体大小';

  @override
  String get danmakuFontWeight => '字体粗细';

  @override
  String get danmakuSpeed => '弹幕速度';

  @override
  String get danmakuFrameRate => '弹幕帧率';

  @override
  String get danmakuTypeFilterSection => '按弹幕类型屏蔽';

  @override
  String get danmakuTypeFixed => '固定';

  @override
  String get danmakuTypeScroll => '滚动';

  @override
  String get danmakuTypeColor => '彩色';

  @override
  String get danmakuTypeBottom => '底部';

  @override
  String get danmakuOcclusionSection => '画面防遮挡';

  @override
  String get danmakuHideDuplicateTitle => '隐藏重复弹幕';

  @override
  String get danmakuHideDuplicateSubtitle => '合并高频重复内容，减少同屏密集刷屏。';

  @override
  String get danmakuAvoidSubtitleTitle => '底部字幕区域防遮挡';

  @override
  String get danmakuAvoidSubtitleSubtitle => '优先避开字幕所在区域，减少弹幕压住字幕。';

  @override
  String get danmakuAvoidCenterTitle => '主体穿透遮挡';

  @override
  String get danmakuAvoidCenterSubtitle => '优先使用动态蒙版扣除人物区域内的弹幕，不可用时会恢复普通弹幕。';

  @override
  String get danmakuAiSampleInterval => 'AI 采样间隔';

  @override
  String get danmakuAiSampleSize => 'AI 采样大小';

  @override
  String get danmakuSourceSection => '弹幕来源';

  @override
  String get danmakuLayerEnabledTitle => '启用弹幕层';

  @override
  String get danmakuLayerEnabledSubtitle => '关闭后右上角设置入口会隐藏，仅保留左下角开关。';

  @override
  String danmakuCurrentStatus(Object status, Object summary) {
    return '当前状态：$status  ·  $summary';
  }

  @override
  String get danmakuSourcePriority => '来源优先级';

  @override
  String danmakuSourcePriorityDescription(Object priority) {
    return '当本地弹幕和网络弹幕都可用时，优先自动载入 $priority。';
  }

  @override
  String get danmakuLocalFirst => '本地优先';

  @override
  String get danmakuNetworkFirst => '网络优先';

  @override
  String get danmakuSavedTitle => '已保存弹幕';

  @override
  String get danmakuSavedEmptySubtitle => '统一管理本地弹幕和弹弹play缓存。';

  @override
  String danmakuSavedCountSubtitle(int count) {
    return '当前已保存 $count 个弹幕来源。';
  }

  @override
  String get danmakuSearchTitle => '搜索弹幕';

  @override
  String get danmakuDanDanPlay => '弹弹play';

  @override
  String get danmakuSearchAnimeSubtitle => '通过弹弹play搜索当前番剧和剧集，直接导入网络弹幕。';

  @override
  String get danmakuSearchSourceSubtitle => '通过弹弹play搜索当前片源相关结果，直接导入网络弹幕。';

  @override
  String get danmakuManualImportTitle => '手动导入弹幕';

  @override
  String get danmakuManualImportSubtitle =>
      '支持本地 XML / JSON 弹幕文件，导入后会替换当前已载入弹幕。';

  @override
  String get danmakuLocalFile => '本地文件';

  @override
  String get danmakuLocalImport => '本地导入';

  @override
  String get danmakuNoSavedSources => '还没有已保存弹幕来源';

  @override
  String get danmakuLocalSource => '本地弹幕';

  @override
  String get danmakuSearchHint => '可自动带入当前内容，也可以改词重搜';

  @override
  String danmakuCurrentMatch(Object context) {
    return '当前匹配：$context';
  }

  @override
  String get danmakuNoSearchResults => '没有搜索到可用结果';

  @override
  String get danmakuConfigRequired => '请先在配置中填入弹弹play AppId / AppSecret';

  @override
  String get danmakuSizeSmall => '较小';

  @override
  String get danmakuSizeSlightlySmall => '偏小';

  @override
  String get danmakuSizeStandard => '标准';

  @override
  String get danmakuSizeSlightlyLarge => '偏大';

  @override
  String get danmakuSizeLarge => '较大';

  @override
  String get danmakuWeightThin => '较细';

  @override
  String get danmakuWeightThick => '较粗';

  @override
  String get danmakuWeightVeryThick => '很粗';

  @override
  String get danmakuAreaQuarter => '1/4 屏';

  @override
  String get danmakuAreaHalf => '半屏';

  @override
  String get danmakuAreaThreeQuarter => '3/4 屏';

  @override
  String get danmakuAreaFull => '全屏';

  @override
  String get danmakuSpeedSlow => '慢';

  @override
  String get danmakuSpeedFast => '快';

  @override
  String get danmakuSpeedVeryFast => '极快';

  @override
  String get danmakuOcclusionDisabledTitle => '主体遮挡已关闭';

  @override
  String get danmakuOcclusionMaskTitle => '精细遮罩中';

  @override
  String get danmakuOcclusionBboxTitle => '人物框兜底中';

  @override
  String get danmakuOcclusionEnabledTitle => '主体遮挡已启用';

  @override
  String get danmakuOcclusionUnavailableTitle => '主体遮挡暂不可用';

  @override
  String get danmakuOcclusionDisabledSubtitle => '关闭后会恢复普通弹幕显示。';

  @override
  String get danmakuOcclusionMaskCached => '已复用精细遮罩缓存';

  @override
  String get danmakuOcclusionMaskRealtime => '正在使用实时精细遮罩';

  @override
  String get danmakuOcclusionBboxFallback => '正在使用人物框兜底';

  @override
  String get danmakuOcclusionNormal => '遮挡状态正常';

  @override
  String danmakuOcclusionBackendStatus(Object backend, Object status) {
    return '当前后端：$backend，$status。';
  }

  @override
  String danmakuOcclusionBackendWithReason(Object backend, Object reason) {
    return '当前后端：$backend，$reason';
  }

  @override
  String danmakuOcclusionBackendOnly(Object backend) {
    return '当前后端：$backend';
  }

  @override
  String get danmakuOcclusionCaptureUnsupported => '当前视频输出后端不支持 AI 采样';

  @override
  String get danmakuOcclusionCaptureBudgetUnsupported =>
      '当前链路在高刷新率下已禁用实时 AI 采样';

  @override
  String get danmakuEnabled => '弹幕已开启';

  @override
  String get danmakuDisabled => '弹幕已关闭';

  @override
  String get danmakuNeedSearchKeyword => '请先输入要搜索的番剧名称';

  @override
  String danmakuSearchRateLimited(int seconds) {
    return '搜索过于频繁，请 $seconds 秒后再试。';
  }

  @override
  String get danmakuSearchFailed => '搜索弹幕失败';

  @override
  String get danmakuNoAvailableData => '没有获取到可用弹幕数据';

  @override
  String get danmakuImportFailed => '导入弹幕失败';

  @override
  String danmakuImportFailedWithError(Object error) {
    return '导入弹幕失败: $error';
  }

  @override
  String get danmakuReadSelectedFileFailed => '无法读取已选择的弹幕文件';

  @override
  String danmakuImportedCount(int count) {
    return '已导入 $count 条弹幕';
  }

  @override
  String danmakuLoadedCount(int count) {
    return '已载入 $count 条弹幕';
  }

  @override
  String get danmakuSavedFileInvalidRemoved => '弹幕文件已失效，已从列表移除';

  @override
  String get danmakuSavedSourceDeleted => '已删除保存的弹幕来源';

  @override
  String get danmakuReadSavedFileFailed => '无法读取已保存的弹幕文件';

  @override
  String get danmakuAutoMatchNoResultBlocked => '当前片源自动匹配弹幕无结果，后续不再自动请求，可手动搜索。';

  @override
  String get danmakuAutoMatchFailed => '当前片源自动匹配弹幕失败';

  @override
  String danmakuAutoMatchBlockedWithReason(Object reason) {
    return '$reason，后续不再自动请求，可手动搜索。';
  }

  @override
  String get danmakuSwitchedLocalFirst => '已切换为本地优先';

  @override
  String get danmakuSwitchedNetworkFirst => '已切换为网络优先';

  @override
  String get danmakuLayerDisabledSummary => '弹幕层已关闭，开启后会按当前优先级自动载入弹幕。';

  @override
  String get danmakuLoadedLocalSummary => '当前已加载本地弹幕';

  @override
  String get danmakuLoadedNetworkSummary => '当前已加载弹弹play弹幕';

  @override
  String get danmakuLoadedGenericSummary => '当前已加载弹幕';

  @override
  String danmakuLoadedWithLabelSummary(Object prefix, Object label, int count) {
    return '$prefix：$label，共 $count 条。';
  }

  @override
  String danmakuLoadedCountSummary(Object prefix, int count) {
    return '$prefix，共 $count 条。';
  }

  @override
  String get danmakuStatusLocal => '本地';

  @override
  String get danmakuStatusNetwork => '弹弹play';

  @override
  String get danmakuStatusNotLoaded => '未载入';

  @override
  String get danmakuNoLoadedSearchOrImportSummary =>
      '当前还没有载入弹幕，可搜索弹弹play弹幕或手动导入本地弹幕。';

  @override
  String danmakuNoLoadedManualImportWithTitleSummary(Object title) {
    return '$title 暂未载入弹幕，可手动导入本地弹幕。';
  }

  @override
  String get danmakuNoLoadedManualImportSummary => '当前片源暂未载入弹幕，可手动导入本地弹幕。';

  @override
  String get danmakuSearchButton => '搜索';

  @override
  String get danmakuSavedSourceLocalLabel => '本地';

  @override
  String danmakuSavedSourceSubtitleWithCount(
    Object type,
    int count,
    Object detail,
  ) {
    return '$type · $count 条 · $detail';
  }

  @override
  String danmakuSavedSourceSubtitle(Object type, Object detail) {
    return '$type · $detail';
  }

  @override
  String get danmakuCurrent => '当前';

  @override
  String get playerFitModeUnavailable => '画面模式暂未接入';

  @override
  String get playerPictureInPictureUnavailable => '当前无法进入小窗播放';

  @override
  String playerResumePrompt(Object position) {
    return '继续播放到 $position';
  }

  @override
  String get playerRestartFromBeginning => '从头播放';

  @override
  String playerAutoPlayNextPrompt(int seconds) {
    return '$seconds 秒后自动连播下一集';
  }

  @override
  String get playerReloadAction => '重载';

  @override
  String get playerEpisodeAction => '选集';

  @override
  String get playerAudioTrackAction => '音轨';

  @override
  String get playerSubtitleOffAction => '字幕关';

  @override
  String get playerSubtitleAction => '字幕';

  @override
  String get playerCloudDriveModeTitle => '网盘播放方式';

  @override
  String get playerCloudDriveAccountName => '网盘';

  @override
  String get playerCloudDriveDirectUnavailable => '当前没有可用的网盘直链播放源';

  @override
  String get playerCloudDriveProxyUnavailable => '当前没有可用的 NAS 代理播放源';

  @override
  String get playerCloudDriveSwitchingDirect => '正在为您切换至网盘直连播放，请稍候...';

  @override
  String get playerCloudDriveSwitchingProxy => '正在为您切换至 NAS 代理播放，请稍候...';

  @override
  String playerSeasonCountLabel(int count) {
    return '$count季';
  }

  @override
  String get playerNoEpisodes => '暂无选集';

  @override
  String get playerDownloadedBadge => '已下载';

  @override
  String get playerNetworkOffline => '离线';

  @override
  String get playerNetworkOnline => '网络';

  @override
  String playerSkipPromptCountdown(int seconds, Object label) {
    return '$seconds 秒后跳过$label';
  }

  @override
  String playerSkipPromptSoon(Object label) {
    return '即将跳过$label';
  }

  @override
  String get playerSkipPromptDismissSubtitle => '点击关闭后，本次不会自动跳过';

  @override
  String get playerReplayAction => '重新播放';

  @override
  String get playerBackAction => '返回';

  @override
  String get playerCloudDrivePlayingFile => '正在播放网盘文件';

  @override
  String get playerCloudDriveModeDescription =>
      '播放速度、画质等能力取决于网盘侧规则。如遇播放异常，可尝试切换播放方式。';

  @override
  String get playerCloudDriveDirectTitle => '网盘直连播放';

  @override
  String get playerCloudDriveDirectSubtitle => '速度较快，省流';

  @override
  String get playerCloudDriveProxyTitle => 'NAS 代理播放';

  @override
  String get playerCloudDriveProxySubtitle => '色调或音频异常时可尝试切换';

  @override
  String get playerRecommendedBadge => '推荐';

  @override
  String get settingsBookmarkManagerTitle => '书签管理';

  @override
  String get settingsBookmarkEmptySummary => '还没有书签';

  @override
  String settingsBookmarkCountSummary(int count) {
    return '共 $count 个书签';
  }

  @override
  String get settingsDanmakuDefaultEnabled => '默认开启';

  @override
  String get settingsDanmakuDefaultDisabled => '默认关闭';

  @override
  String get settingsDanmakuLocalFirst => '本地优先';

  @override
  String get settingsDanmakuNetworkFirst => '网络优先';

  @override
  String get settingsScreenshotCustomDirectoryNotReady => '自定义目录未就绪';

  @override
  String get settingsScreenshotWithSubtitles => '携带字幕';

  @override
  String get settingsScreenshotImageOnly => '仅画面';

  @override
  String get settingsScreenshotWithSubtitleLayer => '携带字幕层';

  @override
  String get settingsScreenshotImageOnlySummary => '仅保存画面';

  @override
  String get settingsScreenshotImageOnlyDescription => '不携带字幕层。';

  @override
  String get settingsScreenshotWithSubtitlesDescription => '保存当前字幕层。';

  @override
  String get settingsScreenshotCustomDirectoryUnsetSummary => '自定义目录未设置。';

  @override
  String settingsScreenshotCustomDirectoryInvalidSummary(Object name) {
    return '已记录自定义目录“$name”，但授权失效，需要重新选择。';
  }

  @override
  String settingsScreenshotCustomDirectoryActiveSummary(Object name) {
    return '当前保存到自定义目录“$name”。';
  }

  @override
  String get settingsScreenshotDirectoryUnset => '未设置';

  @override
  String get settingsScreenshotDirectoryInvalid => '授权失效';

  @override
  String get settingsScreenshotSavePathPicturesTitle => '系统相册';

  @override
  String get settingsScreenshotSavePathPicturesDescription =>
      '保存到 Pictures/FlyPlayer，适合普通截图查看。';

  @override
  String get settingsScreenshotSavePathDcimTitle => '相机目录';

  @override
  String get settingsScreenshotSavePathDcimDescription =>
      '保存到 DCIM/FlyPlayer，更容易被系统相册归类展示。';

  @override
  String get settingsScreenshotSavePathAppPicturesTitle => '应用目录';

  @override
  String get settingsScreenshotSavePathAppPicturesDescription =>
      '保存到应用专属图片目录，更干净，但部分图库不会直接扫描。';

  @override
  String get settingsScreenshotSavePathCustomTitle => '自定义目录';

  @override
  String get settingsScreenshotSavePathCustomDescription =>
      '保存到用户自己选择的文件夹，适合集中管理截图。';

  @override
  String get settingsScreenshotSelectCustomDirectoryFirst => '请先选择截图自定义目录';

  @override
  String get settingsScreenshotCustomDirectoryInvalidRetry => '自定义目录已失效，请重新选择';

  @override
  String get settingsScreenshotReadingCustomDirectory => '正在读取当前自定义目录状态...';

  @override
  String get settingsScreenshotDirectoryUnsetSentence => '未设置目录。';

  @override
  String settingsScreenshotDirectoryInvalidWithName(Object name) {
    return '已记录目录“$name”，但当前授权失效，需要重新选择。';
  }

  @override
  String settingsScreenshotCurrentDirectory(Object name) {
    return '当前目录：$name';
  }

  @override
  String get settingsScreenshotCustomDirectoryManagement => '自定义目录管理';

  @override
  String get settingsScreenshotDirectoryAvailable => '目录可用';

  @override
  String get settingsScreenshotDirectoryNeedsReselect => '需重选';

  @override
  String settingsScreenshotDirectoryActiveDetail(Object name) {
    return '截图保存目录：“$name”。';
  }

  @override
  String get settingsScreenshotDirectorySetupHint => '先选择一个文件夹，再切换到“自定义目录”模式。';

  @override
  String settingsScreenshotDirectoryInvalidDetail(Object name) {
    return '原来的目录“$name”不可用了，请重新选择。';
  }

  @override
  String get settingsScreenshotChooseDirectory => '选择目录';

  @override
  String get settingsScreenshotChangeDirectory => '更换目录';

  @override
  String get settingsScreenshotSetAsCurrentDirectory => '设为当前保存目录';

  @override
  String get settingsScreenshotNoDirectorySelected => '未选择目录';

  @override
  String get settingsScreenshotCustomDirectoryUpdated => '已更新截图自定义目录';

  @override
  String get settingsScreenshotCustomDirectoryRecordedUnavailable =>
      '目录已记录，但当前不可用';

  @override
  String get settingsScreenshotClearCustomDirectoryTitle => '清除截图自定义目录';

  @override
  String get settingsScreenshotClearCustomDirectoryContent =>
      '这不会删除已经保存的截图，只会移除当前目录授权。';

  @override
  String get settingsScreenshotCustomDirectoryCleared => '已清除截图自定义目录';

  @override
  String get settingsScreenshotCustomDirectoryActivated => '截图保存目录已切换为自定义目录';

  @override
  String get settingsScreenshotNoDirectoryChosen => '还没有选择目录';

  @override
  String get settingsScreenshotDirectoryWritable => '可写入';

  @override
  String get settingsScreenshotDirectoryExpired => '已失效';

  @override
  String get settingsScreenshotDirectoryWriteHint => '新截图将写入该目录。';

  @override
  String get settingsScreenshotDirectoryPickHint => '选择文件夹后可作为截图保存目录。';

  @override
  String get settingsScreenshotDirectoryExpiredHint =>
      '目录授权已经失效，需要重新选择后才能继续保存截图。';

  @override
  String get settingsScreenshotClearAuthorization => '清除授权';

  @override
  String get settingsScreenshotCurrentStatus => '当前状态';

  @override
  String get settingsScreenshotCustomDirectoryEnabledStatus =>
      '当前截图已经使用自定义目录保存。更换目录后，新截图会进入新目录，旧截图不会迁移。';

  @override
  String get settingsScreenshotCustomDirectoryDisabledStatus => '当前未启用自定义目录。';

  @override
  String get detailOverviewEmpty => '暂无简介';

  @override
  String get mediaDetailsTitle => '文件媒体信息';

  @override
  String get mediaDetailsVideoSection => '视频';

  @override
  String get mediaDetailsAudioSection => '音频';

  @override
  String get mediaDetailsSubtitleSection => '字幕';

  @override
  String get mediaDetailsFieldEncoder => '编码器';

  @override
  String get mediaDetailsFieldProfile => '配置';

  @override
  String get mediaDetailsFieldLevel => '等级';

  @override
  String get mediaDetailsFieldResolution => '分辨率';

  @override
  String get mediaDetailsFieldAspectRatio => '宽高比';

  @override
  String get mediaDetailsFieldInterlaced => '隔行扫描';

  @override
  String get mediaDetailsFieldFrameRate => '帧率';

  @override
  String get mediaDetailsFieldBitrate => '码率';

  @override
  String get mediaDetailsFieldRange => '视频动态范围';

  @override
  String get mediaDetailsFieldColorPrimaries => '色彩原色';

  @override
  String get mediaDetailsFieldColorSpace => '色彩空间';

  @override
  String get mediaDetailsFieldColorTransfer => '色彩转换';

  @override
  String get mediaDetailsFieldBitDepth => '位深度';

  @override
  String get mediaDetailsFieldPixelFormat => '像素格式';

  @override
  String get mediaDetailsFieldRefs => '参考帧';

  @override
  String get mediaDetailsFieldLanguage => '语言';

  @override
  String get mediaDetailsFieldChannels => '声道';

  @override
  String get mediaDetailsFieldSampleRate => '采样率';

  @override
  String get mediaDetailsFieldLayout => '布局';

  @override
  String get mediaDetailsFieldDefault => '默认';

  @override
  String get mediaDetailsFieldForced => '强制';

  @override
  String get mediaDetailsFieldExternal => '外部';

  @override
  String get detailSeasonSpecial => '特别篇';

  @override
  String detailSeasonNumber(int number) {
    return '第 $number 季';
  }

  @override
  String detailEpisodeNumber(int number) {
    return '第 $number 集';
  }

  @override
  String detailSeasonEpisodeNumber(int season, int episode) {
    return '第 $season 季 第 $episode 集';
  }

  @override
  String detailSpecialEpisodeNumber(int episode) {
    return '特别篇 第 $episode 集';
  }

  @override
  String detailNamedEpisodeNumber(Object title, int episode) {
    return '$title 第 $episode 集';
  }

  @override
  String get detailSeasonDefault => '季';

  @override
  String get detailSeasonInfoDefault => '季信息';

  @override
  String detailTvSeasonCount(int count) {
    return '共 $count 季';
  }

  @override
  String get detailSeasonEmpty => '暂无季列表';

  @override
  String get detailEpisodeTitle => '选集';

  @override
  String get detailEpisodeEmpty => '暂无剧集信息';

  @override
  String get detailEpisodeUnknown => '未知集数';

  @override
  String detailEpisodeTotal(int count) {
    return '共 $count 集';
  }

  @override
  String get commonDetails => '详情';

  @override
  String get commonLoading => '加载中';

  @override
  String get detailImdbEmpty => '暂无 IMDB 链接';

  @override
  String get detailImdbOpenFailed => '无法打开 IMDB 链接';

  @override
  String detailRatingScore(Object score) {
    return '$score 分';
  }

  @override
  String get commonClickTooFastRetryLater => '点击过快，请稍后再试';

  @override
  String get commonOperationFailedRetryLater => '操作失败，请稍后重试';

  @override
  String get actionFavoriteAdd => '收藏';

  @override
  String get actionFavoriteRemove => '取消收藏';

  @override
  String get actionFavoriteAdded => '已加入收藏';

  @override
  String get actionFavoriteRemoved => '已取消收藏';

  @override
  String get actionMarkAsWatched => '标记为已观看';

  @override
  String get actionMarkAsUnwatched => '标记为未观看';

  @override
  String get actionMarkedAsWatched => '已标记为已观看';

  @override
  String get actionMarkedAsUnwatched => '已标记为未观看';

  @override
  String get detailFavoriteFailed => '收藏失败';

  @override
  String get detailUnfavoriteFailed => '取消收藏失败';

  @override
  String get detailMarkWatchedFailed => '标记为已观看失败';

  @override
  String get detailMarkUnwatchedFailed => '标记为未观看失败';

  @override
  String get detailDownloadUnavailable => '暂无可下载资源';

  @override
  String get detailContinuePlay => '继续播放';

  @override
  String get detailPlay => '播放';

  @override
  String get detailOverviewTitle => '简介';

  @override
  String get detailCastCrewTitle => '演职人员';

  @override
  String get detailFileInfoTitle => '文件信息';

  @override
  String get detailFileLocation => '文件位置';

  @override
  String get detailFileSize => '文件大小';

  @override
  String get detailFileCreatedAt => '文件创建日期';

  @override
  String get detailFileAddedAt => '添加日期';

  @override
  String get detailFileConvert => '转换';

  @override
  String detailPlaybackError(Object error) {
    return '播放异常: $error';
  }

  @override
  String detailPlayInfoFailedWithError(Object error) {
    return '获取播放流失败: $error';
  }

  @override
  String get detailPreparingPlayback => '正在准备播放，请稍候';

  @override
  String get detailPlayPlaceholder => '播放接口已预留';

  @override
  String get detailPlayInfoFailed => '获取播放信息失败';

  @override
  String get detailDownloadPlaceholder => '下载接口已预留';

  @override
  String get detailLocalVideoInvalid => '本地视频文件无效';

  @override
  String get detailTmdbEmpty => '暂无 TMDB 链接';

  @override
  String get detailTmdbOpenFailed => '无法打开 TMDB 链接';

  @override
  String get commonOther => '其他';

  @override
  String commonDurationHoursMinutes(int hours, int minutes) {
    return '$hours 小时 $minutes 分钟';
  }

  @override
  String commonDurationMinutesSeconds(int minutes, int seconds) {
    return '$minutes 分钟 $seconds 秒';
  }

  @override
  String commonDurationMinutes(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String commonDurationSeconds(int seconds) {
    return '$seconds 秒';
  }

  @override
  String get downloadLoadingInfo => '正在获取下载信息，请稍候';

  @override
  String get downloadNoResources => '暂无可下载资源';

  @override
  String get downloadNoQuality => '暂无可下载清晰度';

  @override
  String get downloadSelectItem => '选择下载条目';

  @override
  String get downloadQuality => '下载清晰度';

  @override
  String get downloadSelectQuality => '选择下载清晰度';

  @override
  String get downloadDownload => '下载';

  @override
  String get downloadOpenList => '打开下载列表';

  @override
  String get downloadLoadFailed => '获取下载信息失败，请稍后重试';

  @override
  String get downloadSourceQuality => '原画';

  @override
  String get downloadDownloaded => '已下载';

  @override
  String downloadStartedWithQuality(Object quality) {
    return '已开始下载 $quality';
  }

  @override
  String downloadImportedFromCacheWithQuality(Object quality) {
    return '已从缓存加入下载 $quality';
  }

  @override
  String get downloadItemDownloading => '该条目正在下载';

  @override
  String get downloadItemDownloaded => '该条目已下载';

  @override
  String downloadFailedWithError(Object error) {
    return '下载失败：$error';
  }

  @override
  String get downloadListTitle => '下载列表';

  @override
  String get trackSubtitleOff => '关闭字幕';

  @override
  String get trackSubtitleNone => '无字幕';

  @override
  String get trackAudioNone => '无音频';

  @override
  String get trackSubtitleUnknownLanguage => '未知语言';

  @override
  String get trackSubtitleDefaultSuffix => '默认';

  @override
  String get trackSubtitleExternalSuffix => '外挂';

  @override
  String get trackSubtitleName => '字幕';

  @override
  String get playerSubtitleSelectTitle => '选择字幕';

  @override
  String get playerAudioSelectTitle => '选择音频';

  @override
  String get logNoExportableLogs => '当前没有可导出的日志';

  @override
  String logTxtExported(Object path) {
    return 'TXT 已导出到 $path';
  }

  @override
  String logExternalUnavailableExported(Object path) {
    return '外部存储不可用，已导出到临时目录 $path';
  }

  @override
  String logExportFailed(Object error) {
    return '导出失败：$error';
  }

  @override
  String get logClearTitle => '清空日志';

  @override
  String get logClearContent => '会移除当前已记录的报错日志，这个操作不能恢复。';

  @override
  String get logClearConfirm => '清空';

  @override
  String get logCleared => '日志已清空';

  @override
  String get logInfoTitle => '日志信息';

  @override
  String get logErrorLogTitle => '报错日志';

  @override
  String get logErrorLogDescription => '全局异常记录，支持导出为 TXT。';

  @override
  String get logTotal => '总数';

  @override
  String get logErrors => '错误';

  @override
  String get logLatest => '最近';

  @override
  String get logNone => '暂无';

  @override
  String get logExporting => '导出中...';

  @override
  String get logExportTxt => '导出 TXT';

  @override
  String get logClearing => '清空中...';

  @override
  String get logClearAction => '清空日志';

  @override
  String get logEmptyTitle => '暂无报错日志';

  @override
  String get logEmptySubtitle => '发生全局异常后将自动生成记录。';

  @override
  String get logCollapseStack => '收起堆栈';

  @override
  String get logExpandStack => '展开堆栈';

  @override
  String get downloadEmptyDownloaded => '没有已下载的影片';

  @override
  String get downloadEmptyDownloading => '没有下载中的影片';

  @override
  String downloadImportedLocalVideos(int count) {
    return '已导入 $count 个本地下载视频';
  }

  @override
  String get downloadNoImportableVideos => '没有发现需要导入的视频';

  @override
  String get downloadNoRecoverableFiles => '没有找到可恢复的下载文件';

  @override
  String get downloadRefreshFilesFailed => '刷新下载文件失败';

  @override
  String get downloadRefreshFilesTooltip => '刷新下载文件';

  @override
  String get commonEdit => '编辑';

  @override
  String get commonSelectAll => '全选';

  @override
  String get commonDeselectAll => '取消全选';

  @override
  String get downloadDeleteFilesTitle => '删除视频文件';

  @override
  String get downloadDeleteFilesContent => '确认删除所选视频文件？删除后将不可恢复。';

  @override
  String get downloadPreparingPlayback => '正在准备播放，请稍候';

  @override
  String get downloadLocalFileMissing => '本地视频文件不存在';

  @override
  String get downloadDetailTitle => '下载详情';

  @override
  String downloadSelectedCount(int count) {
    return '已选择 $count 项';
  }

  @override
  String downloadVideoCount(int count) {
    return '视频 $count';
  }

  @override
  String downloadTranscodingPercent(int percent) {
    return '转码中 $percent%';
  }

  @override
  String get downloadCalculating => '计算中';

  @override
  String get downloadWaiting => '等待中';

  @override
  String get downloadPendingGenerate => '待生成';

  @override
  String get downloadTranscoding => '转码中';

  @override
  String get downloadDownloading => '下载中';

  @override
  String get downloadCurrentStage => '当前阶段';

  @override
  String get downloadSpeed => '下载速度';

  @override
  String get downloadCloudTranscoding => '云端转码';

  @override
  String get downloadEstimatedFile => '预计文件';

  @override
  String get downloadTransferredTotal => '已下 / 总计';

  @override
  String get downloadDownloadedTab => '已下载';

  @override
  String get downloadDownloadingTab => '下载中';

  @override
  String get storageTitle => '储存管理';

  @override
  String get storageRefreshTooltip => '刷新';

  @override
  String get storageAppDataDangerTitle => '应用数据与危险操作';

  @override
  String get storageAppDataTitle => '应用数据';

  @override
  String get storageAppDataDescription => '这些内容通常是用户记录和个性化配置，不会和普通缓存一起清理。';

  @override
  String get storageTotalUsage => '总占用';

  @override
  String storageLastRefreshed(Object time) {
    return '上次刷新 $time';
  }

  @override
  String get storageClearSelectedCacheTitle => '清理选中缓存';

  @override
  String get storageClearSelectedCacheMessage => '将删除选中的播放缓存文件，删除后需要重新缓存。是否继续？';

  @override
  String get storageClearSelectedDownloadsTitle => '清理已下载文件';

  @override
  String get storageClearSelectedDownloadsMessage =>
      '将删除选中的本地下载文件，删除后需要重新下载。是否继续？';

  @override
  String get storagePlaybackActiveMessage => '播放中不可清理播放缓存';

  @override
  String get storageClearFailedMessage => '清理失败，请稍后重试';

  @override
  String get storageEmptyPlaybackSelection => '请先勾选要清理的缓存';

  @override
  String get storageEmptyDownloadSelection => '请先勾选要清理的下载文件';

  @override
  String get storageSelectedPlaybackCleared => '已清理选中的播放缓存';

  @override
  String get storageSelectedDownloadsCleared => '已清理选中的下载文件';

  @override
  String get storageCacheResolutionFallback => '缓存';

  @override
  String get storageCacheVideoFallback => '缓存视频';

  @override
  String storageSeasonGroupTitle(Object seriesTitle, int season) {
    return '$seriesTitle 第$season季';
  }

  @override
  String storageSpecialGroupTitle(Object seriesTitle) {
    return '$seriesTitle 特别篇';
  }

  @override
  String storagePromoteConverted(int count) {
    return '已转为下载 $count 项';
  }

  @override
  String storagePromoteExisting(int count) {
    return '已有下载 $count 项';
  }

  @override
  String storagePromoteUnavailable(int count) {
    return '不可转换 $count 项';
  }

  @override
  String get storageNoConvertibleCache => '当前没有可转换的完整缓存';

  @override
  String storageClearItemTitle(Object title) {
    return '清理$title';
  }

  @override
  String storageClearItemMessage(Object title) {
    return '将清理$title，对应文件会被删除。是否继续？';
  }

  @override
  String storageClearItemSuccess(Object title) {
    return '$title已清理';
  }

  @override
  String storageClearItemRestricted(Object title) {
    return '$title已部分清理，公共目录未授权';
  }

  @override
  String storageActionCompleted(Object title) {
    return '$title已完成';
  }

  @override
  String storageActionFailed(Object title) {
    return '$title失败，请稍后重试';
  }

  @override
  String get storageClearBookmarksTitle => '清空书签';

  @override
  String get storageClearBookmarksSubtitle => '仅删除播放书签记录';

  @override
  String get storageClearBookmarksMessage => '将删除全部播放书签，此操作不可恢复。';

  @override
  String get storageClearSavedThemesTitle => '清空已保存主题';

  @override
  String get storageClearSavedThemesSubtitle => '保留当前自定义配置';

  @override
  String get storageClearSavedThemesMessage => '将删除已保存主题，但不会影响当前自定义配置。';

  @override
  String get storageClearDynamicThemeTitle => '清空动态取色缓存';

  @override
  String get storageClearDynamicThemeSubtitle => '下次进入详情页会重新为图片取色';

  @override
  String get storageClearDynamicThemeMessage =>
      '将删除本地保存的动态取色结果，之后再次进入详情页时会重新采样取色。';

  @override
  String get storageClearDanmakuSourcesTitle => '清空弹幕来源';

  @override
  String get storageClearDanmakuSourcesSubtitle => '删除已保存的弹幕来源记录';

  @override
  String get storageClearDanmakuSourcesMessage => '将删除已保存的弹幕来源记录。';

  @override
  String get storageClearLoginHistoryTitle => '清空登录历史';

  @override
  String get storageClearLoginHistorySubtitle => '不会退出当前会话';

  @override
  String get storageClearLoginHistoryMessage => '将删除历史登录记录，不会退出当前登录。';

  @override
  String get storageResetSettingsTitle => '重置设置';

  @override
  String get storageResetSettingsSubtitle => '主题、播放器、截图、弹幕与平行窗口设置';

  @override
  String get storageResetSettingsMessage =>
      '将重置主题、播放器、截图、弹幕和平行窗口设置，不会清理缓存和用户文件。';

  @override
  String get storageTotal => '总计';

  @override
  String get storageNoUsageData => '暂无占用数据';

  @override
  String get storageUsageCategory => '占用分类';

  @override
  String get storageCategoryDetails => '分类详情';

  @override
  String get storagePlaybackFiles => '播放缓存';

  @override
  String get storageDownloadFiles => '下载文件';

  @override
  String storagePromoteSelected(int count) {
    return '转为下载 ($count)';
  }

  @override
  String storageClearSelected(int count) {
    return '清理选中 ($count)';
  }

  @override
  String get storageNoPlaybackCache => '当前没有可清理的播放缓存。';

  @override
  String get storageNoDownloadFiles => '当前没有可查看的本地下载文件。';

  @override
  String get storageCompleteCache => '完整缓存';

  @override
  String get storageIncompleteCache => '未完整缓存';

  @override
  String get storageCompletedCache => '已完整缓存';

  @override
  String get storageEnterManagement => '进入管理';

  @override
  String get storageEstimated => '估算';

  @override
  String get storageRestricted => '权限受限';

  @override
  String get commonApply => '应用';

  @override
  String get commonAll => '全部';

  @override
  String get commonAscending => '升序';

  @override
  String get commonDescending => '降序';

  @override
  String get screenshotGalleryTitle => '截图图库';

  @override
  String screenshotSelectedCount(int count) {
    return '已选中 $count 张';
  }

  @override
  String get screenshotUnknownResolution => '未知分辨率';

  @override
  String get screenshotDeleteTitle => '删除截图';

  @override
  String screenshotDeleteContent(int count) {
    return '将删除选中的 $count 张截图，删除后无法恢复。';
  }

  @override
  String screenshotDeletedCount(int count) {
    return '已删除 $count 张截图';
  }

  @override
  String get screenshotDeleteNone => '没有删除任何截图';

  @override
  String get screenshotSourcePictures => '系统相册';

  @override
  String get screenshotSourceDcim => '相机目录';

  @override
  String get screenshotSourceApp => '应用目录';

  @override
  String get screenshotSourceCustom => '自定义目录';

  @override
  String get screenshotSearchTitle => '搜索截图';

  @override
  String get screenshotSearchHint => '输入截图名、目录或来源';

  @override
  String get screenshotClearSearch => '清空搜索';

  @override
  String get screenshotFilterSortTitle => '筛选与排序';

  @override
  String get screenshotSourceFilter => '来源筛选';

  @override
  String get screenshotSortStandard => '排序标准';

  @override
  String screenshotCurrentSortGroup(Object field, Object direction) {
    return '当前按 $field$direction分组';
  }

  @override
  String get screenshotSortDescription => '支持多级排序，排在最上面的规则优先级最高，页面分组也按它展示。';

  @override
  String get screenshotAddSort => '添加排序';

  @override
  String get screenshotApplySort => '应用排序';

  @override
  String get screenshotMoveUpPriority => '上移优先级';

  @override
  String get screenshotMoveDownPriority => '下移优先级';

  @override
  String get screenshotDeleteRule => '删除规则';

  @override
  String screenshotSearchEmpty(Object query) {
    return '没有找到和“$query”相关的截图。';
  }

  @override
  String get screenshotEmptyPictures => '系统相册里还没有截图。';

  @override
  String get screenshotEmptyDcim => '相机目录里还没有截图。';

  @override
  String get screenshotEmptyApp => '应用目录里还没有截图。';

  @override
  String get screenshotEmptyCustom => '自定义目录里还没有截图。';

  @override
  String get screenshotEmptyDefault => '当前没有可预览的截图。';

  @override
  String get screenshotRefreshHint => '下拉刷新后会重新扫描可访问目录。';

  @override
  String get screenshotAuthorizePublicDirectories => '授权公共目录';

  @override
  String get screenshotInfoCategory => '分类';

  @override
  String get screenshotInfoFormat => '格式';

  @override
  String get screenshotInfoSourceDirectory => '来源目录';

  @override
  String get screenshotInfoTakenAt => '拍摄时间';

  @override
  String get screenshotInfoFileSize => '文件大小';

  @override
  String get screenshotInfoStorageType => '存储类型';

  @override
  String get screenshotInfoResolution => '分辨率';

  @override
  String get screenshotManagedDirectory => '受管目录';

  @override
  String get screenshotLocalFile => '本地文件';

  @override
  String get screenshotLoading => '读取中';

  @override
  String get screenshotUltraHdrNotice =>
      '该文件为 Ultra HDR JPEG，应用内预览可能只显示 SDR 基底，相册中可按系统能力显示 HDR。';

  @override
  String get screenshotFormatImage => '图片';

  @override
  String get screenshotSortDate => '日期';

  @override
  String get screenshotSortFileName => '文件名';

  @override
  String get screenshotSortSize => '大小';

  @override
  String get screenshotSortResolution => '分辨率';

  @override
  String get screenshotSortDirectory => '目录';

  @override
  String get screenshotSortSource => '来源';

  @override
  String get screenshotDateToday => '今天';

  @override
  String get screenshotDateYesterday => '昨天';

  @override
  String get screenshotDateBeforeYesterday => '前天';

  @override
  String screenshotMonthDay(int month, int day) {
    return '$month月$day日';
  }

  @override
  String get screenshotSizeOver10Mb => '10 MB 以上';

  @override
  String get screenshotSizeUnder100Kb => '100 KB 以下';

  @override
  String get bookmarkNoteDialogTitle => '书签备注';

  @override
  String get bookmarkNoteDialogHint => '记录这个书签的作用，比如名场面、关键转折、复习点';

  @override
  String get bookmarkNoteCollapse => '收起';

  @override
  String get bookmarkNoteExpand => '更多';

  @override
  String get mpvEqEditorTitle => '高级均衡';

  @override
  String get mpvEqEditorSubtitle => '上下拖动每个频段，细微调整整体音色。';

  @override
  String get mpvEqReset => '归零';

  @override
  String get themePresetMidnightSubtitle => '深夜影院感，层次稳重';

  @override
  String get themePresetOceanSubtitle => '冷海风格，信息感更强';

  @override
  String get themePresetForestSubtitle => '自然绿调，观感更柔和';

  @override
  String get themePresetGraphiteSubtitle => '中性石墨，适合长期使用';

  @override
  String get themePresetSunsetSubtitle => '暖调落日，氛围更明显';

  @override
  String get themePresetAuroraSubtitle => '清亮极光，更偏轻快科技感';

  @override
  String get themePresetLatteSubtitle => '奶白纸感，适合亮背景偏好';

  @override
  String get themeAccentBlue => '星蓝';

  @override
  String get themeAccentCyan => '冰青';

  @override
  String get themeAccentGreen => '松绿';

  @override
  String get themeAccentAmber => '琥珀';

  @override
  String get themeAccentRose => '赤霓';

  @override
  String get themeAccentCoral => '珊瑚';

  @override
  String get themeAccentIndigo => '靛青';

  @override
  String get themeAccentMint => '薄荷';

  @override
  String get themeBackgroundNight => '夜幕';

  @override
  String get themeBackgroundSlate => '石墨';

  @override
  String get themeBackgroundOcean => '深海';

  @override
  String get themeBackgroundMoss => '苔绿';

  @override
  String get themeBackgroundEmber => '余烬';

  @override
  String get themeBackgroundPearl => '珠雾';

  @override
  String get themeBackgroundLinen => '亚麻';

  @override
  String get themeBackgroundIvory => '奶白';

  @override
  String get themeDynamicModeOff => '关闭';

  @override
  String get themeDynamicModeDetailsAndPeople => '详情页和人物页';

  @override
  String get themeDynamicIntensitySubtle => '轻柔';

  @override
  String get themeDynamicIntensityMedium => '中度';

  @override
  String get themeDynamicIntensityVivid => '鲜明';

  @override
  String get themeDynamicIntensityAdvanced => '高级';

  @override
  String get themeDynamicBehaviorSubtle => '当前页轻量取色，按钮和边框会跟随变化';

  @override
  String get themeDynamicBehaviorMedium => '当前页完整取色，推荐';

  @override
  String get themeDynamicBehaviorVivid => '高级取色，普通页面流可联动主屏';

  @override
  String get themeCurrentCustomTitle => '当前自定义';

  @override
  String get themeCurrentCustomSubtitle => '手动调整后的当前配方';

  @override
  String get themeSavedDefaultSubtitle => '已保存主题';

  @override
  String get themeColorHue => '色相';

  @override
  String get themeColorSaturation => '饱和度';

  @override
  String get themeColorValue => '明度';

  @override
  String get themeQuickColors => '快速颜色';

  @override
  String get themePreviewCurrentAppearance => '当前外观';

  @override
  String get themePreviewPrimaryButton => '主按钮';

  @override
  String get themePreviewSelectedTab => '选中标签';

  @override
  String get themePreviewMore => '更多';

  @override
  String get themeSamplePage => '页面';

  @override
  String get themeSampleCard => '卡片';

  @override
  String get themeSampleBottomBar => '底栏';

  @override
  String get themeSampleContinuePlay => '继续播放';

  @override
  String get themeSampleSecondaryAction => '次要操作';

  @override
  String get themeSampleSelected => '已选中';

  @override
  String get themeSampleUnselected => '未选中';

  @override
  String get themeSampleViewDetails => '查看详情';

  @override
  String get themeFixedSectionTitle => '固定主题';

  @override
  String get themeFixedSectionSubtitle => '官方预设，切换后立即作为全局主题生效。';

  @override
  String get themeCustomSectionSubtitle => '自定义配色与已保存主题管理。';

  @override
  String get themeCurrentCustomCardSubtitle => '编辑颜色分类与当前配方。';

  @override
  String get themeNoSavedThemesTitle => '还没有已保存主题';

  @override
  String get themeNoSavedThemesSubtitle => '可在详情页更多菜单中保存当前主题。';

  @override
  String get themeCustomBaseName => '自定义主题';

  @override
  String get themeCustomRecipePageSubtitle => '当前自定义配方，可按颜色分类编辑并另存为自定义主题。';

  @override
  String get themeCustomLabel => '自定义';

  @override
  String get themePaletteButton => '调色盘';

  @override
  String get themeBackgroundControlTitle => '背景主色';

  @override
  String get themeBackgroundControlSubtitle => '控制页面底色、卡片层级、导航栏和整体氛围基调。';

  @override
  String get themeCustomBackgroundPickerTitle => '自定义背景色';

  @override
  String get themeAccentControlTitle => '主操作色';

  @override
  String get themeAccentControlSubtitle => '控制主按钮、进度条、确认动作和主要强调元素。';

  @override
  String get themeCustomAccentPickerTitle => '自定义主操作色';

  @override
  String get themeSelectionControlTitle => '选中色';

  @override
  String get themeSelectionControlSubtitle => '控制选中态、边框高亮和标签状态。';

  @override
  String get themeCustomSelectionPickerTitle => '自定义选中色';

  @override
  String get themeLinkControlTitle => '链接高亮色';

  @override
  String get themeLinkControlSubtitle => '控制“更多”、跳转文本和轻量提示的强调色。';

  @override
  String get themeCustomLinkPickerTitle => '自定义链接色';

  @override
  String get themeRecipePresetLabel => '预设';

  @override
  String get themeRecipeBackgroundLabel => '背景';

  @override
  String get themeRecipeAccentLabel => '主操作';

  @override
  String get themeRecipeSelectionLabel => '选中色';

  @override
  String get themeRecipeLinkLabel => '链接色';

  @override
  String get themeRecipeCurrentTitle => '当前配方';

  @override
  String get themeDynamicTitle => '动态取色主题';

  @override
  String get themeDynamicSubtitle => '详情页和人物页可基于海报临时取色，退出后恢复当前主题。';

  @override
  String get themeDynamicScopeDetailsAndPeople => '当前范围: 详情页和人物页';

  @override
  String get themeDynamicScopeOff => '当前范围: 已关闭';

  @override
  String get themeDynamicDescription => '控制背景主色、面板层级、桥接渐变与环境色；按钮和链接保持固定颜色。';

  @override
  String get themeDynamicDisabled => '详情页取色已关闭';

  @override
  String get themeDynamicPlayerNote => '播放态不覆盖主屏主题；高级强度会联动普通页面。';

  @override
  String get mpvEqAllBandsReset => '已归零所有 EQ 频段';

  @override
  String mpvEqPresetApplied(Object name) {
    return '已套用预设: $name';
  }

  @override
  String get mpvEqPresetSaved => '已保存 EQ 预设';

  @override
  String mpvEqPresetDeleted(Object name) {
    return '已删除预设: $name';
  }

  @override
  String get mpvEqSavePresetTitle => '保存 EQ 预设';

  @override
  String get mpvEqSavePresetHint => '例如: 夜间对白 / 动漫人声';

  @override
  String get mpvEqMyPresetsTitle => '我的预设';

  @override
  String get mpvEqMyPresetsSubtitle => '把当前频段组合保存成多套预设，后面一键套用。';

  @override
  String get mpvEqSaveCurrent => '保存当前';

  @override
  String get mpvEqEmptyPresets => '还没有自定义 EQ 预设，调好以后可以直接保存。';

  @override
  String get mpvEqSummaryNeutral => '全部频段保持 0 dB。';

  @override
  String get mpvEqApply => '套用';

  @override
  String get homeTitle => '首页';

  @override
  String get homeContinueWatching => '继续观看';

  @override
  String get favoriteTabEpisodes => '剧集';

  @override
  String get favoriteTabPeople => '人物';

  @override
  String get homeActionViewDetail => '查看影片详情';

  @override
  String get homeActionRestartPlayback => '从头开始播放';

  @override
  String get homeActionRemoveFromContinue => '从“继续观看”中移除';

  @override
  String get homeRemovedFromContinue => '已从继续观看中移除';

  @override
  String get homeLoginRequired => '请先到“设置”页登录 NAS，再返回影视页加载内容。';

  @override
  String get parallelWindowTitle => '平行窗口设置';

  @override
  String get parallelWindowEnableTitle => '启用平行窗口';

  @override
  String get parallelWindowEnableSubtitle => '开启后，大屏设备的二级页面优先在副屏展开；关闭后使用单屏导航。';

  @override
  String get parallelWindowPrimarySideTitle => '主屏位置';

  @override
  String get parallelWindowPrimaryLeftTitle => '左侧主屏';

  @override
  String get parallelWindowPrimaryLeftSubtitle => '默认首页在左，右侧展开详情或设置。';

  @override
  String get parallelWindowPrimaryRightTitle => '右侧主屏';

  @override
  String get parallelWindowPrimaryRightSubtitle => '右侧为主屏，左侧展开详情或设置。';

  @override
  String get parallelWindowPlaybackSideTitle => '播放主屏位置';

  @override
  String get parallelWindowPlaybackLeftTitle => '左侧为播放主屏';

  @override
  String get parallelWindowPlaybackLeftSubtitle => '进入分屏播放后，左边保持播放器，右边放详情或首页。';

  @override
  String get parallelWindowPlaybackRightTitle => '右侧为播放主屏';

  @override
  String get parallelWindowPlaybackRightSubtitle => '进入分屏播放后，右边保持播放器，左边放详情或首页。';

  @override
  String get parallelWindowSplitRatioTitle => '分屏比例';

  @override
  String get parallelWindowSplitBalancedSubtitle => '默认，兼顾列表浏览和右侧详情。';

  @override
  String get parallelWindowSplitEqualSubtitle => '左右均衡，适合双侧并行操作。';

  @override
  String get parallelWindowSplitFocusDetailSubtitle => '副屏更宽，适合详情和播放信息。';

  @override
  String get parallelWindowSplitFocusHomeSubtitle => '主屏稍宽，适合首页或列表操作。';

  @override
  String get parallelWindowDefaultFullscreenTitle => '默认播放全屏';

  @override
  String get parallelWindowDefaultFullscreenOnSubtitle =>
      '点击播放后先进入全屏播放器，再由按钮切到分屏。';

  @override
  String get parallelWindowDefaultFullscreenOffSubtitle =>
      '点击播放后优先保持平行窗口分屏，不先放大全屏。';

  @override
  String get parallelWindowImmersiveTitle => '平行窗口沉浸模式';

  @override
  String get parallelWindowImmersiveOnSubtitle => '进入平行窗口后隐藏状态栏，内容直接顶到屏幕顶部。';

  @override
  String get parallelWindowImmersiveOffSubtitle => '保留状态栏，使用常规分屏显示。';

  @override
  String get danmakuSpeedNormal => '正常';

  @override
  String get danmakuSpeedFaster => '较快';

  @override
  String get danmakuAreaOneTenth => '1/10屏';

  @override
  String get danmakuAreaOneQuarter => '1/4屏';

  @override
  String get danmakuAreaThreeQuarters => '3/4屏';

  @override
  String get danmakuFontSmall => '较小';

  @override
  String get danmakuFontSlightlySmall => '偏小';

  @override
  String get danmakuFontStandard => '标准';

  @override
  String get danmakuFontSlightlyLarge => '偏大';

  @override
  String get danmakuFontLarge => '较大';

  @override
  String get danmakuSourceManagementTitle => '来源管理';

  @override
  String get danmakuSourceManagementSubtitle =>
      '统一管理网络弹幕和本地导入弹幕，支持按来源层级查看与手动删除。';

  @override
  String get danmakuManagementTitle => '弹幕管理';

  @override
  String danmakuSavedSourceCount(int count) {
    return '当前已保存 $count 个弹幕来源';
  }

  @override
  String get danmakuBasicSectionTitle => '基础';

  @override
  String get danmakuBasicSectionSubtitle => '这些是全局默认值，不依赖当前播放页面。';

  @override
  String get danmakuDefaultEnabledTitle => '默认开启弹幕';

  @override
  String get danmakuDefaultEnabledSubtitle => '进入播放器时默认带着弹幕设置启动。';

  @override
  String get danmakuPreviewEnabledTitle => '详情页预览弹幕';

  @override
  String get danmakuPreviewEnabledSubtitle => '在非播放页展示弹幕预览时使用这项默认值。';

  @override
  String get danmakuSourcePriorityTitle => '来源优先';

  @override
  String get danmakuSourcePrioritySubtitle => '控制本地弹幕和网络弹幕同时可用时的默认选择。';

  @override
  String get danmakuPreferLocal => '本地优先';

  @override
  String get danmakuPreferNetwork => '网络优先';

  @override
  String get danmakuDisplayStyleTitle => '显示样式';

  @override
  String get danmakuDisplayStyleSubtitle => '这些设置适合在非播放页提前调好，进播放器后直接沿用。';

  @override
  String get danmakuDisplayAreaTitle => '显示区域';

  @override
  String get danmakuOpacityTitle => '不透明度';

  @override
  String get danmakuDensityTitle => '弹幕密度';

  @override
  String get danmakuFontSizeTitle => '字体大小';

  @override
  String get danmakuSpeedTitle => '弹幕速度';

  @override
  String get danmakuTypeFilterTitle => '类型过滤';

  @override
  String get danmakuTypeFilterSubtitle => '控制默认显示哪些弹幕类型。';

  @override
  String get danmakuAvoidanceTitle => '防遮挡';

  @override
  String get danmakuAvoidanceSubtitle => '这些默认规则更适合全局预先设定。';

  @override
  String get commonRefresh => '刷新';

  @override
  String get playStatsTitle => '播放统计';

  @override
  String get playStatsClearTitle => '清空播放统计';

  @override
  String get playStatsClearContent => '这会删除本地播放历史和所有聚合统计数据。';

  @override
  String get playStatsClearTooltip => '清空统计';

  @override
  String playStatsLoadFailed(Object error) {
    return '加载播放统计失败：$error';
  }

  @override
  String get playStatsOverview => '总览';

  @override
  String get playStatsTotalPlayedDuration => '总播放时长';

  @override
  String get playStatsTotalClicks => '总点击数';

  @override
  String get playStatsTotalViews => '总观看数';

  @override
  String get playStatsTotalCompletedVideos => '总完播视频数';

  @override
  String get playStatsTotalCompletedSeasons => '总完播季数';

  @override
  String get playStatsBackfillTitle => '后台补全';

  @override
  String get playStatsBackfillRunning => '正在后台补全年份、国家、类型和演职人员。';

  @override
  String get playStatsAnimeList => '番剧列表';

  @override
  String get playStatsNoAnimeStats => '还没有番剧播放统计。';

  @override
  String get playStatsUnnamedAnime => '未命名番剧';

  @override
  String playStatsAnimeSubtitle(int seasonCount, int ungroupedCount) {
    return '季度 $seasonCount / 未分组视频 $ungroupedCount';
  }

  @override
  String get playStatsMovieList => '电影列表';

  @override
  String playStatsMovieSubtitle(int historyCount, int viewCount) {
    return '电影 / 历史 $historyCount 条 / 观看数 $viewCount';
  }

  @override
  String get playStatsOrphanVideos => '异常未归类视频';

  @override
  String playStatsOrphanSubtitle(int historyCount) {
    return '未匹配番剧或季度 / 历史 $historyCount 条';
  }

  @override
  String get playStatsUnlinkedHistory => '未关联历史';

  @override
  String playStatsCountItems(int count) {
    return '共 $count 条';
  }

  @override
  String get playStatsYes => '是';

  @override
  String get playStatsNo => '否';

  @override
  String playStatsDurationHours(int hours, int minutes, int seconds) {
    return '$hours 小时 $minutes 分钟 $seconds 秒';
  }

  @override
  String playStatsDurationMinutes(int minutes, int seconds) {
    return '$minutes 分钟 $seconds 秒';
  }

  @override
  String playStatsDurationSeconds(int seconds) {
    return '$seconds 秒';
  }

  @override
  String get playStatsStartSourceManual => '手动打开';

  @override
  String get playStatsStartSourceManualSwitch => '手动换集';

  @override
  String get playStatsStartSourceAutoNext => '自动连播';

  @override
  String get playStatsStartSourceReplay => '重播';

  @override
  String get playStatsStartSourceSystemResume => '系统恢复';

  @override
  String get playStatsAnimeDetail => '番剧详情';

  @override
  String get playStatsAnimeFields => '番剧字段';

  @override
  String get playStatsAnimeMetadata => '番剧元数据';

  @override
  String get playStatsSeasonList => '季度列表';

  @override
  String get playStatsNoSeasonData => '没有季度数据。';

  @override
  String get playStatsUnnamedSeason => '未命名季度';

  @override
  String playStatsSeasonSubtitle(int episodeCount, int completedCount) {
    return '剧集 $episodeCount / 已完播 $completedCount';
  }

  @override
  String get playStatsUngroupedVideos => '未归属到季度的视频';

  @override
  String get playStatsSeasonDetail => '季度详情';

  @override
  String get playStatsSeasonFields => '季度字段';

  @override
  String get playStatsCredits => '演职人员';

  @override
  String get playStatsEpisodeList => '剧集列表';

  @override
  String get playStatsNoEpisodeData => '没有剧集数据。';

  @override
  String get playStatsVideoDetail => '视频详情';

  @override
  String get playStatsMovieFields => '电影字段';

  @override
  String get playStatsEpisodeFields => '剧集字段';

  @override
  String get playStatsPlaybackHistory => '播放历史';

  @override
  String get playStatsNoPlaybackHistory => '没有播放历史。';

  @override
  String get playStatsHistoryDetail => '播放历史详情';

  @override
  String get playStatsHistoryFields => '历史字段';

  @override
  String get playStatsUnnamedVideo => '未命名视频';

  @override
  String playStatsVideoSubtitle(int historyCount, int viewCount) {
    return '历史 $historyCount 条 / 观看数 $viewCount';
  }

  @override
  String playStatsHistoryEntrySubtitle(
    Object startedAt,
    Object watchedDuration,
    Object completed,
  ) {
    return '$startedAt / 观看 $watchedDuration / 完播 $completed';
  }

  @override
  String get playStatsNoCreditSnapshot => '当前没有记录到演职人员快照。';

  @override
  String playStatsPageIndicator(int currentPage, int pageCount) {
    return '第 $currentPage 页 / 共 $pageCount 页';
  }

  @override
  String get playStatsPreviousPage => '上一页';

  @override
  String get playStatsNextPage => '下一页';

  @override
  String get playStatsFieldAnimeId => '番剧 ID';

  @override
  String get playStatsFieldTitle => '标题';

  @override
  String get playStatsFieldClickCount => '点击数';

  @override
  String get playStatsFieldViewCount => '观看数';

  @override
  String get playStatsFieldTotalPlayedDuration => '累计播放时长';

  @override
  String get playStatsFieldForwardSeekCount => '快进次数';

  @override
  String get playStatsFieldBackwardSeekCount => '回退次数';

  @override
  String get playStatsFieldWatchedEpisodeCount => '已观看正片集数';

  @override
  String get playStatsFieldCompletedEpisodeCount => '已完播正片集数';

  @override
  String get playStatsFieldCompletedSeasonCount => '已完播季数';

  @override
  String get playStatsFieldLastPlayedAt => '上次播放时间';

  @override
  String get playStatsFieldYear => '年份';

  @override
  String get playStatsFieldCountryFirstValue => '国家首值';

  @override
  String get playStatsFieldCountryCodes => '国家地区代码';

  @override
  String get playStatsFieldCountryNames => '国家地区中文';

  @override
  String get playStatsFieldGenreIds => '类型 ID';

  @override
  String get playStatsFieldGenreNames => '类型中文';

  @override
  String get playStatsFieldSeasonId => '季度 ID';

  @override
  String get playStatsFieldTotalEpisodeCount => '总正片集数';

  @override
  String get playStatsFieldWatchedEpisodeCountShort => '已观看集数';

  @override
  String get playStatsFieldCompletedEpisodeCountShort => '已完播集数';

  @override
  String get playStatsFieldIsSeasonCompleted => '是否季完播';

  @override
  String get playStatsFieldVideoId => '视频 ID';

  @override
  String get playStatsFieldAnimeTitle => '番剧标题';

  @override
  String get playStatsFieldSeasonTitle => '季度标题';

  @override
  String get playStatsFieldVideoKind => '视频种类';

  @override
  String get playStatsFieldCountsTowardCompletion => '是否计入季完播';

  @override
  String get playStatsFieldMediaDuration => '媒体总时长';

  @override
  String get playStatsFieldAutoPlayCount => '自动连播次数';

  @override
  String get playStatsFieldMaxProgress => '最大播放进度';

  @override
  String get playStatsFieldLastProgress => '最后播放进度';

  @override
  String get playStatsFieldLastPosition => '最后播放位置';

  @override
  String get playStatsFieldCompleted => '是否完播';

  @override
  String get playStatsFieldMetadataEnriched => '元数据已补全';

  @override
  String get playStatsFieldHistoryId => '历史 ID';

  @override
  String get playStatsFieldStartSource => '开始来源';

  @override
  String get playStatsFieldStartedAt => '开始时间';

  @override
  String get playStatsFieldEndedAt => '结束时间';

  @override
  String get playStatsFieldWatchedDuration => '观看时长';

  @override
  String get playStatsFieldMaxPosition => '最大播放位置';

  @override
  String get playStatsFieldCountedAsView => '是否计入观看';

  @override
  String get playStatsFieldCountedAsCompleted => '是否计入完播';

  @override
  String get playStatsFieldOpDetected => '已识别 OP';

  @override
  String get playStatsFieldEdDetected => '已识别 ED';

  @override
  String get playStatsFieldOpSkipped => '已跳过 OP';

  @override
  String get playStatsFieldEdSkipped => '已跳过 ED';

  @override
  String get playStatsFieldOpNotSkipped => '未跳过 OP';

  @override
  String get playStatsFieldEdNotSkipped => '未跳过 ED';

  @override
  String get playStatsFieldOpPlayedDuration => 'OP 播放时长';

  @override
  String get playStatsFieldEdPlayedDuration => 'ED 播放时长';

  @override
  String get playStatsFieldPersonId => '人员 ID';

  @override
  String get playStatsFieldName => '姓名';

  @override
  String get playStatsFieldRole => '角色';

  @override
  String get playStatsFieldJob => '工种';

  @override
  String get playStatsFieldOrder => '排序';

  @override
  String get commonRetry => '重试';

  @override
  String get playStatsReportDetailData => '详细数据';

  @override
  String get playStatsReportRangeTitle => '观影战报时间范围';

  @override
  String get playStatsReportSwitching => '切换中';

  @override
  String get playStatsReportBackfillingMetadata => '正在补全类型、国家地区、年份和演职人员数据';

  @override
  String get playStatsReportLoadFailedTitle => '加载播放统计失败';

  @override
  String get playStatsReportUnknownError => '未知错误';

  @override
  String playStatsReportErrorMessage(Object error) {
    return '错误信息：$error';
  }

  @override
  String get playStatsReportActivityTitle => '活跃趋势';

  @override
  String get playStatsReportActivitySubtitle => '按天观察播放时长变化，看看这段时间里哪几天看得最久。';

  @override
  String get playStatsReportDailyDurationTitle => '每日播放时长';

  @override
  String get playStatsReportDailyDurationSubtitle => '看最近一段时间里，哪几天看得最久。';

  @override
  String get playStatsReportContentTitle => '内容偏好';

  @override
  String get playStatsReportContentSubtitle => '用播放时长加权，看看你最近更偏好的内容类型与人物。';

  @override
  String get playStatsReportContentShare => '内容占比';

  @override
  String get playStatsReportAffinityTitle => '演职人员亲和榜';

  @override
  String get playStatsReportBehaviorTitle => '观看行为';

  @override
  String get playStatsReportBehaviorSubtitle => '统计来源、完播率、快进回退以及 OP/ED 的观看习惯。';

  @override
  String get playStatsReportStartSource => '播放来源';

  @override
  String playStatsReportCountTimes(int count) {
    return '$count 次';
  }

  @override
  String get playStatsReportCompletionRate => '完播率';

  @override
  String playStatsReportSessionRatio(int completed, int total) {
    return '$completed/$total 次会话';
  }

  @override
  String get playStatsReportTotalActions => '总操作数';

  @override
  String playStatsReportSeekSummary(int forwardCount, int backwardCount) {
    return '快进 $forwardCount · 回退 $backwardCount';
  }

  @override
  String get playStatsReportIntroOp => '片头 OP';

  @override
  String get playStatsReportOutroEd => '片尾 ED';

  @override
  String get playStatsReportRankingTitle => '排行与回看';

  @override
  String get playStatsReportRankingSubtitle => '保留最近活跃内容、继续观看线索和当前最常看的内容。';

  @override
  String get playStatsReportAnimeRankingTitle => '剧集榜';

  @override
  String get playStatsReportAnimeRankingSubtitle => '按剧集聚合后的总观看时长排行';

  @override
  String get playStatsReportVideoRankingTitle => '单集 / 视频榜';

  @override
  String get playStatsReportVideoRankingSubtitle => '按具体视频或单集聚合的观看时长排行';

  @override
  String get playStatsReportRecentHistoryTitle => '最近观看';

  @override
  String get playStatsReportRecentHistorySubtitle => '最近发生的播放记录时间线';

  @override
  String playStatsReportDurationHoursMinutes(int hours, int minutes) {
    return '$hours 小时 $minutes 分钟';
  }

  @override
  String playStatsReportDurationHours(int hours) {
    return '$hours 小时';
  }

  @override
  String playStatsReportDurationMinutes(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String get playStatsReportWeekdayMon => '一';

  @override
  String get playStatsReportWeekdayTue => '二';

  @override
  String get playStatsReportWeekdayWed => '三';

  @override
  String get playStatsReportWeekdayThu => '四';

  @override
  String get playStatsReportWeekdayFri => '五';

  @override
  String get playStatsReportWeekdaySat => '六';

  @override
  String get playStatsReportWeekdaySun => '日';

  @override
  String get playStatsReportStartSourceManual => '手动播放';

  @override
  String get playStatsReportStartSourceManualSwitch => '手动切换';

  @override
  String get playStatsReportStartSourceReplay => '重新播放';

  @override
  String playStatsReportHistorySubtitle(
    Object startedAt,
    Object watchedDuration,
  ) {
    return '$startedAt · 观看 $watchedDuration';
  }

  @override
  String playStatsReportHistoryMeta(
    Object source,
    Object watchedDuration,
    Object startedAt,
  ) {
    return '$source · 观看 $watchedDuration · $startedAt';
  }

  @override
  String playStatsReportMovieWatchedSubtitle(Object watchedDuration) {
    return '电影 · 观看 $watchedDuration';
  }

  @override
  String playStatsReportWatchedDuration(Object watchedDuration) {
    return '观看 $watchedDuration';
  }

  @override
  String get playStatsReportFrequentPerson => '常看人物';

  @override
  String playStatsReportProgress(Object progress) {
    return '进度 $progress';
  }

  @override
  String get playStatsReportOccupationDirector => '导演';

  @override
  String get playStatsReportOccupationProducer => '制片';

  @override
  String get playStatsReportOccupationExecutiveProducer => '监制';

  @override
  String get playStatsReportOccupationWriter => '编剧';

  @override
  String get playStatsReportOccupationOriginal => '原作';

  @override
  String get playStatsReportOccupationComposer => '作曲';

  @override
  String get playStatsReportOccupationMusic => '音乐';

  @override
  String get playStatsReportOccupationEditor => '剪辑';

  @override
  String get playStatsReportOccupationCinematography => '摄影';

  @override
  String get playStatsReportOccupationVoice => '配音';

  @override
  String get playStatsReportOccupationActor => '演员';

  @override
  String get playStatsReportOccupationCrew => '幕后';

  @override
  String get playStatsReportOccupationSound => '音效';

  @override
  String get playStatsReportOccupationArt => '美术';

  @override
  String get playStatsReportOccupationVisualEffects => '特效';

  @override
  String playStatsReportHeroTitle(Object range) {
    return '$range观影战报';
  }

  @override
  String get playStatsReportActiveDays => '活跃天数';

  @override
  String playStatsReportTotalDuration(Object duration) {
    return '累计 $duration';
  }

  @override
  String get playStatsReportClickCount => '播放次数';

  @override
  String get playStatsReportClickCountDescription =>
      '统计这段时间里，你主动点开播放或手动切换内容的次数。';

  @override
  String get playStatsReportClickCountDetail => '更接近你发起了多少次播放，不包含自动连播或系统恢复。';

  @override
  String get playStatsReportViewCount => '观看次数';

  @override
  String get playStatsReportViewCountDescription =>
      '只统计达到有效观看门槛的播放记录，用来看你真正进入观看状态了多少次。';

  @override
  String get playStatsReportViewCountDetail => '剧集需看满 20%，电影需看满 10%。';

  @override
  String get playStatsReportCompletedVideos => '完播视频';

  @override
  String get playStatsReportCompletedVideosDescription =>
      '统计被判定为完整看完的具体视频条目数，更接近你真正看完了多少集或多少部片。';

  @override
  String get playStatsReportCompletedVideosDetail =>
      '通常需要看满约 80%，并且结尾不是一拖而过，才会记入完播。';

  @override
  String get playStatsReportCompletedSeasons => '完播季度';

  @override
  String get playStatsReportCompletedSeasonsDescription =>
      '统计在当前时间范围内，被判定为整季看完的季度数量。';

  @override
  String get playStatsReportCompletedSeasonsDetail =>
      '只有计入季完播的正片都完成后，这一季才会记作 1 个完播季度。';

  @override
  String get playStatsReportMetadataCoverage => '元数据覆盖';

  @override
  String get playStatsReportMetadataCoverageDescription =>
      '反映这批内容里，类型、国家地区、年份和演职人员等信息补全得有多完整。';

  @override
  String get playStatsReportMetadataCoverageDetail =>
      '覆盖越高，下面的偏好分析和亲和榜越完整、越可靠。';

  @override
  String get playStatsReportNoTrendData => '暂无播放趋势数据';

  @override
  String get playStatsReportNoViewCountData => '暂无观看次数数据';

  @override
  String playStatsReportBarTooltip(int month, int day, int count) {
    return '$month/$day\n$count 次';
  }

  @override
  String get playStatsReportNoHeatmapData => '暂无活跃时段数据';

  @override
  String playStatsReportHeatmapTooltip(
    Object weekday,
    Object hour,
    int count,
    Object duration,
  ) {
    return '周$weekday $hour:00\n$count 次 / $duration';
  }

  @override
  String get playStatsReportHeatmapLow => '少';

  @override
  String get playStatsReportHeatmapHigh => '多';

  @override
  String get playStatsReportNoSeekActions => '本时间段几乎没有快进或回退操作';

  @override
  String playStatsReportNoDetectionRecord(Object label) {
    return '$label 暂无检测记录';
  }

  @override
  String playStatsReportOpEdDetectedSkipped(
    int detectedCount,
    int skippedCount,
  ) {
    return '检测 $detectedCount 次 · 跳过 $skippedCount 次';
  }

  @override
  String get playStatsReportSkipped => '跳过';

  @override
  String get playStatsReportWatchedCompletely => '完整观看';

  @override
  String get playStatsReportNoDistributionData => '暂无分布数据';

  @override
  String get playStatsReportMetadataBackfilling => '相关元数据还在补全中';

  @override
  String get playStatsReportNoRankingData => '当前没有足够的排行数据';

  @override
  String get playStatsReportNoRecentHistory => '最近还没有新的观看记录';

  @override
  String get playStatsReportJumpPageTitle => '跳转页码';

  @override
  String playStatsReportJumpPageDescription(int pageCount) {
    return '输入 1 到 $pageCount 之间的页码';
  }

  @override
  String get playStatsReportPageNumberLabel => '页码';

  @override
  String playStatsReportPageNumberHint(int page) {
    return '例如 $page';
  }

  @override
  String get playStatsReportJumpPageAction => '跳转';

  @override
  String playStatsReportPageIndicator(int currentPage, int pageCount) {
    return '第 $currentPage / $pageCount 页';
  }

  @override
  String get playStatsReportJumpPage => '跳页';

  @override
  String get playStatsReportFirstPage => '第一页';

  @override
  String get playStatsReportLastPage => '最后页';

  @override
  String get playStatsReportNoContinueWatching => '目前没有适合继续观看的内容';

  @override
  String playStatsReportLastWatchedAt(Object time) {
    return '上次观看 $time';
  }

  @override
  String get playStatsReportEmptyTitle => '还没有可展示的观影战报';

  @override
  String get playStatsReportEmptySubtitle => '开始播放内容后，这里会自动生成趋势、偏好、行为和回看报表。';

  @override
  String get playStatsReportUnnamedEpisode => '未命名剧集';

  @override
  String playStatsReportAnimeRankSubtitle(int sessionCount, int viewCount) {
    return '观看 $sessionCount 次 · 完整观看 $viewCount 次';
  }

  @override
  String get playStatsReportUnknownPerson => '未知人物';

  @override
  String get bookmarkManagerLegacyBookmark => '旧书签';

  @override
  String get bookmarkManagerUnnamedWork => '未命名作品';

  @override
  String get bookmarkManagerSpecialSeason => '特别篇';

  @override
  String bookmarkManagerSeasonLabel(int season) {
    return '第$season季';
  }

  @override
  String bookmarkManagerEpisodeLabel(int episode) {
    return '第$episode集';
  }

  @override
  String get bookmarkManagerUnnamedEpisode => '未命名剧集';

  @override
  String get bookmarkManagerEditNoteTitle => '编辑书签备注';

  @override
  String get bookmarkManagerNoEpisodeBookmarks => '该集下已经没有书签';

  @override
  String get bookmarkManagerNoteAction => '备注';

  @override
  String get danmakuManagerLegacySource => '旧来源';

  @override
  String get danmakuManagerUnnamedItem => '未命名条目';

  @override
  String danmakuManagerSourceCount(int count) {
    return '共 $count 个来源';
  }

  @override
  String get danmakuManagerNetworkDanmaku => '网络弹幕';

  @override
  String get danmakuManagerLocalImport => '本地导入';

  @override
  String danmakuManagerCommentCount(int count) {
    return '$count 条';
  }

  @override
  String get danmakuManagerUnnamedSource => '未命名弹幕来源';

  @override
  String mediaEpisodeCount(int count) {
    return '共$count集';
  }

  @override
  String mediaSeasonCount(int count) {
    return '共$count季';
  }

  @override
  String mediaWorkCount(int count) {
    return '共$count 个作品';
  }

  @override
  String get fileInfoLocationLabel => '文件位置';

  @override
  String get fileInfoSizeLabel => '文件大小';

  @override
  String get fileInfoCreatedAtLabel => '文件创建日期';

  @override
  String get fileInfoAddedAtLabel => '添加日期';

  @override
  String get fileInfoToggleToFriendly => '转换';

  @override
  String fileInfoStorageSpace(Object volumeNo) {
    return '存储空间$volumeNo';
  }

  @override
  String fileInfoStorageSpaceFile(Object volumeNo, Object name) {
    return '存储空间$volumeNo/$name 的文件';
  }

  @override
  String get fnConnectNasAddressFailed => 'FN Connect 登录失败，未能解析 NAS 地址';

  @override
  String get playerHostInvalidArgs => '当前播放器参数错误';

  @override
  String get themeSaveDefaultBase => '自定义主题';

  @override
  String themeSaveName(Object base) {
    return '$base主题色';
  }

  @override
  String storageSeriesGroupSubtitle(
    int seasonCount,
    int entryCount,
    Object size,
    Object time,
  ) {
    return '$seasonCount 季 · $entryCount 集 · $size · 最近 $time';
  }

  @override
  String storageSeasonGroupSubtitle(int entryCount, Object size, Object time) {
    return '$entryCount 集 · $size · 最近 $time';
  }

  @override
  String storageGroupedPageSummary(int totalCount, int pageSize) {
    return '$totalCount 个作品 · 每页 $pageSize 个';
  }

  @override
  String get storageUnknownWork => '未知作品';

  @override
  String get storageUngroupedSeason => '未分季';

  @override
  String storageSeasonNumberSpaced(int season) {
    return '第 $season 季';
  }

  @override
  String storageEpisodeTitleWithNumber(int episode, Object title) {
    return '第 $episode 集 $title';
  }

  @override
  String get storageUnknownEpisode => '未知集数';
}

/// The translations for Chinese, as used in China (`zh_CN`).
class AppLocalizationsZhCn extends AppLocalizationsZh {
  AppLocalizationsZhCn() : super('zh_CN');

  @override
  String get appTitle => 'Fly Player';

  @override
  String get globalLoadFailed => '加载失败';

  @override
  String get navMovies => '影视';

  @override
  String get navSettings => '设置';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsSearchTooltip => '搜索设置项';

  @override
  String get settingsLanguageTitle => '应用语言';

  @override
  String get settingsLanguageSubtitleSystem => '跟随系统';

  @override
  String get settingsLanguageSubtitleZhCN => '简体中文';

  @override
  String get languageSheetTitle => '应用语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get languageSystemSubtitle => '使用系统语言偏好';

  @override
  String get languageZhCN => '简体中文';

  @override
  String get languageZhCNSubtitle => '固定使用简体中文';

  @override
  String get commonCancel => '取消';

  @override
  String get commonConfirm => '确认';

  @override
  String get commonSave => '保存';

  @override
  String get commonRefreshRetry => '刷新重试';

  @override
  String get commonNone => '无';

  @override
  String get commonEmpty => '没有内容';

  @override
  String get commonNoData => '暂无数据';

  @override
  String get commonNoAccessLibrary => '没有可访问的媒体库，请联系管理员';

  @override
  String get authExitTitle => '退出登录';

  @override
  String get authExitContent => '确认退出当前帐号？';

  @override
  String get mediaAllItemsTitle => '全部影视';

  @override
  String get mediaLibraryFallbackName => '媒体库';

  @override
  String get collectionLayoutTitle => '布局方式';

  @override
  String get collectionLayoutSubtitle => '切换合集详情中的列表布局';

  @override
  String get collectionLayoutViewSection => '视图';

  @override
  String get collectionLayoutPosterWall => '海报墙';

  @override
  String get collectionLayoutList => '列表';

  @override
  String get collectionLayoutPosterSection => '海报';

  @override
  String get collectionLayoutHorizontalPoster => '横幅';

  @override
  String get collectionLayoutVerticalPoster => '竖幅';

  @override
  String collectionItemCount(int count) {
    return '共 $count 项';
  }

  @override
  String get localFileAuthorizeFirst => '请先授权一个文件夹，然后在应用内选择本地文件';

  @override
  String get localFileNoAuthorizedFolder => '还没有授权本地文件夹，先授权一个目录后才能在应用内浏览';

  @override
  String get localFileAuthorizationCanceled => '没有完成文件夹授权，无法读取本地文件';

  @override
  String get localFileAuthorizedFolderUnavailable => '已授权的目录当前不可访问，请重新授权文件夹';

  @override
  String get localFileReadDirectoryFailedRetry => '读取目录失败，请重新授权后重试';

  @override
  String localFileReadDirectoryFailed(Object error) {
    return '读取目录失败: $error';
  }

  @override
  String get localFileAuthorizeFolder => '授权文件夹';

  @override
  String get localFileChangeFolder => '更换文件夹';

  @override
  String get localFileParentDirectory => '返回上一级';

  @override
  String get localFileFolder => '文件夹';

  @override
  String get detailMoreActionsTitle => '更多操作';

  @override
  String get detailCurrentPage => '当前详情页';

  @override
  String get detailSaveCurrentTheme => '保存当前主题';

  @override
  String get detailSaveCurrentThemeSubtitle => '把当前取色保存成一套可复用的自定义主题';

  @override
  String get detailSaveCurrentThemeUnavailable => '当前页面还没有可保存的动态取色结果';

  @override
  String detailThemeSaved(Object name) {
    return '已保存主题：$name';
  }

  @override
  String get detailThemeNameLabel => '主题名称';

  @override
  String get detailThemeDescriptionLabel => '说明（可选）';

  @override
  String get detailThemeNameDuplicate => '主题名称不能重复';

  @override
  String get presetNameLabel => '名称';

  @override
  String get presetDescriptionLabel => '描述';

  @override
  String get presetNameRequired => '请输入名称';

  @override
  String get presetAutoFill => '自动填入';

  @override
  String get presetDescriptionHint => '可选，简单写一下这个预设的用途';

  @override
  String get audioSpecDolbySurround => '杜比环绕';

  @override
  String get audioSpecDolbyAtmos => '杜比全景声';

  @override
  String get audioSpecDts => 'DTS';

  @override
  String get audioSpecStereo => '立体声';

  @override
  String get resourceTypeDirectory => '目录';

  @override
  String get resourceTypeVideo => '视频';

  @override
  String get listFilterButton => '筛选';

  @override
  String get listFilterAll => '全部';

  @override
  String get listFilterResetButton => '重置';

  @override
  String get listFilterDecadeRecent => '今年';

  @override
  String get listTypeMovie => '电影';

  @override
  String get listTypeTv => '电视剧';

  @override
  String get listRecognitionUnmatched => '未匹配';

  @override
  String get listRecognitionMatched => '已匹配';

  @override
  String get listRecognitionNfo => 'NFO匹配';

  @override
  String get listWatched => '已观看';

  @override
  String get listUnwatched => '未观看';

  @override
  String get listFilterType => '影视分类';

  @override
  String get listFilterGenres => '类型';

  @override
  String get listFilterLocate => '国家和地区';

  @override
  String get listFilterDecade => '发行年份';

  @override
  String get listFilterResolution => '分辨率';

  @override
  String get listFilterColorRange => '视频动态范围';

  @override
  String get listFilterAudioType => '音频规格';

  @override
  String get listFilterRecognitionStatus => '匹配状态';

  @override
  String get listFilterWatched => '是否观看';

  @override
  String get listSortTitle => '排序';

  @override
  String get listSortCreateTime => '按添加日期';

  @override
  String get listSortReleaseDate => '按发行年份';

  @override
  String get listSortTitleField => '按标题';

  @override
  String get listSortVoteAverage => '按评分';

  @override
  String get listSortAsc => '升序';

  @override
  String get listSortDesc => '降序';

  @override
  String get searchHistory => '搜索历史';

  @override
  String searchResultCount(int count) {
    return '$count个搜索结果';
  }

  @override
  String get searchPlaceholder => '搜索';

  @override
  String personItemCount(int count) {
    return '共 $count 个作品';
  }

  @override
  String get personJobActor => '演员';

  @override
  String get personJobDirector => '导演';

  @override
  String get personJobScreenplay => '编剧';

  @override
  String get personJobWriter => '编剧';

  @override
  String get personJobProducer => '制片人';

  @override
  String personAsJob(Object job) {
    return '作为$job';
  }

  @override
  String get personBiographyTitle => '演员简介';

  @override
  String get routeErrorMissingDetail => '缺少详情参数';

  @override
  String get routeErrorMissingSeason => '缺少季详情参数';

  @override
  String get routeErrorMissingPerson => '缺少人物详情参数';

  @override
  String get routeErrorMissingDownload => '缺少下载详情参数';

  @override
  String get connectionAppName => '飞牛播放器';

  @override
  String get connectionUserNameHint => '用户名';

  @override
  String get connectionPasswordHint => '密码';

  @override
  String get connectionRememberLogin => '保持登录';

  @override
  String get connectionHttpsAccess => 'HTTPS 安全访问';

  @override
  String get connectionLogin => '登录';

  @override
  String get connectionOpenDownloads => '查看已下载数据';

  @override
  String get connectionLoginHistory => '登录历史';

  @override
  String get connectionClear => '清空';

  @override
  String get connectionNoLoginHistory => '暂无登录历史';

  @override
  String get connectionOperationFailedRetryLater => '操作失败，请稍后重试';

  @override
  String get connectionOperationFailedRetry => '操作失败，请重试';

  @override
  String get connectionServerRequired => '请输入服务器地址';

  @override
  String get connectionUserNameRequired => '请输入用户名';

  @override
  String get connectionPasswordRequired => '请输入密码';

  @override
  String get connectionInvalidCredential => '用户名或密码错误';

  @override
  String get connectionNetworkError => '网络异常，请检查后重试';

  @override
  String get connectionValidationFailed => '验证失败';

  @override
  String get settingsThemeTitle => '主题设置';

  @override
  String settingsThemeSubtitle(Object title, Object subtitle) {
    return '$title · $subtitle';
  }

  @override
  String get settingsThemeKeywords => '主题|配色|颜色|外观';

  @override
  String get settingsCustomThemeTitle => '自定义主题';

  @override
  String get settingsCustomThemeSubtitle => '已保存主题管理';

  @override
  String get settingsCustomThemeKeywords => '自定义主题|保存主题|主题管理';

  @override
  String get settingsCustomRecipeTitle => '颜色分类控制';

  @override
  String get settingsCustomRecipeSubtitle => '自定义主题配色编辑';

  @override
  String get settingsCustomRecipeLocation => '设置 > 主题设置 > 当前自定义';

  @override
  String get settingsCustomRecipeKeywords => '颜色分类|当前自定义|调色';

  @override
  String get settingsMpvTitle => 'MPV播放器设置';

  @override
  String get settingsMpvSubtitle => '播放器参数设置';

  @override
  String get settingsMpvKeywords => 'mpv|播放器|外部播放';

  @override
  String get settingsParallelWindowTitle => '并行窗口设置';

  @override
  String get settingsParallelWindowKeywords => '并行窗口|双屏|分屏';

  @override
  String get settingsParallelSummaryEnabledLeft => '已开启 · 左侧主屏';

  @override
  String get settingsParallelSummaryEnabledRight => '已开启 · 右侧主屏';

  @override
  String get settingsParallelSummaryDisabled => '已关闭 · 当前使用单屏模式';

  @override
  String get settingsDownloadTitle => '下载管理';

  @override
  String get settingsDownloadSubtitle => '已下载与下载中内容管理';

  @override
  String get settingsDownloadKeywords => '下载|下载管理|已下载|下载中|离线视频';

  @override
  String get settingsStorageTitle => '储存管理';

  @override
  String get settingsStorageSubtitle => '缓存、截图、日志与应用数据';

  @override
  String get settingsStorageKeywords => '储存管理|缓存|播放缓存|截图文件|应用数据|清理缓存';

  @override
  String get settingsPlayStatsTitle => '全局播放数据统计';

  @override
  String get settingsPlayStatsSubtitle => '本地播放统计与历史记录';

  @override
  String get settingsPlayStatsKeywords => '播放统计|播放历史|本地统计|sqlite';

  @override
  String get settingsOtherTitle => '其他';

  @override
  String get settingsOtherSubtitle => '书签、弹幕与截图设置';

  @override
  String get settingsOtherKeywords => '其他|辅助设置';

  @override
  String get settingsLogTitle => '日志信息';

  @override
  String get settingsLogSubtitle => '应用日志与导出';

  @override
  String get settingsLogKeywords => '日志|报错|txt|导出';

  @override
  String get settingsBookmarkTitle => '书签管理';

  @override
  String get settingsBookmarkSubtitle => '书签列表与定位';

  @override
  String get settingsBookmarkKeywords => '书签|bookmark';

  @override
  String get settingsDanmakuTitle => '弹幕设置';

  @override
  String get settingsDanmakuSubtitle => '默认样式与来源策略';

  @override
  String get settingsDanmakuKeywords => '弹幕|danmaku';

  @override
  String get settingsScreenshotTitle => '截图设置';

  @override
  String get settingsScreenshotSubtitle => '字幕携带和保存路径';

  @override
  String get settingsScreenshotKeywords => '截图|相册目录|保存路径';

  @override
  String get settingsScreenshotIncludeSubtitlesTitle => '截图是否携带字幕';

  @override
  String get settingsScreenshotIncludeSubtitlesSubtitle => '字幕携带选项';

  @override
  String get settingsScreenshotIncludeSubtitlesKeywords => '截图|字幕|携带字幕';

  @override
  String get settingsScreenshotSavePathTitle => '截图保存路径设置';

  @override
  String get settingsScreenshotSavePathSubtitle => '保存路径选项';

  @override
  String get settingsScreenshotSavePathKeywords => '截图|保存路径|相册目录';

  @override
  String get settingsScreenshotCustomDirectoryTitle => '截图自定义目录';

  @override
  String get settingsScreenshotCustomDirectorySubtitle => '自定义目录管理';

  @override
  String get settingsScreenshotCustomDirectoryKeywords => '截图|自定义目录|文件夹';

  @override
  String get settingsScreenshotPreviewTitle => '截图预览';

  @override
  String get settingsScreenshotPreviewSubtitle => '已保存截图管理';

  @override
  String get settingsScreenshotPreviewKeywords => '截图|预览|删除截图|管理截图';

  @override
  String get settingsMpvQuickModeTitle => 'MPV 快速模式';

  @override
  String get settingsMpvQuickModeSubtitle => '快捷预设与模式切换';

  @override
  String get settingsMpvQuickModeKeywords => 'mpv|快速模式|高保真|极速模式';

  @override
  String get settingsMpvPictureTitle => 'MPV 画面调节';

  @override
  String get settingsMpvPictureSubtitle => '滤镜、HDR、插帧与即时调节';

  @override
  String get settingsMpvPictureKeywords => 'mpv|画面|hdr|插帧|滤镜';

  @override
  String get settingsMpvAudioTitle => 'MPV 音频调节';

  @override
  String get settingsMpvAudioSubtitle => 'EQ、限幅、低音增强与人声增强';

  @override
  String get settingsMpvAudioKeywords => 'mpv|音频|eq|高保真|限幅';

  @override
  String get settingsMpvPlaybackTitle => 'MPV 播放与缓存';

  @override
  String get settingsMpvPlaybackSubtitle => '同步模式、缓存策略与缓存大小';

  @override
  String get settingsMpvPlaybackKeywords => 'mpv|缓存|缓冲|同步';

  @override
  String get settingsMpvCompatibilityTitle => 'MPV 兼容与诊断';

  @override
  String get settingsMpvCompatibilitySubtitle => '兼容模式和播放器诊断信息';

  @override
  String get settingsMpvCompatibilityKeywords => 'mpv|兼容|诊断|播放信息';

  @override
  String get settingsLocationRoot => '设置';

  @override
  String get settingsLocationTheme => '设置 > 主题设置';

  @override
  String get settingsLocationOther => '设置 > 其他';

  @override
  String get settingsLocationScreenshot => '设置 > 其他 > 截图设置';

  @override
  String get settingsLocationMpv => '设置 > MPV播放器设置';

  @override
  String settingsLocationMpvWithSection(Object section) {
    return '设置 > MPV播放器设置 > $section';
  }

  @override
  String get settingsMpvPictureSection => '画面调节';

  @override
  String get settingsMpvAudioSection => '音频调节';

  @override
  String get settingsMpvPlaybackSection => '播放与缓存';

  @override
  String get settingsMpvCompatibilitySection => '兼容与诊断';

  @override
  String get settingsSearchResults => '搜索结果';

  @override
  String get settingsSearchFrequent => '常用入口';

  @override
  String get settingsSearchHint => '搜索设置项';

  @override
  String get settingsSearchEmptyResults => '没有找到相关设置项。';

  @override
  String get settingsSearchEmptyPrompt => '先输入关键字，或从常用入口开始。';

  @override
  String get mpvContinueEnable => '继续开启';

  @override
  String get mpvGenericSettingTitle => '调节项';

  @override
  String get mpvPictureCategorySubtitle => '滤镜、渲染、HDR 与插帧';

  @override
  String get mpvPictureCategoryDescription => '围绕画面观感的细项调节，适合按片源逐步细调。';

  @override
  String get mpvAudioCategorySubtitle => '音量、EQ、增强与声道混合';

  @override
  String get mpvAudioCategoryDescription => '音频处理、高保真模式与声道输出设置。';

  @override
  String get mpvPlaybackCategorySubtitle => '同步模式、缓存策略与缓存大小';

  @override
  String get mpvPlaybackCategoryDescription => '主要影响拖动响应、缓存强度和播放稳定性。';

  @override
  String get mpvCompatibilityCategorySubtitle => '兼容模式与诊断';

  @override
  String get mpvCompatibilityCategoryDescription => '兼容性回退与播放诊断。';

  @override
  String get mpvSettingDebandTitle => '去色带';

  @override
  String get mpvSettingDebandSubtitle => '处理渐变断层和暗部条带。';

  @override
  String get mpvSettingSharpenTitle => '锐化';

  @override
  String get mpvSettingSharpenSubtitle => '提升线条和边缘清晰度。';

  @override
  String get mpvSettingDenoiseTitle => '降噪';

  @override
  String get mpvSettingDenoiseSubtitle => '压制噪点和颗粒感。';

  @override
  String get mpvSettingDeinterlaceTitle => '反交错';

  @override
  String get mpvSettingDeinterlaceSubtitle => '适配隔行扫描片源。';

  @override
  String get mpvSettingScaleProfileTitle => '缩放算法';

  @override
  String get mpvSettingScaleProfileSubtitle => '控制放大和缩小时的取向。';

  @override
  String get mpvSettingHdrModeTitle => 'HDR 处理';

  @override
  String get mpvSettingHdrModeSubtitle => '调整 HDR 映射和整体亮度取向。';

  @override
  String get mpvSettingFrameInterpolationTitle => '插帧';

  @override
  String get mpvSettingFrameInterpolationSubtitle => '提升运动流畅度，性能开销更高。';

  @override
  String get mpvSettingVideoSyncTitle => '同步模式';

  @override
  String get mpvSettingVideoSyncSubtitle => '控制音画同步与刷新率优先级。';

  @override
  String get mpvSettingCacheProfileTitle => '缓存策略';

  @override
  String get mpvSettingCacheProfileSubtitle => '按片源和网络环境切换缓存风格。';

  @override
  String get mpvSettingCacheSizeTitle => '缓存大小';

  @override
  String get mpvSettingCacheSizeSubtitle => '单独调整最大预读缓存上限。';

  @override
  String get mpvSettingVolumeGainTitle => '音量放大';

  @override
  String get mpvSettingVolumeGainSubtitle => '提高偏小声音源的输出上限。';

  @override
  String get mpvSettingAudioHighFidelityTitle => '高保真模式';

  @override
  String get mpvSettingAudioHighFidelitySubtitle => '优先保持干净解码输出，旁路大部分后处理。';

  @override
  String get mpvSettingDynamicRangeTitle => '动态范围压缩';

  @override
  String get mpvSettingDynamicRangeSubtitle => '让对白更靠前，夜间播放更稳。';

  @override
  String get mpvSettingAudioEqTitle => 'EQ 均衡器';

  @override
  String get mpvSettingAudioEqSubtitle => '调整低频、中频和高频的听感平衡。';

  @override
  String get mpvSettingAudioLimiterTitle => '峰值限幅';

  @override
  String get mpvSettingAudioLimiterSubtitle => '抑制突发峰值，避免爆音。';

  @override
  String get mpvSettingAudioBassBoostTitle => '低音增强';

  @override
  String get mpvSettingAudioBassBoostSubtitle => '增强低频氛围和下潜感。';

  @override
  String get mpvSettingAudioVoiceEnhanceTitle => '人声增强';

  @override
  String get mpvSettingAudioVoiceEnhanceSubtitle => '提升对白和人声清晰度。';

  @override
  String get mpvSettingChannelMixTitle => '声道混合';

  @override
  String get mpvSettingChannelMixSubtitle => '控制多声道输出的下混方式。';

  @override
  String get mpvSettingCompatibilityTitle => '兼容模式';

  @override
  String get mpvSettingCompatibilitySubtitle => '遇到异常时优先回退到更稳妥方案。';

  @override
  String get mpvCurrentSchemeTitle => '当前方案';

  @override
  String get mpvSmartRecommendationTitle => '智能推荐';

  @override
  String get mpvSmartRecommendationSubtitle =>
      '根据当前片源的分辨率、码率、HDR 和音轨信息推荐更合适的场景预设';

  @override
  String get mpvNoRecommendationTitle => '当前没有推荐';

  @override
  String get mpvNoRecommendationDescription => '当前片源信息还不完整，先保留手动选择。';

  @override
  String get mpvPictureQuickPresetTitle => '画质快速预设';

  @override
  String get mpvPictureQuickPresetSubtitle => '快速套用动画、影院、流畅等画质方案';

  @override
  String get mpvPictureQuickPresetDescription =>
      '这里只放画面相关方案，音频增强已经拆到独立的音频快速预设。';

  @override
  String get mpvAudioQuickPresetTitle => '音频快速预设';

  @override
  String get mpvAudioQuickPresetSubtitle => '高保真、EQ、低音增强、人声增强一键切换';

  @override
  String get mpvAudioQuickPresetDescription =>
      '一键切换高保真、对白增强、低频氛围和夜间压缩，不再和画质预设混在一起。';

  @override
  String get mpvCustomManagementTitle => '自定义管理';

  @override
  String get mpvCustomManagementSubtitle => '把画质自定义、音频自定义和即时调节统一收进三级页面管理';

  @override
  String get mpvCustomManagementDescription =>
      '首页只保留快速预设；即时调节、分类细调和保存当前预设都统一收进这里。';

  @override
  String get mpvPictureCustomTitle => '画质自定义';

  @override
  String get mpvPictureCustomSubtitle => '即时调节、滤镜、渲染、HDR、插帧、同步、缓存和兼容项';

  @override
  String get mpvPictureCustomDescription =>
      '即时调节和所有画质相关细项都统一放在这里管理，保存后会生成独立画质预设。';

  @override
  String get mpvAudioCustomTitle => '音频自定义';

  @override
  String get mpvAudioCustomSubtitle => '高保真、音量增强、EQ、限幅、低音增强、人声增强和声道混合';

  @override
  String get mpvAudioCustomDescription =>
      '把高保真、EQ、音量增强和所有音频后处理统一放在这里管理，保存后会生成独立音频预设。';

  @override
  String get mpvSaveCurrentPictureTitle => '保存当前画质';

  @override
  String get mpvSaveCurrentPictureSubtitle => '把当前即时调节和画质增强另存为独立预设';

  @override
  String get mpvSaveCurrentAudioTitle => '保存当前音频';

  @override
  String get mpvSaveCurrentAudioSubtitle => '把当前音频增强和 EQ 另存为独立预设';

  @override
  String get mpvInstantAdjustTitle => '即时调节';

  @override
  String get mpvInstantAdjustSubtitle => '亮度、对比度、饱和度、Gamma、色相';

  @override
  String get mpvSavedPicturePreset => '已保存画质预设';

  @override
  String get mpvSavedAudioPreset => '已保存音频预设';

  @override
  String get mpvCurrentCustom => '当前自定义';

  @override
  String get mpvNotUsed => '未使用';

  @override
  String get mpvDefault => '默认';

  @override
  String get mpvAllDefault => '全部默认';

  @override
  String mpvChangedCount(int count) {
    return '已调整 $count 项';
  }

  @override
  String get mpvSavedPresetKindPicture => '画质';

  @override
  String get mpvSavedPresetKindAudio => '音频';

  @override
  String mpvPresetNameLabel(Object kind) {
    return '$kind预设名称';
  }

  @override
  String mpvPresetDuplicateName(Object kind) {
    return '$kind预设名称不能重复';
  }

  @override
  String mpvPresetSavedMessage(Object kind, Object name) {
    return '已保存$kind预设：$name';
  }

  @override
  String mpvPresetDefaultBaseName(Object kind) {
    return '$kind预设';
  }

  @override
  String mpvPresetRenameTitle(Object kind) {
    return '重命名$kind预设';
  }

  @override
  String get commonRemarkOptional => '备注（可选）';

  @override
  String get commonDescriptionOptional => '说明（可选）';

  @override
  String get mpvPicturePresetOffLabel => '默认';

  @override
  String get mpvPicturePresetOffDescription => '关闭额外画质增强，优先保证兼容性和稳定性。';

  @override
  String get mpvPicturePresetAnimeLabel => '动画清晰';

  @override
  String get mpvPicturePresetAnimeDescription =>
      '通过轻微对比度和饱和度调整突出线条感，不再默认带入重滤镜。';

  @override
  String get mpvPicturePresetCinemaLabel => '影院柔和';

  @override
  String get mpvPicturePresetCinemaDescription => '用较轻的亮暗和饱和调整偏向影院观感，避免额外画面计算。';

  @override
  String get mpvPicturePresetSmoothLabel => '流畅优先';

  @override
  String get mpvPicturePresetSmoothDescription => '偏向稳定和响应的轻量流畅方案，不再默认带入插帧。';

  @override
  String get mpvAudioPresetOffLabel => '默认';

  @override
  String get mpvAudioPresetOffDescription => '关闭额外音频增强，保留基础播放参数。';

  @override
  String get mpvAudioPresetHiFiLabel => '原声保真';

  @override
  String get mpvAudioPresetHiFiDescription => '打开高保真，旁路 EQ 和增强，适合耳机和高质量片源。';

  @override
  String get mpvAudioPresetBalancedLabel => '通用增强';

  @override
  String get mpvAudioPresetBalancedDescription =>
      '轻度提亮人声和低频，适合大多数普通剧集、综艺和日常看片。';

  @override
  String get mpvAudioPresetDialogueLabel => '人声清晰';

  @override
  String get mpvAudioPresetDialogueDescription => '抬前对白和中高频细节，适合台词偏轻的片源。';

  @override
  String get mpvAudioPresetSpeakerClearLabel => '外放清晰';

  @override
  String get mpvAudioPresetSpeakerClearDescription =>
      '针对手机和平板外放，压住爆点、把对白往前推，减少糊成一团。';

  @override
  String get mpvAudioPresetCinemaBassLabel => '影院低频';

  @override
  String get mpvAudioPresetCinemaBassDescription => '增强低频氛围和厚度，适合动作片、配乐片和外放。';

  @override
  String get mpvAudioPresetHeadphoneImmersiveLabel => '耳机沉浸';

  @override
  String get mpvAudioPresetHeadphoneImmersiveDescription =>
      '保留动态感，补一点氛围和厚度，适合耳机听电影和演唱会现场。';

  @override
  String get mpvAudioPresetNightLabel => '夜间均衡';

  @override
  String get mpvAudioPresetNightDescription => '压低爆点、抬前对白，适合深夜外放和追剧。';

  @override
  String get mpvScenePresetStableClearLabel => '省电稳定';

  @override
  String get mpvScenePresetStableClearDescription =>
      '优先照顾解码稳定和系统流畅度，适合 4K、HDR、HEVC 和高码率片源。';

  @override
  String get mpvScenePresetBalancedMovieLabel => '通用观影';

  @override
  String get mpvScenePresetBalancedMovieDescription =>
      '用轻量画质和通用增强音频组成的日常观影片方案，适合大多数普通片源。';

  @override
  String get mpvScenePresetAnimeDialogueLabel => '追番对白';

  @override
  String get mpvScenePresetAnimeDialogueDescription =>
      '保留动画线条感并把对白往前提，适合动画、综艺和日常追番。';

  @override
  String get mpvScenePresetSpeakerClearLabel => '外放清晰';

  @override
  String get mpvScenePresetSpeakerClearDescription =>
      '优先照顾手机和平板外放，把爆点压住并把对白往前推。';

  @override
  String get mpvScenePresetNightBingeLabel => '夜间追剧';

  @override
  String get mpvScenePresetNightBingeDescription =>
      '偏向稳定和夜间聆听，压低爆点并减少长时间观看的刺耳感。';

  @override
  String get mpvScenePresetHeadphoneImmersiveLabel => '耳机沉浸';

  @override
  String get mpvScenePresetHeadphoneImmersiveDescription =>
      '画面保持轻柔层次，耳机下保留氛围感和低频厚度。';

  @override
  String get mpvSceneRecommendationStableTitle => '推荐稳定优先';

  @override
  String get mpvSceneRecommendationStableReason =>
      '当前片源负载偏高，建议先用更稳的轻量场景，避免播放器和系统一起掉帧。';

  @override
  String get mpvSceneRecommendationImmersiveTitle => '推荐电影沉浸';

  @override
  String get mpvSceneRecommendationImmersiveReason =>
      '当前音轨更适合保留氛围感和低频厚度的电影向组合。';

  @override
  String get mpvSceneRecommendationSpeakerTitle => '推荐清晰外放';

  @override
  String get mpvSceneRecommendationSpeakerReason =>
      '当前音轨偏轻，优先把对白和主体声推前，普通剧集和外放更省心。';

  @override
  String get mpvSceneRecommendationBalancedTitle => '推荐通用观影';

  @override
  String get mpvSceneRecommendationBalancedReason =>
      '当前片源负载正常，先用平衡一些的画质和音频组合最稳妥。';

  @override
  String get mpvVideoAdjustGenericTitle => '画面参数';

  @override
  String get mpvVideoAdjustBrightnessTitle => '亮度';

  @override
  String get mpvVideoAdjustBrightnessSubtitle => '提亮暗场或压暗过曝画面。';

  @override
  String get mpvVideoAdjustContrastTitle => '对比度';

  @override
  String get mpvVideoAdjustContrastSubtitle => '拉开明暗层次，数值过高会让高光和阴影更硬。';

  @override
  String get mpvVideoAdjustSaturationTitle => '饱和度';

  @override
  String get mpvVideoAdjustSaturationSubtitle => '控制整体颜色浓度。';

  @override
  String get mpvVideoAdjustGammaTitle => 'Gamma';

  @override
  String get mpvVideoAdjustGammaSubtitle => '偏向中间调修正，适合微调灰雾感和暗部层次。';

  @override
  String get mpvVideoAdjustHueTitle => '色相';

  @override
  String get mpvVideoAdjustHueSubtitle => '整体色调偏移，建议小幅调整，用来修正偏色片源。';

  @override
  String get mpvVideoAdjustStatusTitle => '画面参数';

  @override
  String get mpvVideoAdjustDescription =>
      '这些值会直接写入 mpv 的亮度、对比度、饱和度、Gamma 和色相参数，并会一起保存到画质预设中。';

  @override
  String get mpvVideoAdjustDrawerDescription =>
      '这些参数直接对应 mpv 原生视频均衡项，适合播放中微调，不会像 HDR 或插帧那样频繁触发重载。';

  @override
  String get mpvVideoAdjustAllDefaultSummary => '亮度、对比度、饱和度、Gamma 和色相都保持在默认值。';

  @override
  String get mpvOptionOff => '关闭';

  @override
  String get mpvOptionOn => '开启';

  @override
  String get mpvOptionAuto => '自动';

  @override
  String get mpvOptionLow => '轻度';

  @override
  String get mpvOptionMedium => '标准';

  @override
  String get mpvOptionStrong => '标准';

  @override
  String get mpvOptionFast => '快速';

  @override
  String get mpvOptionBalanced => '标准';

  @override
  String get mpvOptionQuality => '高质量';

  @override
  String get mpvOptionForce => '强制开启';

  @override
  String get mpvOptionSdrMap => 'SDR 映射';

  @override
  String get mpvOptionConservative => '保守映射';

  @override
  String get mpvOptionEnhanced => '增强映射';

  @override
  String get mpvOptionAudio => '音频优先';

  @override
  String get mpvOptionDisplay => '显示优先';

  @override
  String get mpvOptionSmooth => '平滑同步';

  @override
  String get mpvOptionDefault => '智能分配';

  @override
  String get mpvOptionLowLatency => '极速响应';

  @override
  String get mpvOptionStable => '稳定缓冲';

  @override
  String get mpvOptionNetwork => '网盘 / STRM / NAS';

  @override
  String get mpvOptionLight => '轻度';

  @override
  String get mpvOptionSoft => '柔和';

  @override
  String get mpvOptionClarity => '清晰';

  @override
  String get mpvOptionCinema => '影院';

  @override
  String get mpvOptionCustom => '高级自定义';

  @override
  String get mpvOptionStereo => '立体声优先';

  @override
  String get mpvOptionSurround => '环绕优先';

  @override
  String get mpvOptionSoftwareFallback => '软件优先';

  @override
  String get commonOk => '知道了';

  @override
  String get commonEnter => '进入';

  @override
  String get commonView => '查看';

  @override
  String get commonRename => '重命名';

  @override
  String get commonDelete => '删除';

  @override
  String get commonClear => '清空';

  @override
  String get commonJump => '跳转';

  @override
  String get playerAbLoopPoint => 'A点';

  @override
  String get playerAbLoopUnavailable => '当前时长不足，无法设置 A-B 循环';

  @override
  String playerAbLoopPointSet(Object position) {
    return 'A 点已设置到 $position';
  }

  @override
  String get playerAbLoopMinimumSpan => 'A-B 间隔至少需要 0.8 秒';

  @override
  String playerAbLoopSet(Object start, Object end) {
    return 'A-B 循环已设置 $start - $end';
  }

  @override
  String get playerAbLoopCleared => 'A-B 循环已清除';

  @override
  String get playerBookmarkNone => '无书签';

  @override
  String playerBookmarkCount(int count) {
    return '$count 个';
  }

  @override
  String get playerBookmarkEmptySummary => '为当前片段记录关键时间点，之后可以快速跳回。';

  @override
  String playerBookmarkRecentSummary(Object position, int count) {
    return '最近书签 $position，共 $count 个。';
  }

  @override
  String get playerBookmarkNoteDialogTitle => '添加书签备注';

  @override
  String playerBookmarkAdded(Object position) {
    return '已添加书签 $position';
  }

  @override
  String get playerBookmarkDeleted => '已删除书签';

  @override
  String get playerBookmarkCleared => '当前片段书签已清空';

  @override
  String playerBookmarkJumped(Object position) {
    return '已跳转到 $position';
  }

  @override
  String get playerBookmarkTitle => '书签';

  @override
  String get playerBookmarkAddCurrent => '添加当前';

  @override
  String get playerBookmarkCurrentSegment => '当前片段';

  @override
  String get playerBookmarkEmptyPrompt => '还没有书签，点击右上角“添加当前”即可记录当前时间点。';

  @override
  String playerBookmarkCreatedAt(Object time) {
    return '创建于 $time';
  }

  @override
  String get playerEpisodeList => '剧集列表';

  @override
  String get playerEpisodeSpecialSeason => '特别篇';

  @override
  String playerEpisodeSeasonTemplate(Object season) {
    return '第$season季';
  }

  @override
  String get playerEpisodePlaying => '播放中..';

  @override
  String get playerEpisodeWatched => '已观看';

  @override
  String playerEpisodeWatchedPercent(Object percent) {
    return '已观看$percent%';
  }

  @override
  String get playerEpisodeUnwatched => '未观看';

  @override
  String get playerEpisodePickerTitle => '选集';

  @override
  String get playerEpisodeLast => '已经是最后一集了';

  @override
  String get playerEpisodeFirst => '已经是第一集了';

  @override
  String get playerEpisodeViewSaveFailed => '选集视图保存失败';

  @override
  String get playerEpisodeNoAvailableList => '当前片源没有可用选集列表';

  @override
  String playerEpisodeLoadListFailed(Object error) {
    return '加载选集列表失败: $error';
  }

  @override
  String playerEpisodeLoadSeasonFailed(Object error) {
    return '加载该季选集失败: $error';
  }

  @override
  String playerEpisodeNumberLabel(int episode) {
    return '第 $episode 集';
  }

  @override
  String get playerEpisodePreparingPlayback => '正在准备播放...';

  @override
  String playerEpisodeSwitchingTo(Object episode) {
    return '正在切换到 $episode...';
  }

  @override
  String get playerSubtitleLanguageEnglish => '英文';

  @override
  String get playerSubtitleLanguageChinese => '中文';

  @override
  String get playerSubtitleClosing => '正在关闭字幕...';

  @override
  String playerSubtitleSwitching(Object title, Object suffix) {
    return '正在切换到$title$suffix 字幕...';
  }

  @override
  String get playerSubtitleClosingPleaseWait => '正在为您关闭字幕，请稍等...';

  @override
  String playerSubtitleSwitchingPleaseWait(Object title, Object suffix) {
    return '正在为您切换至$title$suffix 字幕，请稍等...';
  }

  @override
  String get playerSubtitleUnknownTrack => '未知字幕';

  @override
  String get playerSubtitleExternal => '外挂';

  @override
  String get playerSubtitleFileFallbackApplied => '当前字幕文件不可直接获取，已切换兼容方案';

  @override
  String playerSubtitleLoadFailed(Object error) {
    return '字幕加载失败: $error';
  }

  @override
  String get playerAudioUnknownTrack => '未知音轨';

  @override
  String get playerQualityOriginal => '原画';

  @override
  String get playerQualityGeneric => '清晰度';

  @override
  String get playerLoadingPreparingEnvironment => '正在准备播放环境...';

  @override
  String get playerLoadingInitializingPlayer => '正在初始化播放器...';

  @override
  String get playerLoadingPreparingSource => '正在准备播放源...';

  @override
  String get playerLoadingBuffering => '视频缓冲中...';

  @override
  String get playerLoadingSeeking => '正在定位播放进度...';

  @override
  String get playerLoadingOpeningSource => '正在打开播放源...';

  @override
  String get playerLoadingPreparingVideo => '正在准备画面...';

  @override
  String get playerLoadingVideo => '视频加载中...';

  @override
  String get mpvNoSavedPicturePresetTitle => '暂无已保存画质预设';

  @override
  String get mpvNoSavedPicturePresetContent => '可在“画质自定义”中保存预设。';

  @override
  String get mpvNoSavedAudioPresetTitle => '暂无已保存音频预设';

  @override
  String get mpvNoSavedAudioPresetContent => '可在“音频自定义”中保存预设。';

  @override
  String get mpvPresetManagementStatus => '预设管理';

  @override
  String get mpvPresetManagementSummary => '画质自定义、音频自定义与已保存预设管理。';

  @override
  String get mpvSavedPresetDefaultDescription => '已保存的独立预设，可随时再次应用。';

  @override
  String get mpvPresetApplied => '当前已应用';

  @override
  String get mpvTapToApply => '点按应用';

  @override
  String get mpvVideoFiltersCategoryTitle => '视频滤镜';

  @override
  String get mpvVideoFiltersCategorySubtitle => '去色带、锐化、降噪、反交错、缩放算法';

  @override
  String get mpvVideoFiltersCategoryDescription => '主要针对画面净化、边缘锐度和缩放观感。';

  @override
  String get mpvPlayerDiagnosticsTitle => '播放器诊断信息';

  @override
  String get mpvPlayerDiagnosticsSubtitle => '查看当前 codec、输出、色彩和源信息';

  @override
  String get mpvCacheSettingStatusTitle => '缓存设定';

  @override
  String get mpvCacheSettingAutoDescription =>
      '当前由缓存策略自动分配上限。关闭自动后，可直接拖动滑杆控制缓存百分比。';

  @override
  String get mpvCacheSettingManualDescription =>
      '缓存百分比越高，越有利于高码率和不稳定网络，但也会占用更多内存和存储。';

  @override
  String get mpvCacheAutoSwitchTitle => '自动缓存';

  @override
  String get mpvCacheAutoSwitchAutoSubtitle => '当前由缓存策略自动分配缓冲上限';

  @override
  String get mpvCacheAutoSwitchManualSubtitle => '关闭后可手动指定缓存百分比';

  @override
  String get mpvCacheSliderTitle => '滑动设定';

  @override
  String get mpvCacheSliderSubtitle => '拖动滑杆调整缓存百分比，修改后会立即应用到当前播放器。';

  @override
  String mpvCachePercentSettingLabel(Object value) {
    return '缓存设定：$value';
  }

  @override
  String get mpvCacheHelpDefaultContent =>
      '自动档。播放器会根据片源类型决定更合适的缓冲强度，本地文件更偏常规，较重的网络片源会自动偏向更稳的缓冲。';

  @override
  String get mpvCacheHelpLowLatencyContent =>
      '预读最轻，拖动、切换和回填最快，但抗抖动最弱。更适合本地视频，或者局域网很稳时追求跟手感。';

  @override
  String get mpvCacheHelpStableContent =>
      '中等偏重缓冲，优先减少抖动导致的卡顿。拖动响应会比极速慢一点，但更适合大多数 NAS、网盘和 STRM 观看。';

  @override
  String get mpvCacheHelpNetworkContent =>
      '最重的一档，给高码率网盘、STRM 和 NAS 片源更多预读空间。起播和拖动后的回填更重，但最抗波动。';

  @override
  String get mpvCacheHelpGenericContent => '当前选项用于控制预读力度和缓冲风格。';

  @override
  String get mpvCacheHelpDefaultExtra => '适合：不想自己判断时直接用。';

  @override
  String get mpvCacheHelpLowLatencyExtra => '适合：本地硬盘视频、局域网很稳时的 NAS。';

  @override
  String get mpvCacheHelpStableExtra => '适合：大多数 NAS、网盘和普通 STRM。';

  @override
  String get mpvCacheHelpNetworkExtra => '适合：高码率、大体积、跨网络访问的片源。';

  @override
  String get mpvPerformanceWarningTitle => '性能提醒';

  @override
  String get mpvPerformanceWarningDebandMedium =>
      '中档去色带会增加额外画面处理开销，部分设备可能出现掉帧、发热或系统卡顿。';

  @override
  String get mpvPerformanceWarningSharpen =>
      '锐化会增加滤镜计算量，片源较重或设备较弱时可能导致播放掉帧和界面不流畅。';

  @override
  String get mpvPerformanceWarningDenoise =>
      '降噪属于较重的视频滤镜，移动设备上很容易带来明显掉帧、发热甚至系统卡顿。';

  @override
  String get mpvPerformanceWarningDeinterlaceForce =>
      '强制反交错会让所有片源都走额外处理链路，普通逐行片源通常没有必要，且可能拖慢播放。';

  @override
  String get mpvPerformanceWarningScaleQuality =>
      '高质量缩放会增加 GPU 和渲染压力，高分辨率或高码率片源上更容易出现掉帧。';

  @override
  String get mpvPerformanceWarningHdr =>
      '这个 HDR 模式会增加色调映射压力，HDR、10-bit 或高分辨率片源上可能导致明显卡顿。';

  @override
  String get mpvPerformanceWarningFrameInterpolation =>
      '插帧是最容易拖慢播放和系统流畅度的选项之一，开启后可能出现视频掉帧、UI 掉帧和系统卡顿。';

  @override
  String get mpvPerformanceWarningVideoSyncSmooth =>
      '平滑同步会更积极地贴合屏幕刷新率，部分设备上会增加合成与同步压力。';

  @override
  String get mpvPerformanceWarningCacheNetwork =>
      '网络重缓存会占用更多内存，并让拖动回填更重，只建议在高码率远程片源上使用。';

  @override
  String get mpvPerformanceWarningCacheSize =>
      '较大的缓冲会占用更多内存，并让起播、拖动后的回填更重；低内存设备上可能影响系统流畅度。';

  @override
  String get mpvPerformanceWarningGeneric => '当前选项可能增加播放器负载，请根据设备性能谨慎开启。';

  @override
  String get mpvAudioEqAdvancedTitle => '高级频段调整';

  @override
  String get mpvAudioEqAdvancedSubtitle => '进入上下滑动频谱页，自定义每个频段并保存多套预设。';

  @override
  String get mpvAudioEqAdvancedHeader => '高级均衡';

  @override
  String get mpvCurrentlyUsed => '当前使用';

  @override
  String get commonReset => '重置';

  @override
  String get commonRestoreDefault => '恢复默认';

  @override
  String playerQualitySwitching(Object quality, Object suffix) {
    return '正在为您切换至 $quality$suffix 画质，请稍等...';
  }

  @override
  String playerQualitySwitchFailed(Object error) {
    return '切换清晰度失败: $error';
  }

  @override
  String get playerQualityNoAvailableOptions => '当前没有可切换清晰度';

  @override
  String get playerQualitySheetTitle => '清晰度';

  @override
  String get playerQualitySheetSection => '清晰度列表';

  @override
  String get playerQualityRecommendedExpired => '推荐清晰度已失效';

  @override
  String get playerQualityDownloaded => '已下载';

  @override
  String playerWeakNetworkSuggestionTitle(Object quality) {
    return '网络较慢，建议切换到 $quality';
  }

  @override
  String playerWeakNetworkSwitching(Object quality) {
    return '网络较慢，正在切换到 $quality，请稍候...';
  }

  @override
  String get playerAutoFilterFallbackApplied => '检测到帧率不稳定，已自动关闭滤镜';

  @override
  String get playerAdvancedSettingsTitle => '高级设置';

  @override
  String get playerDecoderTitle => '解码方式';

  @override
  String get playerDecoderSubtitle => '切换当前播放器使用的解码方式';

  @override
  String get playerCacheSettingsTitle => '缓存设置';

  @override
  String get playerCacheSettingsSubtitle => '直接按百分比调节播放器缓存策略强度。';

  @override
  String get playerMonitorTitle => '播放监测';

  @override
  String get playerMonitorSubtitle => '设置左上角悬浮信息显示的性能占用和实时帧率';

  @override
  String get playerExtremePlaybackTitle => '极限播放';

  @override
  String get playerExtremePlaybackEnabledSubtitle =>
      '边下边播已开启，退出播放器后会清理本次播放缓存。切换时会重新加载当前播放源。';

  @override
  String get playerExtremePlaybackDisabledSubtitle =>
      '边下边播开启后，退出播放器会自动删除已下载缓存，但会增加内存和存储空间消耗。';

  @override
  String get playerVideoInfoTitle => '视频信息';

  @override
  String get playerVideoInfoSubtitle => '查看当前播放链路、渲染输出和片源信息';

  @override
  String get playerMonitorStatusTitle => '播放监控';

  @override
  String get playerMonitorStatusDescription =>
      '显示在左上角，可拖动并记住位置。GPU 占用取决于设备是否开放系统节点。';

  @override
  String get playerPerformanceMonitorTitle => '性能监控';

  @override
  String get playerPerformanceMonitorSubtitle => '显示 CPU / GPU 占用百分比';

  @override
  String get playerFpsMonitorTitle => '实时帧率';

  @override
  String get playerFpsMonitorSubtitle => '显示当前视频输出 FPS，默认关闭';

  @override
  String get playerHardwareDecoderTitle => '硬件解码';

  @override
  String get playerHardwareDecoderSubtitle => '性能高，优先选择';

  @override
  String get playerSoftwareDecoderTitle => '软件解码';

  @override
  String get playerSoftwareDecoderSubtitle => '兼容性更高，适合硬解异常时切换';

  @override
  String playerDecoderSwitching(Object mode) {
    return '正在切换为 $mode，请稍等...';
  }

  @override
  String get playerMonitorPartiallyEnabled => '部分开启';

  @override
  String get playerMonitorOff => '已关闭';

  @override
  String get playerAspectFit => '适应';

  @override
  String get playerAspectFill => '填充';

  @override
  String get playerAspectRatioTitle => '画面比例';

  @override
  String get playerPreparingPlayback => '正在准备播放';

  @override
  String get playerRefreshingPlaybackSession => '正在刷新播放会话...';

  @override
  String get playerPlaybackSessionExpiredRecovering => '播放会话已过期，正在恢复播放...';

  @override
  String get playerRefreshPlaybackSessionFailed => '刷新播放会话失败';

  @override
  String get playerRecoverPlaybackSessionFailed => '恢复播放会话失败';

  @override
  String playerGenericError(Object title, Object error) {
    return '$title: $error';
  }

  @override
  String get playerIntroSkipped => '已跳过片头';

  @override
  String get playerOutroSkipped => '已跳过片尾';

  @override
  String get playerChapterSkipPromptDismissed =>
      '本次播放已忽略跳过提示，如需关闭可在设置中禁用片头片尾跳过。';

  @override
  String get playerCacheFullyAvailable => '当前视频已全部缓存';

  @override
  String get playerCacheNotReadyForDownload => '当前缓存尚未完整，暂时不能转为下载';

  @override
  String get playerCurrentVideo => '当前视频';

  @override
  String get playerCacheImportFailed => '缓存转下载失败';

  @override
  String get playerCacheImportedToDownload => '已转为下载';

  @override
  String get playerAlreadyInDownloadList => '已在下载列表中';

  @override
  String get playerAddingToDownloadList => '正在加入下载列表';

  @override
  String get playerLayoutSwitchFailed => '切换播放布局失败';

  @override
  String get playerUiLocked => '界面已锁定';

  @override
  String get playerUiUnlocked => '界面已解锁';

  @override
  String get playerReloadRequiredRecovering => '当前播放需要重新加载，正在为您恢复播放，请稍候...';

  @override
  String get playerErrorHintFailed => '失败';

  @override
  String get playerErrorHintError => '错误';

  @override
  String get playerErrorHintUnavailable => '不可';

  @override
  String get playerErrorHintMissing => '缺少';

  @override
  String get playerErrorHintNone => '暂无';

  @override
  String get playerErrorHintNotLoaded => '未加载';

  @override
  String get playerErrorHintNotExtracted => '未提取';

  @override
  String get playerSettingsTitle => '设置';

  @override
  String get playerAutoRotateTitle => '自动旋转';

  @override
  String get playerAutoRotateSystemSubtitle => '跟随系统方向自动切换';

  @override
  String get playerAutoRotateLockedSubtitle => '锁定当前播放方向';

  @override
  String get playerAutoPlayTitle => '自动连播';

  @override
  String get playerAutoPlayEnabledSubtitle => '当前集播放完成后自动播放下一集';

  @override
  String get playerAutoPlayDisabledSubtitle => '关闭后播放完成停留当前集';

  @override
  String get playerNextEpisodePreloadTitle => '下一级预加载';

  @override
  String get playerNextEpisodePreloadEnabledSubtitle =>
      '片尾倒计时开始时预加载下一集，尽量减少黑屏和等待';

  @override
  String get playerNextEpisodePreloadDisabledSubtitle => '关闭后保持原本的自动连播切集方式';

  @override
  String get playerNextEpisodePreloadRequiresAutoPlay => '需先开启自动连播';

  @override
  String playerCurrentValue(Object value) {
    return '当前：$value';
  }

  @override
  String get playerIntroOutroSettingsTitle => '片头片尾设置';

  @override
  String get playerBookmarkSettingsSubtitle => '记录当前片段关键时间点并快速跳转';

  @override
  String get playerSelectIntroChapterTitle => '选择片头章节';

  @override
  String get playerSelectOutroChapterTitle => '选择片尾章节';

  @override
  String get playerIntroOutroStatusTitle => 'OP/ED 跳过';

  @override
  String get playerEnabled => '已开启';

  @override
  String get playerIntroOutroAutoSkipToggleTitle => '启用自动跳过';

  @override
  String get playerIntroOutroAutoSkipToggleSubtitle => '开启后按官方配置跳过片头片尾';

  @override
  String get playerAdvancedAdjustmentLabel => '高级调整';

  @override
  String get playerIntroOutroDefaultDurationHint => '默认 1-2 分钟，必要时再微调';

  @override
  String get playerIntroOutroOffTitle => '关闭';

  @override
  String get playerIntroOutroOffSubtitle => '不自动跳过片头片尾';

  @override
  String get playerIntroOutroOfficialTitle => '自动跳过官方片头片尾';

  @override
  String get playerIntroOutroOfficialSubtitle => '使用飞牛官方片头片尾时长配置';

  @override
  String get playerIntroOutroOfficialSettingsTitle => '飞牛官方设置';

  @override
  String get playerIntroOutroOfficialSettingsSubtitle => '设置官方片头片尾跳过时长';

  @override
  String get playerIntroOutroChapterModeTitle => '章节判断跳过';

  @override
  String get playerIntroOutroChapterModeSubtitle => '根据章节自动判断，或手动选择章节作为 OP/ED';

  @override
  String get playerIntroOutroChapterSettingsTitle => '章节跳过设置';

  @override
  String get playerSkipIntroTitle => '跳过片头';

  @override
  String get playerSkipOutroTitle => '跳过片尾';

  @override
  String get playerIntroDurationTitle => '片头时长';

  @override
  String get playerOutroDurationTitle => '片尾时长';

  @override
  String get playerOfficialIntroDescription => '设置官方片头跳过时长';

  @override
  String get playerOfficialOutroDescription => '设置官方片尾跳过时长';

  @override
  String get playerCurrentPlaybackTime => '当前播放时间';

  @override
  String get playerSetAsIntro => '设为片头';

  @override
  String get playerSetAsOutro => '设为片尾';

  @override
  String get playerCustomDurationTitle => '自定义';

  @override
  String get playerCustomDurationSubtitle => '距离片头/片尾多少秒时开始跳过';

  @override
  String get playerResetToZeroSeconds => '恢复为 0 秒';

  @override
  String get playerIntroOutroAutoModeTitle => '自动判断';

  @override
  String get playerIntroOutroAutoModeSubtitle => '根据章节位置和短章节时长自动识别 OP/ED';

  @override
  String get playerIntroOutroManualModeTitle => '手动选择章节';

  @override
  String get playerIntroOutroManualModeSubtitle => '手动指定章节作为片头片尾';

  @override
  String get playerIntroOutroAutoRangeLabel => '自动判断范围';

  @override
  String get playerIntroMaxChapterDurationTitle => '片头最大章节时长';

  @override
  String get playerIntroMaxChapterDurationSubtitle => '前段短章节小于该时长时，优先判定为片头';

  @override
  String get playerOutroMaxChapterDurationTitle => '片尾最大章节时长';

  @override
  String get playerOutroMaxChapterDurationSubtitle => '尾段短章节小于该时长时，优先判定为片尾';

  @override
  String get playerIntroChapterTitle => '片头章节';

  @override
  String get playerIntroChapterSubtitle => '手动指定片头章节';

  @override
  String get playerOutroChapterTitle => '片尾章节';

  @override
  String get playerOutroChapterSubtitle => '手动指定片尾章节';

  @override
  String get playerUnset => '未设置';

  @override
  String playerChapterNumber(int chapter) {
    return '第 $chapter 章';
  }

  @override
  String playerChapterLoadFailed(Object error) {
    return '读取章节失败: $error';
  }

  @override
  String get playerNoAvailableChapters => '当前视频没有可用章节';

  @override
  String get playerNoChapter => '不使用章节';

  @override
  String get playerIntroOutroSourceChapterLabel => '章节判断';

  @override
  String get playerIntroOutroSourceOffLabel => '已关闭';

  @override
  String get playerIntroOutroManualLabel => '手动选择';

  @override
  String get playerIntroOutroAutoLabel => '自动判断';

  @override
  String playerIntroOutroManualSummary(Object intro, Object outro) {
    return '片头：$intro，片尾：$outro';
  }

  @override
  String get playerUnrecognized => '未识别';

  @override
  String playerIntroOutroAutoSummary(Object intro, Object outro) {
    return '自动判断结果，片头：$intro，片尾：$outro';
  }

  @override
  String get playerIntroOutroOffSummary => '关闭后不会自动跳过片头片尾';

  @override
  String playerIntroOutroOfficialSummary(Object intro, Object outro) {
    return '官方片头 $intro，片尾 $outro';
  }

  @override
  String playerEpisodeSwitchFailed(Object error) {
    return '切换剧集失败: $error';
  }

  @override
  String get playerNotReady => '播放器未就绪';

  @override
  String get playerListenVideoEnabled => '已开启听视频模式';

  @override
  String get playerListenVideoRestored => '已恢复视频画面';

  @override
  String get playerListenVideoSwitchFailed => '听视频模式切换失败';

  @override
  String get playerVideoRestoreFailed => '视频画面恢复失败';

  @override
  String get playerScreenshotModuleMissing => '截图模块未加载，请重启应用';

  @override
  String get playerScreenshotFailed => '截图失败';

  @override
  String get playerScreenshotSaved => '截图已保存';

  @override
  String get playerScreenshotCustomDirectoryRequired => '请先在截图设置里选择自定义目录';

  @override
  String get playerScreenshotCustomDirectoryUnavailable => '自定义目录不可用，请重新选择';

  @override
  String get playerScreenshotUnavailable => '当前还不能截图';

  @override
  String get playerScreenshotSaveFailed => '截图保存失败';

  @override
  String get playerDiagnosticsTitle => '播放诊断';

  @override
  String playerDiagnosticsLoadFailed(Object error) {
    return '读取播放诊断失败：$error';
  }

  @override
  String get playerDiagnosticsEmpty => '暂时没有可显示的播放信息';

  @override
  String get playerDiagnosticsPlaybackSection => '播放信息';

  @override
  String get playerDiagnosticsStatus => '状态';

  @override
  String get playerDiagnosticsPosition => '当前位置';

  @override
  String get playerDiagnosticsDuration => '总时长';

  @override
  String get playerDiagnosticsSpeed => '播放速度';

  @override
  String get playerDiagnosticsPaused => '已暂停';

  @override
  String get playerDiagnosticsError => '错误';

  @override
  String get playerDiagnosticsVideoSection => '视频';

  @override
  String get playerDiagnosticsVideoCodec => '视频编码';

  @override
  String get playerDiagnosticsDolbyVision => '杜比视界';

  @override
  String get playerDiagnosticsResolution => '分辨率';

  @override
  String get playerDiagnosticsVideoOutput => '视频输出';

  @override
  String get playerDiagnosticsDecoder => '解码方式';

  @override
  String get playerDiagnosticsAudioSection => '音频';

  @override
  String get playerDiagnosticsCurrentAudioTrack => '当前音轨';

  @override
  String get playerDiagnosticsAudioCodec => '音频编码';

  @override
  String get playerDiagnosticsAudioChain => '音频链路';

  @override
  String get playerDiagnosticsOutputParams => '输出参数';

  @override
  String get playerDiagnosticsOutputDevice => '输出设备';

  @override
  String get playerDiagnosticsExternalAudio => '已接入外接音频';

  @override
  String get playerDiagnosticsUsbAudio => 'USB / 小尾巴';

  @override
  String get playerDiagnosticsSystemDefaultOutput => '系统默认输出';

  @override
  String get playerDiagnosticsCurrentSubtitle => '当前字幕';

  @override
  String get playerDiagnosticsOutputDisplaySection => '输出与显示';

  @override
  String get playerDiagnosticsHdrDolbyPipeline => 'HDR / 杜比链路';

  @override
  String get playerDiagnosticsColorMode => '色彩模式';

  @override
  String get playerDiagnosticsDeviceInfo => '设备信息';

  @override
  String get playerDiagnosticsSourceSection => '片源';

  @override
  String get playerDiagnosticsTitleLabel => '标题';

  @override
  String get playerDiagnosticsMediaId => '媒体标识';

  @override
  String get playerDiagnosticsVideoStream => '视频流';

  @override
  String get playerDiagnosticsAudioStream => '音频流';

  @override
  String get playerDiagnosticsSubtitleStream => '字幕流';

  @override
  String get commonYes => '是';

  @override
  String get commonNo => '否';

  @override
  String get playerDolbyVisionSource => '杜比视界片源';

  @override
  String get playerHdrSource => 'HDR片源';

  @override
  String get playerSdrSource => 'SDR片源';

  @override
  String get playerHdrDirect => 'HDR直出';

  @override
  String get playerSdrTonemap => 'SDR映射';

  @override
  String get playerSdrPipeline => 'SDR链路';

  @override
  String get playerAudioPassthrough => '直通输出';

  @override
  String get playerAudioDecodedNonPassthrough => '解码播放（非直通）';

  @override
  String get playerAudioDecoded => '解码播放';

  @override
  String get playerRecognized => '已识别';

  @override
  String get playerConnected => '已接入';

  @override
  String get playerNotDetected => '未检测到';

  @override
  String get danmakuSettingsTitle => '弹幕设置';

  @override
  String get danmakuDisplaySection => '显示调节';

  @override
  String get danmakuDisplayArea => '显示区域';

  @override
  String get danmakuOpacity => '不透明度';

  @override
  String get danmakuDensity => '弹幕密度';

  @override
  String get danmakuFontSize => '字体大小';

  @override
  String get danmakuFontWeight => '字体粗细';

  @override
  String get danmakuSpeed => '弹幕速度';

  @override
  String get danmakuFrameRate => '弹幕帧率';

  @override
  String get danmakuTypeFilterSection => '按弹幕类型屏蔽';

  @override
  String get danmakuTypeFixed => '固定';

  @override
  String get danmakuTypeScroll => '滚动';

  @override
  String get danmakuTypeColor => '彩色';

  @override
  String get danmakuTypeBottom => '底部';

  @override
  String get danmakuOcclusionSection => '画面防遮挡';

  @override
  String get danmakuHideDuplicateTitle => '隐藏重复弹幕';

  @override
  String get danmakuHideDuplicateSubtitle => '合并高频重复内容，减少同屏密集刷屏。';

  @override
  String get danmakuAvoidSubtitleTitle => '底部字幕区域防遮挡';

  @override
  String get danmakuAvoidSubtitleSubtitle => '优先避开字幕所在区域，减少弹幕压住字幕。';

  @override
  String get danmakuAvoidCenterTitle => '主体穿透遮挡';

  @override
  String get danmakuAvoidCenterSubtitle => '优先使用动态蒙版扣除人物区域内的弹幕，不可用时会恢复普通弹幕。';

  @override
  String get danmakuAiSampleInterval => 'AI 采样间隔';

  @override
  String get danmakuAiSampleSize => 'AI 采样大小';

  @override
  String get danmakuSourceSection => '弹幕来源';

  @override
  String get danmakuLayerEnabledTitle => '启用弹幕层';

  @override
  String get danmakuLayerEnabledSubtitle => '关闭后右上角设置入口会隐藏，仅保留左下角开关。';

  @override
  String danmakuCurrentStatus(Object status, Object summary) {
    return '当前状态：$status  ·  $summary';
  }

  @override
  String get danmakuSourcePriority => '来源优先级';

  @override
  String danmakuSourcePriorityDescription(Object priority) {
    return '当本地弹幕和网络弹幕都可用时，优先自动载入 $priority。';
  }

  @override
  String get danmakuLocalFirst => '本地优先';

  @override
  String get danmakuNetworkFirst => '网络优先';

  @override
  String get danmakuSavedTitle => '已保存弹幕';

  @override
  String get danmakuSavedEmptySubtitle => '统一管理本地弹幕和弹弹play缓存。';

  @override
  String danmakuSavedCountSubtitle(int count) {
    return '当前已保存 $count 个弹幕来源。';
  }

  @override
  String get danmakuSearchTitle => '搜索弹幕';

  @override
  String get danmakuDanDanPlay => '弹弹play';

  @override
  String get danmakuSearchAnimeSubtitle => '通过弹弹play搜索当前番剧和剧集，直接导入网络弹幕。';

  @override
  String get danmakuSearchSourceSubtitle => '通过弹弹play搜索当前片源相关结果，直接导入网络弹幕。';

  @override
  String get danmakuManualImportTitle => '手动导入弹幕';

  @override
  String get danmakuManualImportSubtitle =>
      '支持本地 XML / JSON 弹幕文件，导入后会替换当前已载入弹幕。';

  @override
  String get danmakuLocalFile => '本地文件';

  @override
  String get danmakuLocalImport => '本地导入';

  @override
  String get danmakuNoSavedSources => '还没有已保存弹幕来源';

  @override
  String get danmakuLocalSource => '本地弹幕';

  @override
  String get danmakuSearchHint => '可自动带入当前内容，也可以改词重搜';

  @override
  String danmakuCurrentMatch(Object context) {
    return '当前匹配：$context';
  }

  @override
  String get danmakuNoSearchResults => '没有搜索到可用结果';

  @override
  String get danmakuConfigRequired => '请先在配置中填入弹弹play AppId / AppSecret';

  @override
  String get danmakuSizeSmall => '较小';

  @override
  String get danmakuSizeSlightlySmall => '偏小';

  @override
  String get danmakuSizeStandard => '标准';

  @override
  String get danmakuSizeSlightlyLarge => '偏大';

  @override
  String get danmakuSizeLarge => '较大';

  @override
  String get danmakuWeightThin => '较细';

  @override
  String get danmakuWeightThick => '较粗';

  @override
  String get danmakuWeightVeryThick => '很粗';

  @override
  String get danmakuAreaQuarter => '1/4 屏';

  @override
  String get danmakuAreaHalf => '半屏';

  @override
  String get danmakuAreaThreeQuarter => '3/4 屏';

  @override
  String get danmakuAreaFull => '全屏';

  @override
  String get danmakuSpeedSlow => '慢';

  @override
  String get danmakuSpeedFast => '快';

  @override
  String get danmakuSpeedVeryFast => '极快';

  @override
  String get danmakuOcclusionDisabledTitle => '主体遮挡已关闭';

  @override
  String get danmakuOcclusionMaskTitle => '精细遮罩中';

  @override
  String get danmakuOcclusionBboxTitle => '人物框兜底中';

  @override
  String get danmakuOcclusionEnabledTitle => '主体遮挡已启用';

  @override
  String get danmakuOcclusionUnavailableTitle => '主体遮挡暂不可用';

  @override
  String get danmakuOcclusionDisabledSubtitle => '关闭后会恢复普通弹幕显示。';

  @override
  String get danmakuOcclusionMaskCached => '已复用精细遮罩缓存';

  @override
  String get danmakuOcclusionMaskRealtime => '正在使用实时精细遮罩';

  @override
  String get danmakuOcclusionBboxFallback => '正在使用人物框兜底';

  @override
  String get danmakuOcclusionNormal => '遮挡状态正常';

  @override
  String danmakuOcclusionBackendStatus(Object backend, Object status) {
    return '当前后端：$backend，$status。';
  }

  @override
  String danmakuOcclusionBackendWithReason(Object backend, Object reason) {
    return '当前后端：$backend，$reason';
  }

  @override
  String danmakuOcclusionBackendOnly(Object backend) {
    return '当前后端：$backend';
  }

  @override
  String get danmakuOcclusionCaptureUnsupported => '当前视频输出后端不支持 AI 采样';

  @override
  String get danmakuOcclusionCaptureBudgetUnsupported =>
      '当前链路在高刷新率下已禁用实时 AI 采样';

  @override
  String get danmakuEnabled => '弹幕已开启';

  @override
  String get danmakuDisabled => '弹幕已关闭';

  @override
  String get danmakuNeedSearchKeyword => '请先输入要搜索的番剧名称';

  @override
  String danmakuSearchRateLimited(int seconds) {
    return '搜索过于频繁，请 $seconds 秒后再试。';
  }

  @override
  String get danmakuSearchFailed => '搜索弹幕失败';

  @override
  String get danmakuNoAvailableData => '没有获取到可用弹幕数据';

  @override
  String get danmakuImportFailed => '导入弹幕失败';

  @override
  String danmakuImportFailedWithError(Object error) {
    return '导入弹幕失败: $error';
  }

  @override
  String get danmakuReadSelectedFileFailed => '无法读取已选择的弹幕文件';

  @override
  String danmakuImportedCount(int count) {
    return '已导入 $count 条弹幕';
  }

  @override
  String danmakuLoadedCount(int count) {
    return '已载入 $count 条弹幕';
  }

  @override
  String get danmakuSavedFileInvalidRemoved => '弹幕文件已失效，已从列表移除';

  @override
  String get danmakuSavedSourceDeleted => '已删除保存的弹幕来源';

  @override
  String get danmakuReadSavedFileFailed => '无法读取已保存的弹幕文件';

  @override
  String get danmakuAutoMatchNoResultBlocked => '当前片源自动匹配弹幕无结果，后续不再自动请求，可手动搜索。';

  @override
  String get danmakuAutoMatchFailed => '当前片源自动匹配弹幕失败';

  @override
  String danmakuAutoMatchBlockedWithReason(Object reason) {
    return '$reason，后续不再自动请求，可手动搜索。';
  }

  @override
  String get danmakuSwitchedLocalFirst => '已切换为本地优先';

  @override
  String get danmakuSwitchedNetworkFirst => '已切换为网络优先';

  @override
  String get danmakuLayerDisabledSummary => '弹幕层已关闭，开启后会按当前优先级自动载入弹幕。';

  @override
  String get danmakuLoadedLocalSummary => '当前已加载本地弹幕';

  @override
  String get danmakuLoadedNetworkSummary => '当前已加载弹弹play弹幕';

  @override
  String get danmakuLoadedGenericSummary => '当前已加载弹幕';

  @override
  String danmakuLoadedWithLabelSummary(Object prefix, Object label, int count) {
    return '$prefix：$label，共 $count 条。';
  }

  @override
  String danmakuLoadedCountSummary(Object prefix, int count) {
    return '$prefix，共 $count 条。';
  }

  @override
  String get danmakuStatusLocal => '本地';

  @override
  String get danmakuStatusNetwork => '弹弹play';

  @override
  String get danmakuStatusNotLoaded => '未载入';

  @override
  String get danmakuNoLoadedSearchOrImportSummary =>
      '当前还没有载入弹幕，可搜索弹弹play弹幕或手动导入本地弹幕。';

  @override
  String danmakuNoLoadedManualImportWithTitleSummary(Object title) {
    return '$title 暂未载入弹幕，可手动导入本地弹幕。';
  }

  @override
  String get danmakuNoLoadedManualImportSummary => '当前片源暂未载入弹幕，可手动导入本地弹幕。';

  @override
  String get danmakuSearchButton => '搜索';

  @override
  String get danmakuSavedSourceLocalLabel => '本地';

  @override
  String danmakuSavedSourceSubtitleWithCount(
    Object type,
    int count,
    Object detail,
  ) {
    return '$type · $count 条 · $detail';
  }

  @override
  String danmakuSavedSourceSubtitle(Object type, Object detail) {
    return '$type · $detail';
  }

  @override
  String get danmakuCurrent => '当前';

  @override
  String get playerFitModeUnavailable => '画面模式暂未接入';

  @override
  String get playerPictureInPictureUnavailable => '当前无法进入小窗播放';

  @override
  String playerResumePrompt(Object position) {
    return '继续播放到 $position';
  }

  @override
  String get playerRestartFromBeginning => '从头播放';

  @override
  String playerAutoPlayNextPrompt(int seconds) {
    return '$seconds 秒后自动连播下一集';
  }

  @override
  String get playerReloadAction => '重载';

  @override
  String get playerEpisodeAction => '选集';

  @override
  String get playerAudioTrackAction => '音轨';

  @override
  String get playerSubtitleOffAction => '字幕关';

  @override
  String get playerSubtitleAction => '字幕';

  @override
  String get playerCloudDriveModeTitle => '网盘播放方式';

  @override
  String get playerCloudDriveAccountName => '网盘';

  @override
  String get playerCloudDriveDirectUnavailable => '当前没有可用的网盘直链播放源';

  @override
  String get playerCloudDriveProxyUnavailable => '当前没有可用的 NAS 代理播放源';

  @override
  String get playerCloudDriveSwitchingDirect => '正在为您切换至网盘直连播放，请稍候...';

  @override
  String get playerCloudDriveSwitchingProxy => '正在为您切换至 NAS 代理播放，请稍候...';

  @override
  String playerSeasonCountLabel(int count) {
    return '$count季';
  }

  @override
  String get playerNoEpisodes => '暂无选集';

  @override
  String get playerDownloadedBadge => '已下载';

  @override
  String get playerNetworkOffline => '离线';

  @override
  String get playerNetworkOnline => '网络';

  @override
  String playerSkipPromptCountdown(int seconds, Object label) {
    return '$seconds 秒后跳过$label';
  }

  @override
  String playerSkipPromptSoon(Object label) {
    return '即将跳过$label';
  }

  @override
  String get playerSkipPromptDismissSubtitle => '点击关闭后，本次不会自动跳过';

  @override
  String get playerReplayAction => '重新播放';

  @override
  String get playerBackAction => '返回';

  @override
  String get playerCloudDrivePlayingFile => '正在播放网盘文件';

  @override
  String get playerCloudDriveModeDescription =>
      '播放速度、画质等能力取决于网盘侧规则。如遇播放异常，可尝试切换播放方式。';

  @override
  String get playerCloudDriveDirectTitle => '网盘直连播放';

  @override
  String get playerCloudDriveDirectSubtitle => '速度较快，省流';

  @override
  String get playerCloudDriveProxyTitle => 'NAS 代理播放';

  @override
  String get playerCloudDriveProxySubtitle => '色调或音频异常时可尝试切换';

  @override
  String get playerRecommendedBadge => '推荐';

  @override
  String get settingsBookmarkManagerTitle => '书签管理';

  @override
  String get settingsBookmarkEmptySummary => '还没有书签';

  @override
  String settingsBookmarkCountSummary(int count) {
    return '共 $count 个书签';
  }

  @override
  String get settingsDanmakuDefaultEnabled => '默认开启';

  @override
  String get settingsDanmakuDefaultDisabled => '默认关闭';

  @override
  String get settingsDanmakuLocalFirst => '本地优先';

  @override
  String get settingsDanmakuNetworkFirst => '网络优先';

  @override
  String get settingsScreenshotCustomDirectoryNotReady => '自定义目录未就绪';

  @override
  String get settingsScreenshotWithSubtitles => '携带字幕';

  @override
  String get settingsScreenshotImageOnly => '仅画面';

  @override
  String get settingsScreenshotWithSubtitleLayer => '携带字幕层';

  @override
  String get settingsScreenshotImageOnlySummary => '仅保存画面';

  @override
  String get settingsScreenshotImageOnlyDescription => '不携带字幕层。';

  @override
  String get settingsScreenshotWithSubtitlesDescription => '保存当前字幕层。';

  @override
  String get settingsScreenshotCustomDirectoryUnsetSummary => '自定义目录未设置。';

  @override
  String settingsScreenshotCustomDirectoryInvalidSummary(Object name) {
    return '已记录自定义目录“$name”，但授权失效，需要重新选择。';
  }

  @override
  String settingsScreenshotCustomDirectoryActiveSummary(Object name) {
    return '当前保存到自定义目录“$name”。';
  }

  @override
  String get settingsScreenshotDirectoryUnset => '未设置';

  @override
  String get settingsScreenshotDirectoryInvalid => '授权失效';

  @override
  String get settingsScreenshotSavePathPicturesTitle => '系统相册';

  @override
  String get settingsScreenshotSavePathPicturesDescription =>
      '保存到 Pictures/FlyPlayer，适合普通截图查看。';

  @override
  String get settingsScreenshotSavePathDcimTitle => '相机目录';

  @override
  String get settingsScreenshotSavePathDcimDescription =>
      '保存到 DCIM/FlyPlayer，更容易被系统相册归类展示。';

  @override
  String get settingsScreenshotSavePathAppPicturesTitle => '应用目录';

  @override
  String get settingsScreenshotSavePathAppPicturesDescription =>
      '保存到应用专属图片目录，更干净，但部分图库不会直接扫描。';

  @override
  String get settingsScreenshotSavePathCustomTitle => '自定义目录';

  @override
  String get settingsScreenshotSavePathCustomDescription =>
      '保存到用户自己选择的文件夹，适合集中管理截图。';

  @override
  String get settingsScreenshotSelectCustomDirectoryFirst => '请先选择截图自定义目录';

  @override
  String get settingsScreenshotCustomDirectoryInvalidRetry => '自定义目录已失效，请重新选择';

  @override
  String get settingsScreenshotReadingCustomDirectory => '正在读取当前自定义目录状态...';

  @override
  String get settingsScreenshotDirectoryUnsetSentence => '未设置目录。';

  @override
  String settingsScreenshotDirectoryInvalidWithName(Object name) {
    return '已记录目录“$name”，但当前授权失效，需要重新选择。';
  }

  @override
  String settingsScreenshotCurrentDirectory(Object name) {
    return '当前目录：$name';
  }

  @override
  String get settingsScreenshotCustomDirectoryManagement => '自定义目录管理';

  @override
  String get settingsScreenshotDirectoryAvailable => '目录可用';

  @override
  String get settingsScreenshotDirectoryNeedsReselect => '需重选';

  @override
  String settingsScreenshotDirectoryActiveDetail(Object name) {
    return '截图保存目录：“$name”。';
  }

  @override
  String get settingsScreenshotDirectorySetupHint => '先选择一个文件夹，再切换到“自定义目录”模式。';

  @override
  String settingsScreenshotDirectoryInvalidDetail(Object name) {
    return '原来的目录“$name”不可用了，请重新选择。';
  }

  @override
  String get settingsScreenshotChooseDirectory => '选择目录';

  @override
  String get settingsScreenshotChangeDirectory => '更换目录';

  @override
  String get settingsScreenshotSetAsCurrentDirectory => '设为当前保存目录';

  @override
  String get settingsScreenshotNoDirectorySelected => '未选择目录';

  @override
  String get settingsScreenshotCustomDirectoryUpdated => '已更新截图自定义目录';

  @override
  String get settingsScreenshotCustomDirectoryRecordedUnavailable =>
      '目录已记录，但当前不可用';

  @override
  String get settingsScreenshotClearCustomDirectoryTitle => '清除截图自定义目录';

  @override
  String get settingsScreenshotClearCustomDirectoryContent =>
      '这不会删除已经保存的截图，只会移除当前目录授权。';

  @override
  String get settingsScreenshotCustomDirectoryCleared => '已清除截图自定义目录';

  @override
  String get settingsScreenshotCustomDirectoryActivated => '截图保存目录已切换为自定义目录';

  @override
  String get settingsScreenshotNoDirectoryChosen => '还没有选择目录';

  @override
  String get settingsScreenshotDirectoryWritable => '可写入';

  @override
  String get settingsScreenshotDirectoryExpired => '已失效';

  @override
  String get settingsScreenshotDirectoryWriteHint => '新截图将写入该目录。';

  @override
  String get settingsScreenshotDirectoryPickHint => '选择文件夹后可作为截图保存目录。';

  @override
  String get settingsScreenshotDirectoryExpiredHint =>
      '目录授权已经失效，需要重新选择后才能继续保存截图。';

  @override
  String get settingsScreenshotClearAuthorization => '清除授权';

  @override
  String get settingsScreenshotCurrentStatus => '当前状态';

  @override
  String get settingsScreenshotCustomDirectoryEnabledStatus =>
      '当前截图已经使用自定义目录保存。更换目录后，新截图会进入新目录，旧截图不会迁移。';

  @override
  String get settingsScreenshotCustomDirectoryDisabledStatus => '当前未启用自定义目录。';

  @override
  String get detailOverviewEmpty => '暂无简介';

  @override
  String get mediaDetailsTitle => '文件媒体信息';

  @override
  String get mediaDetailsVideoSection => '视频';

  @override
  String get mediaDetailsAudioSection => '音频';

  @override
  String get mediaDetailsSubtitleSection => '字幕';

  @override
  String get mediaDetailsFieldEncoder => '编码器';

  @override
  String get mediaDetailsFieldProfile => '配置';

  @override
  String get mediaDetailsFieldLevel => '等级';

  @override
  String get mediaDetailsFieldResolution => '分辨率';

  @override
  String get mediaDetailsFieldAspectRatio => '宽高比';

  @override
  String get mediaDetailsFieldInterlaced => '隔行扫描';

  @override
  String get mediaDetailsFieldFrameRate => '帧率';

  @override
  String get mediaDetailsFieldBitrate => '码率';

  @override
  String get mediaDetailsFieldRange => '视频动态范围';

  @override
  String get mediaDetailsFieldColorPrimaries => '色彩原色';

  @override
  String get mediaDetailsFieldColorSpace => '色彩空间';

  @override
  String get mediaDetailsFieldColorTransfer => '色彩转换';

  @override
  String get mediaDetailsFieldBitDepth => '位深度';

  @override
  String get mediaDetailsFieldPixelFormat => '像素格式';

  @override
  String get mediaDetailsFieldRefs => '参考帧';

  @override
  String get mediaDetailsFieldLanguage => '语言';

  @override
  String get mediaDetailsFieldChannels => '声道';

  @override
  String get mediaDetailsFieldSampleRate => '采样率';

  @override
  String get mediaDetailsFieldLayout => '布局';

  @override
  String get mediaDetailsFieldDefault => '默认';

  @override
  String get mediaDetailsFieldForced => '强制';

  @override
  String get mediaDetailsFieldExternal => '外部';

  @override
  String get detailSeasonSpecial => '特别篇';

  @override
  String detailSeasonNumber(int number) {
    return '第 $number 季';
  }

  @override
  String detailEpisodeNumber(int number) {
    return '第 $number 集';
  }

  @override
  String detailSeasonEpisodeNumber(int season, int episode) {
    return '第 $season 季 第 $episode 集';
  }

  @override
  String detailSpecialEpisodeNumber(int episode) {
    return '特别篇 第 $episode 集';
  }

  @override
  String detailNamedEpisodeNumber(Object title, int episode) {
    return '$title 第 $episode 集';
  }

  @override
  String get detailSeasonDefault => '季';

  @override
  String get detailSeasonInfoDefault => '季信息';

  @override
  String detailTvSeasonCount(int count) {
    return '共 $count 季';
  }

  @override
  String get detailSeasonEmpty => '暂无季列表';

  @override
  String get detailEpisodeTitle => '选集';

  @override
  String get detailEpisodeEmpty => '暂无剧集信息';

  @override
  String get detailEpisodeUnknown => '未知集数';

  @override
  String detailEpisodeTotal(int count) {
    return '共 $count 集';
  }

  @override
  String get commonDetails => '详情';

  @override
  String get commonLoading => '加载中';

  @override
  String get detailImdbEmpty => '暂无 IMDB 链接';

  @override
  String get detailImdbOpenFailed => '无法打开 IMDB 链接';

  @override
  String detailRatingScore(Object score) {
    return '$score 分';
  }

  @override
  String get commonClickTooFastRetryLater => '点击过快，请稍后再试';

  @override
  String get commonOperationFailedRetryLater => '操作失败，请稍后重试';

  @override
  String get actionFavoriteAdd => '收藏';

  @override
  String get actionFavoriteRemove => '取消收藏';

  @override
  String get actionFavoriteAdded => '已加入收藏';

  @override
  String get actionFavoriteRemoved => '已取消收藏';

  @override
  String get actionMarkAsWatched => '标记为已观看';

  @override
  String get actionMarkAsUnwatched => '标记为未观看';

  @override
  String get actionMarkedAsWatched => '已标记为已观看';

  @override
  String get actionMarkedAsUnwatched => '已标记为未观看';

  @override
  String get detailFavoriteFailed => '收藏失败';

  @override
  String get detailUnfavoriteFailed => '取消收藏失败';

  @override
  String get detailMarkWatchedFailed => '标记为已观看失败';

  @override
  String get detailMarkUnwatchedFailed => '标记为未观看失败';

  @override
  String get detailDownloadUnavailable => '暂无可下载资源';

  @override
  String get detailContinuePlay => '继续播放';

  @override
  String get detailPlay => '播放';

  @override
  String get detailOverviewTitle => '简介';

  @override
  String get detailCastCrewTitle => '演职人员';

  @override
  String get detailFileInfoTitle => '文件信息';

  @override
  String get detailFileLocation => '文件位置';

  @override
  String get detailFileSize => '文件大小';

  @override
  String get detailFileCreatedAt => '文件创建日期';

  @override
  String get detailFileAddedAt => '添加日期';

  @override
  String get detailFileConvert => '转换';

  @override
  String detailPlaybackError(Object error) {
    return '播放异常: $error';
  }

  @override
  String detailPlayInfoFailedWithError(Object error) {
    return '获取播放流失败: $error';
  }

  @override
  String get detailPreparingPlayback => '正在准备播放，请稍候';

  @override
  String get detailPlayPlaceholder => '播放接口已预留';

  @override
  String get detailPlayInfoFailed => '获取播放信息失败';

  @override
  String get detailDownloadPlaceholder => '下载接口已预留';

  @override
  String get detailLocalVideoInvalid => '本地视频文件无效';

  @override
  String get detailTmdbEmpty => '暂无 TMDB 链接';

  @override
  String get detailTmdbOpenFailed => '无法打开 TMDB 链接';

  @override
  String get commonOther => '其他';

  @override
  String commonDurationHoursMinutes(int hours, int minutes) {
    return '$hours 小时 $minutes 分钟';
  }

  @override
  String commonDurationMinutesSeconds(int minutes, int seconds) {
    return '$minutes 分钟 $seconds 秒';
  }

  @override
  String commonDurationMinutes(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String commonDurationSeconds(int seconds) {
    return '$seconds 秒';
  }

  @override
  String get downloadLoadingInfo => '正在获取下载信息，请稍候';

  @override
  String get downloadNoResources => '暂无可下载资源';

  @override
  String get downloadNoQuality => '暂无可下载清晰度';

  @override
  String get downloadSelectItem => '选择下载条目';

  @override
  String get downloadQuality => '下载清晰度';

  @override
  String get downloadSelectQuality => '选择下载清晰度';

  @override
  String get downloadDownload => '下载';

  @override
  String get downloadOpenList => '打开下载列表';

  @override
  String get downloadLoadFailed => '获取下载信息失败，请稍后重试';

  @override
  String get downloadSourceQuality => '原画';

  @override
  String get downloadDownloaded => '已下载';

  @override
  String downloadStartedWithQuality(Object quality) {
    return '已开始下载 $quality';
  }

  @override
  String downloadImportedFromCacheWithQuality(Object quality) {
    return '已从缓存加入下载 $quality';
  }

  @override
  String get downloadItemDownloading => '该条目正在下载';

  @override
  String get downloadItemDownloaded => '该条目已下载';

  @override
  String downloadFailedWithError(Object error) {
    return '下载失败：$error';
  }

  @override
  String get downloadListTitle => '下载列表';

  @override
  String get trackSubtitleOff => '关闭字幕';

  @override
  String get trackSubtitleNone => '无字幕';

  @override
  String get trackAudioNone => '无音频';

  @override
  String get trackSubtitleUnknownLanguage => '未知语言';

  @override
  String get trackSubtitleDefaultSuffix => '默认';

  @override
  String get trackSubtitleExternalSuffix => '外挂';

  @override
  String get trackSubtitleName => '字幕';

  @override
  String get playerSubtitleSelectTitle => '选择字幕';

  @override
  String get playerAudioSelectTitle => '选择音频';

  @override
  String get logNoExportableLogs => '当前没有可导出的日志';

  @override
  String logTxtExported(Object path) {
    return 'TXT 已导出到 $path';
  }

  @override
  String logExternalUnavailableExported(Object path) {
    return '外部存储不可用，已导出到临时目录 $path';
  }

  @override
  String logExportFailed(Object error) {
    return '导出失败：$error';
  }

  @override
  String get logClearTitle => '清空日志';

  @override
  String get logClearContent => '会移除当前已记录的报错日志，这个操作不能恢复。';

  @override
  String get logClearConfirm => '清空';

  @override
  String get logCleared => '日志已清空';

  @override
  String get logInfoTitle => '日志信息';

  @override
  String get logErrorLogTitle => '报错日志';

  @override
  String get logErrorLogDescription => '全局异常记录，支持导出为 TXT。';

  @override
  String get logTotal => '总数';

  @override
  String get logErrors => '错误';

  @override
  String get logLatest => '最近';

  @override
  String get logNone => '暂无';

  @override
  String get logExporting => '导出中...';

  @override
  String get logExportTxt => '导出 TXT';

  @override
  String get logClearing => '清空中...';

  @override
  String get logClearAction => '清空日志';

  @override
  String get logEmptyTitle => '暂无报错日志';

  @override
  String get logEmptySubtitle => '发生全局异常后将自动生成记录。';

  @override
  String get logCollapseStack => '收起堆栈';

  @override
  String get logExpandStack => '展开堆栈';

  @override
  String get downloadEmptyDownloaded => '没有已下载的影片';

  @override
  String get downloadEmptyDownloading => '没有下载中的影片';

  @override
  String downloadImportedLocalVideos(int count) {
    return '已导入 $count 个本地下载视频';
  }

  @override
  String get downloadNoImportableVideos => '没有发现需要导入的视频';

  @override
  String get downloadNoRecoverableFiles => '没有找到可恢复的下载文件';

  @override
  String get downloadRefreshFilesFailed => '刷新下载文件失败';

  @override
  String get downloadRefreshFilesTooltip => '刷新下载文件';

  @override
  String get commonEdit => '编辑';

  @override
  String get commonSelectAll => '全选';

  @override
  String get commonDeselectAll => '取消全选';

  @override
  String get downloadDeleteFilesTitle => '删除视频文件';

  @override
  String get downloadDeleteFilesContent => '确认删除所选视频文件？删除后将不可恢复。';

  @override
  String get downloadPreparingPlayback => '正在准备播放，请稍候';

  @override
  String get downloadLocalFileMissing => '本地视频文件不存在';

  @override
  String get downloadDetailTitle => '下载详情';

  @override
  String downloadSelectedCount(int count) {
    return '已选择 $count 项';
  }

  @override
  String downloadVideoCount(int count) {
    return '视频 $count';
  }

  @override
  String downloadTranscodingPercent(int percent) {
    return '转码中 $percent%';
  }

  @override
  String get downloadCalculating => '计算中';

  @override
  String get downloadWaiting => '等待中';

  @override
  String get downloadPendingGenerate => '待生成';

  @override
  String get downloadTranscoding => '转码中';

  @override
  String get downloadDownloading => '下载中';

  @override
  String get downloadCurrentStage => '当前阶段';

  @override
  String get downloadSpeed => '下载速度';

  @override
  String get downloadCloudTranscoding => '云端转码';

  @override
  String get downloadEstimatedFile => '预计文件';

  @override
  String get downloadTransferredTotal => '已下 / 总计';

  @override
  String get downloadDownloadedTab => '已下载';

  @override
  String get downloadDownloadingTab => '下载中';

  @override
  String get storageTitle => '储存管理';

  @override
  String get storageRefreshTooltip => '刷新';

  @override
  String get storageAppDataDangerTitle => '应用数据与危险操作';

  @override
  String get storageAppDataTitle => '应用数据';

  @override
  String get storageAppDataDescription => '这些内容通常是用户记录和个性化配置，不会和普通缓存一起清理。';

  @override
  String get storageTotalUsage => '总占用';

  @override
  String storageLastRefreshed(Object time) {
    return '上次刷新 $time';
  }

  @override
  String get storageClearSelectedCacheTitle => '清理选中缓存';

  @override
  String get storageClearSelectedCacheMessage => '将删除选中的播放缓存文件，删除后需要重新缓存。是否继续？';

  @override
  String get storageClearSelectedDownloadsTitle => '清理已下载文件';

  @override
  String get storageClearSelectedDownloadsMessage =>
      '将删除选中的本地下载文件，删除后需要重新下载。是否继续？';

  @override
  String get storagePlaybackActiveMessage => '播放中不可清理播放缓存';

  @override
  String get storageClearFailedMessage => '清理失败，请稍后重试';

  @override
  String get storageEmptyPlaybackSelection => '请先勾选要清理的缓存';

  @override
  String get storageEmptyDownloadSelection => '请先勾选要清理的下载文件';

  @override
  String get storageSelectedPlaybackCleared => '已清理选中的播放缓存';

  @override
  String get storageSelectedDownloadsCleared => '已清理选中的下载文件';

  @override
  String get storageCacheResolutionFallback => '缓存';

  @override
  String get storageCacheVideoFallback => '缓存视频';

  @override
  String storageSeasonGroupTitle(Object seriesTitle, int season) {
    return '$seriesTitle 第$season季';
  }

  @override
  String storageSpecialGroupTitle(Object seriesTitle) {
    return '$seriesTitle 特别篇';
  }

  @override
  String storagePromoteConverted(int count) {
    return '已转为下载 $count 项';
  }

  @override
  String storagePromoteExisting(int count) {
    return '已有下载 $count 项';
  }

  @override
  String storagePromoteUnavailable(int count) {
    return '不可转换 $count 项';
  }

  @override
  String get storageNoConvertibleCache => '当前没有可转换的完整缓存';

  @override
  String storageClearItemTitle(Object title) {
    return '清理$title';
  }

  @override
  String storageClearItemMessage(Object title) {
    return '将清理$title，对应文件会被删除。是否继续？';
  }

  @override
  String storageClearItemSuccess(Object title) {
    return '$title已清理';
  }

  @override
  String storageClearItemRestricted(Object title) {
    return '$title已部分清理，公共目录未授权';
  }

  @override
  String storageActionCompleted(Object title) {
    return '$title已完成';
  }

  @override
  String storageActionFailed(Object title) {
    return '$title失败，请稍后重试';
  }

  @override
  String get storageClearBookmarksTitle => '清空书签';

  @override
  String get storageClearBookmarksSubtitle => '仅删除播放书签记录';

  @override
  String get storageClearBookmarksMessage => '将删除全部播放书签，此操作不可恢复。';

  @override
  String get storageClearSavedThemesTitle => '清空已保存主题';

  @override
  String get storageClearSavedThemesSubtitle => '保留当前自定义配置';

  @override
  String get storageClearSavedThemesMessage => '将删除已保存主题，但不会影响当前自定义配置。';

  @override
  String get storageClearDynamicThemeTitle => '清空动态取色缓存';

  @override
  String get storageClearDynamicThemeSubtitle => '下次进入详情页会重新为图片取色';

  @override
  String get storageClearDynamicThemeMessage =>
      '将删除本地保存的动态取色结果，之后再次进入详情页时会重新采样取色。';

  @override
  String get storageClearDanmakuSourcesTitle => '清空弹幕来源';

  @override
  String get storageClearDanmakuSourcesSubtitle => '删除已保存的弹幕来源记录';

  @override
  String get storageClearDanmakuSourcesMessage => '将删除已保存的弹幕来源记录。';

  @override
  String get storageClearLoginHistoryTitle => '清空登录历史';

  @override
  String get storageClearLoginHistorySubtitle => '不会退出当前会话';

  @override
  String get storageClearLoginHistoryMessage => '将删除历史登录记录，不会退出当前登录。';

  @override
  String get storageResetSettingsTitle => '重置设置';

  @override
  String get storageResetSettingsSubtitle => '主题、播放器、截图、弹幕与平行窗口设置';

  @override
  String get storageResetSettingsMessage =>
      '将重置主题、播放器、截图、弹幕和平行窗口设置，不会清理缓存和用户文件。';

  @override
  String get storageTotal => '总计';

  @override
  String get storageNoUsageData => '暂无占用数据';

  @override
  String get storageUsageCategory => '占用分类';

  @override
  String get storageCategoryDetails => '分类详情';

  @override
  String get storagePlaybackFiles => '播放缓存';

  @override
  String get storageDownloadFiles => '下载文件';

  @override
  String storagePromoteSelected(int count) {
    return '转为下载 ($count)';
  }

  @override
  String storageClearSelected(int count) {
    return '清理选中 ($count)';
  }

  @override
  String get storageNoPlaybackCache => '当前没有可清理的播放缓存。';

  @override
  String get storageNoDownloadFiles => '当前没有可查看的本地下载文件。';

  @override
  String get storageCompleteCache => '完整缓存';

  @override
  String get storageIncompleteCache => '未完整缓存';

  @override
  String get storageCompletedCache => '已完整缓存';

  @override
  String get storageEnterManagement => '进入管理';

  @override
  String get storageEstimated => '估算';

  @override
  String get storageRestricted => '权限受限';

  @override
  String get commonApply => '应用';

  @override
  String get commonAll => '全部';

  @override
  String get commonAscending => '升序';

  @override
  String get commonDescending => '降序';

  @override
  String get screenshotGalleryTitle => '截图图库';

  @override
  String screenshotSelectedCount(int count) {
    return '已选中 $count 张';
  }

  @override
  String get screenshotUnknownResolution => '未知分辨率';

  @override
  String get screenshotDeleteTitle => '删除截图';

  @override
  String screenshotDeleteContent(int count) {
    return '将删除选中的 $count 张截图，删除后无法恢复。';
  }

  @override
  String screenshotDeletedCount(int count) {
    return '已删除 $count 张截图';
  }

  @override
  String get screenshotDeleteNone => '没有删除任何截图';

  @override
  String get screenshotSourcePictures => '系统相册';

  @override
  String get screenshotSourceDcim => '相机目录';

  @override
  String get screenshotSourceApp => '应用目录';

  @override
  String get screenshotSourceCustom => '自定义目录';

  @override
  String get screenshotSearchTitle => '搜索截图';

  @override
  String get screenshotSearchHint => '输入截图名、目录或来源';

  @override
  String get screenshotClearSearch => '清空搜索';

  @override
  String get screenshotFilterSortTitle => '筛选与排序';

  @override
  String get screenshotSourceFilter => '来源筛选';

  @override
  String get screenshotSortStandard => '排序标准';

  @override
  String screenshotCurrentSortGroup(Object field, Object direction) {
    return '当前按 $field$direction分组';
  }

  @override
  String get screenshotSortDescription => '支持多级排序，排在最上面的规则优先级最高，页面分组也按它展示。';

  @override
  String get screenshotAddSort => '添加排序';

  @override
  String get screenshotApplySort => '应用排序';

  @override
  String get screenshotMoveUpPriority => '上移优先级';

  @override
  String get screenshotMoveDownPriority => '下移优先级';

  @override
  String get screenshotDeleteRule => '删除规则';

  @override
  String screenshotSearchEmpty(Object query) {
    return '没有找到和“$query”相关的截图。';
  }

  @override
  String get screenshotEmptyPictures => '系统相册里还没有截图。';

  @override
  String get screenshotEmptyDcim => '相机目录里还没有截图。';

  @override
  String get screenshotEmptyApp => '应用目录里还没有截图。';

  @override
  String get screenshotEmptyCustom => '自定义目录里还没有截图。';

  @override
  String get screenshotEmptyDefault => '当前没有可预览的截图。';

  @override
  String get screenshotRefreshHint => '下拉刷新后会重新扫描可访问目录。';

  @override
  String get screenshotAuthorizePublicDirectories => '授权公共目录';

  @override
  String get screenshotInfoCategory => '分类';

  @override
  String get screenshotInfoFormat => '格式';

  @override
  String get screenshotInfoSourceDirectory => '来源目录';

  @override
  String get screenshotInfoTakenAt => '拍摄时间';

  @override
  String get screenshotInfoFileSize => '文件大小';

  @override
  String get screenshotInfoStorageType => '存储类型';

  @override
  String get screenshotInfoResolution => '分辨率';

  @override
  String get screenshotManagedDirectory => '受管目录';

  @override
  String get screenshotLocalFile => '本地文件';

  @override
  String get screenshotLoading => '读取中';

  @override
  String get screenshotUltraHdrNotice =>
      '该文件为 Ultra HDR JPEG，应用内预览可能只显示 SDR 基底，相册中可按系统能力显示 HDR。';

  @override
  String get screenshotFormatImage => '图片';

  @override
  String get screenshotSortDate => '日期';

  @override
  String get screenshotSortFileName => '文件名';

  @override
  String get screenshotSortSize => '大小';

  @override
  String get screenshotSortResolution => '分辨率';

  @override
  String get screenshotSortDirectory => '目录';

  @override
  String get screenshotSortSource => '来源';

  @override
  String get screenshotDateToday => '今天';

  @override
  String get screenshotDateYesterday => '昨天';

  @override
  String get screenshotDateBeforeYesterday => '前天';

  @override
  String screenshotMonthDay(int month, int day) {
    return '$month月$day日';
  }

  @override
  String get screenshotSizeOver10Mb => '10 MB 以上';

  @override
  String get screenshotSizeUnder100Kb => '100 KB 以下';

  @override
  String get bookmarkNoteDialogTitle => '书签备注';

  @override
  String get bookmarkNoteDialogHint => '记录这个书签的作用，比如名场面、关键转折、复习点';

  @override
  String get bookmarkNoteCollapse => '收起';

  @override
  String get bookmarkNoteExpand => '更多';

  @override
  String get mpvEqEditorTitle => '高级均衡';

  @override
  String get mpvEqEditorSubtitle => '上下拖动每个频段，细微调整整体音色。';

  @override
  String get mpvEqReset => '归零';

  @override
  String get themePresetMidnightSubtitle => '深夜影院感，层次稳重';

  @override
  String get themePresetOceanSubtitle => '冷海风格，信息感更强';

  @override
  String get themePresetForestSubtitle => '自然绿调，观感更柔和';

  @override
  String get themePresetGraphiteSubtitle => '中性石墨，适合长期使用';

  @override
  String get themePresetSunsetSubtitle => '暖调落日，氛围更明显';

  @override
  String get themePresetAuroraSubtitle => '清亮极光，更偏轻快科技感';

  @override
  String get themePresetLatteSubtitle => '奶白纸感，适合亮背景偏好';

  @override
  String get themeAccentBlue => '星蓝';

  @override
  String get themeAccentCyan => '冰青';

  @override
  String get themeAccentGreen => '松绿';

  @override
  String get themeAccentAmber => '琥珀';

  @override
  String get themeAccentRose => '赤霓';

  @override
  String get themeAccentCoral => '珊瑚';

  @override
  String get themeAccentIndigo => '靛青';

  @override
  String get themeAccentMint => '薄荷';

  @override
  String get themeBackgroundNight => '夜幕';

  @override
  String get themeBackgroundSlate => '石墨';

  @override
  String get themeBackgroundOcean => '深海';

  @override
  String get themeBackgroundMoss => '苔绿';

  @override
  String get themeBackgroundEmber => '余烬';

  @override
  String get themeBackgroundPearl => '珠雾';

  @override
  String get themeBackgroundLinen => '亚麻';

  @override
  String get themeBackgroundIvory => '奶白';

  @override
  String get themeDynamicModeOff => '关闭';

  @override
  String get themeDynamicModeDetailsAndPeople => '详情页和人物页';

  @override
  String get themeDynamicIntensitySubtle => '轻柔';

  @override
  String get themeDynamicIntensityMedium => '中度';

  @override
  String get themeDynamicIntensityVivid => '鲜明';

  @override
  String get themeDynamicIntensityAdvanced => '高级';

  @override
  String get themeDynamicBehaviorSubtle => '当前页轻量取色，按钮和边框会跟随变化';

  @override
  String get themeDynamicBehaviorMedium => '当前页完整取色，推荐';

  @override
  String get themeDynamicBehaviorVivid => '高级取色，普通页面流可联动主屏';

  @override
  String get themeCurrentCustomTitle => '当前自定义';

  @override
  String get themeCurrentCustomSubtitle => '手动调整后的当前配方';

  @override
  String get themeSavedDefaultSubtitle => '已保存主题';

  @override
  String get themeColorHue => '色相';

  @override
  String get themeColorSaturation => '饱和度';

  @override
  String get themeColorValue => '明度';

  @override
  String get themeQuickColors => '快速颜色';

  @override
  String get themePreviewCurrentAppearance => '当前外观';

  @override
  String get themePreviewPrimaryButton => '主按钮';

  @override
  String get themePreviewSelectedTab => '选中标签';

  @override
  String get themePreviewMore => '更多';

  @override
  String get themeSamplePage => '页面';

  @override
  String get themeSampleCard => '卡片';

  @override
  String get themeSampleBottomBar => '底栏';

  @override
  String get themeSampleContinuePlay => '继续播放';

  @override
  String get themeSampleSecondaryAction => '次要操作';

  @override
  String get themeSampleSelected => '已选中';

  @override
  String get themeSampleUnselected => '未选中';

  @override
  String get themeSampleViewDetails => '查看详情';

  @override
  String get themeFixedSectionTitle => '固定主题';

  @override
  String get themeFixedSectionSubtitle => '官方预设，切换后立即作为全局主题生效。';

  @override
  String get themeCustomSectionSubtitle => '自定义配色与已保存主题管理。';

  @override
  String get themeCurrentCustomCardSubtitle => '编辑颜色分类与当前配方。';

  @override
  String get themeNoSavedThemesTitle => '还没有已保存主题';

  @override
  String get themeNoSavedThemesSubtitle => '可在详情页更多菜单中保存当前主题。';

  @override
  String get themeCustomBaseName => '自定义主题';

  @override
  String get themeCustomRecipePageSubtitle => '当前自定义配方，可按颜色分类编辑并另存为自定义主题。';

  @override
  String get themeCustomLabel => '自定义';

  @override
  String get themePaletteButton => '调色盘';

  @override
  String get themeBackgroundControlTitle => '背景主色';

  @override
  String get themeBackgroundControlSubtitle => '控制页面底色、卡片层级、导航栏和整体氛围基调。';

  @override
  String get themeCustomBackgroundPickerTitle => '自定义背景色';

  @override
  String get themeAccentControlTitle => '主操作色';

  @override
  String get themeAccentControlSubtitle => '控制主按钮、进度条、确认动作和主要强调元素。';

  @override
  String get themeCustomAccentPickerTitle => '自定义主操作色';

  @override
  String get themeSelectionControlTitle => '选中色';

  @override
  String get themeSelectionControlSubtitle => '控制选中态、边框高亮和标签状态。';

  @override
  String get themeCustomSelectionPickerTitle => '自定义选中色';

  @override
  String get themeLinkControlTitle => '链接高亮色';

  @override
  String get themeLinkControlSubtitle => '控制“更多”、跳转文本和轻量提示的强调色。';

  @override
  String get themeCustomLinkPickerTitle => '自定义链接色';

  @override
  String get themeRecipePresetLabel => '预设';

  @override
  String get themeRecipeBackgroundLabel => '背景';

  @override
  String get themeRecipeAccentLabel => '主操作';

  @override
  String get themeRecipeSelectionLabel => '选中色';

  @override
  String get themeRecipeLinkLabel => '链接色';

  @override
  String get themeRecipeCurrentTitle => '当前配方';

  @override
  String get themeDynamicTitle => '动态取色主题';

  @override
  String get themeDynamicSubtitle => '详情页和人物页可基于海报临时取色，退出后恢复当前主题。';

  @override
  String get themeDynamicScopeDetailsAndPeople => '当前范围: 详情页和人物页';

  @override
  String get themeDynamicScopeOff => '当前范围: 已关闭';

  @override
  String get themeDynamicDescription => '控制背景主色、面板层级、桥接渐变与环境色；按钮和链接保持固定颜色。';

  @override
  String get themeDynamicDisabled => '详情页取色已关闭';

  @override
  String get themeDynamicPlayerNote => '播放态不覆盖主屏主题；高级强度会联动普通页面。';

  @override
  String get mpvEqAllBandsReset => '已归零所有 EQ 频段';

  @override
  String mpvEqPresetApplied(Object name) {
    return '已套用预设: $name';
  }

  @override
  String get mpvEqPresetSaved => '已保存 EQ 预设';

  @override
  String mpvEqPresetDeleted(Object name) {
    return '已删除预设: $name';
  }

  @override
  String get mpvEqSavePresetTitle => '保存 EQ 预设';

  @override
  String get mpvEqSavePresetHint => '例如: 夜间对白 / 动漫人声';

  @override
  String get mpvEqMyPresetsTitle => '我的预设';

  @override
  String get mpvEqMyPresetsSubtitle => '把当前频段组合保存成多套预设，后面一键套用。';

  @override
  String get mpvEqSaveCurrent => '保存当前';

  @override
  String get mpvEqEmptyPresets => '还没有自定义 EQ 预设，调好以后可以直接保存。';

  @override
  String get mpvEqSummaryNeutral => '全部频段保持 0 dB。';

  @override
  String get mpvEqApply => '套用';

  @override
  String get homeTitle => '首页';

  @override
  String get homeContinueWatching => '继续观看';

  @override
  String get favoriteTabEpisodes => '剧集';

  @override
  String get favoriteTabPeople => '人物';

  @override
  String get homeActionViewDetail => '查看影片详情';

  @override
  String get homeActionRestartPlayback => '从头开始播放';

  @override
  String get homeActionRemoveFromContinue => '从“继续观看”中移除';

  @override
  String get homeRemovedFromContinue => '已从继续观看中移除';

  @override
  String get homeLoginRequired => '请先到“设置”页登录 NAS，再返回影视页加载内容。';

  @override
  String get parallelWindowTitle => '平行窗口设置';

  @override
  String get parallelWindowEnableTitle => '启用平行窗口';

  @override
  String get parallelWindowEnableSubtitle => '开启后，大屏设备的二级页面优先在副屏展开；关闭后使用单屏导航。';

  @override
  String get parallelWindowPrimarySideTitle => '主屏位置';

  @override
  String get parallelWindowPrimaryLeftTitle => '左侧主屏';

  @override
  String get parallelWindowPrimaryLeftSubtitle => '默认首页在左，右侧展开详情或设置。';

  @override
  String get parallelWindowPrimaryRightTitle => '右侧主屏';

  @override
  String get parallelWindowPrimaryRightSubtitle => '右侧为主屏，左侧展开详情或设置。';

  @override
  String get parallelWindowPlaybackSideTitle => '播放主屏位置';

  @override
  String get parallelWindowPlaybackLeftTitle => '左侧为播放主屏';

  @override
  String get parallelWindowPlaybackLeftSubtitle => '进入分屏播放后，左边保持播放器，右边放详情或首页。';

  @override
  String get parallelWindowPlaybackRightTitle => '右侧为播放主屏';

  @override
  String get parallelWindowPlaybackRightSubtitle => '进入分屏播放后，右边保持播放器，左边放详情或首页。';

  @override
  String get parallelWindowSplitRatioTitle => '分屏比例';

  @override
  String get parallelWindowSplitBalancedSubtitle => '默认，兼顾列表浏览和右侧详情。';

  @override
  String get parallelWindowSplitEqualSubtitle => '左右均衡，适合双侧并行操作。';

  @override
  String get parallelWindowSplitFocusDetailSubtitle => '副屏更宽，适合详情和播放信息。';

  @override
  String get parallelWindowSplitFocusHomeSubtitle => '主屏稍宽，适合首页或列表操作。';

  @override
  String get parallelWindowDefaultFullscreenTitle => '默认播放全屏';

  @override
  String get parallelWindowDefaultFullscreenOnSubtitle =>
      '点击播放后先进入全屏播放器，再由按钮切到分屏。';

  @override
  String get parallelWindowDefaultFullscreenOffSubtitle =>
      '点击播放后优先保持平行窗口分屏，不先放大全屏。';

  @override
  String get parallelWindowImmersiveTitle => '平行窗口沉浸模式';

  @override
  String get parallelWindowImmersiveOnSubtitle => '进入平行窗口后隐藏状态栏，内容直接顶到屏幕顶部。';

  @override
  String get parallelWindowImmersiveOffSubtitle => '保留状态栏，使用常规分屏显示。';

  @override
  String get danmakuSpeedNormal => '正常';

  @override
  String get danmakuSpeedFaster => '较快';

  @override
  String get danmakuAreaOneTenth => '1/10屏';

  @override
  String get danmakuAreaOneQuarter => '1/4屏';

  @override
  String get danmakuAreaThreeQuarters => '3/4屏';

  @override
  String get danmakuFontSmall => '较小';

  @override
  String get danmakuFontSlightlySmall => '偏小';

  @override
  String get danmakuFontStandard => '标准';

  @override
  String get danmakuFontSlightlyLarge => '偏大';

  @override
  String get danmakuFontLarge => '较大';

  @override
  String get danmakuSourceManagementTitle => '来源管理';

  @override
  String get danmakuSourceManagementSubtitle =>
      '统一管理网络弹幕和本地导入弹幕，支持按来源层级查看与手动删除。';

  @override
  String get danmakuManagementTitle => '弹幕管理';

  @override
  String danmakuSavedSourceCount(int count) {
    return '当前已保存 $count 个弹幕来源';
  }

  @override
  String get danmakuBasicSectionTitle => '基础';

  @override
  String get danmakuBasicSectionSubtitle => '这些是全局默认值，不依赖当前播放页面。';

  @override
  String get danmakuDefaultEnabledTitle => '默认开启弹幕';

  @override
  String get danmakuDefaultEnabledSubtitle => '进入播放器时默认带着弹幕设置启动。';

  @override
  String get danmakuPreviewEnabledTitle => '详情页预览弹幕';

  @override
  String get danmakuPreviewEnabledSubtitle => '在非播放页展示弹幕预览时使用这项默认值。';

  @override
  String get danmakuSourcePriorityTitle => '来源优先';

  @override
  String get danmakuSourcePrioritySubtitle => '控制本地弹幕和网络弹幕同时可用时的默认选择。';

  @override
  String get danmakuPreferLocal => '本地优先';

  @override
  String get danmakuPreferNetwork => '网络优先';

  @override
  String get danmakuDisplayStyleTitle => '显示样式';

  @override
  String get danmakuDisplayStyleSubtitle => '这些设置适合在非播放页提前调好，进播放器后直接沿用。';

  @override
  String get danmakuDisplayAreaTitle => '显示区域';

  @override
  String get danmakuOpacityTitle => '不透明度';

  @override
  String get danmakuDensityTitle => '弹幕密度';

  @override
  String get danmakuFontSizeTitle => '字体大小';

  @override
  String get danmakuSpeedTitle => '弹幕速度';

  @override
  String get danmakuTypeFilterTitle => '类型过滤';

  @override
  String get danmakuTypeFilterSubtitle => '控制默认显示哪些弹幕类型。';

  @override
  String get danmakuAvoidanceTitle => '防遮挡';

  @override
  String get danmakuAvoidanceSubtitle => '这些默认规则更适合全局预先设定。';

  @override
  String get commonRefresh => '刷新';

  @override
  String get playStatsTitle => '播放统计';

  @override
  String get playStatsClearTitle => '清空播放统计';

  @override
  String get playStatsClearContent => '这会删除本地播放历史和所有聚合统计数据。';

  @override
  String get playStatsClearTooltip => '清空统计';

  @override
  String playStatsLoadFailed(Object error) {
    return '加载播放统计失败：$error';
  }

  @override
  String get playStatsOverview => '总览';

  @override
  String get playStatsTotalPlayedDuration => '总播放时长';

  @override
  String get playStatsTotalClicks => '总点击数';

  @override
  String get playStatsTotalViews => '总观看数';

  @override
  String get playStatsTotalCompletedVideos => '总完播视频数';

  @override
  String get playStatsTotalCompletedSeasons => '总完播季数';

  @override
  String get playStatsBackfillTitle => '后台补全';

  @override
  String get playStatsBackfillRunning => '正在后台补全年份、国家、类型和演职人员。';

  @override
  String get playStatsAnimeList => '番剧列表';

  @override
  String get playStatsNoAnimeStats => '还没有番剧播放统计。';

  @override
  String get playStatsUnnamedAnime => '未命名番剧';

  @override
  String playStatsAnimeSubtitle(int seasonCount, int ungroupedCount) {
    return '季度 $seasonCount / 未分组视频 $ungroupedCount';
  }

  @override
  String get playStatsMovieList => '电影列表';

  @override
  String playStatsMovieSubtitle(int historyCount, int viewCount) {
    return '电影 / 历史 $historyCount 条 / 观看数 $viewCount';
  }

  @override
  String get playStatsOrphanVideos => '异常未归类视频';

  @override
  String playStatsOrphanSubtitle(int historyCount) {
    return '未匹配番剧或季度 / 历史 $historyCount 条';
  }

  @override
  String get playStatsUnlinkedHistory => '未关联历史';

  @override
  String playStatsCountItems(int count) {
    return '共 $count 条';
  }

  @override
  String get playStatsYes => '是';

  @override
  String get playStatsNo => '否';

  @override
  String playStatsDurationHours(int hours, int minutes, int seconds) {
    return '$hours 小时 $minutes 分钟 $seconds 秒';
  }

  @override
  String playStatsDurationMinutes(int minutes, int seconds) {
    return '$minutes 分钟 $seconds 秒';
  }

  @override
  String playStatsDurationSeconds(int seconds) {
    return '$seconds 秒';
  }

  @override
  String get playStatsStartSourceManual => '手动打开';

  @override
  String get playStatsStartSourceManualSwitch => '手动换集';

  @override
  String get playStatsStartSourceAutoNext => '自动连播';

  @override
  String get playStatsStartSourceReplay => '重播';

  @override
  String get playStatsStartSourceSystemResume => '系统恢复';

  @override
  String get playStatsAnimeDetail => '番剧详情';

  @override
  String get playStatsAnimeFields => '番剧字段';

  @override
  String get playStatsAnimeMetadata => '番剧元数据';

  @override
  String get playStatsSeasonList => '季度列表';

  @override
  String get playStatsNoSeasonData => '没有季度数据。';

  @override
  String get playStatsUnnamedSeason => '未命名季度';

  @override
  String playStatsSeasonSubtitle(int episodeCount, int completedCount) {
    return '剧集 $episodeCount / 已完播 $completedCount';
  }

  @override
  String get playStatsUngroupedVideos => '未归属到季度的视频';

  @override
  String get playStatsSeasonDetail => '季度详情';

  @override
  String get playStatsSeasonFields => '季度字段';

  @override
  String get playStatsCredits => '演职人员';

  @override
  String get playStatsEpisodeList => '剧集列表';

  @override
  String get playStatsNoEpisodeData => '没有剧集数据。';

  @override
  String get playStatsVideoDetail => '视频详情';

  @override
  String get playStatsMovieFields => '电影字段';

  @override
  String get playStatsEpisodeFields => '剧集字段';

  @override
  String get playStatsPlaybackHistory => '播放历史';

  @override
  String get playStatsNoPlaybackHistory => '没有播放历史。';

  @override
  String get playStatsHistoryDetail => '播放历史详情';

  @override
  String get playStatsHistoryFields => '历史字段';

  @override
  String get playStatsUnnamedVideo => '未命名视频';

  @override
  String playStatsVideoSubtitle(int historyCount, int viewCount) {
    return '历史 $historyCount 条 / 观看数 $viewCount';
  }

  @override
  String playStatsHistoryEntrySubtitle(
    Object startedAt,
    Object watchedDuration,
    Object completed,
  ) {
    return '$startedAt / 观看 $watchedDuration / 完播 $completed';
  }

  @override
  String get playStatsNoCreditSnapshot => '当前没有记录到演职人员快照。';

  @override
  String playStatsPageIndicator(int currentPage, int pageCount) {
    return '第 $currentPage 页 / 共 $pageCount 页';
  }

  @override
  String get playStatsPreviousPage => '上一页';

  @override
  String get playStatsNextPage => '下一页';

  @override
  String get playStatsFieldAnimeId => '番剧 ID';

  @override
  String get playStatsFieldTitle => '标题';

  @override
  String get playStatsFieldClickCount => '点击数';

  @override
  String get playStatsFieldViewCount => '观看数';

  @override
  String get playStatsFieldTotalPlayedDuration => '累计播放时长';

  @override
  String get playStatsFieldForwardSeekCount => '快进次数';

  @override
  String get playStatsFieldBackwardSeekCount => '回退次数';

  @override
  String get playStatsFieldWatchedEpisodeCount => '已观看正片集数';

  @override
  String get playStatsFieldCompletedEpisodeCount => '已完播正片集数';

  @override
  String get playStatsFieldCompletedSeasonCount => '已完播季数';

  @override
  String get playStatsFieldLastPlayedAt => '上次播放时间';

  @override
  String get playStatsFieldYear => '年份';

  @override
  String get playStatsFieldCountryFirstValue => '国家首值';

  @override
  String get playStatsFieldCountryCodes => '国家地区代码';

  @override
  String get playStatsFieldCountryNames => '国家地区中文';

  @override
  String get playStatsFieldGenreIds => '类型 ID';

  @override
  String get playStatsFieldGenreNames => '类型中文';

  @override
  String get playStatsFieldSeasonId => '季度 ID';

  @override
  String get playStatsFieldTotalEpisodeCount => '总正片集数';

  @override
  String get playStatsFieldWatchedEpisodeCountShort => '已观看集数';

  @override
  String get playStatsFieldCompletedEpisodeCountShort => '已完播集数';

  @override
  String get playStatsFieldIsSeasonCompleted => '是否季完播';

  @override
  String get playStatsFieldVideoId => '视频 ID';

  @override
  String get playStatsFieldAnimeTitle => '番剧标题';

  @override
  String get playStatsFieldSeasonTitle => '季度标题';

  @override
  String get playStatsFieldVideoKind => '视频种类';

  @override
  String get playStatsFieldCountsTowardCompletion => '是否计入季完播';

  @override
  String get playStatsFieldMediaDuration => '媒体总时长';

  @override
  String get playStatsFieldAutoPlayCount => '自动连播次数';

  @override
  String get playStatsFieldMaxProgress => '最大播放进度';

  @override
  String get playStatsFieldLastProgress => '最后播放进度';

  @override
  String get playStatsFieldLastPosition => '最后播放位置';

  @override
  String get playStatsFieldCompleted => '是否完播';

  @override
  String get playStatsFieldMetadataEnriched => '元数据已补全';

  @override
  String get playStatsFieldHistoryId => '历史 ID';

  @override
  String get playStatsFieldStartSource => '开始来源';

  @override
  String get playStatsFieldStartedAt => '开始时间';

  @override
  String get playStatsFieldEndedAt => '结束时间';

  @override
  String get playStatsFieldWatchedDuration => '观看时长';

  @override
  String get playStatsFieldMaxPosition => '最大播放位置';

  @override
  String get playStatsFieldCountedAsView => '是否计入观看';

  @override
  String get playStatsFieldCountedAsCompleted => '是否计入完播';

  @override
  String get playStatsFieldOpDetected => '已识别 OP';

  @override
  String get playStatsFieldEdDetected => '已识别 ED';

  @override
  String get playStatsFieldOpSkipped => '已跳过 OP';

  @override
  String get playStatsFieldEdSkipped => '已跳过 ED';

  @override
  String get playStatsFieldOpNotSkipped => '未跳过 OP';

  @override
  String get playStatsFieldEdNotSkipped => '未跳过 ED';

  @override
  String get playStatsFieldOpPlayedDuration => 'OP 播放时长';

  @override
  String get playStatsFieldEdPlayedDuration => 'ED 播放时长';

  @override
  String get playStatsFieldPersonId => '人员 ID';

  @override
  String get playStatsFieldName => '姓名';

  @override
  String get playStatsFieldRole => '角色';

  @override
  String get playStatsFieldJob => '工种';

  @override
  String get playStatsFieldOrder => '排序';

  @override
  String get commonRetry => '重试';

  @override
  String get playStatsReportDetailData => '详细数据';

  @override
  String get playStatsReportRangeTitle => '观影战报时间范围';

  @override
  String get playStatsReportSwitching => '切换中';

  @override
  String get playStatsReportBackfillingMetadata => '正在补全类型、国家地区、年份和演职人员数据';

  @override
  String get playStatsReportLoadFailedTitle => '加载播放统计失败';

  @override
  String get playStatsReportUnknownError => '未知错误';

  @override
  String playStatsReportErrorMessage(Object error) {
    return '错误信息：$error';
  }

  @override
  String get playStatsReportActivityTitle => '活跃趋势';

  @override
  String get playStatsReportActivitySubtitle => '按天观察播放时长变化，看看这段时间里哪几天看得最久。';

  @override
  String get playStatsReportDailyDurationTitle => '每日播放时长';

  @override
  String get playStatsReportDailyDurationSubtitle => '看最近一段时间里，哪几天看得最久。';

  @override
  String get playStatsReportContentTitle => '内容偏好';

  @override
  String get playStatsReportContentSubtitle => '用播放时长加权，看看你最近更偏好的内容类型与人物。';

  @override
  String get playStatsReportContentShare => '内容占比';

  @override
  String get playStatsReportAffinityTitle => '演职人员亲和榜';

  @override
  String get playStatsReportBehaviorTitle => '观看行为';

  @override
  String get playStatsReportBehaviorSubtitle => '统计来源、完播率、快进回退以及 OP/ED 的观看习惯。';

  @override
  String get playStatsReportStartSource => '播放来源';

  @override
  String playStatsReportCountTimes(int count) {
    return '$count 次';
  }

  @override
  String get playStatsReportCompletionRate => '完播率';

  @override
  String playStatsReportSessionRatio(int completed, int total) {
    return '$completed/$total 次会话';
  }

  @override
  String get playStatsReportTotalActions => '总操作数';

  @override
  String playStatsReportSeekSummary(int forwardCount, int backwardCount) {
    return '快进 $forwardCount · 回退 $backwardCount';
  }

  @override
  String get playStatsReportIntroOp => '片头 OP';

  @override
  String get playStatsReportOutroEd => '片尾 ED';

  @override
  String get playStatsReportRankingTitle => '排行与回看';

  @override
  String get playStatsReportRankingSubtitle => '保留最近活跃内容、继续观看线索和当前最常看的内容。';

  @override
  String get playStatsReportAnimeRankingTitle => '剧集榜';

  @override
  String get playStatsReportAnimeRankingSubtitle => '按剧集聚合后的总观看时长排行';

  @override
  String get playStatsReportVideoRankingTitle => '单集 / 视频榜';

  @override
  String get playStatsReportVideoRankingSubtitle => '按具体视频或单集聚合的观看时长排行';

  @override
  String get playStatsReportRecentHistoryTitle => '最近观看';

  @override
  String get playStatsReportRecentHistorySubtitle => '最近发生的播放记录时间线';

  @override
  String playStatsReportDurationHoursMinutes(int hours, int minutes) {
    return '$hours 小时 $minutes 分钟';
  }

  @override
  String playStatsReportDurationHours(int hours) {
    return '$hours 小时';
  }

  @override
  String playStatsReportDurationMinutes(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String get playStatsReportWeekdayMon => '一';

  @override
  String get playStatsReportWeekdayTue => '二';

  @override
  String get playStatsReportWeekdayWed => '三';

  @override
  String get playStatsReportWeekdayThu => '四';

  @override
  String get playStatsReportWeekdayFri => '五';

  @override
  String get playStatsReportWeekdaySat => '六';

  @override
  String get playStatsReportWeekdaySun => '日';

  @override
  String get playStatsReportStartSourceManual => '手动播放';

  @override
  String get playStatsReportStartSourceManualSwitch => '手动切换';

  @override
  String get playStatsReportStartSourceReplay => '重新播放';

  @override
  String playStatsReportHistorySubtitle(
    Object startedAt,
    Object watchedDuration,
  ) {
    return '$startedAt · 观看 $watchedDuration';
  }

  @override
  String playStatsReportHistoryMeta(
    Object source,
    Object watchedDuration,
    Object startedAt,
  ) {
    return '$source · 观看 $watchedDuration · $startedAt';
  }

  @override
  String playStatsReportMovieWatchedSubtitle(Object watchedDuration) {
    return '电影 · 观看 $watchedDuration';
  }

  @override
  String playStatsReportWatchedDuration(Object watchedDuration) {
    return '观看 $watchedDuration';
  }

  @override
  String get playStatsReportFrequentPerson => '常看人物';

  @override
  String playStatsReportProgress(Object progress) {
    return '进度 $progress';
  }

  @override
  String get playStatsReportOccupationDirector => '导演';

  @override
  String get playStatsReportOccupationProducer => '制片';

  @override
  String get playStatsReportOccupationExecutiveProducer => '监制';

  @override
  String get playStatsReportOccupationWriter => '编剧';

  @override
  String get playStatsReportOccupationOriginal => '原作';

  @override
  String get playStatsReportOccupationComposer => '作曲';

  @override
  String get playStatsReportOccupationMusic => '音乐';

  @override
  String get playStatsReportOccupationEditor => '剪辑';

  @override
  String get playStatsReportOccupationCinematography => '摄影';

  @override
  String get playStatsReportOccupationVoice => '配音';

  @override
  String get playStatsReportOccupationActor => '演员';

  @override
  String get playStatsReportOccupationCrew => '幕后';

  @override
  String get playStatsReportOccupationSound => '音效';

  @override
  String get playStatsReportOccupationArt => '美术';

  @override
  String get playStatsReportOccupationVisualEffects => '特效';

  @override
  String playStatsReportHeroTitle(Object range) {
    return '$range观影战报';
  }

  @override
  String get playStatsReportActiveDays => '活跃天数';

  @override
  String playStatsReportTotalDuration(Object duration) {
    return '累计 $duration';
  }

  @override
  String get playStatsReportClickCount => '播放次数';

  @override
  String get playStatsReportClickCountDescription =>
      '统计这段时间里，你主动点开播放或手动切换内容的次数。';

  @override
  String get playStatsReportClickCountDetail => '更接近你发起了多少次播放，不包含自动连播或系统恢复。';

  @override
  String get playStatsReportViewCount => '观看次数';

  @override
  String get playStatsReportViewCountDescription =>
      '只统计达到有效观看门槛的播放记录，用来看你真正进入观看状态了多少次。';

  @override
  String get playStatsReportViewCountDetail => '剧集需看满 20%，电影需看满 10%。';

  @override
  String get playStatsReportCompletedVideos => '完播视频';

  @override
  String get playStatsReportCompletedVideosDescription =>
      '统计被判定为完整看完的具体视频条目数，更接近你真正看完了多少集或多少部片。';

  @override
  String get playStatsReportCompletedVideosDetail =>
      '通常需要看满约 80%，并且结尾不是一拖而过，才会记入完播。';

  @override
  String get playStatsReportCompletedSeasons => '完播季度';

  @override
  String get playStatsReportCompletedSeasonsDescription =>
      '统计在当前时间范围内，被判定为整季看完的季度数量。';

  @override
  String get playStatsReportCompletedSeasonsDetail =>
      '只有计入季完播的正片都完成后，这一季才会记作 1 个完播季度。';

  @override
  String get playStatsReportMetadataCoverage => '元数据覆盖';

  @override
  String get playStatsReportMetadataCoverageDescription =>
      '反映这批内容里，类型、国家地区、年份和演职人员等信息补全得有多完整。';

  @override
  String get playStatsReportMetadataCoverageDetail =>
      '覆盖越高，下面的偏好分析和亲和榜越完整、越可靠。';

  @override
  String get playStatsReportNoTrendData => '暂无播放趋势数据';

  @override
  String get playStatsReportNoViewCountData => '暂无观看次数数据';

  @override
  String playStatsReportBarTooltip(int month, int day, int count) {
    return '$month/$day\n$count 次';
  }

  @override
  String get playStatsReportNoHeatmapData => '暂无活跃时段数据';

  @override
  String playStatsReportHeatmapTooltip(
    Object weekday,
    Object hour,
    int count,
    Object duration,
  ) {
    return '周$weekday $hour:00\n$count 次 / $duration';
  }

  @override
  String get playStatsReportHeatmapLow => '少';

  @override
  String get playStatsReportHeatmapHigh => '多';

  @override
  String get playStatsReportNoSeekActions => '本时间段几乎没有快进或回退操作';

  @override
  String playStatsReportNoDetectionRecord(Object label) {
    return '$label 暂无检测记录';
  }

  @override
  String playStatsReportOpEdDetectedSkipped(
    int detectedCount,
    int skippedCount,
  ) {
    return '检测 $detectedCount 次 · 跳过 $skippedCount 次';
  }

  @override
  String get playStatsReportSkipped => '跳过';

  @override
  String get playStatsReportWatchedCompletely => '完整观看';

  @override
  String get playStatsReportNoDistributionData => '暂无分布数据';

  @override
  String get playStatsReportMetadataBackfilling => '相关元数据还在补全中';

  @override
  String get playStatsReportNoRankingData => '当前没有足够的排行数据';

  @override
  String get playStatsReportNoRecentHistory => '最近还没有新的观看记录';

  @override
  String get playStatsReportJumpPageTitle => '跳转页码';

  @override
  String playStatsReportJumpPageDescription(int pageCount) {
    return '输入 1 到 $pageCount 之间的页码';
  }

  @override
  String get playStatsReportPageNumberLabel => '页码';

  @override
  String playStatsReportPageNumberHint(int page) {
    return '例如 $page';
  }

  @override
  String get playStatsReportJumpPageAction => '跳转';

  @override
  String playStatsReportPageIndicator(int currentPage, int pageCount) {
    return '第 $currentPage / $pageCount 页';
  }

  @override
  String get playStatsReportJumpPage => '跳页';

  @override
  String get playStatsReportFirstPage => '第一页';

  @override
  String get playStatsReportLastPage => '最后页';

  @override
  String get playStatsReportNoContinueWatching => '目前没有适合继续观看的内容';

  @override
  String playStatsReportLastWatchedAt(Object time) {
    return '上次观看 $time';
  }

  @override
  String get playStatsReportEmptyTitle => '还没有可展示的观影战报';

  @override
  String get playStatsReportEmptySubtitle => '开始播放内容后，这里会自动生成趋势、偏好、行为和回看报表。';

  @override
  String get playStatsReportUnnamedEpisode => '未命名剧集';

  @override
  String playStatsReportAnimeRankSubtitle(int sessionCount, int viewCount) {
    return '观看 $sessionCount 次 · 完整观看 $viewCount 次';
  }

  @override
  String get playStatsReportUnknownPerson => '未知人物';

  @override
  String get bookmarkManagerLegacyBookmark => '旧书签';

  @override
  String get bookmarkManagerUnnamedWork => '未命名作品';

  @override
  String get bookmarkManagerSpecialSeason => '特别篇';

  @override
  String bookmarkManagerSeasonLabel(int season) {
    return '第$season季';
  }

  @override
  String bookmarkManagerEpisodeLabel(int episode) {
    return '第$episode集';
  }

  @override
  String get bookmarkManagerUnnamedEpisode => '未命名剧集';

  @override
  String get bookmarkManagerEditNoteTitle => '编辑书签备注';

  @override
  String get bookmarkManagerNoEpisodeBookmarks => '该集下已经没有书签';

  @override
  String get bookmarkManagerNoteAction => '备注';

  @override
  String get danmakuManagerLegacySource => '旧来源';

  @override
  String get danmakuManagerUnnamedItem => '未命名条目';

  @override
  String danmakuManagerSourceCount(int count) {
    return '共 $count 个来源';
  }

  @override
  String get danmakuManagerNetworkDanmaku => '网络弹幕';

  @override
  String get danmakuManagerLocalImport => '本地导入';

  @override
  String danmakuManagerCommentCount(int count) {
    return '$count 条';
  }

  @override
  String get danmakuManagerUnnamedSource => '未命名弹幕来源';

  @override
  String mediaEpisodeCount(int count) {
    return '共$count集';
  }

  @override
  String mediaSeasonCount(int count) {
    return '共$count季';
  }

  @override
  String mediaWorkCount(int count) {
    return '共$count 个作品';
  }

  @override
  String get fileInfoLocationLabel => '文件位置';

  @override
  String get fileInfoSizeLabel => '文件大小';

  @override
  String get fileInfoCreatedAtLabel => '文件创建日期';

  @override
  String get fileInfoAddedAtLabel => '添加日期';

  @override
  String get fileInfoToggleToFriendly => '转换';

  @override
  String fileInfoStorageSpace(Object volumeNo) {
    return '存储空间$volumeNo';
  }

  @override
  String fileInfoStorageSpaceFile(Object volumeNo, Object name) {
    return '存储空间$volumeNo/$name 的文件';
  }

  @override
  String get fnConnectNasAddressFailed => 'FN Connect 登录失败，未能解析 NAS 地址';

  @override
  String get playerHostInvalidArgs => '当前播放器参数错误';

  @override
  String get themeSaveDefaultBase => '自定义主题';

  @override
  String themeSaveName(Object base) {
    return '$base主题色';
  }

  @override
  String storageSeriesGroupSubtitle(
    int seasonCount,
    int entryCount,
    Object size,
    Object time,
  ) {
    return '$seasonCount 季 · $entryCount 集 · $size · 最近 $time';
  }

  @override
  String storageSeasonGroupSubtitle(int entryCount, Object size, Object time) {
    return '$entryCount 集 · $size · 最近 $time';
  }

  @override
  String storageGroupedPageSummary(int totalCount, int pageSize) {
    return '$totalCount 个作品 · 每页 $pageSize 个';
  }

  @override
  String get storageUnknownWork => '未知作品';

  @override
  String get storageUngroupedSeason => '未分季';

  @override
  String storageSeasonNumberSpaced(int season) {
    return '第 $season 季';
  }

  @override
  String storageEpisodeTitleWithNumber(int episode, Object title) {
    return '第 $episode 集 $title';
  }

  @override
  String get storageUnknownEpisode => '未知集数';
}
