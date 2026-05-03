import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('zh'),
    Locale('zh', 'CN'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'Fly Player'**
  String get appTitle;

  /// No description provided for @globalLoadFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'加载失败'**
  String get globalLoadFailed;

  /// No description provided for @navMovies.
  ///
  /// In zh_CN, this message translates to:
  /// **'影视'**
  String get navMovies;

  /// No description provided for @navSettings.
  ///
  /// In zh_CN, this message translates to:
  /// **'设置'**
  String get navSettings;

  /// No description provided for @settingsTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'设置'**
  String get settingsTitle;

  /// No description provided for @settingsSearchTooltip.
  ///
  /// In zh_CN, this message translates to:
  /// **'搜索设置项'**
  String get settingsSearchTooltip;

  /// No description provided for @settingsLanguageTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'应用语言'**
  String get settingsLanguageTitle;

  /// No description provided for @settingsLanguageSubtitleSystem.
  ///
  /// In zh_CN, this message translates to:
  /// **'跟随系统'**
  String get settingsLanguageSubtitleSystem;

  /// No description provided for @settingsLanguageSubtitleZhCN.
  ///
  /// In zh_CN, this message translates to:
  /// **'简体中文'**
  String get settingsLanguageSubtitleZhCN;

  /// No description provided for @languageSheetTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'应用语言'**
  String get languageSheetTitle;

  /// No description provided for @languageSystem.
  ///
  /// In zh_CN, this message translates to:
  /// **'跟随系统'**
  String get languageSystem;

  /// No description provided for @languageSystemSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'使用系统语言偏好'**
  String get languageSystemSubtitle;

  /// No description provided for @languageZhCN.
  ///
  /// In zh_CN, this message translates to:
  /// **'简体中文'**
  String get languageZhCN;

  /// No description provided for @languageZhCNSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'固定使用简体中文'**
  String get languageZhCNSubtitle;

  /// No description provided for @commonCancel.
  ///
  /// In zh_CN, this message translates to:
  /// **'取消'**
  String get commonCancel;

  /// No description provided for @commonConfirm.
  ///
  /// In zh_CN, this message translates to:
  /// **'确认'**
  String get commonConfirm;

  /// No description provided for @commonSave.
  ///
  /// In zh_CN, this message translates to:
  /// **'保存'**
  String get commonSave;

  /// No description provided for @commonRefreshRetry.
  ///
  /// In zh_CN, this message translates to:
  /// **'刷新重试'**
  String get commonRefreshRetry;

  /// No description provided for @commonNone.
  ///
  /// In zh_CN, this message translates to:
  /// **'无'**
  String get commonNone;

  /// No description provided for @commonEmpty.
  ///
  /// In zh_CN, this message translates to:
  /// **'没有内容'**
  String get commonEmpty;

  /// No description provided for @commonNoData.
  ///
  /// In zh_CN, this message translates to:
  /// **'暂无数据'**
  String get commonNoData;

  /// No description provided for @commonNoAccessLibrary.
  ///
  /// In zh_CN, this message translates to:
  /// **'没有可访问的媒体库，请联系管理员'**
  String get commonNoAccessLibrary;

  /// No description provided for @authExitTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'退出登录'**
  String get authExitTitle;

  /// No description provided for @authExitContent.
  ///
  /// In zh_CN, this message translates to:
  /// **'确认退出当前帐号？'**
  String get authExitContent;

  /// No description provided for @mediaAllItemsTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'全部影视'**
  String get mediaAllItemsTitle;

  /// No description provided for @mediaLibraryFallbackName.
  ///
  /// In zh_CN, this message translates to:
  /// **'媒体库'**
  String get mediaLibraryFallbackName;

  /// No description provided for @collectionLayoutTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'布局方式'**
  String get collectionLayoutTitle;

  /// No description provided for @collectionLayoutSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'切换合集详情中的列表布局'**
  String get collectionLayoutSubtitle;

  /// No description provided for @collectionLayoutViewSection.
  ///
  /// In zh_CN, this message translates to:
  /// **'视图'**
  String get collectionLayoutViewSection;

  /// No description provided for @collectionLayoutPosterWall.
  ///
  /// In zh_CN, this message translates to:
  /// **'海报墙'**
  String get collectionLayoutPosterWall;

  /// No description provided for @collectionLayoutList.
  ///
  /// In zh_CN, this message translates to:
  /// **'列表'**
  String get collectionLayoutList;

  /// No description provided for @collectionLayoutPosterSection.
  ///
  /// In zh_CN, this message translates to:
  /// **'海报'**
  String get collectionLayoutPosterSection;

  /// No description provided for @collectionLayoutHorizontalPoster.
  ///
  /// In zh_CN, this message translates to:
  /// **'横幅'**
  String get collectionLayoutHorizontalPoster;

  /// No description provided for @collectionLayoutVerticalPoster.
  ///
  /// In zh_CN, this message translates to:
  /// **'竖幅'**
  String get collectionLayoutVerticalPoster;

  /// No description provided for @collectionItemCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'共 {count} 项'**
  String collectionItemCount(int count);

  /// No description provided for @localFileAuthorizeFirst.
  ///
  /// In zh_CN, this message translates to:
  /// **'请先授权一个文件夹，然后在应用内选择本地文件'**
  String get localFileAuthorizeFirst;

  /// No description provided for @localFileNoAuthorizedFolder.
  ///
  /// In zh_CN, this message translates to:
  /// **'还没有授权本地文件夹，先授权一个目录后才能在应用内浏览'**
  String get localFileNoAuthorizedFolder;

  /// No description provided for @localFileAuthorizationCanceled.
  ///
  /// In zh_CN, this message translates to:
  /// **'没有完成文件夹授权，无法读取本地文件'**
  String get localFileAuthorizationCanceled;

  /// No description provided for @localFileAuthorizedFolderUnavailable.
  ///
  /// In zh_CN, this message translates to:
  /// **'已授权的目录当前不可访问，请重新授权文件夹'**
  String get localFileAuthorizedFolderUnavailable;

  /// No description provided for @localFileReadDirectoryFailedRetry.
  ///
  /// In zh_CN, this message translates to:
  /// **'读取目录失败，请重新授权后重试'**
  String get localFileReadDirectoryFailedRetry;

  /// No description provided for @localFileReadDirectoryFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'读取目录失败: {error}'**
  String localFileReadDirectoryFailed(Object error);

  /// No description provided for @localFileAuthorizeFolder.
  ///
  /// In zh_CN, this message translates to:
  /// **'授权文件夹'**
  String get localFileAuthorizeFolder;

  /// No description provided for @localFileChangeFolder.
  ///
  /// In zh_CN, this message translates to:
  /// **'更换文件夹'**
  String get localFileChangeFolder;

  /// No description provided for @localFileParentDirectory.
  ///
  /// In zh_CN, this message translates to:
  /// **'返回上一级'**
  String get localFileParentDirectory;

  /// No description provided for @localFileFolder.
  ///
  /// In zh_CN, this message translates to:
  /// **'文件夹'**
  String get localFileFolder;

  /// No description provided for @detailMoreActionsTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'更多操作'**
  String get detailMoreActionsTitle;

  /// No description provided for @detailCurrentPage.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前详情页'**
  String get detailCurrentPage;

  /// No description provided for @detailSaveCurrentTheme.
  ///
  /// In zh_CN, this message translates to:
  /// **'保存当前主题'**
  String get detailSaveCurrentTheme;

  /// No description provided for @detailSaveCurrentThemeSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'把当前取色保存成一套可复用的自定义主题'**
  String get detailSaveCurrentThemeSubtitle;

  /// No description provided for @detailSaveCurrentThemeUnavailable.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前页面还没有可保存的动态取色结果'**
  String get detailSaveCurrentThemeUnavailable;

  /// No description provided for @detailThemeSaved.
  ///
  /// In zh_CN, this message translates to:
  /// **'已保存主题：{name}'**
  String detailThemeSaved(Object name);

  /// No description provided for @detailThemeNameLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'主题名称'**
  String get detailThemeNameLabel;

  /// No description provided for @detailThemeDescriptionLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'说明（可选）'**
  String get detailThemeDescriptionLabel;

  /// No description provided for @detailThemeNameDuplicate.
  ///
  /// In zh_CN, this message translates to:
  /// **'主题名称不能重复'**
  String get detailThemeNameDuplicate;

  /// No description provided for @presetNameLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'名称'**
  String get presetNameLabel;

  /// No description provided for @presetDescriptionLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'描述'**
  String get presetDescriptionLabel;

  /// No description provided for @presetNameRequired.
  ///
  /// In zh_CN, this message translates to:
  /// **'请输入名称'**
  String get presetNameRequired;

  /// No description provided for @presetAutoFill.
  ///
  /// In zh_CN, this message translates to:
  /// **'自动填入'**
  String get presetAutoFill;

  /// No description provided for @presetDescriptionHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'可选，简单写一下这个预设的用途'**
  String get presetDescriptionHint;

  /// No description provided for @audioSpecDolbySurround.
  ///
  /// In zh_CN, this message translates to:
  /// **'杜比环绕'**
  String get audioSpecDolbySurround;

  /// No description provided for @audioSpecDolbyAtmos.
  ///
  /// In zh_CN, this message translates to:
  /// **'杜比全景声'**
  String get audioSpecDolbyAtmos;

  /// No description provided for @audioSpecDts.
  ///
  /// In zh_CN, this message translates to:
  /// **'DTS'**
  String get audioSpecDts;

  /// No description provided for @audioSpecStereo.
  ///
  /// In zh_CN, this message translates to:
  /// **'立体声'**
  String get audioSpecStereo;

  /// No description provided for @resourceTypeDirectory.
  ///
  /// In zh_CN, this message translates to:
  /// **'目录'**
  String get resourceTypeDirectory;

  /// No description provided for @resourceTypeVideo.
  ///
  /// In zh_CN, this message translates to:
  /// **'视频'**
  String get resourceTypeVideo;

  /// No description provided for @listFilterButton.
  ///
  /// In zh_CN, this message translates to:
  /// **'筛选'**
  String get listFilterButton;

  /// No description provided for @listFilterAll.
  ///
  /// In zh_CN, this message translates to:
  /// **'全部'**
  String get listFilterAll;

  /// No description provided for @listFilterResetButton.
  ///
  /// In zh_CN, this message translates to:
  /// **'重置'**
  String get listFilterResetButton;

  /// No description provided for @listFilterDecadeRecent.
  ///
  /// In zh_CN, this message translates to:
  /// **'今年'**
  String get listFilterDecadeRecent;

  /// No description provided for @listTypeMovie.
  ///
  /// In zh_CN, this message translates to:
  /// **'电影'**
  String get listTypeMovie;

  /// No description provided for @listTypeTv.
  ///
  /// In zh_CN, this message translates to:
  /// **'电视剧'**
  String get listTypeTv;

  /// No description provided for @listRecognitionUnmatched.
  ///
  /// In zh_CN, this message translates to:
  /// **'未匹配'**
  String get listRecognitionUnmatched;

  /// No description provided for @listRecognitionMatched.
  ///
  /// In zh_CN, this message translates to:
  /// **'已匹配'**
  String get listRecognitionMatched;

  /// No description provided for @listRecognitionNfo.
  ///
  /// In zh_CN, this message translates to:
  /// **'NFO匹配'**
  String get listRecognitionNfo;

  /// No description provided for @listWatched.
  ///
  /// In zh_CN, this message translates to:
  /// **'已观看'**
  String get listWatched;

  /// No description provided for @listUnwatched.
  ///
  /// In zh_CN, this message translates to:
  /// **'未观看'**
  String get listUnwatched;

  /// No description provided for @listFilterType.
  ///
  /// In zh_CN, this message translates to:
  /// **'影视分类'**
  String get listFilterType;

  /// No description provided for @listFilterGenres.
  ///
  /// In zh_CN, this message translates to:
  /// **'类型'**
  String get listFilterGenres;

  /// No description provided for @listFilterLocate.
  ///
  /// In zh_CN, this message translates to:
  /// **'国家和地区'**
  String get listFilterLocate;

  /// No description provided for @listFilterDecade.
  ///
  /// In zh_CN, this message translates to:
  /// **'发行年份'**
  String get listFilterDecade;

  /// No description provided for @listFilterResolution.
  ///
  /// In zh_CN, this message translates to:
  /// **'分辨率'**
  String get listFilterResolution;

  /// No description provided for @listFilterColorRange.
  ///
  /// In zh_CN, this message translates to:
  /// **'视频动态范围'**
  String get listFilterColorRange;

  /// No description provided for @listFilterAudioType.
  ///
  /// In zh_CN, this message translates to:
  /// **'音频规格'**
  String get listFilterAudioType;

  /// No description provided for @listFilterRecognitionStatus.
  ///
  /// In zh_CN, this message translates to:
  /// **'匹配状态'**
  String get listFilterRecognitionStatus;

  /// No description provided for @listFilterWatched.
  ///
  /// In zh_CN, this message translates to:
  /// **'是否观看'**
  String get listFilterWatched;

  /// No description provided for @listSortTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'排序'**
  String get listSortTitle;

  /// No description provided for @listSortCreateTime.
  ///
  /// In zh_CN, this message translates to:
  /// **'按添加日期'**
  String get listSortCreateTime;

  /// No description provided for @listSortReleaseDate.
  ///
  /// In zh_CN, this message translates to:
  /// **'按发行年份'**
  String get listSortReleaseDate;

  /// No description provided for @listSortTitleField.
  ///
  /// In zh_CN, this message translates to:
  /// **'按标题'**
  String get listSortTitleField;

  /// No description provided for @listSortVoteAverage.
  ///
  /// In zh_CN, this message translates to:
  /// **'按评分'**
  String get listSortVoteAverage;

  /// No description provided for @listSortAsc.
  ///
  /// In zh_CN, this message translates to:
  /// **'升序'**
  String get listSortAsc;

  /// No description provided for @listSortDesc.
  ///
  /// In zh_CN, this message translates to:
  /// **'降序'**
  String get listSortDesc;

  /// No description provided for @searchHistory.
  ///
  /// In zh_CN, this message translates to:
  /// **'搜索历史'**
  String get searchHistory;

  /// No description provided for @searchResultCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'{count}个搜索结果'**
  String searchResultCount(int count);

  /// No description provided for @searchPlaceholder.
  ///
  /// In zh_CN, this message translates to:
  /// **'搜索'**
  String get searchPlaceholder;

  /// No description provided for @personItemCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'共 {count} 个作品'**
  String personItemCount(int count);

  /// No description provided for @personJobActor.
  ///
  /// In zh_CN, this message translates to:
  /// **'演员'**
  String get personJobActor;

  /// No description provided for @personJobDirector.
  ///
  /// In zh_CN, this message translates to:
  /// **'导演'**
  String get personJobDirector;

  /// No description provided for @personJobScreenplay.
  ///
  /// In zh_CN, this message translates to:
  /// **'编剧'**
  String get personJobScreenplay;

  /// No description provided for @personJobWriter.
  ///
  /// In zh_CN, this message translates to:
  /// **'编剧'**
  String get personJobWriter;

  /// No description provided for @personJobProducer.
  ///
  /// In zh_CN, this message translates to:
  /// **'制片人'**
  String get personJobProducer;

  /// No description provided for @personAsJob.
  ///
  /// In zh_CN, this message translates to:
  /// **'作为{job}'**
  String personAsJob(Object job);

  /// No description provided for @personBiographyTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'演员简介'**
  String get personBiographyTitle;

  /// No description provided for @routeErrorMissingDetail.
  ///
  /// In zh_CN, this message translates to:
  /// **'缺少详情参数'**
  String get routeErrorMissingDetail;

  /// No description provided for @routeErrorMissingSeason.
  ///
  /// In zh_CN, this message translates to:
  /// **'缺少季详情参数'**
  String get routeErrorMissingSeason;

  /// No description provided for @routeErrorMissingPerson.
  ///
  /// In zh_CN, this message translates to:
  /// **'缺少人物详情参数'**
  String get routeErrorMissingPerson;

  /// No description provided for @routeErrorMissingDownload.
  ///
  /// In zh_CN, this message translates to:
  /// **'缺少下载详情参数'**
  String get routeErrorMissingDownload;

  /// No description provided for @connectionAppName.
  ///
  /// In zh_CN, this message translates to:
  /// **'飞牛播放器'**
  String get connectionAppName;

  /// No description provided for @connectionUserNameHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'用户名'**
  String get connectionUserNameHint;

  /// No description provided for @connectionPasswordHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'密码'**
  String get connectionPasswordHint;

  /// No description provided for @connectionRememberLogin.
  ///
  /// In zh_CN, this message translates to:
  /// **'保持登录'**
  String get connectionRememberLogin;

  /// No description provided for @connectionHttpsAccess.
  ///
  /// In zh_CN, this message translates to:
  /// **'HTTPS 安全访问'**
  String get connectionHttpsAccess;

  /// No description provided for @connectionLogin.
  ///
  /// In zh_CN, this message translates to:
  /// **'登录'**
  String get connectionLogin;

  /// No description provided for @connectionOpenDownloads.
  ///
  /// In zh_CN, this message translates to:
  /// **'查看已下载数据'**
  String get connectionOpenDownloads;

  /// No description provided for @connectionLoginHistory.
  ///
  /// In zh_CN, this message translates to:
  /// **'登录历史'**
  String get connectionLoginHistory;

  /// No description provided for @connectionClear.
  ///
  /// In zh_CN, this message translates to:
  /// **'清空'**
  String get connectionClear;

  /// No description provided for @connectionNoLoginHistory.
  ///
  /// In zh_CN, this message translates to:
  /// **'暂无登录历史'**
  String get connectionNoLoginHistory;

  /// No description provided for @connectionOperationFailedRetryLater.
  ///
  /// In zh_CN, this message translates to:
  /// **'操作失败，请稍后重试'**
  String get connectionOperationFailedRetryLater;

  /// No description provided for @connectionOperationFailedRetry.
  ///
  /// In zh_CN, this message translates to:
  /// **'操作失败，请重试'**
  String get connectionOperationFailedRetry;

  /// No description provided for @connectionServerRequired.
  ///
  /// In zh_CN, this message translates to:
  /// **'请输入服务器地址'**
  String get connectionServerRequired;

  /// No description provided for @connectionUserNameRequired.
  ///
  /// In zh_CN, this message translates to:
  /// **'请输入用户名'**
  String get connectionUserNameRequired;

  /// No description provided for @connectionPasswordRequired.
  ///
  /// In zh_CN, this message translates to:
  /// **'请输入密码'**
  String get connectionPasswordRequired;

  /// No description provided for @connectionInvalidCredential.
  ///
  /// In zh_CN, this message translates to:
  /// **'用户名或密码错误'**
  String get connectionInvalidCredential;

  /// No description provided for @connectionNetworkError.
  ///
  /// In zh_CN, this message translates to:
  /// **'网络异常，请检查后重试'**
  String get connectionNetworkError;

  /// No description provided for @connectionValidationFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'验证失败'**
  String get connectionValidationFailed;

  /// No description provided for @settingsThemeTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'主题设置'**
  String get settingsThemeTitle;

  /// No description provided for @settingsThemeSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'{title} · {subtitle}'**
  String settingsThemeSubtitle(Object title, Object subtitle);

  /// No description provided for @settingsThemeKeywords.
  ///
  /// In zh_CN, this message translates to:
  /// **'主题|配色|颜色|外观'**
  String get settingsThemeKeywords;

  /// No description provided for @settingsCustomThemeTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'自定义主题'**
  String get settingsCustomThemeTitle;

  /// No description provided for @settingsCustomThemeSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'已保存主题管理'**
  String get settingsCustomThemeSubtitle;

  /// No description provided for @settingsCustomThemeKeywords.
  ///
  /// In zh_CN, this message translates to:
  /// **'自定义主题|保存主题|主题管理'**
  String get settingsCustomThemeKeywords;

  /// No description provided for @settingsCustomRecipeTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'颜色分类控制'**
  String get settingsCustomRecipeTitle;

  /// No description provided for @settingsCustomRecipeSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'自定义主题配色编辑'**
  String get settingsCustomRecipeSubtitle;

  /// No description provided for @settingsCustomRecipeLocation.
  ///
  /// In zh_CN, this message translates to:
  /// **'设置 > 主题设置 > 当前自定义'**
  String get settingsCustomRecipeLocation;

  /// No description provided for @settingsCustomRecipeKeywords.
  ///
  /// In zh_CN, this message translates to:
  /// **'颜色分类|当前自定义|调色'**
  String get settingsCustomRecipeKeywords;

  /// No description provided for @settingsMpvTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'MPV播放器设置'**
  String get settingsMpvTitle;

  /// No description provided for @settingsMpvSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放器参数设置'**
  String get settingsMpvSubtitle;

  /// No description provided for @settingsMpvKeywords.
  ///
  /// In zh_CN, this message translates to:
  /// **'mpv|播放器|外部播放'**
  String get settingsMpvKeywords;

  /// No description provided for @settingsParallelWindowTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'并行窗口设置'**
  String get settingsParallelWindowTitle;

  /// No description provided for @settingsParallelWindowKeywords.
  ///
  /// In zh_CN, this message translates to:
  /// **'并行窗口|双屏|分屏'**
  String get settingsParallelWindowKeywords;

  /// No description provided for @settingsParallelSummaryEnabledLeft.
  ///
  /// In zh_CN, this message translates to:
  /// **'已开启 · 左侧主屏'**
  String get settingsParallelSummaryEnabledLeft;

  /// No description provided for @settingsParallelSummaryEnabledRight.
  ///
  /// In zh_CN, this message translates to:
  /// **'已开启 · 右侧主屏'**
  String get settingsParallelSummaryEnabledRight;

  /// No description provided for @settingsParallelSummaryDisabled.
  ///
  /// In zh_CN, this message translates to:
  /// **'已关闭 · 当前使用单屏模式'**
  String get settingsParallelSummaryDisabled;

  /// No description provided for @settingsDownloadTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载管理'**
  String get settingsDownloadTitle;

  /// No description provided for @settingsDownloadSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'已下载与下载中内容管理'**
  String get settingsDownloadSubtitle;

  /// No description provided for @settingsDownloadKeywords.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载|下载管理|已下载|下载中|离线视频'**
  String get settingsDownloadKeywords;

  /// No description provided for @settingsStorageTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'储存管理'**
  String get settingsStorageTitle;

  /// No description provided for @settingsStorageSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'缓存、截图、日志与应用数据'**
  String get settingsStorageSubtitle;

  /// No description provided for @settingsStorageKeywords.
  ///
  /// In zh_CN, this message translates to:
  /// **'储存管理|缓存|播放缓存|截图文件|应用数据|清理缓存'**
  String get settingsStorageKeywords;

  /// No description provided for @settingsPlayStatsTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'全局播放数据统计'**
  String get settingsPlayStatsTitle;

  /// No description provided for @settingsPlayStatsSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'本地播放统计与历史记录'**
  String get settingsPlayStatsSubtitle;

  /// No description provided for @settingsPlayStatsKeywords.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放统计|播放历史|本地统计|sqlite'**
  String get settingsPlayStatsKeywords;

  /// No description provided for @settingsOtherTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'其他'**
  String get settingsOtherTitle;

  /// No description provided for @settingsOtherSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'书签、弹幕与截图设置'**
  String get settingsOtherSubtitle;

  /// No description provided for @settingsOtherKeywords.
  ///
  /// In zh_CN, this message translates to:
  /// **'其他|辅助设置'**
  String get settingsOtherKeywords;

  /// No description provided for @settingsLogTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'日志信息'**
  String get settingsLogTitle;

  /// No description provided for @settingsLogSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'应用日志与导出'**
  String get settingsLogSubtitle;

  /// No description provided for @settingsLogKeywords.
  ///
  /// In zh_CN, this message translates to:
  /// **'日志|报错|txt|导出'**
  String get settingsLogKeywords;

  /// No description provided for @settingsBookmarkTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'书签管理'**
  String get settingsBookmarkTitle;

  /// No description provided for @settingsBookmarkSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'书签列表与定位'**
  String get settingsBookmarkSubtitle;

  /// No description provided for @settingsBookmarkKeywords.
  ///
  /// In zh_CN, this message translates to:
  /// **'书签|bookmark'**
  String get settingsBookmarkKeywords;

  /// No description provided for @settingsDanmakuTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'弹幕设置'**
  String get settingsDanmakuTitle;

  /// No description provided for @settingsDanmakuSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'默认样式与来源策略'**
  String get settingsDanmakuSubtitle;

  /// No description provided for @settingsDanmakuKeywords.
  ///
  /// In zh_CN, this message translates to:
  /// **'弹幕|danmaku'**
  String get settingsDanmakuKeywords;

  /// No description provided for @settingsScreenshotTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'截图设置'**
  String get settingsScreenshotTitle;

  /// No description provided for @settingsScreenshotSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'字幕携带和保存路径'**
  String get settingsScreenshotSubtitle;

  /// No description provided for @settingsScreenshotKeywords.
  ///
  /// In zh_CN, this message translates to:
  /// **'截图|相册目录|保存路径'**
  String get settingsScreenshotKeywords;

  /// No description provided for @settingsScreenshotIncludeSubtitlesTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'截图是否携带字幕'**
  String get settingsScreenshotIncludeSubtitlesTitle;

  /// No description provided for @settingsScreenshotIncludeSubtitlesSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'字幕携带选项'**
  String get settingsScreenshotIncludeSubtitlesSubtitle;

  /// No description provided for @settingsScreenshotIncludeSubtitlesKeywords.
  ///
  /// In zh_CN, this message translates to:
  /// **'截图|字幕|携带字幕'**
  String get settingsScreenshotIncludeSubtitlesKeywords;

  /// No description provided for @settingsScreenshotSavePathTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'截图保存路径设置'**
  String get settingsScreenshotSavePathTitle;

  /// No description provided for @settingsScreenshotSavePathSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'保存路径选项'**
  String get settingsScreenshotSavePathSubtitle;

  /// No description provided for @settingsScreenshotSavePathKeywords.
  ///
  /// In zh_CN, this message translates to:
  /// **'截图|保存路径|相册目录'**
  String get settingsScreenshotSavePathKeywords;

  /// No description provided for @settingsScreenshotCustomDirectoryTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'截图自定义目录'**
  String get settingsScreenshotCustomDirectoryTitle;

  /// No description provided for @settingsScreenshotCustomDirectorySubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'自定义目录管理'**
  String get settingsScreenshotCustomDirectorySubtitle;

  /// No description provided for @settingsScreenshotCustomDirectoryKeywords.
  ///
  /// In zh_CN, this message translates to:
  /// **'截图|自定义目录|文件夹'**
  String get settingsScreenshotCustomDirectoryKeywords;

  /// No description provided for @settingsScreenshotPreviewTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'截图预览'**
  String get settingsScreenshotPreviewTitle;

  /// No description provided for @settingsScreenshotPreviewSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'已保存截图管理'**
  String get settingsScreenshotPreviewSubtitle;

  /// No description provided for @settingsScreenshotPreviewKeywords.
  ///
  /// In zh_CN, this message translates to:
  /// **'截图|预览|删除截图|管理截图'**
  String get settingsScreenshotPreviewKeywords;

  /// No description provided for @settingsMpvQuickModeTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'MPV 快速模式'**
  String get settingsMpvQuickModeTitle;

  /// No description provided for @settingsMpvQuickModeSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'快捷预设与模式切换'**
  String get settingsMpvQuickModeSubtitle;

  /// No description provided for @settingsMpvQuickModeKeywords.
  ///
  /// In zh_CN, this message translates to:
  /// **'mpv|快速模式|高保真|极速模式'**
  String get settingsMpvQuickModeKeywords;

  /// No description provided for @settingsMpvPictureTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'MPV 画面调节'**
  String get settingsMpvPictureTitle;

  /// No description provided for @settingsMpvPictureSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'滤镜、HDR、插帧与即时调节'**
  String get settingsMpvPictureSubtitle;

  /// No description provided for @settingsMpvPictureKeywords.
  ///
  /// In zh_CN, this message translates to:
  /// **'mpv|画面|hdr|插帧|滤镜'**
  String get settingsMpvPictureKeywords;

  /// No description provided for @settingsMpvAudioTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'MPV 音频调节'**
  String get settingsMpvAudioTitle;

  /// No description provided for @settingsMpvAudioSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'EQ、限幅、低音增强与人声增强'**
  String get settingsMpvAudioSubtitle;

  /// No description provided for @settingsMpvAudioKeywords.
  ///
  /// In zh_CN, this message translates to:
  /// **'mpv|音频|eq|高保真|限幅'**
  String get settingsMpvAudioKeywords;

  /// No description provided for @settingsMpvPlaybackTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'MPV 播放与缓存'**
  String get settingsMpvPlaybackTitle;

  /// No description provided for @settingsMpvPlaybackSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'同步模式、缓存策略与缓存大小'**
  String get settingsMpvPlaybackSubtitle;

  /// No description provided for @settingsMpvPlaybackKeywords.
  ///
  /// In zh_CN, this message translates to:
  /// **'mpv|缓存|缓冲|同步'**
  String get settingsMpvPlaybackKeywords;

  /// No description provided for @settingsMpvCompatibilityTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'MPV 兼容与诊断'**
  String get settingsMpvCompatibilityTitle;

  /// No description provided for @settingsMpvCompatibilitySubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'兼容模式和播放器诊断信息'**
  String get settingsMpvCompatibilitySubtitle;

  /// No description provided for @settingsMpvCompatibilityKeywords.
  ///
  /// In zh_CN, this message translates to:
  /// **'mpv|兼容|诊断|播放信息'**
  String get settingsMpvCompatibilityKeywords;

  /// No description provided for @settingsLocationRoot.
  ///
  /// In zh_CN, this message translates to:
  /// **'设置'**
  String get settingsLocationRoot;

  /// No description provided for @settingsLocationTheme.
  ///
  /// In zh_CN, this message translates to:
  /// **'设置 > 主题设置'**
  String get settingsLocationTheme;

  /// No description provided for @settingsLocationOther.
  ///
  /// In zh_CN, this message translates to:
  /// **'设置 > 其他'**
  String get settingsLocationOther;

  /// No description provided for @settingsLocationScreenshot.
  ///
  /// In zh_CN, this message translates to:
  /// **'设置 > 其他 > 截图设置'**
  String get settingsLocationScreenshot;

  /// No description provided for @settingsLocationMpv.
  ///
  /// In zh_CN, this message translates to:
  /// **'设置 > MPV播放器设置'**
  String get settingsLocationMpv;

  /// No description provided for @settingsLocationMpvWithSection.
  ///
  /// In zh_CN, this message translates to:
  /// **'设置 > MPV播放器设置 > {section}'**
  String settingsLocationMpvWithSection(Object section);

  /// No description provided for @settingsMpvPictureSection.
  ///
  /// In zh_CN, this message translates to:
  /// **'画面调节'**
  String get settingsMpvPictureSection;

  /// No description provided for @settingsMpvAudioSection.
  ///
  /// In zh_CN, this message translates to:
  /// **'音频调节'**
  String get settingsMpvAudioSection;

  /// No description provided for @settingsMpvPlaybackSection.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放与缓存'**
  String get settingsMpvPlaybackSection;

  /// No description provided for @settingsMpvCompatibilitySection.
  ///
  /// In zh_CN, this message translates to:
  /// **'兼容与诊断'**
  String get settingsMpvCompatibilitySection;

  /// No description provided for @settingsSearchResults.
  ///
  /// In zh_CN, this message translates to:
  /// **'搜索结果'**
  String get settingsSearchResults;

  /// No description provided for @settingsSearchFrequent.
  ///
  /// In zh_CN, this message translates to:
  /// **'常用入口'**
  String get settingsSearchFrequent;

  /// No description provided for @settingsSearchHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'搜索设置项'**
  String get settingsSearchHint;

  /// No description provided for @settingsSearchEmptyResults.
  ///
  /// In zh_CN, this message translates to:
  /// **'没有找到相关设置项。'**
  String get settingsSearchEmptyResults;

  /// No description provided for @settingsSearchEmptyPrompt.
  ///
  /// In zh_CN, this message translates to:
  /// **'先输入关键字，或从常用入口开始。'**
  String get settingsSearchEmptyPrompt;

  /// No description provided for @mpvContinueEnable.
  ///
  /// In zh_CN, this message translates to:
  /// **'继续开启'**
  String get mpvContinueEnable;

  /// No description provided for @mpvGenericSettingTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'调节项'**
  String get mpvGenericSettingTitle;

  /// No description provided for @mpvPictureCategorySubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'滤镜、渲染、HDR 与插帧'**
  String get mpvPictureCategorySubtitle;

  /// No description provided for @mpvPictureCategoryDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'围绕画面观感的细项调节，适合按片源逐步细调。'**
  String get mpvPictureCategoryDescription;

  /// No description provided for @mpvAudioCategorySubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'音量、EQ、增强与声道混合'**
  String get mpvAudioCategorySubtitle;

  /// No description provided for @mpvAudioCategoryDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'音频处理、高保真模式与声道输出设置。'**
  String get mpvAudioCategoryDescription;

  /// No description provided for @mpvPlaybackCategorySubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'同步模式、缓存策略与缓存大小'**
  String get mpvPlaybackCategorySubtitle;

  /// No description provided for @mpvPlaybackCategoryDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'主要影响拖动响应、缓存强度和播放稳定性。'**
  String get mpvPlaybackCategoryDescription;

  /// No description provided for @mpvCompatibilityCategorySubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'兼容模式与诊断'**
  String get mpvCompatibilityCategorySubtitle;

  /// No description provided for @mpvCompatibilityCategoryDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'兼容性回退与播放诊断。'**
  String get mpvCompatibilityCategoryDescription;

  /// No description provided for @mpvSettingDebandTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'去色带'**
  String get mpvSettingDebandTitle;

  /// No description provided for @mpvSettingDebandSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'处理渐变断层和暗部条带。'**
  String get mpvSettingDebandSubtitle;

  /// No description provided for @mpvSettingSharpenTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'锐化'**
  String get mpvSettingSharpenTitle;

  /// No description provided for @mpvSettingSharpenSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'提升线条和边缘清晰度。'**
  String get mpvSettingSharpenSubtitle;

  /// No description provided for @mpvSettingDenoiseTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'降噪'**
  String get mpvSettingDenoiseTitle;

  /// No description provided for @mpvSettingDenoiseSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'压制噪点和颗粒感。'**
  String get mpvSettingDenoiseSubtitle;

  /// No description provided for @mpvSettingDeinterlaceTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'反交错'**
  String get mpvSettingDeinterlaceTitle;

  /// No description provided for @mpvSettingDeinterlaceSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'适配隔行扫描片源。'**
  String get mpvSettingDeinterlaceSubtitle;

  /// No description provided for @mpvSettingScaleProfileTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'缩放算法'**
  String get mpvSettingScaleProfileTitle;

  /// No description provided for @mpvSettingScaleProfileSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'控制放大和缩小时的取向。'**
  String get mpvSettingScaleProfileSubtitle;

  /// No description provided for @mpvSettingHdrModeTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'HDR 处理'**
  String get mpvSettingHdrModeTitle;

  /// No description provided for @mpvSettingHdrModeSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'调整 HDR 映射和整体亮度取向。'**
  String get mpvSettingHdrModeSubtitle;

  /// No description provided for @mpvSettingFrameInterpolationTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'插帧'**
  String get mpvSettingFrameInterpolationTitle;

  /// No description provided for @mpvSettingFrameInterpolationSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'提升运动流畅度，性能开销更高。'**
  String get mpvSettingFrameInterpolationSubtitle;

  /// No description provided for @mpvSettingVideoSyncTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'同步模式'**
  String get mpvSettingVideoSyncTitle;

  /// No description provided for @mpvSettingVideoSyncSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'控制音画同步与刷新率优先级。'**
  String get mpvSettingVideoSyncSubtitle;

  /// No description provided for @mpvSettingCacheProfileTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'缓存策略'**
  String get mpvSettingCacheProfileTitle;

  /// No description provided for @mpvSettingCacheProfileSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'按片源和网络环境切换缓存风格。'**
  String get mpvSettingCacheProfileSubtitle;

  /// No description provided for @mpvSettingCacheSizeTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'缓存大小'**
  String get mpvSettingCacheSizeTitle;

  /// No description provided for @mpvSettingCacheSizeSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'单独调整最大预读缓存上限。'**
  String get mpvSettingCacheSizeSubtitle;

  /// No description provided for @mpvSettingVolumeGainTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'音量放大'**
  String get mpvSettingVolumeGainTitle;

  /// No description provided for @mpvSettingVolumeGainSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'提高偏小声音源的输出上限。'**
  String get mpvSettingVolumeGainSubtitle;

  /// No description provided for @mpvSettingAudioHighFidelityTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'高保真模式'**
  String get mpvSettingAudioHighFidelityTitle;

  /// No description provided for @mpvSettingAudioHighFidelitySubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'优先保持干净解码输出，旁路大部分后处理。'**
  String get mpvSettingAudioHighFidelitySubtitle;

  /// No description provided for @mpvSettingDynamicRangeTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'动态范围压缩'**
  String get mpvSettingDynamicRangeTitle;

  /// No description provided for @mpvSettingDynamicRangeSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'让对白更靠前，夜间播放更稳。'**
  String get mpvSettingDynamicRangeSubtitle;

  /// No description provided for @mpvSettingAudioEqTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'EQ 均衡器'**
  String get mpvSettingAudioEqTitle;

  /// No description provided for @mpvSettingAudioEqSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'调整低频、中频和高频的听感平衡。'**
  String get mpvSettingAudioEqSubtitle;

  /// No description provided for @mpvSettingAudioLimiterTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'峰值限幅'**
  String get mpvSettingAudioLimiterTitle;

  /// No description provided for @mpvSettingAudioLimiterSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'抑制突发峰值，避免爆音。'**
  String get mpvSettingAudioLimiterSubtitle;

  /// No description provided for @mpvSettingAudioBassBoostTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'低音增强'**
  String get mpvSettingAudioBassBoostTitle;

  /// No description provided for @mpvSettingAudioBassBoostSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'增强低频氛围和下潜感。'**
  String get mpvSettingAudioBassBoostSubtitle;

  /// No description provided for @mpvSettingAudioVoiceEnhanceTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'人声增强'**
  String get mpvSettingAudioVoiceEnhanceTitle;

  /// No description provided for @mpvSettingAudioVoiceEnhanceSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'提升对白和人声清晰度。'**
  String get mpvSettingAudioVoiceEnhanceSubtitle;

  /// No description provided for @mpvSettingChannelMixTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'声道混合'**
  String get mpvSettingChannelMixTitle;

  /// No description provided for @mpvSettingChannelMixSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'控制多声道输出的下混方式。'**
  String get mpvSettingChannelMixSubtitle;

  /// No description provided for @mpvSettingCompatibilityTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'兼容模式'**
  String get mpvSettingCompatibilityTitle;

  /// No description provided for @mpvSettingCompatibilitySubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'遇到异常时优先回退到更稳妥方案。'**
  String get mpvSettingCompatibilitySubtitle;

  /// No description provided for @mpvCurrentSchemeTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前方案'**
  String get mpvCurrentSchemeTitle;

  /// No description provided for @mpvSmartRecommendationTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'智能推荐'**
  String get mpvSmartRecommendationTitle;

  /// No description provided for @mpvSmartRecommendationSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'根据当前片源的分辨率、码率、HDR 和音轨信息推荐更合适的场景预设'**
  String get mpvSmartRecommendationSubtitle;

  /// No description provided for @mpvNoRecommendationTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前没有推荐'**
  String get mpvNoRecommendationTitle;

  /// No description provided for @mpvNoRecommendationDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前片源信息还不完整，先保留手动选择。'**
  String get mpvNoRecommendationDescription;

  /// No description provided for @mpvPictureQuickPresetTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'画质快速预设'**
  String get mpvPictureQuickPresetTitle;

  /// No description provided for @mpvPictureQuickPresetSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'快速套用动画、影院、流畅等画质方案'**
  String get mpvPictureQuickPresetSubtitle;

  /// No description provided for @mpvPictureQuickPresetDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'这里只放画面相关方案，音频增强已经拆到独立的音频快速预设。'**
  String get mpvPictureQuickPresetDescription;

  /// No description provided for @mpvAudioQuickPresetTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'音频快速预设'**
  String get mpvAudioQuickPresetTitle;

  /// No description provided for @mpvAudioQuickPresetSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'高保真、EQ、低音增强、人声增强一键切换'**
  String get mpvAudioQuickPresetSubtitle;

  /// No description provided for @mpvAudioQuickPresetDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'一键切换高保真、对白增强、低频氛围和夜间压缩，不再和画质预设混在一起。'**
  String get mpvAudioQuickPresetDescription;

  /// No description provided for @mpvCustomManagementTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'自定义管理'**
  String get mpvCustomManagementTitle;

  /// No description provided for @mpvCustomManagementSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'把画质自定义、音频自定义和即时调节统一收进三级页面管理'**
  String get mpvCustomManagementSubtitle;

  /// No description provided for @mpvCustomManagementDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'首页只保留快速预设；即时调节、分类细调和保存当前预设都统一收进这里。'**
  String get mpvCustomManagementDescription;

  /// No description provided for @mpvPictureCustomTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'画质自定义'**
  String get mpvPictureCustomTitle;

  /// No description provided for @mpvPictureCustomSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'即时调节、滤镜、渲染、HDR、插帧、同步、缓存和兼容项'**
  String get mpvPictureCustomSubtitle;

  /// No description provided for @mpvPictureCustomDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'即时调节和所有画质相关细项都统一放在这里管理，保存后会生成独立画质预设。'**
  String get mpvPictureCustomDescription;

  /// No description provided for @mpvAudioCustomTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'音频自定义'**
  String get mpvAudioCustomTitle;

  /// No description provided for @mpvAudioCustomSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'高保真、音量增强、EQ、限幅、低音增强、人声增强和声道混合'**
  String get mpvAudioCustomSubtitle;

  /// No description provided for @mpvAudioCustomDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'把高保真、EQ、音量增强和所有音频后处理统一放在这里管理，保存后会生成独立音频预设。'**
  String get mpvAudioCustomDescription;

  /// No description provided for @mpvSaveCurrentPictureTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'保存当前画质'**
  String get mpvSaveCurrentPictureTitle;

  /// No description provided for @mpvSaveCurrentPictureSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'把当前即时调节和画质增强另存为独立预设'**
  String get mpvSaveCurrentPictureSubtitle;

  /// No description provided for @mpvSaveCurrentAudioTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'保存当前音频'**
  String get mpvSaveCurrentAudioTitle;

  /// No description provided for @mpvSaveCurrentAudioSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'把当前音频增强和 EQ 另存为独立预设'**
  String get mpvSaveCurrentAudioSubtitle;

  /// No description provided for @mpvInstantAdjustTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'即时调节'**
  String get mpvInstantAdjustTitle;

  /// No description provided for @mpvInstantAdjustSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'亮度、对比度、饱和度、Gamma、色相'**
  String get mpvInstantAdjustSubtitle;

  /// No description provided for @mpvSavedPicturePreset.
  ///
  /// In zh_CN, this message translates to:
  /// **'已保存画质预设'**
  String get mpvSavedPicturePreset;

  /// No description provided for @mpvSavedAudioPreset.
  ///
  /// In zh_CN, this message translates to:
  /// **'已保存音频预设'**
  String get mpvSavedAudioPreset;

  /// No description provided for @mpvCurrentCustom.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前自定义'**
  String get mpvCurrentCustom;

  /// No description provided for @mpvNotUsed.
  ///
  /// In zh_CN, this message translates to:
  /// **'未使用'**
  String get mpvNotUsed;

  /// No description provided for @mpvDefault.
  ///
  /// In zh_CN, this message translates to:
  /// **'默认'**
  String get mpvDefault;

  /// No description provided for @mpvAllDefault.
  ///
  /// In zh_CN, this message translates to:
  /// **'全部默认'**
  String get mpvAllDefault;

  /// No description provided for @mpvChangedCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'已调整 {count} 项'**
  String mpvChangedCount(int count);

  /// No description provided for @mpvSavedPresetKindPicture.
  ///
  /// In zh_CN, this message translates to:
  /// **'画质'**
  String get mpvSavedPresetKindPicture;

  /// No description provided for @mpvSavedPresetKindAudio.
  ///
  /// In zh_CN, this message translates to:
  /// **'音频'**
  String get mpvSavedPresetKindAudio;

  /// No description provided for @mpvPresetNameLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'{kind}预设名称'**
  String mpvPresetNameLabel(Object kind);

  /// No description provided for @mpvPresetDuplicateName.
  ///
  /// In zh_CN, this message translates to:
  /// **'{kind}预设名称不能重复'**
  String mpvPresetDuplicateName(Object kind);

  /// No description provided for @mpvPresetSavedMessage.
  ///
  /// In zh_CN, this message translates to:
  /// **'已保存{kind}预设：{name}'**
  String mpvPresetSavedMessage(Object kind, Object name);

  /// No description provided for @mpvPresetDefaultBaseName.
  ///
  /// In zh_CN, this message translates to:
  /// **'{kind}预设'**
  String mpvPresetDefaultBaseName(Object kind);

  /// No description provided for @mpvPresetRenameTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'重命名{kind}预设'**
  String mpvPresetRenameTitle(Object kind);

  /// No description provided for @commonRemarkOptional.
  ///
  /// In zh_CN, this message translates to:
  /// **'备注（可选）'**
  String get commonRemarkOptional;

  /// No description provided for @commonDescriptionOptional.
  ///
  /// In zh_CN, this message translates to:
  /// **'说明（可选）'**
  String get commonDescriptionOptional;

  /// No description provided for @mpvPicturePresetOffLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'默认'**
  String get mpvPicturePresetOffLabel;

  /// No description provided for @mpvPicturePresetOffDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'关闭额外画质增强，优先保证兼容性和稳定性。'**
  String get mpvPicturePresetOffDescription;

  /// No description provided for @mpvPicturePresetAnimeLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'动画清晰'**
  String get mpvPicturePresetAnimeLabel;

  /// No description provided for @mpvPicturePresetAnimeDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'通过轻微对比度和饱和度调整突出线条感，不再默认带入重滤镜。'**
  String get mpvPicturePresetAnimeDescription;

  /// No description provided for @mpvPicturePresetCinemaLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'影院柔和'**
  String get mpvPicturePresetCinemaLabel;

  /// No description provided for @mpvPicturePresetCinemaDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'用较轻的亮暗和饱和调整偏向影院观感，避免额外画面计算。'**
  String get mpvPicturePresetCinemaDescription;

  /// No description provided for @mpvPicturePresetSmoothLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'流畅优先'**
  String get mpvPicturePresetSmoothLabel;

  /// No description provided for @mpvPicturePresetSmoothDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'偏向稳定和响应的轻量流畅方案，不再默认带入插帧。'**
  String get mpvPicturePresetSmoothDescription;

  /// No description provided for @mpvAudioPresetOffLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'默认'**
  String get mpvAudioPresetOffLabel;

  /// No description provided for @mpvAudioPresetOffDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'关闭额外音频增强，保留基础播放参数。'**
  String get mpvAudioPresetOffDescription;

  /// No description provided for @mpvAudioPresetHiFiLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'原声保真'**
  String get mpvAudioPresetHiFiLabel;

  /// No description provided for @mpvAudioPresetHiFiDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'打开高保真，旁路 EQ 和增强，适合耳机和高质量片源。'**
  String get mpvAudioPresetHiFiDescription;

  /// No description provided for @mpvAudioPresetBalancedLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'通用增强'**
  String get mpvAudioPresetBalancedLabel;

  /// No description provided for @mpvAudioPresetBalancedDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'轻度提亮人声和低频，适合大多数普通剧集、综艺和日常看片。'**
  String get mpvAudioPresetBalancedDescription;

  /// No description provided for @mpvAudioPresetDialogueLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'人声清晰'**
  String get mpvAudioPresetDialogueLabel;

  /// No description provided for @mpvAudioPresetDialogueDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'抬前对白和中高频细节，适合台词偏轻的片源。'**
  String get mpvAudioPresetDialogueDescription;

  /// No description provided for @mpvAudioPresetSpeakerClearLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'外放清晰'**
  String get mpvAudioPresetSpeakerClearLabel;

  /// No description provided for @mpvAudioPresetSpeakerClearDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'针对手机和平板外放，压住爆点、把对白往前推，减少糊成一团。'**
  String get mpvAudioPresetSpeakerClearDescription;

  /// No description provided for @mpvAudioPresetCinemaBassLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'影院低频'**
  String get mpvAudioPresetCinemaBassLabel;

  /// No description provided for @mpvAudioPresetCinemaBassDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'增强低频氛围和厚度，适合动作片、配乐片和外放。'**
  String get mpvAudioPresetCinemaBassDescription;

  /// No description provided for @mpvAudioPresetHeadphoneImmersiveLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'耳机沉浸'**
  String get mpvAudioPresetHeadphoneImmersiveLabel;

  /// No description provided for @mpvAudioPresetHeadphoneImmersiveDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'保留动态感，补一点氛围和厚度，适合耳机听电影和演唱会现场。'**
  String get mpvAudioPresetHeadphoneImmersiveDescription;

  /// No description provided for @mpvAudioPresetNightLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'夜间均衡'**
  String get mpvAudioPresetNightLabel;

  /// No description provided for @mpvAudioPresetNightDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'压低爆点、抬前对白，适合深夜外放和追剧。'**
  String get mpvAudioPresetNightDescription;

  /// No description provided for @mpvScenePresetStableClearLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'省电稳定'**
  String get mpvScenePresetStableClearLabel;

  /// No description provided for @mpvScenePresetStableClearDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'优先照顾解码稳定和系统流畅度，适合 4K、HDR、HEVC 和高码率片源。'**
  String get mpvScenePresetStableClearDescription;

  /// No description provided for @mpvScenePresetBalancedMovieLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'通用观影'**
  String get mpvScenePresetBalancedMovieLabel;

  /// No description provided for @mpvScenePresetBalancedMovieDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'用轻量画质和通用增强音频组成的日常观影片方案，适合大多数普通片源。'**
  String get mpvScenePresetBalancedMovieDescription;

  /// No description provided for @mpvScenePresetAnimeDialogueLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'追番对白'**
  String get mpvScenePresetAnimeDialogueLabel;

  /// No description provided for @mpvScenePresetAnimeDialogueDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'保留动画线条感并把对白往前提，适合动画、综艺和日常追番。'**
  String get mpvScenePresetAnimeDialogueDescription;

  /// No description provided for @mpvScenePresetSpeakerClearLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'外放清晰'**
  String get mpvScenePresetSpeakerClearLabel;

  /// No description provided for @mpvScenePresetSpeakerClearDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'优先照顾手机和平板外放，把爆点压住并把对白往前推。'**
  String get mpvScenePresetSpeakerClearDescription;

  /// No description provided for @mpvScenePresetNightBingeLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'夜间追剧'**
  String get mpvScenePresetNightBingeLabel;

  /// No description provided for @mpvScenePresetNightBingeDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'偏向稳定和夜间聆听，压低爆点并减少长时间观看的刺耳感。'**
  String get mpvScenePresetNightBingeDescription;

  /// No description provided for @mpvScenePresetHeadphoneImmersiveLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'耳机沉浸'**
  String get mpvScenePresetHeadphoneImmersiveLabel;

  /// No description provided for @mpvScenePresetHeadphoneImmersiveDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'画面保持轻柔层次，耳机下保留氛围感和低频厚度。'**
  String get mpvScenePresetHeadphoneImmersiveDescription;

  /// No description provided for @mpvSceneRecommendationStableTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'推荐稳定优先'**
  String get mpvSceneRecommendationStableTitle;

  /// No description provided for @mpvSceneRecommendationStableReason.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前片源负载偏高，建议先用更稳的轻量场景，避免播放器和系统一起掉帧。'**
  String get mpvSceneRecommendationStableReason;

  /// No description provided for @mpvSceneRecommendationImmersiveTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'推荐电影沉浸'**
  String get mpvSceneRecommendationImmersiveTitle;

  /// No description provided for @mpvSceneRecommendationImmersiveReason.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前音轨更适合保留氛围感和低频厚度的电影向组合。'**
  String get mpvSceneRecommendationImmersiveReason;

  /// No description provided for @mpvSceneRecommendationSpeakerTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'推荐清晰外放'**
  String get mpvSceneRecommendationSpeakerTitle;

  /// No description provided for @mpvSceneRecommendationSpeakerReason.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前音轨偏轻，优先把对白和主体声推前，普通剧集和外放更省心。'**
  String get mpvSceneRecommendationSpeakerReason;

  /// No description provided for @mpvSceneRecommendationBalancedTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'推荐通用观影'**
  String get mpvSceneRecommendationBalancedTitle;

  /// No description provided for @mpvSceneRecommendationBalancedReason.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前片源负载正常，先用平衡一些的画质和音频组合最稳妥。'**
  String get mpvSceneRecommendationBalancedReason;

  /// No description provided for @mpvVideoAdjustGenericTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'画面参数'**
  String get mpvVideoAdjustGenericTitle;

  /// No description provided for @mpvVideoAdjustBrightnessTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'亮度'**
  String get mpvVideoAdjustBrightnessTitle;

  /// No description provided for @mpvVideoAdjustBrightnessSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'提亮暗场或压暗过曝画面。'**
  String get mpvVideoAdjustBrightnessSubtitle;

  /// No description provided for @mpvVideoAdjustContrastTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'对比度'**
  String get mpvVideoAdjustContrastTitle;

  /// No description provided for @mpvVideoAdjustContrastSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'拉开明暗层次，数值过高会让高光和阴影更硬。'**
  String get mpvVideoAdjustContrastSubtitle;

  /// No description provided for @mpvVideoAdjustSaturationTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'饱和度'**
  String get mpvVideoAdjustSaturationTitle;

  /// No description provided for @mpvVideoAdjustSaturationSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'控制整体颜色浓度。'**
  String get mpvVideoAdjustSaturationSubtitle;

  /// No description provided for @mpvVideoAdjustGammaTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'Gamma'**
  String get mpvVideoAdjustGammaTitle;

  /// No description provided for @mpvVideoAdjustGammaSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'偏向中间调修正，适合微调灰雾感和暗部层次。'**
  String get mpvVideoAdjustGammaSubtitle;

  /// No description provided for @mpvVideoAdjustHueTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'色相'**
  String get mpvVideoAdjustHueTitle;

  /// No description provided for @mpvVideoAdjustHueSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'整体色调偏移，建议小幅调整，用来修正偏色片源。'**
  String get mpvVideoAdjustHueSubtitle;

  /// No description provided for @mpvVideoAdjustStatusTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'画面参数'**
  String get mpvVideoAdjustStatusTitle;

  /// No description provided for @mpvVideoAdjustDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'这些值会直接写入 mpv 的亮度、对比度、饱和度、Gamma 和色相参数，并会一起保存到画质预设中。'**
  String get mpvVideoAdjustDescription;

  /// No description provided for @mpvVideoAdjustDrawerDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'这些参数直接对应 mpv 原生视频均衡项，适合播放中微调，不会像 HDR 或插帧那样频繁触发重载。'**
  String get mpvVideoAdjustDrawerDescription;

  /// No description provided for @mpvVideoAdjustAllDefaultSummary.
  ///
  /// In zh_CN, this message translates to:
  /// **'亮度、对比度、饱和度、Gamma 和色相都保持在默认值。'**
  String get mpvVideoAdjustAllDefaultSummary;

  /// No description provided for @mpvOptionOff.
  ///
  /// In zh_CN, this message translates to:
  /// **'关闭'**
  String get mpvOptionOff;

  /// No description provided for @mpvOptionOn.
  ///
  /// In zh_CN, this message translates to:
  /// **'开启'**
  String get mpvOptionOn;

  /// No description provided for @mpvOptionAuto.
  ///
  /// In zh_CN, this message translates to:
  /// **'自动'**
  String get mpvOptionAuto;

  /// No description provided for @mpvOptionLow.
  ///
  /// In zh_CN, this message translates to:
  /// **'轻度'**
  String get mpvOptionLow;

  /// No description provided for @mpvOptionMedium.
  ///
  /// In zh_CN, this message translates to:
  /// **'标准'**
  String get mpvOptionMedium;

  /// No description provided for @mpvOptionStrong.
  ///
  /// In zh_CN, this message translates to:
  /// **'标准'**
  String get mpvOptionStrong;

  /// No description provided for @mpvOptionFast.
  ///
  /// In zh_CN, this message translates to:
  /// **'快速'**
  String get mpvOptionFast;

  /// No description provided for @mpvOptionBalanced.
  ///
  /// In zh_CN, this message translates to:
  /// **'标准'**
  String get mpvOptionBalanced;

  /// No description provided for @mpvOptionQuality.
  ///
  /// In zh_CN, this message translates to:
  /// **'高质量'**
  String get mpvOptionQuality;

  /// No description provided for @mpvOptionForce.
  ///
  /// In zh_CN, this message translates to:
  /// **'强制开启'**
  String get mpvOptionForce;

  /// No description provided for @mpvOptionSdrMap.
  ///
  /// In zh_CN, this message translates to:
  /// **'SDR 映射'**
  String get mpvOptionSdrMap;

  /// No description provided for @mpvOptionConservative.
  ///
  /// In zh_CN, this message translates to:
  /// **'保守映射'**
  String get mpvOptionConservative;

  /// No description provided for @mpvOptionEnhanced.
  ///
  /// In zh_CN, this message translates to:
  /// **'增强映射'**
  String get mpvOptionEnhanced;

  /// No description provided for @mpvOptionAudio.
  ///
  /// In zh_CN, this message translates to:
  /// **'音频优先'**
  String get mpvOptionAudio;

  /// No description provided for @mpvOptionDisplay.
  ///
  /// In zh_CN, this message translates to:
  /// **'显示优先'**
  String get mpvOptionDisplay;

  /// No description provided for @mpvOptionSmooth.
  ///
  /// In zh_CN, this message translates to:
  /// **'平滑同步'**
  String get mpvOptionSmooth;

  /// No description provided for @mpvOptionDefault.
  ///
  /// In zh_CN, this message translates to:
  /// **'智能分配'**
  String get mpvOptionDefault;

  /// No description provided for @mpvOptionLowLatency.
  ///
  /// In zh_CN, this message translates to:
  /// **'极速响应'**
  String get mpvOptionLowLatency;

  /// No description provided for @mpvOptionStable.
  ///
  /// In zh_CN, this message translates to:
  /// **'稳定缓冲'**
  String get mpvOptionStable;

  /// No description provided for @mpvOptionNetwork.
  ///
  /// In zh_CN, this message translates to:
  /// **'网盘 / STRM / NAS'**
  String get mpvOptionNetwork;

  /// No description provided for @mpvOptionLight.
  ///
  /// In zh_CN, this message translates to:
  /// **'轻度'**
  String get mpvOptionLight;

  /// No description provided for @mpvOptionSoft.
  ///
  /// In zh_CN, this message translates to:
  /// **'柔和'**
  String get mpvOptionSoft;

  /// No description provided for @mpvOptionClarity.
  ///
  /// In zh_CN, this message translates to:
  /// **'清晰'**
  String get mpvOptionClarity;

  /// No description provided for @mpvOptionCinema.
  ///
  /// In zh_CN, this message translates to:
  /// **'影院'**
  String get mpvOptionCinema;

  /// No description provided for @mpvOptionCustom.
  ///
  /// In zh_CN, this message translates to:
  /// **'高级自定义'**
  String get mpvOptionCustom;

  /// No description provided for @mpvOptionStereo.
  ///
  /// In zh_CN, this message translates to:
  /// **'立体声优先'**
  String get mpvOptionStereo;

  /// No description provided for @mpvOptionSurround.
  ///
  /// In zh_CN, this message translates to:
  /// **'环绕优先'**
  String get mpvOptionSurround;

  /// No description provided for @mpvOptionSoftwareFallback.
  ///
  /// In zh_CN, this message translates to:
  /// **'软件优先'**
  String get mpvOptionSoftwareFallback;

  /// No description provided for @commonOk.
  ///
  /// In zh_CN, this message translates to:
  /// **'知道了'**
  String get commonOk;

  /// No description provided for @commonEnter.
  ///
  /// In zh_CN, this message translates to:
  /// **'进入'**
  String get commonEnter;

  /// No description provided for @commonView.
  ///
  /// In zh_CN, this message translates to:
  /// **'查看'**
  String get commonView;

  /// No description provided for @commonRename.
  ///
  /// In zh_CN, this message translates to:
  /// **'重命名'**
  String get commonRename;

  /// No description provided for @commonDelete.
  ///
  /// In zh_CN, this message translates to:
  /// **'删除'**
  String get commonDelete;

  /// No description provided for @commonClear.
  ///
  /// In zh_CN, this message translates to:
  /// **'清空'**
  String get commonClear;

  /// No description provided for @commonJump.
  ///
  /// In zh_CN, this message translates to:
  /// **'跳转'**
  String get commonJump;

  /// No description provided for @playerAbLoopPoint.
  ///
  /// In zh_CN, this message translates to:
  /// **'A点'**
  String get playerAbLoopPoint;

  /// No description provided for @playerAbLoopUnavailable.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前时长不足，无法设置 A-B 循环'**
  String get playerAbLoopUnavailable;

  /// No description provided for @playerAbLoopPointSet.
  ///
  /// In zh_CN, this message translates to:
  /// **'A 点已设置到 {position}'**
  String playerAbLoopPointSet(Object position);

  /// No description provided for @playerAbLoopMinimumSpan.
  ///
  /// In zh_CN, this message translates to:
  /// **'A-B 间隔至少需要 0.8 秒'**
  String get playerAbLoopMinimumSpan;

  /// No description provided for @playerAbLoopSet.
  ///
  /// In zh_CN, this message translates to:
  /// **'A-B 循环已设置 {start} - {end}'**
  String playerAbLoopSet(Object start, Object end);

  /// No description provided for @playerAbLoopCleared.
  ///
  /// In zh_CN, this message translates to:
  /// **'A-B 循环已清除'**
  String get playerAbLoopCleared;

  /// No description provided for @playerBookmarkNone.
  ///
  /// In zh_CN, this message translates to:
  /// **'无书签'**
  String get playerBookmarkNone;

  /// No description provided for @playerBookmarkCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'{count} 个'**
  String playerBookmarkCount(int count);

  /// No description provided for @playerBookmarkEmptySummary.
  ///
  /// In zh_CN, this message translates to:
  /// **'为当前片段记录关键时间点，之后可以快速跳回。'**
  String get playerBookmarkEmptySummary;

  /// No description provided for @playerBookmarkRecentSummary.
  ///
  /// In zh_CN, this message translates to:
  /// **'最近书签 {position}，共 {count} 个。'**
  String playerBookmarkRecentSummary(Object position, int count);

  /// No description provided for @playerBookmarkNoteDialogTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'添加书签备注'**
  String get playerBookmarkNoteDialogTitle;

  /// No description provided for @playerBookmarkAdded.
  ///
  /// In zh_CN, this message translates to:
  /// **'已添加书签 {position}'**
  String playerBookmarkAdded(Object position);

  /// No description provided for @playerBookmarkDeleted.
  ///
  /// In zh_CN, this message translates to:
  /// **'已删除书签'**
  String get playerBookmarkDeleted;

  /// No description provided for @playerBookmarkCleared.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前片段书签已清空'**
  String get playerBookmarkCleared;

  /// No description provided for @playerBookmarkJumped.
  ///
  /// In zh_CN, this message translates to:
  /// **'已跳转到 {position}'**
  String playerBookmarkJumped(Object position);

  /// No description provided for @playerBookmarkTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'书签'**
  String get playerBookmarkTitle;

  /// No description provided for @playerBookmarkAddCurrent.
  ///
  /// In zh_CN, this message translates to:
  /// **'添加当前'**
  String get playerBookmarkAddCurrent;

  /// No description provided for @playerBookmarkCurrentSegment.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前片段'**
  String get playerBookmarkCurrentSegment;

  /// No description provided for @playerBookmarkEmptyPrompt.
  ///
  /// In zh_CN, this message translates to:
  /// **'还没有书签，点击右上角“添加当前”即可记录当前时间点。'**
  String get playerBookmarkEmptyPrompt;

  /// No description provided for @playerBookmarkCreatedAt.
  ///
  /// In zh_CN, this message translates to:
  /// **'创建于 {time}'**
  String playerBookmarkCreatedAt(Object time);

  /// No description provided for @playerEpisodeList.
  ///
  /// In zh_CN, this message translates to:
  /// **'剧集列表'**
  String get playerEpisodeList;

  /// No description provided for @playerEpisodeSpecialSeason.
  ///
  /// In zh_CN, this message translates to:
  /// **'特别篇'**
  String get playerEpisodeSpecialSeason;

  /// No description provided for @playerEpisodeSeasonTemplate.
  ///
  /// In zh_CN, this message translates to:
  /// **'第{season}季'**
  String playerEpisodeSeasonTemplate(Object season);

  /// No description provided for @playerEpisodePlaying.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放中..'**
  String get playerEpisodePlaying;

  /// No description provided for @playerEpisodeWatched.
  ///
  /// In zh_CN, this message translates to:
  /// **'已观看'**
  String get playerEpisodeWatched;

  /// No description provided for @playerEpisodeWatchedPercent.
  ///
  /// In zh_CN, this message translates to:
  /// **'已观看{percent}%'**
  String playerEpisodeWatchedPercent(Object percent);

  /// No description provided for @playerEpisodeUnwatched.
  ///
  /// In zh_CN, this message translates to:
  /// **'未观看'**
  String get playerEpisodeUnwatched;

  /// No description provided for @playerEpisodePickerTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'选集'**
  String get playerEpisodePickerTitle;

  /// No description provided for @playerEpisodeLast.
  ///
  /// In zh_CN, this message translates to:
  /// **'已经是最后一集了'**
  String get playerEpisodeLast;

  /// No description provided for @playerEpisodeFirst.
  ///
  /// In zh_CN, this message translates to:
  /// **'已经是第一集了'**
  String get playerEpisodeFirst;

  /// No description provided for @playerEpisodeViewSaveFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'选集视图保存失败'**
  String get playerEpisodeViewSaveFailed;

  /// No description provided for @playerEpisodeNoAvailableList.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前片源没有可用选集列表'**
  String get playerEpisodeNoAvailableList;

  /// No description provided for @playerEpisodeLoadListFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'加载选集列表失败: {error}'**
  String playerEpisodeLoadListFailed(Object error);

  /// No description provided for @playerEpisodeLoadSeasonFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'加载该季选集失败: {error}'**
  String playerEpisodeLoadSeasonFailed(Object error);

  /// No description provided for @playerEpisodeNumberLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'第 {episode} 集'**
  String playerEpisodeNumberLabel(int episode);

  /// No description provided for @playerEpisodePreparingPlayback.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在准备播放...'**
  String get playerEpisodePreparingPlayback;

  /// No description provided for @playerEpisodeSwitchingTo.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在切换到 {episode}...'**
  String playerEpisodeSwitchingTo(Object episode);

  /// No description provided for @playerSubtitleLanguageEnglish.
  ///
  /// In zh_CN, this message translates to:
  /// **'英文'**
  String get playerSubtitleLanguageEnglish;

  /// No description provided for @playerSubtitleLanguageChinese.
  ///
  /// In zh_CN, this message translates to:
  /// **'中文'**
  String get playerSubtitleLanguageChinese;

  /// No description provided for @playerSubtitleClosing.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在关闭字幕...'**
  String get playerSubtitleClosing;

  /// No description provided for @playerSubtitleSwitching.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在切换到{title}{suffix} 字幕...'**
  String playerSubtitleSwitching(Object title, Object suffix);

  /// No description provided for @playerSubtitleClosingPleaseWait.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在为您关闭字幕，请稍等...'**
  String get playerSubtitleClosingPleaseWait;

  /// No description provided for @playerSubtitleSwitchingPleaseWait.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在为您切换至{title}{suffix} 字幕，请稍等...'**
  String playerSubtitleSwitchingPleaseWait(Object title, Object suffix);

  /// No description provided for @playerSubtitleUnknownTrack.
  ///
  /// In zh_CN, this message translates to:
  /// **'未知字幕'**
  String get playerSubtitleUnknownTrack;

  /// No description provided for @playerSubtitleExternal.
  ///
  /// In zh_CN, this message translates to:
  /// **'外挂'**
  String get playerSubtitleExternal;

  /// No description provided for @playerSubtitleFileFallbackApplied.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前字幕文件不可直接获取，已切换兼容方案'**
  String get playerSubtitleFileFallbackApplied;

  /// No description provided for @playerSubtitleLoadFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'字幕加载失败: {error}'**
  String playerSubtitleLoadFailed(Object error);

  /// No description provided for @playerAudioUnknownTrack.
  ///
  /// In zh_CN, this message translates to:
  /// **'未知音轨'**
  String get playerAudioUnknownTrack;

  /// No description provided for @playerQualityOriginal.
  ///
  /// In zh_CN, this message translates to:
  /// **'原画'**
  String get playerQualityOriginal;

  /// No description provided for @playerQualityGeneric.
  ///
  /// In zh_CN, this message translates to:
  /// **'清晰度'**
  String get playerQualityGeneric;

  /// No description provided for @playerLoadingPreparingEnvironment.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在准备播放环境...'**
  String get playerLoadingPreparingEnvironment;

  /// No description provided for @playerLoadingInitializingPlayer.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在初始化播放器...'**
  String get playerLoadingInitializingPlayer;

  /// No description provided for @playerLoadingPreparingSource.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在准备播放源...'**
  String get playerLoadingPreparingSource;

  /// No description provided for @playerLoadingBuffering.
  ///
  /// In zh_CN, this message translates to:
  /// **'视频缓冲中...'**
  String get playerLoadingBuffering;

  /// No description provided for @playerLoadingSeeking.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在定位播放进度...'**
  String get playerLoadingSeeking;

  /// No description provided for @playerLoadingOpeningSource.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在打开播放源...'**
  String get playerLoadingOpeningSource;

  /// No description provided for @playerLoadingPreparingVideo.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在准备画面...'**
  String get playerLoadingPreparingVideo;

  /// No description provided for @playerLoadingVideo.
  ///
  /// In zh_CN, this message translates to:
  /// **'视频加载中...'**
  String get playerLoadingVideo;

  /// No description provided for @mpvNoSavedPicturePresetTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'暂无已保存画质预设'**
  String get mpvNoSavedPicturePresetTitle;

  /// No description provided for @mpvNoSavedPicturePresetContent.
  ///
  /// In zh_CN, this message translates to:
  /// **'可在“画质自定义”中保存预设。'**
  String get mpvNoSavedPicturePresetContent;

  /// No description provided for @mpvNoSavedAudioPresetTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'暂无已保存音频预设'**
  String get mpvNoSavedAudioPresetTitle;

  /// No description provided for @mpvNoSavedAudioPresetContent.
  ///
  /// In zh_CN, this message translates to:
  /// **'可在“音频自定义”中保存预设。'**
  String get mpvNoSavedAudioPresetContent;

  /// No description provided for @mpvPresetManagementStatus.
  ///
  /// In zh_CN, this message translates to:
  /// **'预设管理'**
  String get mpvPresetManagementStatus;

  /// No description provided for @mpvPresetManagementSummary.
  ///
  /// In zh_CN, this message translates to:
  /// **'画质自定义、音频自定义与已保存预设管理。'**
  String get mpvPresetManagementSummary;

  /// No description provided for @mpvSavedPresetDefaultDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'已保存的独立预设，可随时再次应用。'**
  String get mpvSavedPresetDefaultDescription;

  /// No description provided for @mpvPresetApplied.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前已应用'**
  String get mpvPresetApplied;

  /// No description provided for @mpvTapToApply.
  ///
  /// In zh_CN, this message translates to:
  /// **'点按应用'**
  String get mpvTapToApply;

  /// No description provided for @mpvVideoFiltersCategoryTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'视频滤镜'**
  String get mpvVideoFiltersCategoryTitle;

  /// No description provided for @mpvVideoFiltersCategorySubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'去色带、锐化、降噪、反交错、缩放算法'**
  String get mpvVideoFiltersCategorySubtitle;

  /// No description provided for @mpvVideoFiltersCategoryDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'主要针对画面净化、边缘锐度和缩放观感。'**
  String get mpvVideoFiltersCategoryDescription;

  /// No description provided for @mpvPlayerDiagnosticsTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放器诊断信息'**
  String get mpvPlayerDiagnosticsTitle;

  /// No description provided for @mpvPlayerDiagnosticsSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'查看当前 codec、输出、色彩和源信息'**
  String get mpvPlayerDiagnosticsSubtitle;

  /// No description provided for @mpvCacheSettingStatusTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'缓存设定'**
  String get mpvCacheSettingStatusTitle;

  /// No description provided for @mpvCacheSettingAutoDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前由缓存策略自动分配上限。关闭自动后，可直接拖动滑杆控制缓存百分比。'**
  String get mpvCacheSettingAutoDescription;

  /// No description provided for @mpvCacheSettingManualDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'缓存百分比越高，越有利于高码率和不稳定网络，但也会占用更多内存和存储。'**
  String get mpvCacheSettingManualDescription;

  /// No description provided for @mpvCacheAutoSwitchTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'自动缓存'**
  String get mpvCacheAutoSwitchTitle;

  /// No description provided for @mpvCacheAutoSwitchAutoSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前由缓存策略自动分配缓冲上限'**
  String get mpvCacheAutoSwitchAutoSubtitle;

  /// No description provided for @mpvCacheAutoSwitchManualSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'关闭后可手动指定缓存百分比'**
  String get mpvCacheAutoSwitchManualSubtitle;

  /// No description provided for @mpvCacheSliderTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'滑动设定'**
  String get mpvCacheSliderTitle;

  /// No description provided for @mpvCacheSliderSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'拖动滑杆调整缓存百分比，修改后会立即应用到当前播放器。'**
  String get mpvCacheSliderSubtitle;

  /// No description provided for @mpvCachePercentSettingLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'缓存设定：{value}'**
  String mpvCachePercentSettingLabel(Object value);

  /// No description provided for @mpvCacheHelpDefaultContent.
  ///
  /// In zh_CN, this message translates to:
  /// **'自动档。播放器会根据片源类型决定更合适的缓冲强度，本地文件更偏常规，较重的网络片源会自动偏向更稳的缓冲。'**
  String get mpvCacheHelpDefaultContent;

  /// No description provided for @mpvCacheHelpLowLatencyContent.
  ///
  /// In zh_CN, this message translates to:
  /// **'预读最轻，拖动、切换和回填最快，但抗抖动最弱。更适合本地视频，或者局域网很稳时追求跟手感。'**
  String get mpvCacheHelpLowLatencyContent;

  /// No description provided for @mpvCacheHelpStableContent.
  ///
  /// In zh_CN, this message translates to:
  /// **'中等偏重缓冲，优先减少抖动导致的卡顿。拖动响应会比极速慢一点，但更适合大多数 NAS、网盘和 STRM 观看。'**
  String get mpvCacheHelpStableContent;

  /// No description provided for @mpvCacheHelpNetworkContent.
  ///
  /// In zh_CN, this message translates to:
  /// **'最重的一档，给高码率网盘、STRM 和 NAS 片源更多预读空间。起播和拖动后的回填更重，但最抗波动。'**
  String get mpvCacheHelpNetworkContent;

  /// No description provided for @mpvCacheHelpGenericContent.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前选项用于控制预读力度和缓冲风格。'**
  String get mpvCacheHelpGenericContent;

  /// No description provided for @mpvCacheHelpDefaultExtra.
  ///
  /// In zh_CN, this message translates to:
  /// **'适合：不想自己判断时直接用。'**
  String get mpvCacheHelpDefaultExtra;

  /// No description provided for @mpvCacheHelpLowLatencyExtra.
  ///
  /// In zh_CN, this message translates to:
  /// **'适合：本地硬盘视频、局域网很稳时的 NAS。'**
  String get mpvCacheHelpLowLatencyExtra;

  /// No description provided for @mpvCacheHelpStableExtra.
  ///
  /// In zh_CN, this message translates to:
  /// **'适合：大多数 NAS、网盘和普通 STRM。'**
  String get mpvCacheHelpStableExtra;

  /// No description provided for @mpvCacheHelpNetworkExtra.
  ///
  /// In zh_CN, this message translates to:
  /// **'适合：高码率、大体积、跨网络访问的片源。'**
  String get mpvCacheHelpNetworkExtra;

  /// No description provided for @mpvPerformanceWarningTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'性能提醒'**
  String get mpvPerformanceWarningTitle;

  /// No description provided for @mpvPerformanceWarningDebandMedium.
  ///
  /// In zh_CN, this message translates to:
  /// **'中档去色带会增加额外画面处理开销，部分设备可能出现掉帧、发热或系统卡顿。'**
  String get mpvPerformanceWarningDebandMedium;

  /// No description provided for @mpvPerformanceWarningSharpen.
  ///
  /// In zh_CN, this message translates to:
  /// **'锐化会增加滤镜计算量，片源较重或设备较弱时可能导致播放掉帧和界面不流畅。'**
  String get mpvPerformanceWarningSharpen;

  /// No description provided for @mpvPerformanceWarningDenoise.
  ///
  /// In zh_CN, this message translates to:
  /// **'降噪属于较重的视频滤镜，移动设备上很容易带来明显掉帧、发热甚至系统卡顿。'**
  String get mpvPerformanceWarningDenoise;

  /// No description provided for @mpvPerformanceWarningDeinterlaceForce.
  ///
  /// In zh_CN, this message translates to:
  /// **'强制反交错会让所有片源都走额外处理链路，普通逐行片源通常没有必要，且可能拖慢播放。'**
  String get mpvPerformanceWarningDeinterlaceForce;

  /// No description provided for @mpvPerformanceWarningScaleQuality.
  ///
  /// In zh_CN, this message translates to:
  /// **'高质量缩放会增加 GPU 和渲染压力，高分辨率或高码率片源上更容易出现掉帧。'**
  String get mpvPerformanceWarningScaleQuality;

  /// No description provided for @mpvPerformanceWarningHdr.
  ///
  /// In zh_CN, this message translates to:
  /// **'这个 HDR 模式会增加色调映射压力，HDR、10-bit 或高分辨率片源上可能导致明显卡顿。'**
  String get mpvPerformanceWarningHdr;

  /// No description provided for @mpvPerformanceWarningFrameInterpolation.
  ///
  /// In zh_CN, this message translates to:
  /// **'插帧是最容易拖慢播放和系统流畅度的选项之一，开启后可能出现视频掉帧、UI 掉帧和系统卡顿。'**
  String get mpvPerformanceWarningFrameInterpolation;

  /// No description provided for @mpvPerformanceWarningVideoSyncSmooth.
  ///
  /// In zh_CN, this message translates to:
  /// **'平滑同步会更积极地贴合屏幕刷新率，部分设备上会增加合成与同步压力。'**
  String get mpvPerformanceWarningVideoSyncSmooth;

  /// No description provided for @mpvPerformanceWarningCacheNetwork.
  ///
  /// In zh_CN, this message translates to:
  /// **'网络重缓存会占用更多内存，并让拖动回填更重，只建议在高码率远程片源上使用。'**
  String get mpvPerformanceWarningCacheNetwork;

  /// No description provided for @mpvPerformanceWarningCacheSize.
  ///
  /// In zh_CN, this message translates to:
  /// **'较大的缓冲会占用更多内存，并让起播、拖动后的回填更重；低内存设备上可能影响系统流畅度。'**
  String get mpvPerformanceWarningCacheSize;

  /// No description provided for @mpvPerformanceWarningGeneric.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前选项可能增加播放器负载，请根据设备性能谨慎开启。'**
  String get mpvPerformanceWarningGeneric;

  /// No description provided for @mpvAudioEqAdvancedTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'高级频段调整'**
  String get mpvAudioEqAdvancedTitle;

  /// No description provided for @mpvAudioEqAdvancedSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'进入上下滑动频谱页，自定义每个频段并保存多套预设。'**
  String get mpvAudioEqAdvancedSubtitle;

  /// No description provided for @mpvAudioEqAdvancedHeader.
  ///
  /// In zh_CN, this message translates to:
  /// **'高级均衡'**
  String get mpvAudioEqAdvancedHeader;

  /// No description provided for @mpvCurrentlyUsed.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前使用'**
  String get mpvCurrentlyUsed;

  /// No description provided for @commonReset.
  ///
  /// In zh_CN, this message translates to:
  /// **'重置'**
  String get commonReset;

  /// No description provided for @commonRestoreDefault.
  ///
  /// In zh_CN, this message translates to:
  /// **'恢复默认'**
  String get commonRestoreDefault;

  /// No description provided for @playerQualitySwitching.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在为您切换至 {quality}{suffix} 画质，请稍等...'**
  String playerQualitySwitching(Object quality, Object suffix);

  /// No description provided for @playerQualitySwitchFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'切换清晰度失败: {error}'**
  String playerQualitySwitchFailed(Object error);

  /// No description provided for @playerQualityNoAvailableOptions.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前没有可切换清晰度'**
  String get playerQualityNoAvailableOptions;

  /// No description provided for @playerQualitySheetTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'清晰度'**
  String get playerQualitySheetTitle;

  /// No description provided for @playerQualitySheetSection.
  ///
  /// In zh_CN, this message translates to:
  /// **'清晰度列表'**
  String get playerQualitySheetSection;

  /// No description provided for @playerQualityRecommendedExpired.
  ///
  /// In zh_CN, this message translates to:
  /// **'推荐清晰度已失效'**
  String get playerQualityRecommendedExpired;

  /// No description provided for @playerQualityDownloaded.
  ///
  /// In zh_CN, this message translates to:
  /// **'已下载'**
  String get playerQualityDownloaded;

  /// No description provided for @playerWeakNetworkSuggestionTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'网络较慢，建议切换到 {quality}'**
  String playerWeakNetworkSuggestionTitle(Object quality);

  /// No description provided for @playerWeakNetworkSwitching.
  ///
  /// In zh_CN, this message translates to:
  /// **'网络较慢，正在切换到 {quality}，请稍候...'**
  String playerWeakNetworkSwitching(Object quality);

  /// No description provided for @playerAutoFilterFallbackApplied.
  ///
  /// In zh_CN, this message translates to:
  /// **'检测到帧率不稳定，已自动关闭滤镜'**
  String get playerAutoFilterFallbackApplied;

  /// No description provided for @playerAdvancedSettingsTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'高级设置'**
  String get playerAdvancedSettingsTitle;

  /// No description provided for @playerDecoderTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'解码方式'**
  String get playerDecoderTitle;

  /// No description provided for @playerDecoderSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'切换当前播放器使用的解码方式'**
  String get playerDecoderSubtitle;

  /// No description provided for @playerCacheSettingsTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'缓存设置'**
  String get playerCacheSettingsTitle;

  /// No description provided for @playerCacheSettingsSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'直接按百分比调节播放器缓存策略强度。'**
  String get playerCacheSettingsSubtitle;

  /// No description provided for @playerMonitorTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放监测'**
  String get playerMonitorTitle;

  /// No description provided for @playerMonitorSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'设置左上角悬浮信息显示的性能占用和实时帧率'**
  String get playerMonitorSubtitle;

  /// No description provided for @playerExtremePlaybackTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'极限播放'**
  String get playerExtremePlaybackTitle;

  /// No description provided for @playerExtremePlaybackEnabledSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'边下边播已开启，退出播放器后会清理本次播放缓存。切换时会重新加载当前播放源。'**
  String get playerExtremePlaybackEnabledSubtitle;

  /// No description provided for @playerExtremePlaybackDisabledSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'边下边播开启后，退出播放器会自动删除已下载缓存，但会增加内存和存储空间消耗。'**
  String get playerExtremePlaybackDisabledSubtitle;

  /// No description provided for @playerVideoInfoTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'视频信息'**
  String get playerVideoInfoTitle;

  /// No description provided for @playerVideoInfoSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'查看当前播放链路、渲染输出和片源信息'**
  String get playerVideoInfoSubtitle;

  /// No description provided for @playerMonitorStatusTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放监控'**
  String get playerMonitorStatusTitle;

  /// No description provided for @playerMonitorStatusDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'显示在左上角，可拖动并记住位置。GPU 占用取决于设备是否开放系统节点。'**
  String get playerMonitorStatusDescription;

  /// No description provided for @playerPerformanceMonitorTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'性能监控'**
  String get playerPerformanceMonitorTitle;

  /// No description provided for @playerPerformanceMonitorSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'显示 CPU / GPU 占用百分比'**
  String get playerPerformanceMonitorSubtitle;

  /// No description provided for @playerFpsMonitorTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'实时帧率'**
  String get playerFpsMonitorTitle;

  /// No description provided for @playerFpsMonitorSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'显示当前视频输出 FPS，默认关闭'**
  String get playerFpsMonitorSubtitle;

  /// No description provided for @playerHardwareDecoderTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'硬件解码'**
  String get playerHardwareDecoderTitle;

  /// No description provided for @playerHardwareDecoderSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'性能高，优先选择'**
  String get playerHardwareDecoderSubtitle;

  /// No description provided for @playerSoftwareDecoderTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'软件解码'**
  String get playerSoftwareDecoderTitle;

  /// No description provided for @playerSoftwareDecoderSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'兼容性更高，适合硬解异常时切换'**
  String get playerSoftwareDecoderSubtitle;

  /// No description provided for @playerDecoderSwitching.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在切换为 {mode}，请稍等...'**
  String playerDecoderSwitching(Object mode);

  /// No description provided for @playerMonitorPartiallyEnabled.
  ///
  /// In zh_CN, this message translates to:
  /// **'部分开启'**
  String get playerMonitorPartiallyEnabled;

  /// No description provided for @playerMonitorOff.
  ///
  /// In zh_CN, this message translates to:
  /// **'已关闭'**
  String get playerMonitorOff;

  /// No description provided for @playerAspectFit.
  ///
  /// In zh_CN, this message translates to:
  /// **'适应'**
  String get playerAspectFit;

  /// No description provided for @playerAspectFill.
  ///
  /// In zh_CN, this message translates to:
  /// **'填充'**
  String get playerAspectFill;

  /// No description provided for @playerAspectRatioTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'画面比例'**
  String get playerAspectRatioTitle;

  /// No description provided for @playerPreparingPlayback.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在准备播放'**
  String get playerPreparingPlayback;

  /// No description provided for @playerRefreshingPlaybackSession.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在刷新播放会话...'**
  String get playerRefreshingPlaybackSession;

  /// No description provided for @playerPlaybackSessionExpiredRecovering.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放会话已过期，正在恢复播放...'**
  String get playerPlaybackSessionExpiredRecovering;

  /// No description provided for @playerRefreshPlaybackSessionFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'刷新播放会话失败'**
  String get playerRefreshPlaybackSessionFailed;

  /// No description provided for @playerRecoverPlaybackSessionFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'恢复播放会话失败'**
  String get playerRecoverPlaybackSessionFailed;

  /// No description provided for @playerGenericError.
  ///
  /// In zh_CN, this message translates to:
  /// **'{title}: {error}'**
  String playerGenericError(Object title, Object error);

  /// No description provided for @playerIntroSkipped.
  ///
  /// In zh_CN, this message translates to:
  /// **'已跳过片头'**
  String get playerIntroSkipped;

  /// No description provided for @playerOutroSkipped.
  ///
  /// In zh_CN, this message translates to:
  /// **'已跳过片尾'**
  String get playerOutroSkipped;

  /// No description provided for @playerChapterSkipPromptDismissed.
  ///
  /// In zh_CN, this message translates to:
  /// **'本次播放已忽略跳过提示，如需关闭可在设置中禁用片头片尾跳过。'**
  String get playerChapterSkipPromptDismissed;

  /// No description provided for @playerCacheFullyAvailable.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前视频已全部缓存'**
  String get playerCacheFullyAvailable;

  /// No description provided for @playerCacheNotReadyForDownload.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前缓存尚未完整，暂时不能转为下载'**
  String get playerCacheNotReadyForDownload;

  /// No description provided for @playerCurrentVideo.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前视频'**
  String get playerCurrentVideo;

  /// No description provided for @playerCacheImportFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'缓存转下载失败'**
  String get playerCacheImportFailed;

  /// No description provided for @playerCacheImportedToDownload.
  ///
  /// In zh_CN, this message translates to:
  /// **'已转为下载'**
  String get playerCacheImportedToDownload;

  /// No description provided for @playerAlreadyInDownloadList.
  ///
  /// In zh_CN, this message translates to:
  /// **'已在下载列表中'**
  String get playerAlreadyInDownloadList;

  /// No description provided for @playerAddingToDownloadList.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在加入下载列表'**
  String get playerAddingToDownloadList;

  /// No description provided for @playerLayoutSwitchFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'切换播放布局失败'**
  String get playerLayoutSwitchFailed;

  /// No description provided for @playerUiLocked.
  ///
  /// In zh_CN, this message translates to:
  /// **'界面已锁定'**
  String get playerUiLocked;

  /// No description provided for @playerUiUnlocked.
  ///
  /// In zh_CN, this message translates to:
  /// **'界面已解锁'**
  String get playerUiUnlocked;

  /// No description provided for @playerReloadRequiredRecovering.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前播放需要重新加载，正在为您恢复播放，请稍候...'**
  String get playerReloadRequiredRecovering;

  /// No description provided for @playerErrorHintFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'失败'**
  String get playerErrorHintFailed;

  /// No description provided for @playerErrorHintError.
  ///
  /// In zh_CN, this message translates to:
  /// **'错误'**
  String get playerErrorHintError;

  /// No description provided for @playerErrorHintUnavailable.
  ///
  /// In zh_CN, this message translates to:
  /// **'不可'**
  String get playerErrorHintUnavailable;

  /// No description provided for @playerErrorHintMissing.
  ///
  /// In zh_CN, this message translates to:
  /// **'缺少'**
  String get playerErrorHintMissing;

  /// No description provided for @playerErrorHintNone.
  ///
  /// In zh_CN, this message translates to:
  /// **'暂无'**
  String get playerErrorHintNone;

  /// No description provided for @playerErrorHintNotLoaded.
  ///
  /// In zh_CN, this message translates to:
  /// **'未加载'**
  String get playerErrorHintNotLoaded;

  /// No description provided for @playerErrorHintNotExtracted.
  ///
  /// In zh_CN, this message translates to:
  /// **'未提取'**
  String get playerErrorHintNotExtracted;

  /// No description provided for @playerSettingsTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'设置'**
  String get playerSettingsTitle;

  /// No description provided for @playerAutoRotateTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'自动旋转'**
  String get playerAutoRotateTitle;

  /// No description provided for @playerAutoRotateSystemSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'跟随系统方向自动切换'**
  String get playerAutoRotateSystemSubtitle;

  /// No description provided for @playerAutoRotateLockedSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'锁定当前播放方向'**
  String get playerAutoRotateLockedSubtitle;

  /// No description provided for @playerAutoPlayTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'自动连播'**
  String get playerAutoPlayTitle;

  /// No description provided for @playerAutoPlayEnabledSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前集播放完成后自动播放下一集'**
  String get playerAutoPlayEnabledSubtitle;

  /// No description provided for @playerAutoPlayDisabledSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'关闭后播放完成停留当前集'**
  String get playerAutoPlayDisabledSubtitle;

  /// No description provided for @playerNextEpisodePreloadTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'下一级预加载'**
  String get playerNextEpisodePreloadTitle;

  /// No description provided for @playerNextEpisodePreloadEnabledSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'片尾倒计时开始时预加载下一集，尽量减少黑屏和等待'**
  String get playerNextEpisodePreloadEnabledSubtitle;

  /// No description provided for @playerNextEpisodePreloadDisabledSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'关闭后保持原本的自动连播切集方式'**
  String get playerNextEpisodePreloadDisabledSubtitle;

  /// No description provided for @playerNextEpisodePreloadRequiresAutoPlay.
  ///
  /// In zh_CN, this message translates to:
  /// **'需先开启自动连播'**
  String get playerNextEpisodePreloadRequiresAutoPlay;

  /// No description provided for @playerCurrentValue.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前：{value}'**
  String playerCurrentValue(Object value);

  /// No description provided for @playerIntroOutroSettingsTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'片头片尾设置'**
  String get playerIntroOutroSettingsTitle;

  /// No description provided for @playerBookmarkSettingsSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'记录当前片段关键时间点并快速跳转'**
  String get playerBookmarkSettingsSubtitle;

  /// No description provided for @playerSelectIntroChapterTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'选择片头章节'**
  String get playerSelectIntroChapterTitle;

  /// No description provided for @playerSelectOutroChapterTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'选择片尾章节'**
  String get playerSelectOutroChapterTitle;

  /// No description provided for @playerIntroOutroStatusTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'OP/ED 跳过'**
  String get playerIntroOutroStatusTitle;

  /// No description provided for @playerEnabled.
  ///
  /// In zh_CN, this message translates to:
  /// **'已开启'**
  String get playerEnabled;

  /// No description provided for @playerIntroOutroAutoSkipToggleTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'启用自动跳过'**
  String get playerIntroOutroAutoSkipToggleTitle;

  /// No description provided for @playerIntroOutroAutoSkipToggleSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'开启后按官方配置跳过片头片尾'**
  String get playerIntroOutroAutoSkipToggleSubtitle;

  /// No description provided for @playerAdvancedAdjustmentLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'高级调整'**
  String get playerAdvancedAdjustmentLabel;

  /// No description provided for @playerIntroOutroDefaultDurationHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'默认 1-2 分钟，必要时再微调'**
  String get playerIntroOutroDefaultDurationHint;

  /// No description provided for @playerIntroOutroOffTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'关闭'**
  String get playerIntroOutroOffTitle;

  /// No description provided for @playerIntroOutroOffSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'不自动跳过片头片尾'**
  String get playerIntroOutroOffSubtitle;

  /// No description provided for @playerIntroOutroOfficialTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'自动跳过官方片头片尾'**
  String get playerIntroOutroOfficialTitle;

  /// No description provided for @playerIntroOutroOfficialSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'使用飞牛官方片头片尾时长配置'**
  String get playerIntroOutroOfficialSubtitle;

  /// No description provided for @playerIntroOutroOfficialSettingsTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'飞牛官方设置'**
  String get playerIntroOutroOfficialSettingsTitle;

  /// No description provided for @playerIntroOutroOfficialSettingsSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'设置官方片头片尾跳过时长'**
  String get playerIntroOutroOfficialSettingsSubtitle;

  /// No description provided for @playerIntroOutroChapterModeTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'章节判断跳过'**
  String get playerIntroOutroChapterModeTitle;

  /// No description provided for @playerIntroOutroChapterModeSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'根据章节自动判断，或手动选择章节作为 OP/ED'**
  String get playerIntroOutroChapterModeSubtitle;

  /// No description provided for @playerIntroOutroChapterSettingsTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'章节跳过设置'**
  String get playerIntroOutroChapterSettingsTitle;

  /// No description provided for @playerSkipIntroTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'跳过片头'**
  String get playerSkipIntroTitle;

  /// No description provided for @playerSkipOutroTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'跳过片尾'**
  String get playerSkipOutroTitle;

  /// No description provided for @playerIntroDurationTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'片头时长'**
  String get playerIntroDurationTitle;

  /// No description provided for @playerOutroDurationTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'片尾时长'**
  String get playerOutroDurationTitle;

  /// No description provided for @playerOfficialIntroDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'设置官方片头跳过时长'**
  String get playerOfficialIntroDescription;

  /// No description provided for @playerOfficialOutroDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'设置官方片尾跳过时长'**
  String get playerOfficialOutroDescription;

  /// No description provided for @playerCurrentPlaybackTime.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前播放时间'**
  String get playerCurrentPlaybackTime;

  /// No description provided for @playerSetAsIntro.
  ///
  /// In zh_CN, this message translates to:
  /// **'设为片头'**
  String get playerSetAsIntro;

  /// No description provided for @playerSetAsOutro.
  ///
  /// In zh_CN, this message translates to:
  /// **'设为片尾'**
  String get playerSetAsOutro;

  /// No description provided for @playerCustomDurationTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'自定义'**
  String get playerCustomDurationTitle;

  /// No description provided for @playerCustomDurationSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'距离片头/片尾多少秒时开始跳过'**
  String get playerCustomDurationSubtitle;

  /// No description provided for @playerResetToZeroSeconds.
  ///
  /// In zh_CN, this message translates to:
  /// **'恢复为 0 秒'**
  String get playerResetToZeroSeconds;

  /// No description provided for @playerIntroOutroAutoModeTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'自动判断'**
  String get playerIntroOutroAutoModeTitle;

  /// No description provided for @playerIntroOutroAutoModeSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'根据章节位置和短章节时长自动识别 OP/ED'**
  String get playerIntroOutroAutoModeSubtitle;

  /// No description provided for @playerIntroOutroManualModeTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'手动选择章节'**
  String get playerIntroOutroManualModeTitle;

  /// No description provided for @playerIntroOutroManualModeSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'手动指定章节作为片头片尾'**
  String get playerIntroOutroManualModeSubtitle;

  /// No description provided for @playerIntroOutroAutoRangeLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'自动判断范围'**
  String get playerIntroOutroAutoRangeLabel;

  /// No description provided for @playerIntroMaxChapterDurationTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'片头最大章节时长'**
  String get playerIntroMaxChapterDurationTitle;

  /// No description provided for @playerIntroMaxChapterDurationSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'前段短章节小于该时长时，优先判定为片头'**
  String get playerIntroMaxChapterDurationSubtitle;

  /// No description provided for @playerOutroMaxChapterDurationTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'片尾最大章节时长'**
  String get playerOutroMaxChapterDurationTitle;

  /// No description provided for @playerOutroMaxChapterDurationSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'尾段短章节小于该时长时，优先判定为片尾'**
  String get playerOutroMaxChapterDurationSubtitle;

  /// No description provided for @playerIntroChapterTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'片头章节'**
  String get playerIntroChapterTitle;

  /// No description provided for @playerIntroChapterSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'手动指定片头章节'**
  String get playerIntroChapterSubtitle;

  /// No description provided for @playerOutroChapterTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'片尾章节'**
  String get playerOutroChapterTitle;

  /// No description provided for @playerOutroChapterSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'手动指定片尾章节'**
  String get playerOutroChapterSubtitle;

  /// No description provided for @playerUnset.
  ///
  /// In zh_CN, this message translates to:
  /// **'未设置'**
  String get playerUnset;

  /// No description provided for @playerChapterNumber.
  ///
  /// In zh_CN, this message translates to:
  /// **'第 {chapter} 章'**
  String playerChapterNumber(int chapter);

  /// No description provided for @playerChapterLoadFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'读取章节失败: {error}'**
  String playerChapterLoadFailed(Object error);

  /// No description provided for @playerNoAvailableChapters.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前视频没有可用章节'**
  String get playerNoAvailableChapters;

  /// No description provided for @playerNoChapter.
  ///
  /// In zh_CN, this message translates to:
  /// **'不使用章节'**
  String get playerNoChapter;

  /// No description provided for @playerIntroOutroSourceChapterLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'章节判断'**
  String get playerIntroOutroSourceChapterLabel;

  /// No description provided for @playerIntroOutroSourceOffLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'已关闭'**
  String get playerIntroOutroSourceOffLabel;

  /// No description provided for @playerIntroOutroManualLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'手动选择'**
  String get playerIntroOutroManualLabel;

  /// No description provided for @playerIntroOutroAutoLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'自动判断'**
  String get playerIntroOutroAutoLabel;

  /// No description provided for @playerIntroOutroManualSummary.
  ///
  /// In zh_CN, this message translates to:
  /// **'片头：{intro}，片尾：{outro}'**
  String playerIntroOutroManualSummary(Object intro, Object outro);

  /// No description provided for @playerUnrecognized.
  ///
  /// In zh_CN, this message translates to:
  /// **'未识别'**
  String get playerUnrecognized;

  /// No description provided for @playerIntroOutroAutoSummary.
  ///
  /// In zh_CN, this message translates to:
  /// **'自动判断结果，片头：{intro}，片尾：{outro}'**
  String playerIntroOutroAutoSummary(Object intro, Object outro);

  /// No description provided for @playerIntroOutroOffSummary.
  ///
  /// In zh_CN, this message translates to:
  /// **'关闭后不会自动跳过片头片尾'**
  String get playerIntroOutroOffSummary;

  /// No description provided for @playerIntroOutroOfficialSummary.
  ///
  /// In zh_CN, this message translates to:
  /// **'官方片头 {intro}，片尾 {outro}'**
  String playerIntroOutroOfficialSummary(Object intro, Object outro);

  /// No description provided for @playerEpisodeSwitchFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'切换剧集失败: {error}'**
  String playerEpisodeSwitchFailed(Object error);

  /// No description provided for @playerNotReady.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放器未就绪'**
  String get playerNotReady;

  /// No description provided for @playerListenVideoEnabled.
  ///
  /// In zh_CN, this message translates to:
  /// **'已开启听视频模式'**
  String get playerListenVideoEnabled;

  /// No description provided for @playerListenVideoRestored.
  ///
  /// In zh_CN, this message translates to:
  /// **'已恢复视频画面'**
  String get playerListenVideoRestored;

  /// No description provided for @playerListenVideoSwitchFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'听视频模式切换失败'**
  String get playerListenVideoSwitchFailed;

  /// No description provided for @playerVideoRestoreFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'视频画面恢复失败'**
  String get playerVideoRestoreFailed;

  /// No description provided for @playerScreenshotModuleMissing.
  ///
  /// In zh_CN, this message translates to:
  /// **'截图模块未加载，请重启应用'**
  String get playerScreenshotModuleMissing;

  /// No description provided for @playerScreenshotFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'截图失败'**
  String get playerScreenshotFailed;

  /// No description provided for @playerScreenshotSaved.
  ///
  /// In zh_CN, this message translates to:
  /// **'截图已保存'**
  String get playerScreenshotSaved;

  /// No description provided for @playerScreenshotCustomDirectoryRequired.
  ///
  /// In zh_CN, this message translates to:
  /// **'请先在截图设置里选择自定义目录'**
  String get playerScreenshotCustomDirectoryRequired;

  /// No description provided for @playerScreenshotCustomDirectoryUnavailable.
  ///
  /// In zh_CN, this message translates to:
  /// **'自定义目录不可用，请重新选择'**
  String get playerScreenshotCustomDirectoryUnavailable;

  /// No description provided for @playerScreenshotUnavailable.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前还不能截图'**
  String get playerScreenshotUnavailable;

  /// No description provided for @playerScreenshotSaveFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'截图保存失败'**
  String get playerScreenshotSaveFailed;

  /// No description provided for @playerDiagnosticsTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放诊断'**
  String get playerDiagnosticsTitle;

  /// No description provided for @playerDiagnosticsLoadFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'读取播放诊断失败：{error}'**
  String playerDiagnosticsLoadFailed(Object error);

  /// No description provided for @playerDiagnosticsEmpty.
  ///
  /// In zh_CN, this message translates to:
  /// **'暂时没有可显示的播放信息'**
  String get playerDiagnosticsEmpty;

  /// No description provided for @playerDiagnosticsPlaybackSection.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放信息'**
  String get playerDiagnosticsPlaybackSection;

  /// No description provided for @playerDiagnosticsStatus.
  ///
  /// In zh_CN, this message translates to:
  /// **'状态'**
  String get playerDiagnosticsStatus;

  /// No description provided for @playerDiagnosticsPosition.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前位置'**
  String get playerDiagnosticsPosition;

  /// No description provided for @playerDiagnosticsDuration.
  ///
  /// In zh_CN, this message translates to:
  /// **'总时长'**
  String get playerDiagnosticsDuration;

  /// No description provided for @playerDiagnosticsSpeed.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放速度'**
  String get playerDiagnosticsSpeed;

  /// No description provided for @playerDiagnosticsPaused.
  ///
  /// In zh_CN, this message translates to:
  /// **'已暂停'**
  String get playerDiagnosticsPaused;

  /// No description provided for @playerDiagnosticsError.
  ///
  /// In zh_CN, this message translates to:
  /// **'错误'**
  String get playerDiagnosticsError;

  /// No description provided for @playerDiagnosticsVideoSection.
  ///
  /// In zh_CN, this message translates to:
  /// **'视频'**
  String get playerDiagnosticsVideoSection;

  /// No description provided for @playerDiagnosticsVideoCodec.
  ///
  /// In zh_CN, this message translates to:
  /// **'视频编码'**
  String get playerDiagnosticsVideoCodec;

  /// No description provided for @playerDiagnosticsDolbyVision.
  ///
  /// In zh_CN, this message translates to:
  /// **'杜比视界'**
  String get playerDiagnosticsDolbyVision;

  /// No description provided for @playerDiagnosticsResolution.
  ///
  /// In zh_CN, this message translates to:
  /// **'分辨率'**
  String get playerDiagnosticsResolution;

  /// No description provided for @playerDiagnosticsVideoOutput.
  ///
  /// In zh_CN, this message translates to:
  /// **'视频输出'**
  String get playerDiagnosticsVideoOutput;

  /// No description provided for @playerDiagnosticsDecoder.
  ///
  /// In zh_CN, this message translates to:
  /// **'解码方式'**
  String get playerDiagnosticsDecoder;

  /// No description provided for @playerDiagnosticsAudioSection.
  ///
  /// In zh_CN, this message translates to:
  /// **'音频'**
  String get playerDiagnosticsAudioSection;

  /// No description provided for @playerDiagnosticsCurrentAudioTrack.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前音轨'**
  String get playerDiagnosticsCurrentAudioTrack;

  /// No description provided for @playerDiagnosticsAudioCodec.
  ///
  /// In zh_CN, this message translates to:
  /// **'音频编码'**
  String get playerDiagnosticsAudioCodec;

  /// No description provided for @playerDiagnosticsAudioChain.
  ///
  /// In zh_CN, this message translates to:
  /// **'音频链路'**
  String get playerDiagnosticsAudioChain;

  /// No description provided for @playerDiagnosticsOutputParams.
  ///
  /// In zh_CN, this message translates to:
  /// **'输出参数'**
  String get playerDiagnosticsOutputParams;

  /// No description provided for @playerDiagnosticsOutputDevice.
  ///
  /// In zh_CN, this message translates to:
  /// **'输出设备'**
  String get playerDiagnosticsOutputDevice;

  /// No description provided for @playerDiagnosticsExternalAudio.
  ///
  /// In zh_CN, this message translates to:
  /// **'已接入外接音频'**
  String get playerDiagnosticsExternalAudio;

  /// No description provided for @playerDiagnosticsUsbAudio.
  ///
  /// In zh_CN, this message translates to:
  /// **'USB / 小尾巴'**
  String get playerDiagnosticsUsbAudio;

  /// No description provided for @playerDiagnosticsSystemDefaultOutput.
  ///
  /// In zh_CN, this message translates to:
  /// **'系统默认输出'**
  String get playerDiagnosticsSystemDefaultOutput;

  /// No description provided for @playerDiagnosticsCurrentSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前字幕'**
  String get playerDiagnosticsCurrentSubtitle;

  /// No description provided for @playerDiagnosticsOutputDisplaySection.
  ///
  /// In zh_CN, this message translates to:
  /// **'输出与显示'**
  String get playerDiagnosticsOutputDisplaySection;

  /// No description provided for @playerDiagnosticsHdrDolbyPipeline.
  ///
  /// In zh_CN, this message translates to:
  /// **'HDR / 杜比链路'**
  String get playerDiagnosticsHdrDolbyPipeline;

  /// No description provided for @playerDiagnosticsColorMode.
  ///
  /// In zh_CN, this message translates to:
  /// **'色彩模式'**
  String get playerDiagnosticsColorMode;

  /// No description provided for @playerDiagnosticsDeviceInfo.
  ///
  /// In zh_CN, this message translates to:
  /// **'设备信息'**
  String get playerDiagnosticsDeviceInfo;

  /// No description provided for @playerDiagnosticsSourceSection.
  ///
  /// In zh_CN, this message translates to:
  /// **'片源'**
  String get playerDiagnosticsSourceSection;

  /// No description provided for @playerDiagnosticsTitleLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'标题'**
  String get playerDiagnosticsTitleLabel;

  /// No description provided for @playerDiagnosticsMediaId.
  ///
  /// In zh_CN, this message translates to:
  /// **'媒体标识'**
  String get playerDiagnosticsMediaId;

  /// No description provided for @playerDiagnosticsVideoStream.
  ///
  /// In zh_CN, this message translates to:
  /// **'视频流'**
  String get playerDiagnosticsVideoStream;

  /// No description provided for @playerDiagnosticsAudioStream.
  ///
  /// In zh_CN, this message translates to:
  /// **'音频流'**
  String get playerDiagnosticsAudioStream;

  /// No description provided for @playerDiagnosticsSubtitleStream.
  ///
  /// In zh_CN, this message translates to:
  /// **'字幕流'**
  String get playerDiagnosticsSubtitleStream;

  /// No description provided for @commonYes.
  ///
  /// In zh_CN, this message translates to:
  /// **'是'**
  String get commonYes;

  /// No description provided for @commonNo.
  ///
  /// In zh_CN, this message translates to:
  /// **'否'**
  String get commonNo;

  /// No description provided for @playerDolbyVisionSource.
  ///
  /// In zh_CN, this message translates to:
  /// **'杜比视界片源'**
  String get playerDolbyVisionSource;

  /// No description provided for @playerHdrSource.
  ///
  /// In zh_CN, this message translates to:
  /// **'HDR片源'**
  String get playerHdrSource;

  /// No description provided for @playerSdrSource.
  ///
  /// In zh_CN, this message translates to:
  /// **'SDR片源'**
  String get playerSdrSource;

  /// No description provided for @playerHdrDirect.
  ///
  /// In zh_CN, this message translates to:
  /// **'HDR直出'**
  String get playerHdrDirect;

  /// No description provided for @playerSdrTonemap.
  ///
  /// In zh_CN, this message translates to:
  /// **'SDR映射'**
  String get playerSdrTonemap;

  /// No description provided for @playerSdrPipeline.
  ///
  /// In zh_CN, this message translates to:
  /// **'SDR链路'**
  String get playerSdrPipeline;

  /// No description provided for @playerAudioPassthrough.
  ///
  /// In zh_CN, this message translates to:
  /// **'直通输出'**
  String get playerAudioPassthrough;

  /// No description provided for @playerAudioDecodedNonPassthrough.
  ///
  /// In zh_CN, this message translates to:
  /// **'解码播放（非直通）'**
  String get playerAudioDecodedNonPassthrough;

  /// No description provided for @playerAudioDecoded.
  ///
  /// In zh_CN, this message translates to:
  /// **'解码播放'**
  String get playerAudioDecoded;

  /// No description provided for @playerRecognized.
  ///
  /// In zh_CN, this message translates to:
  /// **'已识别'**
  String get playerRecognized;

  /// No description provided for @playerConnected.
  ///
  /// In zh_CN, this message translates to:
  /// **'已接入'**
  String get playerConnected;

  /// No description provided for @playerNotDetected.
  ///
  /// In zh_CN, this message translates to:
  /// **'未检测到'**
  String get playerNotDetected;

  /// No description provided for @danmakuSettingsTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'弹幕设置'**
  String get danmakuSettingsTitle;

  /// No description provided for @danmakuDisplaySection.
  ///
  /// In zh_CN, this message translates to:
  /// **'显示调节'**
  String get danmakuDisplaySection;

  /// No description provided for @danmakuDisplayArea.
  ///
  /// In zh_CN, this message translates to:
  /// **'显示区域'**
  String get danmakuDisplayArea;

  /// No description provided for @danmakuOpacity.
  ///
  /// In zh_CN, this message translates to:
  /// **'不透明度'**
  String get danmakuOpacity;

  /// No description provided for @danmakuDensity.
  ///
  /// In zh_CN, this message translates to:
  /// **'弹幕密度'**
  String get danmakuDensity;

  /// No description provided for @danmakuFontSize.
  ///
  /// In zh_CN, this message translates to:
  /// **'字体大小'**
  String get danmakuFontSize;

  /// No description provided for @danmakuFontWeight.
  ///
  /// In zh_CN, this message translates to:
  /// **'字体粗细'**
  String get danmakuFontWeight;

  /// No description provided for @danmakuSpeed.
  ///
  /// In zh_CN, this message translates to:
  /// **'弹幕速度'**
  String get danmakuSpeed;

  /// No description provided for @danmakuFrameRate.
  ///
  /// In zh_CN, this message translates to:
  /// **'弹幕帧率'**
  String get danmakuFrameRate;

  /// No description provided for @danmakuTypeFilterSection.
  ///
  /// In zh_CN, this message translates to:
  /// **'按弹幕类型屏蔽'**
  String get danmakuTypeFilterSection;

  /// No description provided for @danmakuTypeFixed.
  ///
  /// In zh_CN, this message translates to:
  /// **'固定'**
  String get danmakuTypeFixed;

  /// No description provided for @danmakuTypeScroll.
  ///
  /// In zh_CN, this message translates to:
  /// **'滚动'**
  String get danmakuTypeScroll;

  /// No description provided for @danmakuTypeColor.
  ///
  /// In zh_CN, this message translates to:
  /// **'彩色'**
  String get danmakuTypeColor;

  /// No description provided for @danmakuTypeBottom.
  ///
  /// In zh_CN, this message translates to:
  /// **'底部'**
  String get danmakuTypeBottom;

  /// No description provided for @danmakuOcclusionSection.
  ///
  /// In zh_CN, this message translates to:
  /// **'画面防遮挡'**
  String get danmakuOcclusionSection;

  /// No description provided for @danmakuHideDuplicateTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'隐藏重复弹幕'**
  String get danmakuHideDuplicateTitle;

  /// No description provided for @danmakuHideDuplicateSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'合并高频重复内容，减少同屏密集刷屏。'**
  String get danmakuHideDuplicateSubtitle;

  /// No description provided for @danmakuAvoidSubtitleTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'底部字幕区域防遮挡'**
  String get danmakuAvoidSubtitleTitle;

  /// No description provided for @danmakuAvoidSubtitleSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'优先避开字幕所在区域，减少弹幕压住字幕。'**
  String get danmakuAvoidSubtitleSubtitle;

  /// No description provided for @danmakuAvoidCenterTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'主体穿透遮挡'**
  String get danmakuAvoidCenterTitle;

  /// No description provided for @danmakuAvoidCenterSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'优先使用动态蒙版扣除人物区域内的弹幕，不可用时会恢复普通弹幕。'**
  String get danmakuAvoidCenterSubtitle;

  /// No description provided for @danmakuAiSampleInterval.
  ///
  /// In zh_CN, this message translates to:
  /// **'AI 采样间隔'**
  String get danmakuAiSampleInterval;

  /// No description provided for @danmakuAiSampleSize.
  ///
  /// In zh_CN, this message translates to:
  /// **'AI 采样大小'**
  String get danmakuAiSampleSize;

  /// No description provided for @danmakuSourceSection.
  ///
  /// In zh_CN, this message translates to:
  /// **'弹幕来源'**
  String get danmakuSourceSection;

  /// No description provided for @danmakuLayerEnabledTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'启用弹幕层'**
  String get danmakuLayerEnabledTitle;

  /// No description provided for @danmakuLayerEnabledSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'关闭后右上角设置入口会隐藏，仅保留左下角开关。'**
  String get danmakuLayerEnabledSubtitle;

  /// No description provided for @danmakuCurrentStatus.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前状态：{status}  ·  {summary}'**
  String danmakuCurrentStatus(Object status, Object summary);

  /// No description provided for @danmakuSourcePriority.
  ///
  /// In zh_CN, this message translates to:
  /// **'来源优先级'**
  String get danmakuSourcePriority;

  /// No description provided for @danmakuSourcePriorityDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'当本地弹幕和网络弹幕都可用时，优先自动载入 {priority}。'**
  String danmakuSourcePriorityDescription(Object priority);

  /// No description provided for @danmakuLocalFirst.
  ///
  /// In zh_CN, this message translates to:
  /// **'本地优先'**
  String get danmakuLocalFirst;

  /// No description provided for @danmakuNetworkFirst.
  ///
  /// In zh_CN, this message translates to:
  /// **'网络优先'**
  String get danmakuNetworkFirst;

  /// No description provided for @danmakuSavedTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'已保存弹幕'**
  String get danmakuSavedTitle;

  /// No description provided for @danmakuSavedEmptySubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'统一管理本地弹幕和弹弹play缓存。'**
  String get danmakuSavedEmptySubtitle;

  /// No description provided for @danmakuSavedCountSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前已保存 {count} 个弹幕来源。'**
  String danmakuSavedCountSubtitle(int count);

  /// No description provided for @danmakuSearchTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'搜索弹幕'**
  String get danmakuSearchTitle;

  /// No description provided for @danmakuDanDanPlay.
  ///
  /// In zh_CN, this message translates to:
  /// **'弹弹play'**
  String get danmakuDanDanPlay;

  /// No description provided for @danmakuSearchAnimeSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'通过弹弹play搜索当前番剧和剧集，直接导入网络弹幕。'**
  String get danmakuSearchAnimeSubtitle;

  /// No description provided for @danmakuSearchSourceSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'通过弹弹play搜索当前片源相关结果，直接导入网络弹幕。'**
  String get danmakuSearchSourceSubtitle;

  /// No description provided for @danmakuManualImportTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'手动导入弹幕'**
  String get danmakuManualImportTitle;

  /// No description provided for @danmakuManualImportSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'支持本地 XML / JSON 弹幕文件，导入后会替换当前已载入弹幕。'**
  String get danmakuManualImportSubtitle;

  /// No description provided for @danmakuLocalFile.
  ///
  /// In zh_CN, this message translates to:
  /// **'本地文件'**
  String get danmakuLocalFile;

  /// No description provided for @danmakuLocalImport.
  ///
  /// In zh_CN, this message translates to:
  /// **'本地导入'**
  String get danmakuLocalImport;

  /// No description provided for @danmakuNoSavedSources.
  ///
  /// In zh_CN, this message translates to:
  /// **'还没有已保存弹幕来源'**
  String get danmakuNoSavedSources;

  /// No description provided for @danmakuLocalSource.
  ///
  /// In zh_CN, this message translates to:
  /// **'本地弹幕'**
  String get danmakuLocalSource;

  /// No description provided for @danmakuSearchHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'可自动带入当前内容，也可以改词重搜'**
  String get danmakuSearchHint;

  /// No description provided for @danmakuCurrentMatch.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前匹配：{context}'**
  String danmakuCurrentMatch(Object context);

  /// No description provided for @danmakuNoSearchResults.
  ///
  /// In zh_CN, this message translates to:
  /// **'没有搜索到可用结果'**
  String get danmakuNoSearchResults;

  /// No description provided for @danmakuConfigRequired.
  ///
  /// In zh_CN, this message translates to:
  /// **'请先在配置中填入弹弹play AppId / AppSecret'**
  String get danmakuConfigRequired;

  /// No description provided for @danmakuSizeSmall.
  ///
  /// In zh_CN, this message translates to:
  /// **'较小'**
  String get danmakuSizeSmall;

  /// No description provided for @danmakuSizeSlightlySmall.
  ///
  /// In zh_CN, this message translates to:
  /// **'偏小'**
  String get danmakuSizeSlightlySmall;

  /// No description provided for @danmakuSizeStandard.
  ///
  /// In zh_CN, this message translates to:
  /// **'标准'**
  String get danmakuSizeStandard;

  /// No description provided for @danmakuSizeSlightlyLarge.
  ///
  /// In zh_CN, this message translates to:
  /// **'偏大'**
  String get danmakuSizeSlightlyLarge;

  /// No description provided for @danmakuSizeLarge.
  ///
  /// In zh_CN, this message translates to:
  /// **'较大'**
  String get danmakuSizeLarge;

  /// No description provided for @danmakuWeightThin.
  ///
  /// In zh_CN, this message translates to:
  /// **'较细'**
  String get danmakuWeightThin;

  /// No description provided for @danmakuWeightThick.
  ///
  /// In zh_CN, this message translates to:
  /// **'较粗'**
  String get danmakuWeightThick;

  /// No description provided for @danmakuWeightVeryThick.
  ///
  /// In zh_CN, this message translates to:
  /// **'很粗'**
  String get danmakuWeightVeryThick;

  /// No description provided for @danmakuAreaQuarter.
  ///
  /// In zh_CN, this message translates to:
  /// **'1/4 屏'**
  String get danmakuAreaQuarter;

  /// No description provided for @danmakuAreaHalf.
  ///
  /// In zh_CN, this message translates to:
  /// **'半屏'**
  String get danmakuAreaHalf;

  /// No description provided for @danmakuAreaThreeQuarter.
  ///
  /// In zh_CN, this message translates to:
  /// **'3/4 屏'**
  String get danmakuAreaThreeQuarter;

  /// No description provided for @danmakuAreaFull.
  ///
  /// In zh_CN, this message translates to:
  /// **'全屏'**
  String get danmakuAreaFull;

  /// No description provided for @danmakuSpeedSlow.
  ///
  /// In zh_CN, this message translates to:
  /// **'慢'**
  String get danmakuSpeedSlow;

  /// No description provided for @danmakuSpeedFast.
  ///
  /// In zh_CN, this message translates to:
  /// **'快'**
  String get danmakuSpeedFast;

  /// No description provided for @danmakuSpeedVeryFast.
  ///
  /// In zh_CN, this message translates to:
  /// **'极快'**
  String get danmakuSpeedVeryFast;

  /// No description provided for @danmakuOcclusionDisabledTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'主体遮挡已关闭'**
  String get danmakuOcclusionDisabledTitle;

  /// No description provided for @danmakuOcclusionMaskTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'精细遮罩中'**
  String get danmakuOcclusionMaskTitle;

  /// No description provided for @danmakuOcclusionBboxTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'人物框兜底中'**
  String get danmakuOcclusionBboxTitle;

  /// No description provided for @danmakuOcclusionEnabledTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'主体遮挡已启用'**
  String get danmakuOcclusionEnabledTitle;

  /// No description provided for @danmakuOcclusionUnavailableTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'主体遮挡暂不可用'**
  String get danmakuOcclusionUnavailableTitle;

  /// No description provided for @danmakuOcclusionDisabledSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'关闭后会恢复普通弹幕显示。'**
  String get danmakuOcclusionDisabledSubtitle;

  /// No description provided for @danmakuOcclusionMaskCached.
  ///
  /// In zh_CN, this message translates to:
  /// **'已复用精细遮罩缓存'**
  String get danmakuOcclusionMaskCached;

  /// No description provided for @danmakuOcclusionMaskRealtime.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在使用实时精细遮罩'**
  String get danmakuOcclusionMaskRealtime;

  /// No description provided for @danmakuOcclusionBboxFallback.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在使用人物框兜底'**
  String get danmakuOcclusionBboxFallback;

  /// No description provided for @danmakuOcclusionNormal.
  ///
  /// In zh_CN, this message translates to:
  /// **'遮挡状态正常'**
  String get danmakuOcclusionNormal;

  /// No description provided for @danmakuOcclusionBackendStatus.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前后端：{backend}，{status}。'**
  String danmakuOcclusionBackendStatus(Object backend, Object status);

  /// No description provided for @danmakuOcclusionBackendWithReason.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前后端：{backend}，{reason}'**
  String danmakuOcclusionBackendWithReason(Object backend, Object reason);

  /// No description provided for @danmakuOcclusionBackendOnly.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前后端：{backend}'**
  String danmakuOcclusionBackendOnly(Object backend);

  /// No description provided for @danmakuOcclusionCaptureUnsupported.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前视频输出后端不支持 AI 采样'**
  String get danmakuOcclusionCaptureUnsupported;

  /// No description provided for @danmakuOcclusionCaptureBudgetUnsupported.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前链路在高刷新率下已禁用实时 AI 采样'**
  String get danmakuOcclusionCaptureBudgetUnsupported;

  /// No description provided for @danmakuEnabled.
  ///
  /// In zh_CN, this message translates to:
  /// **'弹幕已开启'**
  String get danmakuEnabled;

  /// No description provided for @danmakuDisabled.
  ///
  /// In zh_CN, this message translates to:
  /// **'弹幕已关闭'**
  String get danmakuDisabled;

  /// No description provided for @danmakuNeedSearchKeyword.
  ///
  /// In zh_CN, this message translates to:
  /// **'请先输入要搜索的番剧名称'**
  String get danmakuNeedSearchKeyword;

  /// No description provided for @danmakuSearchRateLimited.
  ///
  /// In zh_CN, this message translates to:
  /// **'搜索过于频繁，请 {seconds} 秒后再试。'**
  String danmakuSearchRateLimited(int seconds);

  /// No description provided for @danmakuSearchFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'搜索弹幕失败'**
  String get danmakuSearchFailed;

  /// No description provided for @danmakuNoAvailableData.
  ///
  /// In zh_CN, this message translates to:
  /// **'没有获取到可用弹幕数据'**
  String get danmakuNoAvailableData;

  /// No description provided for @danmakuImportFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'导入弹幕失败'**
  String get danmakuImportFailed;

  /// No description provided for @danmakuImportFailedWithError.
  ///
  /// In zh_CN, this message translates to:
  /// **'导入弹幕失败: {error}'**
  String danmakuImportFailedWithError(Object error);

  /// No description provided for @danmakuReadSelectedFileFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'无法读取已选择的弹幕文件'**
  String get danmakuReadSelectedFileFailed;

  /// No description provided for @danmakuImportedCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'已导入 {count} 条弹幕'**
  String danmakuImportedCount(int count);

  /// No description provided for @danmakuLoadedCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'已载入 {count} 条弹幕'**
  String danmakuLoadedCount(int count);

  /// No description provided for @danmakuSavedFileInvalidRemoved.
  ///
  /// In zh_CN, this message translates to:
  /// **'弹幕文件已失效，已从列表移除'**
  String get danmakuSavedFileInvalidRemoved;

  /// No description provided for @danmakuSavedSourceDeleted.
  ///
  /// In zh_CN, this message translates to:
  /// **'已删除保存的弹幕来源'**
  String get danmakuSavedSourceDeleted;

  /// No description provided for @danmakuReadSavedFileFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'无法读取已保存的弹幕文件'**
  String get danmakuReadSavedFileFailed;

  /// No description provided for @danmakuAutoMatchNoResultBlocked.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前片源自动匹配弹幕无结果，后续不再自动请求，可手动搜索。'**
  String get danmakuAutoMatchNoResultBlocked;

  /// No description provided for @danmakuAutoMatchFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前片源自动匹配弹幕失败'**
  String get danmakuAutoMatchFailed;

  /// No description provided for @danmakuAutoMatchBlockedWithReason.
  ///
  /// In zh_CN, this message translates to:
  /// **'{reason}，后续不再自动请求，可手动搜索。'**
  String danmakuAutoMatchBlockedWithReason(Object reason);

  /// No description provided for @danmakuSwitchedLocalFirst.
  ///
  /// In zh_CN, this message translates to:
  /// **'已切换为本地优先'**
  String get danmakuSwitchedLocalFirst;

  /// No description provided for @danmakuSwitchedNetworkFirst.
  ///
  /// In zh_CN, this message translates to:
  /// **'已切换为网络优先'**
  String get danmakuSwitchedNetworkFirst;

  /// No description provided for @danmakuLayerDisabledSummary.
  ///
  /// In zh_CN, this message translates to:
  /// **'弹幕层已关闭，开启后会按当前优先级自动载入弹幕。'**
  String get danmakuLayerDisabledSummary;

  /// No description provided for @danmakuLoadedLocalSummary.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前已加载本地弹幕'**
  String get danmakuLoadedLocalSummary;

  /// No description provided for @danmakuLoadedNetworkSummary.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前已加载弹弹play弹幕'**
  String get danmakuLoadedNetworkSummary;

  /// No description provided for @danmakuLoadedGenericSummary.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前已加载弹幕'**
  String get danmakuLoadedGenericSummary;

  /// No description provided for @danmakuLoadedWithLabelSummary.
  ///
  /// In zh_CN, this message translates to:
  /// **'{prefix}：{label}，共 {count} 条。'**
  String danmakuLoadedWithLabelSummary(Object prefix, Object label, int count);

  /// No description provided for @danmakuLoadedCountSummary.
  ///
  /// In zh_CN, this message translates to:
  /// **'{prefix}，共 {count} 条。'**
  String danmakuLoadedCountSummary(Object prefix, int count);

  /// No description provided for @danmakuStatusLocal.
  ///
  /// In zh_CN, this message translates to:
  /// **'本地'**
  String get danmakuStatusLocal;

  /// No description provided for @danmakuStatusNetwork.
  ///
  /// In zh_CN, this message translates to:
  /// **'弹弹play'**
  String get danmakuStatusNetwork;

  /// No description provided for @danmakuStatusNotLoaded.
  ///
  /// In zh_CN, this message translates to:
  /// **'未载入'**
  String get danmakuStatusNotLoaded;

  /// No description provided for @danmakuNoLoadedSearchOrImportSummary.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前还没有载入弹幕，可搜索弹弹play弹幕或手动导入本地弹幕。'**
  String get danmakuNoLoadedSearchOrImportSummary;

  /// No description provided for @danmakuNoLoadedManualImportWithTitleSummary.
  ///
  /// In zh_CN, this message translates to:
  /// **'{title} 暂未载入弹幕，可手动导入本地弹幕。'**
  String danmakuNoLoadedManualImportWithTitleSummary(Object title);

  /// No description provided for @danmakuNoLoadedManualImportSummary.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前片源暂未载入弹幕，可手动导入本地弹幕。'**
  String get danmakuNoLoadedManualImportSummary;

  /// No description provided for @danmakuSearchButton.
  ///
  /// In zh_CN, this message translates to:
  /// **'搜索'**
  String get danmakuSearchButton;

  /// No description provided for @danmakuSavedSourceLocalLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'本地'**
  String get danmakuSavedSourceLocalLabel;

  /// No description provided for @danmakuSavedSourceSubtitleWithCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'{type} · {count} 条 · {detail}'**
  String danmakuSavedSourceSubtitleWithCount(
    Object type,
    int count,
    Object detail,
  );

  /// No description provided for @danmakuSavedSourceSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'{type} · {detail}'**
  String danmakuSavedSourceSubtitle(Object type, Object detail);

  /// No description provided for @danmakuCurrent.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前'**
  String get danmakuCurrent;

  /// No description provided for @playerFitModeUnavailable.
  ///
  /// In zh_CN, this message translates to:
  /// **'画面模式暂未接入'**
  String get playerFitModeUnavailable;

  /// No description provided for @playerPictureInPictureUnavailable.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前无法进入小窗播放'**
  String get playerPictureInPictureUnavailable;

  /// No description provided for @playerResumePrompt.
  ///
  /// In zh_CN, this message translates to:
  /// **'继续播放到 {position}'**
  String playerResumePrompt(Object position);

  /// No description provided for @playerRestartFromBeginning.
  ///
  /// In zh_CN, this message translates to:
  /// **'从头播放'**
  String get playerRestartFromBeginning;

  /// No description provided for @playerAutoPlayNextPrompt.
  ///
  /// In zh_CN, this message translates to:
  /// **'{seconds} 秒后自动连播下一集'**
  String playerAutoPlayNextPrompt(int seconds);

  /// No description provided for @playerReloadAction.
  ///
  /// In zh_CN, this message translates to:
  /// **'重载'**
  String get playerReloadAction;

  /// No description provided for @playerEpisodeAction.
  ///
  /// In zh_CN, this message translates to:
  /// **'选集'**
  String get playerEpisodeAction;

  /// No description provided for @playerAudioTrackAction.
  ///
  /// In zh_CN, this message translates to:
  /// **'音轨'**
  String get playerAudioTrackAction;

  /// No description provided for @playerSubtitleOffAction.
  ///
  /// In zh_CN, this message translates to:
  /// **'字幕关'**
  String get playerSubtitleOffAction;

  /// No description provided for @playerSubtitleAction.
  ///
  /// In zh_CN, this message translates to:
  /// **'字幕'**
  String get playerSubtitleAction;

  /// No description provided for @playerCloudDriveModeTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'网盘播放方式'**
  String get playerCloudDriveModeTitle;

  /// No description provided for @playerCloudDriveAccountName.
  ///
  /// In zh_CN, this message translates to:
  /// **'网盘'**
  String get playerCloudDriveAccountName;

  /// No description provided for @playerCloudDriveDirectUnavailable.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前没有可用的网盘直链播放源'**
  String get playerCloudDriveDirectUnavailable;

  /// No description provided for @playerCloudDriveProxyUnavailable.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前没有可用的 NAS 代理播放源'**
  String get playerCloudDriveProxyUnavailable;

  /// No description provided for @playerCloudDriveSwitchingDirect.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在为您切换至网盘直连播放，请稍候...'**
  String get playerCloudDriveSwitchingDirect;

  /// No description provided for @playerCloudDriveSwitchingProxy.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在为您切换至 NAS 代理播放，请稍候...'**
  String get playerCloudDriveSwitchingProxy;

  /// No description provided for @playerSeasonCountLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'{count}季'**
  String playerSeasonCountLabel(int count);

  /// No description provided for @playerNoEpisodes.
  ///
  /// In zh_CN, this message translates to:
  /// **'暂无选集'**
  String get playerNoEpisodes;

  /// No description provided for @playerDownloadedBadge.
  ///
  /// In zh_CN, this message translates to:
  /// **'已下载'**
  String get playerDownloadedBadge;

  /// No description provided for @playerNetworkOffline.
  ///
  /// In zh_CN, this message translates to:
  /// **'离线'**
  String get playerNetworkOffline;

  /// No description provided for @playerNetworkOnline.
  ///
  /// In zh_CN, this message translates to:
  /// **'网络'**
  String get playerNetworkOnline;

  /// No description provided for @playerSkipPromptCountdown.
  ///
  /// In zh_CN, this message translates to:
  /// **'{seconds} 秒后跳过{label}'**
  String playerSkipPromptCountdown(int seconds, Object label);

  /// No description provided for @playerSkipPromptSoon.
  ///
  /// In zh_CN, this message translates to:
  /// **'即将跳过{label}'**
  String playerSkipPromptSoon(Object label);

  /// No description provided for @playerSkipPromptDismissSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'点击关闭后，本次不会自动跳过'**
  String get playerSkipPromptDismissSubtitle;

  /// No description provided for @playerReplayAction.
  ///
  /// In zh_CN, this message translates to:
  /// **'重新播放'**
  String get playerReplayAction;

  /// No description provided for @playerBackAction.
  ///
  /// In zh_CN, this message translates to:
  /// **'返回'**
  String get playerBackAction;

  /// No description provided for @playerCloudDrivePlayingFile.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在播放网盘文件'**
  String get playerCloudDrivePlayingFile;

  /// No description provided for @playerCloudDriveModeDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放速度、画质等能力取决于网盘侧规则。如遇播放异常，可尝试切换播放方式。'**
  String get playerCloudDriveModeDescription;

  /// No description provided for @playerCloudDriveDirectTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'网盘直连播放'**
  String get playerCloudDriveDirectTitle;

  /// No description provided for @playerCloudDriveDirectSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'速度较快，省流'**
  String get playerCloudDriveDirectSubtitle;

  /// No description provided for @playerCloudDriveProxyTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'NAS 代理播放'**
  String get playerCloudDriveProxyTitle;

  /// No description provided for @playerCloudDriveProxySubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'色调或音频异常时可尝试切换'**
  String get playerCloudDriveProxySubtitle;

  /// No description provided for @playerRecommendedBadge.
  ///
  /// In zh_CN, this message translates to:
  /// **'推荐'**
  String get playerRecommendedBadge;

  /// No description provided for @settingsBookmarkManagerTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'书签管理'**
  String get settingsBookmarkManagerTitle;

  /// No description provided for @settingsBookmarkEmptySummary.
  ///
  /// In zh_CN, this message translates to:
  /// **'还没有书签'**
  String get settingsBookmarkEmptySummary;

  /// No description provided for @settingsBookmarkCountSummary.
  ///
  /// In zh_CN, this message translates to:
  /// **'共 {count} 个书签'**
  String settingsBookmarkCountSummary(int count);

  /// No description provided for @settingsDanmakuDefaultEnabled.
  ///
  /// In zh_CN, this message translates to:
  /// **'默认开启'**
  String get settingsDanmakuDefaultEnabled;

  /// No description provided for @settingsDanmakuDefaultDisabled.
  ///
  /// In zh_CN, this message translates to:
  /// **'默认关闭'**
  String get settingsDanmakuDefaultDisabled;

  /// No description provided for @settingsDanmakuLocalFirst.
  ///
  /// In zh_CN, this message translates to:
  /// **'本地优先'**
  String get settingsDanmakuLocalFirst;

  /// No description provided for @settingsDanmakuNetworkFirst.
  ///
  /// In zh_CN, this message translates to:
  /// **'网络优先'**
  String get settingsDanmakuNetworkFirst;

  /// No description provided for @settingsScreenshotCustomDirectoryNotReady.
  ///
  /// In zh_CN, this message translates to:
  /// **'自定义目录未就绪'**
  String get settingsScreenshotCustomDirectoryNotReady;

  /// No description provided for @settingsScreenshotWithSubtitles.
  ///
  /// In zh_CN, this message translates to:
  /// **'携带字幕'**
  String get settingsScreenshotWithSubtitles;

  /// No description provided for @settingsScreenshotImageOnly.
  ///
  /// In zh_CN, this message translates to:
  /// **'仅画面'**
  String get settingsScreenshotImageOnly;

  /// No description provided for @settingsScreenshotWithSubtitleLayer.
  ///
  /// In zh_CN, this message translates to:
  /// **'携带字幕层'**
  String get settingsScreenshotWithSubtitleLayer;

  /// No description provided for @settingsScreenshotImageOnlySummary.
  ///
  /// In zh_CN, this message translates to:
  /// **'仅保存画面'**
  String get settingsScreenshotImageOnlySummary;

  /// No description provided for @settingsScreenshotImageOnlyDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'不携带字幕层。'**
  String get settingsScreenshotImageOnlyDescription;

  /// No description provided for @settingsScreenshotWithSubtitlesDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'保存当前字幕层。'**
  String get settingsScreenshotWithSubtitlesDescription;

  /// No description provided for @settingsScreenshotCustomDirectoryUnsetSummary.
  ///
  /// In zh_CN, this message translates to:
  /// **'自定义目录未设置。'**
  String get settingsScreenshotCustomDirectoryUnsetSummary;

  /// No description provided for @settingsScreenshotCustomDirectoryInvalidSummary.
  ///
  /// In zh_CN, this message translates to:
  /// **'已记录自定义目录“{name}”，但授权失效，需要重新选择。'**
  String settingsScreenshotCustomDirectoryInvalidSummary(Object name);

  /// No description provided for @settingsScreenshotCustomDirectoryActiveSummary.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前保存到自定义目录“{name}”。'**
  String settingsScreenshotCustomDirectoryActiveSummary(Object name);

  /// No description provided for @settingsScreenshotDirectoryUnset.
  ///
  /// In zh_CN, this message translates to:
  /// **'未设置'**
  String get settingsScreenshotDirectoryUnset;

  /// No description provided for @settingsScreenshotDirectoryInvalid.
  ///
  /// In zh_CN, this message translates to:
  /// **'授权失效'**
  String get settingsScreenshotDirectoryInvalid;

  /// No description provided for @settingsScreenshotSavePathPicturesTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'系统相册'**
  String get settingsScreenshotSavePathPicturesTitle;

  /// No description provided for @settingsScreenshotSavePathPicturesDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'保存到 Pictures/FlyPlayer，适合普通截图查看。'**
  String get settingsScreenshotSavePathPicturesDescription;

  /// No description provided for @settingsScreenshotSavePathDcimTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'相机目录'**
  String get settingsScreenshotSavePathDcimTitle;

  /// No description provided for @settingsScreenshotSavePathDcimDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'保存到 DCIM/FlyPlayer，更容易被系统相册归类展示。'**
  String get settingsScreenshotSavePathDcimDescription;

  /// No description provided for @settingsScreenshotSavePathAppPicturesTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'应用目录'**
  String get settingsScreenshotSavePathAppPicturesTitle;

  /// No description provided for @settingsScreenshotSavePathAppPicturesDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'保存到应用专属图片目录，更干净，但部分图库不会直接扫描。'**
  String get settingsScreenshotSavePathAppPicturesDescription;

  /// No description provided for @settingsScreenshotSavePathCustomTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'自定义目录'**
  String get settingsScreenshotSavePathCustomTitle;

  /// No description provided for @settingsScreenshotSavePathCustomDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'保存到用户自己选择的文件夹，适合集中管理截图。'**
  String get settingsScreenshotSavePathCustomDescription;

  /// No description provided for @settingsScreenshotSelectCustomDirectoryFirst.
  ///
  /// In zh_CN, this message translates to:
  /// **'请先选择截图自定义目录'**
  String get settingsScreenshotSelectCustomDirectoryFirst;

  /// No description provided for @settingsScreenshotCustomDirectoryInvalidRetry.
  ///
  /// In zh_CN, this message translates to:
  /// **'自定义目录已失效，请重新选择'**
  String get settingsScreenshotCustomDirectoryInvalidRetry;

  /// No description provided for @settingsScreenshotReadingCustomDirectory.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在读取当前自定义目录状态...'**
  String get settingsScreenshotReadingCustomDirectory;

  /// No description provided for @settingsScreenshotDirectoryUnsetSentence.
  ///
  /// In zh_CN, this message translates to:
  /// **'未设置目录。'**
  String get settingsScreenshotDirectoryUnsetSentence;

  /// No description provided for @settingsScreenshotDirectoryInvalidWithName.
  ///
  /// In zh_CN, this message translates to:
  /// **'已记录目录“{name}”，但当前授权失效，需要重新选择。'**
  String settingsScreenshotDirectoryInvalidWithName(Object name);

  /// No description provided for @settingsScreenshotCurrentDirectory.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前目录：{name}'**
  String settingsScreenshotCurrentDirectory(Object name);

  /// No description provided for @settingsScreenshotCustomDirectoryManagement.
  ///
  /// In zh_CN, this message translates to:
  /// **'自定义目录管理'**
  String get settingsScreenshotCustomDirectoryManagement;

  /// No description provided for @settingsScreenshotDirectoryAvailable.
  ///
  /// In zh_CN, this message translates to:
  /// **'目录可用'**
  String get settingsScreenshotDirectoryAvailable;

  /// No description provided for @settingsScreenshotDirectoryNeedsReselect.
  ///
  /// In zh_CN, this message translates to:
  /// **'需重选'**
  String get settingsScreenshotDirectoryNeedsReselect;

  /// No description provided for @settingsScreenshotDirectoryActiveDetail.
  ///
  /// In zh_CN, this message translates to:
  /// **'截图保存目录：“{name}”。'**
  String settingsScreenshotDirectoryActiveDetail(Object name);

  /// No description provided for @settingsScreenshotDirectorySetupHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'先选择一个文件夹，再切换到“自定义目录”模式。'**
  String get settingsScreenshotDirectorySetupHint;

  /// No description provided for @settingsScreenshotDirectoryInvalidDetail.
  ///
  /// In zh_CN, this message translates to:
  /// **'原来的目录“{name}”不可用了，请重新选择。'**
  String settingsScreenshotDirectoryInvalidDetail(Object name);

  /// No description provided for @settingsScreenshotChooseDirectory.
  ///
  /// In zh_CN, this message translates to:
  /// **'选择目录'**
  String get settingsScreenshotChooseDirectory;

  /// No description provided for @settingsScreenshotChangeDirectory.
  ///
  /// In zh_CN, this message translates to:
  /// **'更换目录'**
  String get settingsScreenshotChangeDirectory;

  /// No description provided for @settingsScreenshotSetAsCurrentDirectory.
  ///
  /// In zh_CN, this message translates to:
  /// **'设为当前保存目录'**
  String get settingsScreenshotSetAsCurrentDirectory;

  /// No description provided for @settingsScreenshotNoDirectorySelected.
  ///
  /// In zh_CN, this message translates to:
  /// **'未选择目录'**
  String get settingsScreenshotNoDirectorySelected;

  /// No description provided for @settingsScreenshotCustomDirectoryUpdated.
  ///
  /// In zh_CN, this message translates to:
  /// **'已更新截图自定义目录'**
  String get settingsScreenshotCustomDirectoryUpdated;

  /// No description provided for @settingsScreenshotCustomDirectoryRecordedUnavailable.
  ///
  /// In zh_CN, this message translates to:
  /// **'目录已记录，但当前不可用'**
  String get settingsScreenshotCustomDirectoryRecordedUnavailable;

  /// No description provided for @settingsScreenshotClearCustomDirectoryTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'清除截图自定义目录'**
  String get settingsScreenshotClearCustomDirectoryTitle;

  /// No description provided for @settingsScreenshotClearCustomDirectoryContent.
  ///
  /// In zh_CN, this message translates to:
  /// **'这不会删除已经保存的截图，只会移除当前目录授权。'**
  String get settingsScreenshotClearCustomDirectoryContent;

  /// No description provided for @settingsScreenshotCustomDirectoryCleared.
  ///
  /// In zh_CN, this message translates to:
  /// **'已清除截图自定义目录'**
  String get settingsScreenshotCustomDirectoryCleared;

  /// No description provided for @settingsScreenshotCustomDirectoryActivated.
  ///
  /// In zh_CN, this message translates to:
  /// **'截图保存目录已切换为自定义目录'**
  String get settingsScreenshotCustomDirectoryActivated;

  /// No description provided for @settingsScreenshotNoDirectoryChosen.
  ///
  /// In zh_CN, this message translates to:
  /// **'还没有选择目录'**
  String get settingsScreenshotNoDirectoryChosen;

  /// No description provided for @settingsScreenshotDirectoryWritable.
  ///
  /// In zh_CN, this message translates to:
  /// **'可写入'**
  String get settingsScreenshotDirectoryWritable;

  /// No description provided for @settingsScreenshotDirectoryExpired.
  ///
  /// In zh_CN, this message translates to:
  /// **'已失效'**
  String get settingsScreenshotDirectoryExpired;

  /// No description provided for @settingsScreenshotDirectoryWriteHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'新截图将写入该目录。'**
  String get settingsScreenshotDirectoryWriteHint;

  /// No description provided for @settingsScreenshotDirectoryPickHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'选择文件夹后可作为截图保存目录。'**
  String get settingsScreenshotDirectoryPickHint;

  /// No description provided for @settingsScreenshotDirectoryExpiredHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'目录授权已经失效，需要重新选择后才能继续保存截图。'**
  String get settingsScreenshotDirectoryExpiredHint;

  /// No description provided for @settingsScreenshotClearAuthorization.
  ///
  /// In zh_CN, this message translates to:
  /// **'清除授权'**
  String get settingsScreenshotClearAuthorization;

  /// No description provided for @settingsScreenshotCurrentStatus.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前状态'**
  String get settingsScreenshotCurrentStatus;

  /// No description provided for @settingsScreenshotCustomDirectoryEnabledStatus.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前截图已经使用自定义目录保存。更换目录后，新截图会进入新目录，旧截图不会迁移。'**
  String get settingsScreenshotCustomDirectoryEnabledStatus;

  /// No description provided for @settingsScreenshotCustomDirectoryDisabledStatus.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前未启用自定义目录。'**
  String get settingsScreenshotCustomDirectoryDisabledStatus;

  /// No description provided for @detailOverviewEmpty.
  ///
  /// In zh_CN, this message translates to:
  /// **'暂无简介'**
  String get detailOverviewEmpty;

  /// No description provided for @mediaDetailsTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'文件媒体信息'**
  String get mediaDetailsTitle;

  /// No description provided for @mediaDetailsVideoSection.
  ///
  /// In zh_CN, this message translates to:
  /// **'视频'**
  String get mediaDetailsVideoSection;

  /// No description provided for @mediaDetailsAudioSection.
  ///
  /// In zh_CN, this message translates to:
  /// **'音频'**
  String get mediaDetailsAudioSection;

  /// No description provided for @mediaDetailsSubtitleSection.
  ///
  /// In zh_CN, this message translates to:
  /// **'字幕'**
  String get mediaDetailsSubtitleSection;

  /// No description provided for @mediaDetailsFieldEncoder.
  ///
  /// In zh_CN, this message translates to:
  /// **'编码器'**
  String get mediaDetailsFieldEncoder;

  /// No description provided for @mediaDetailsFieldProfile.
  ///
  /// In zh_CN, this message translates to:
  /// **'配置'**
  String get mediaDetailsFieldProfile;

  /// No description provided for @mediaDetailsFieldLevel.
  ///
  /// In zh_CN, this message translates to:
  /// **'等级'**
  String get mediaDetailsFieldLevel;

  /// No description provided for @mediaDetailsFieldResolution.
  ///
  /// In zh_CN, this message translates to:
  /// **'分辨率'**
  String get mediaDetailsFieldResolution;

  /// No description provided for @mediaDetailsFieldAspectRatio.
  ///
  /// In zh_CN, this message translates to:
  /// **'宽高比'**
  String get mediaDetailsFieldAspectRatio;

  /// No description provided for @mediaDetailsFieldInterlaced.
  ///
  /// In zh_CN, this message translates to:
  /// **'隔行扫描'**
  String get mediaDetailsFieldInterlaced;

  /// No description provided for @mediaDetailsFieldFrameRate.
  ///
  /// In zh_CN, this message translates to:
  /// **'帧率'**
  String get mediaDetailsFieldFrameRate;

  /// No description provided for @mediaDetailsFieldBitrate.
  ///
  /// In zh_CN, this message translates to:
  /// **'码率'**
  String get mediaDetailsFieldBitrate;

  /// No description provided for @mediaDetailsFieldRange.
  ///
  /// In zh_CN, this message translates to:
  /// **'视频动态范围'**
  String get mediaDetailsFieldRange;

  /// No description provided for @mediaDetailsFieldColorPrimaries.
  ///
  /// In zh_CN, this message translates to:
  /// **'色彩原色'**
  String get mediaDetailsFieldColorPrimaries;

  /// No description provided for @mediaDetailsFieldColorSpace.
  ///
  /// In zh_CN, this message translates to:
  /// **'色彩空间'**
  String get mediaDetailsFieldColorSpace;

  /// No description provided for @mediaDetailsFieldColorTransfer.
  ///
  /// In zh_CN, this message translates to:
  /// **'色彩转换'**
  String get mediaDetailsFieldColorTransfer;

  /// No description provided for @mediaDetailsFieldBitDepth.
  ///
  /// In zh_CN, this message translates to:
  /// **'位深度'**
  String get mediaDetailsFieldBitDepth;

  /// No description provided for @mediaDetailsFieldPixelFormat.
  ///
  /// In zh_CN, this message translates to:
  /// **'像素格式'**
  String get mediaDetailsFieldPixelFormat;

  /// No description provided for @mediaDetailsFieldRefs.
  ///
  /// In zh_CN, this message translates to:
  /// **'参考帧'**
  String get mediaDetailsFieldRefs;

  /// No description provided for @mediaDetailsFieldLanguage.
  ///
  /// In zh_CN, this message translates to:
  /// **'语言'**
  String get mediaDetailsFieldLanguage;

  /// No description provided for @mediaDetailsFieldChannels.
  ///
  /// In zh_CN, this message translates to:
  /// **'声道'**
  String get mediaDetailsFieldChannels;

  /// No description provided for @mediaDetailsFieldSampleRate.
  ///
  /// In zh_CN, this message translates to:
  /// **'采样率'**
  String get mediaDetailsFieldSampleRate;

  /// No description provided for @mediaDetailsFieldLayout.
  ///
  /// In zh_CN, this message translates to:
  /// **'布局'**
  String get mediaDetailsFieldLayout;

  /// No description provided for @mediaDetailsFieldDefault.
  ///
  /// In zh_CN, this message translates to:
  /// **'默认'**
  String get mediaDetailsFieldDefault;

  /// No description provided for @mediaDetailsFieldForced.
  ///
  /// In zh_CN, this message translates to:
  /// **'强制'**
  String get mediaDetailsFieldForced;

  /// No description provided for @mediaDetailsFieldExternal.
  ///
  /// In zh_CN, this message translates to:
  /// **'外部'**
  String get mediaDetailsFieldExternal;

  /// No description provided for @detailSeasonSpecial.
  ///
  /// In zh_CN, this message translates to:
  /// **'特别篇'**
  String get detailSeasonSpecial;

  /// No description provided for @detailSeasonNumber.
  ///
  /// In zh_CN, this message translates to:
  /// **'第 {number} 季'**
  String detailSeasonNumber(int number);

  /// No description provided for @detailEpisodeNumber.
  ///
  /// In zh_CN, this message translates to:
  /// **'第 {number} 集'**
  String detailEpisodeNumber(int number);

  /// No description provided for @detailSeasonEpisodeNumber.
  ///
  /// In zh_CN, this message translates to:
  /// **'第 {season} 季 第 {episode} 集'**
  String detailSeasonEpisodeNumber(int season, int episode);

  /// No description provided for @detailSpecialEpisodeNumber.
  ///
  /// In zh_CN, this message translates to:
  /// **'特别篇 第 {episode} 集'**
  String detailSpecialEpisodeNumber(int episode);

  /// No description provided for @detailNamedEpisodeNumber.
  ///
  /// In zh_CN, this message translates to:
  /// **'{title} 第 {episode} 集'**
  String detailNamedEpisodeNumber(Object title, int episode);

  /// No description provided for @detailSeasonDefault.
  ///
  /// In zh_CN, this message translates to:
  /// **'季'**
  String get detailSeasonDefault;

  /// No description provided for @detailSeasonInfoDefault.
  ///
  /// In zh_CN, this message translates to:
  /// **'季信息'**
  String get detailSeasonInfoDefault;

  /// No description provided for @detailTvSeasonCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'共 {count} 季'**
  String detailTvSeasonCount(int count);

  /// No description provided for @detailSeasonEmpty.
  ///
  /// In zh_CN, this message translates to:
  /// **'暂无季列表'**
  String get detailSeasonEmpty;

  /// No description provided for @detailEpisodeTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'选集'**
  String get detailEpisodeTitle;

  /// No description provided for @detailEpisodeEmpty.
  ///
  /// In zh_CN, this message translates to:
  /// **'暂无剧集信息'**
  String get detailEpisodeEmpty;

  /// No description provided for @detailEpisodeUnknown.
  ///
  /// In zh_CN, this message translates to:
  /// **'未知集数'**
  String get detailEpisodeUnknown;

  /// No description provided for @detailEpisodeTotal.
  ///
  /// In zh_CN, this message translates to:
  /// **'共 {count} 集'**
  String detailEpisodeTotal(int count);

  /// No description provided for @commonDetails.
  ///
  /// In zh_CN, this message translates to:
  /// **'详情'**
  String get commonDetails;

  /// No description provided for @commonLoading.
  ///
  /// In zh_CN, this message translates to:
  /// **'加载中'**
  String get commonLoading;

  /// No description provided for @detailImdbEmpty.
  ///
  /// In zh_CN, this message translates to:
  /// **'暂无 IMDB 链接'**
  String get detailImdbEmpty;

  /// No description provided for @detailImdbOpenFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'无法打开 IMDB 链接'**
  String get detailImdbOpenFailed;

  /// No description provided for @detailRatingScore.
  ///
  /// In zh_CN, this message translates to:
  /// **'{score} 分'**
  String detailRatingScore(Object score);

  /// No description provided for @commonClickTooFastRetryLater.
  ///
  /// In zh_CN, this message translates to:
  /// **'点击过快，请稍后再试'**
  String get commonClickTooFastRetryLater;

  /// No description provided for @commonOperationFailedRetryLater.
  ///
  /// In zh_CN, this message translates to:
  /// **'操作失败，请稍后重试'**
  String get commonOperationFailedRetryLater;

  /// No description provided for @actionFavoriteAdd.
  ///
  /// In zh_CN, this message translates to:
  /// **'收藏'**
  String get actionFavoriteAdd;

  /// No description provided for @actionFavoriteRemove.
  ///
  /// In zh_CN, this message translates to:
  /// **'取消收藏'**
  String get actionFavoriteRemove;

  /// No description provided for @actionFavoriteAdded.
  ///
  /// In zh_CN, this message translates to:
  /// **'已加入收藏'**
  String get actionFavoriteAdded;

  /// No description provided for @actionFavoriteRemoved.
  ///
  /// In zh_CN, this message translates to:
  /// **'已取消收藏'**
  String get actionFavoriteRemoved;

  /// No description provided for @actionMarkAsWatched.
  ///
  /// In zh_CN, this message translates to:
  /// **'标记为已观看'**
  String get actionMarkAsWatched;

  /// No description provided for @actionMarkAsUnwatched.
  ///
  /// In zh_CN, this message translates to:
  /// **'标记为未观看'**
  String get actionMarkAsUnwatched;

  /// No description provided for @actionMarkedAsWatched.
  ///
  /// In zh_CN, this message translates to:
  /// **'已标记为已观看'**
  String get actionMarkedAsWatched;

  /// No description provided for @actionMarkedAsUnwatched.
  ///
  /// In zh_CN, this message translates to:
  /// **'已标记为未观看'**
  String get actionMarkedAsUnwatched;

  /// No description provided for @detailFavoriteFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'收藏失败'**
  String get detailFavoriteFailed;

  /// No description provided for @detailUnfavoriteFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'取消收藏失败'**
  String get detailUnfavoriteFailed;

  /// No description provided for @detailMarkWatchedFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'标记为已观看失败'**
  String get detailMarkWatchedFailed;

  /// No description provided for @detailMarkUnwatchedFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'标记为未观看失败'**
  String get detailMarkUnwatchedFailed;

  /// No description provided for @detailDownloadUnavailable.
  ///
  /// In zh_CN, this message translates to:
  /// **'暂无可下载资源'**
  String get detailDownloadUnavailable;

  /// No description provided for @detailContinuePlay.
  ///
  /// In zh_CN, this message translates to:
  /// **'继续播放'**
  String get detailContinuePlay;

  /// No description provided for @detailPlay.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放'**
  String get detailPlay;

  /// No description provided for @detailOverviewTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'简介'**
  String get detailOverviewTitle;

  /// No description provided for @detailCastCrewTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'演职人员'**
  String get detailCastCrewTitle;

  /// No description provided for @detailFileInfoTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'文件信息'**
  String get detailFileInfoTitle;

  /// No description provided for @detailFileLocation.
  ///
  /// In zh_CN, this message translates to:
  /// **'文件位置'**
  String get detailFileLocation;

  /// No description provided for @detailFileSize.
  ///
  /// In zh_CN, this message translates to:
  /// **'文件大小'**
  String get detailFileSize;

  /// No description provided for @detailFileCreatedAt.
  ///
  /// In zh_CN, this message translates to:
  /// **'文件创建日期'**
  String get detailFileCreatedAt;

  /// No description provided for @detailFileAddedAt.
  ///
  /// In zh_CN, this message translates to:
  /// **'添加日期'**
  String get detailFileAddedAt;

  /// No description provided for @detailFileConvert.
  ///
  /// In zh_CN, this message translates to:
  /// **'转换'**
  String get detailFileConvert;

  /// No description provided for @detailPlaybackError.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放异常: {error}'**
  String detailPlaybackError(Object error);

  /// No description provided for @detailPlayInfoFailedWithError.
  ///
  /// In zh_CN, this message translates to:
  /// **'获取播放流失败: {error}'**
  String detailPlayInfoFailedWithError(Object error);

  /// No description provided for @detailPreparingPlayback.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在准备播放，请稍候'**
  String get detailPreparingPlayback;

  /// No description provided for @detailPlayPlaceholder.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放接口已预留'**
  String get detailPlayPlaceholder;

  /// No description provided for @detailPlayInfoFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'获取播放信息失败'**
  String get detailPlayInfoFailed;

  /// No description provided for @detailDownloadPlaceholder.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载接口已预留'**
  String get detailDownloadPlaceholder;

  /// No description provided for @detailLocalVideoInvalid.
  ///
  /// In zh_CN, this message translates to:
  /// **'本地视频文件无效'**
  String get detailLocalVideoInvalid;

  /// No description provided for @detailTmdbEmpty.
  ///
  /// In zh_CN, this message translates to:
  /// **'暂无 TMDB 链接'**
  String get detailTmdbEmpty;

  /// No description provided for @detailTmdbOpenFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'无法打开 TMDB 链接'**
  String get detailTmdbOpenFailed;

  /// No description provided for @commonOther.
  ///
  /// In zh_CN, this message translates to:
  /// **'其他'**
  String get commonOther;

  /// No description provided for @commonDurationHoursMinutes.
  ///
  /// In zh_CN, this message translates to:
  /// **'{hours} 小时 {minutes} 分钟'**
  String commonDurationHoursMinutes(int hours, int minutes);

  /// No description provided for @commonDurationMinutesSeconds.
  ///
  /// In zh_CN, this message translates to:
  /// **'{minutes} 分钟 {seconds} 秒'**
  String commonDurationMinutesSeconds(int minutes, int seconds);

  /// No description provided for @commonDurationMinutes.
  ///
  /// In zh_CN, this message translates to:
  /// **'{minutes} 分钟'**
  String commonDurationMinutes(int minutes);

  /// No description provided for @commonDurationSeconds.
  ///
  /// In zh_CN, this message translates to:
  /// **'{seconds} 秒'**
  String commonDurationSeconds(int seconds);

  /// No description provided for @downloadLoadingInfo.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在获取下载信息，请稍候'**
  String get downloadLoadingInfo;

  /// No description provided for @downloadNoResources.
  ///
  /// In zh_CN, this message translates to:
  /// **'暂无可下载资源'**
  String get downloadNoResources;

  /// No description provided for @downloadNoQuality.
  ///
  /// In zh_CN, this message translates to:
  /// **'暂无可下载清晰度'**
  String get downloadNoQuality;

  /// No description provided for @downloadSelectItem.
  ///
  /// In zh_CN, this message translates to:
  /// **'选择下载条目'**
  String get downloadSelectItem;

  /// No description provided for @downloadQuality.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载清晰度'**
  String get downloadQuality;

  /// No description provided for @downloadSelectQuality.
  ///
  /// In zh_CN, this message translates to:
  /// **'选择下载清晰度'**
  String get downloadSelectQuality;

  /// No description provided for @downloadDownload.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载'**
  String get downloadDownload;

  /// No description provided for @downloadOpenList.
  ///
  /// In zh_CN, this message translates to:
  /// **'打开下载列表'**
  String get downloadOpenList;

  /// No description provided for @downloadLoadFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'获取下载信息失败，请稍后重试'**
  String get downloadLoadFailed;

  /// No description provided for @downloadSourceQuality.
  ///
  /// In zh_CN, this message translates to:
  /// **'原画'**
  String get downloadSourceQuality;

  /// No description provided for @downloadDownloaded.
  ///
  /// In zh_CN, this message translates to:
  /// **'已下载'**
  String get downloadDownloaded;

  /// No description provided for @downloadStartedWithQuality.
  ///
  /// In zh_CN, this message translates to:
  /// **'已开始下载 {quality}'**
  String downloadStartedWithQuality(Object quality);

  /// No description provided for @downloadImportedFromCacheWithQuality.
  ///
  /// In zh_CN, this message translates to:
  /// **'已从缓存加入下载 {quality}'**
  String downloadImportedFromCacheWithQuality(Object quality);

  /// No description provided for @downloadItemDownloading.
  ///
  /// In zh_CN, this message translates to:
  /// **'该条目正在下载'**
  String get downloadItemDownloading;

  /// No description provided for @downloadItemDownloaded.
  ///
  /// In zh_CN, this message translates to:
  /// **'该条目已下载'**
  String get downloadItemDownloaded;

  /// No description provided for @downloadFailedWithError.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载失败：{error}'**
  String downloadFailedWithError(Object error);

  /// No description provided for @downloadListTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载列表'**
  String get downloadListTitle;

  /// No description provided for @trackSubtitleOff.
  ///
  /// In zh_CN, this message translates to:
  /// **'关闭字幕'**
  String get trackSubtitleOff;

  /// No description provided for @trackSubtitleNone.
  ///
  /// In zh_CN, this message translates to:
  /// **'无字幕'**
  String get trackSubtitleNone;

  /// No description provided for @trackAudioNone.
  ///
  /// In zh_CN, this message translates to:
  /// **'无音频'**
  String get trackAudioNone;

  /// No description provided for @trackSubtitleUnknownLanguage.
  ///
  /// In zh_CN, this message translates to:
  /// **'未知语言'**
  String get trackSubtitleUnknownLanguage;

  /// No description provided for @trackSubtitleDefaultSuffix.
  ///
  /// In zh_CN, this message translates to:
  /// **'默认'**
  String get trackSubtitleDefaultSuffix;

  /// No description provided for @trackSubtitleExternalSuffix.
  ///
  /// In zh_CN, this message translates to:
  /// **'外挂'**
  String get trackSubtitleExternalSuffix;

  /// No description provided for @trackSubtitleName.
  ///
  /// In zh_CN, this message translates to:
  /// **'字幕'**
  String get trackSubtitleName;

  /// No description provided for @playerSubtitleSelectTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'选择字幕'**
  String get playerSubtitleSelectTitle;

  /// No description provided for @playerAudioSelectTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'选择音频'**
  String get playerAudioSelectTitle;

  /// No description provided for @logNoExportableLogs.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前没有可导出的日志'**
  String get logNoExportableLogs;

  /// No description provided for @logTxtExported.
  ///
  /// In zh_CN, this message translates to:
  /// **'TXT 已导出到 {path}'**
  String logTxtExported(Object path);

  /// No description provided for @logExternalUnavailableExported.
  ///
  /// In zh_CN, this message translates to:
  /// **'外部存储不可用，已导出到临时目录 {path}'**
  String logExternalUnavailableExported(Object path);

  /// No description provided for @logExportFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'导出失败：{error}'**
  String logExportFailed(Object error);

  /// No description provided for @logClearTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'清空日志'**
  String get logClearTitle;

  /// No description provided for @logClearContent.
  ///
  /// In zh_CN, this message translates to:
  /// **'会移除当前已记录的报错日志，这个操作不能恢复。'**
  String get logClearContent;

  /// No description provided for @logClearConfirm.
  ///
  /// In zh_CN, this message translates to:
  /// **'清空'**
  String get logClearConfirm;

  /// No description provided for @logCleared.
  ///
  /// In zh_CN, this message translates to:
  /// **'日志已清空'**
  String get logCleared;

  /// No description provided for @logInfoTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'日志信息'**
  String get logInfoTitle;

  /// No description provided for @logErrorLogTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'报错日志'**
  String get logErrorLogTitle;

  /// No description provided for @logErrorLogDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'全局异常记录，支持导出为 TXT。'**
  String get logErrorLogDescription;

  /// No description provided for @logTotal.
  ///
  /// In zh_CN, this message translates to:
  /// **'总数'**
  String get logTotal;

  /// No description provided for @logErrors.
  ///
  /// In zh_CN, this message translates to:
  /// **'错误'**
  String get logErrors;

  /// No description provided for @logLatest.
  ///
  /// In zh_CN, this message translates to:
  /// **'最近'**
  String get logLatest;

  /// No description provided for @logNone.
  ///
  /// In zh_CN, this message translates to:
  /// **'暂无'**
  String get logNone;

  /// No description provided for @logExporting.
  ///
  /// In zh_CN, this message translates to:
  /// **'导出中...'**
  String get logExporting;

  /// No description provided for @logExportTxt.
  ///
  /// In zh_CN, this message translates to:
  /// **'导出 TXT'**
  String get logExportTxt;

  /// No description provided for @logClearing.
  ///
  /// In zh_CN, this message translates to:
  /// **'清空中...'**
  String get logClearing;

  /// No description provided for @logClearAction.
  ///
  /// In zh_CN, this message translates to:
  /// **'清空日志'**
  String get logClearAction;

  /// No description provided for @logEmptyTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'暂无报错日志'**
  String get logEmptyTitle;

  /// No description provided for @logEmptySubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'发生全局异常后将自动生成记录。'**
  String get logEmptySubtitle;

  /// No description provided for @logCollapseStack.
  ///
  /// In zh_CN, this message translates to:
  /// **'收起堆栈'**
  String get logCollapseStack;

  /// No description provided for @logExpandStack.
  ///
  /// In zh_CN, this message translates to:
  /// **'展开堆栈'**
  String get logExpandStack;

  /// No description provided for @downloadEmptyDownloaded.
  ///
  /// In zh_CN, this message translates to:
  /// **'没有已下载的影片'**
  String get downloadEmptyDownloaded;

  /// No description provided for @downloadEmptyDownloading.
  ///
  /// In zh_CN, this message translates to:
  /// **'没有下载中的影片'**
  String get downloadEmptyDownloading;

  /// No description provided for @downloadImportedLocalVideos.
  ///
  /// In zh_CN, this message translates to:
  /// **'已导入 {count} 个本地下载视频'**
  String downloadImportedLocalVideos(int count);

  /// No description provided for @downloadNoImportableVideos.
  ///
  /// In zh_CN, this message translates to:
  /// **'没有发现需要导入的视频'**
  String get downloadNoImportableVideos;

  /// No description provided for @downloadNoRecoverableFiles.
  ///
  /// In zh_CN, this message translates to:
  /// **'没有找到可恢复的下载文件'**
  String get downloadNoRecoverableFiles;

  /// No description provided for @downloadRefreshFilesFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'刷新下载文件失败'**
  String get downloadRefreshFilesFailed;

  /// No description provided for @downloadRefreshFilesTooltip.
  ///
  /// In zh_CN, this message translates to:
  /// **'刷新下载文件'**
  String get downloadRefreshFilesTooltip;

  /// No description provided for @commonEdit.
  ///
  /// In zh_CN, this message translates to:
  /// **'编辑'**
  String get commonEdit;

  /// No description provided for @commonSelectAll.
  ///
  /// In zh_CN, this message translates to:
  /// **'全选'**
  String get commonSelectAll;

  /// No description provided for @commonDeselectAll.
  ///
  /// In zh_CN, this message translates to:
  /// **'取消全选'**
  String get commonDeselectAll;

  /// No description provided for @downloadDeleteFilesTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'删除视频文件'**
  String get downloadDeleteFilesTitle;

  /// No description provided for @downloadDeleteFilesContent.
  ///
  /// In zh_CN, this message translates to:
  /// **'确认删除所选视频文件？删除后将不可恢复。'**
  String get downloadDeleteFilesContent;

  /// No description provided for @downloadPreparingPlayback.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在准备播放，请稍候'**
  String get downloadPreparingPlayback;

  /// No description provided for @downloadLocalFileMissing.
  ///
  /// In zh_CN, this message translates to:
  /// **'本地视频文件不存在'**
  String get downloadLocalFileMissing;

  /// No description provided for @downloadDetailTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载详情'**
  String get downloadDetailTitle;

  /// No description provided for @downloadSelectedCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'已选择 {count} 项'**
  String downloadSelectedCount(int count);

  /// No description provided for @downloadVideoCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'视频 {count}'**
  String downloadVideoCount(int count);

  /// No description provided for @downloadTranscodingPercent.
  ///
  /// In zh_CN, this message translates to:
  /// **'转码中 {percent}%'**
  String downloadTranscodingPercent(int percent);

  /// No description provided for @downloadCalculating.
  ///
  /// In zh_CN, this message translates to:
  /// **'计算中'**
  String get downloadCalculating;

  /// No description provided for @downloadWaiting.
  ///
  /// In zh_CN, this message translates to:
  /// **'等待中'**
  String get downloadWaiting;

  /// No description provided for @downloadPendingGenerate.
  ///
  /// In zh_CN, this message translates to:
  /// **'待生成'**
  String get downloadPendingGenerate;

  /// No description provided for @downloadTranscoding.
  ///
  /// In zh_CN, this message translates to:
  /// **'转码中'**
  String get downloadTranscoding;

  /// No description provided for @downloadDownloading.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载中'**
  String get downloadDownloading;

  /// No description provided for @downloadCurrentStage.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前阶段'**
  String get downloadCurrentStage;

  /// No description provided for @downloadSpeed.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载速度'**
  String get downloadSpeed;

  /// No description provided for @downloadCloudTranscoding.
  ///
  /// In zh_CN, this message translates to:
  /// **'云端转码'**
  String get downloadCloudTranscoding;

  /// No description provided for @downloadEstimatedFile.
  ///
  /// In zh_CN, this message translates to:
  /// **'预计文件'**
  String get downloadEstimatedFile;

  /// No description provided for @downloadTransferredTotal.
  ///
  /// In zh_CN, this message translates to:
  /// **'已下 / 总计'**
  String get downloadTransferredTotal;

  /// No description provided for @downloadDownloadedTab.
  ///
  /// In zh_CN, this message translates to:
  /// **'已下载'**
  String get downloadDownloadedTab;

  /// No description provided for @downloadDownloadingTab.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载中'**
  String get downloadDownloadingTab;

  /// No description provided for @storageTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'储存管理'**
  String get storageTitle;

  /// No description provided for @storageRefreshTooltip.
  ///
  /// In zh_CN, this message translates to:
  /// **'刷新'**
  String get storageRefreshTooltip;

  /// No description provided for @storageAppDataDangerTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'应用数据与危险操作'**
  String get storageAppDataDangerTitle;

  /// No description provided for @storageAppDataTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'应用数据'**
  String get storageAppDataTitle;

  /// No description provided for @storageAppDataDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'这些内容通常是用户记录和个性化配置，不会和普通缓存一起清理。'**
  String get storageAppDataDescription;

  /// No description provided for @storageTotalUsage.
  ///
  /// In zh_CN, this message translates to:
  /// **'总占用'**
  String get storageTotalUsage;

  /// No description provided for @storageLastRefreshed.
  ///
  /// In zh_CN, this message translates to:
  /// **'上次刷新 {time}'**
  String storageLastRefreshed(Object time);

  /// No description provided for @storageClearSelectedCacheTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'清理选中缓存'**
  String get storageClearSelectedCacheTitle;

  /// No description provided for @storageClearSelectedCacheMessage.
  ///
  /// In zh_CN, this message translates to:
  /// **'将删除选中的播放缓存文件，删除后需要重新缓存。是否继续？'**
  String get storageClearSelectedCacheMessage;

  /// No description provided for @storageClearSelectedDownloadsTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'清理已下载文件'**
  String get storageClearSelectedDownloadsTitle;

  /// No description provided for @storageClearSelectedDownloadsMessage.
  ///
  /// In zh_CN, this message translates to:
  /// **'将删除选中的本地下载文件，删除后需要重新下载。是否继续？'**
  String get storageClearSelectedDownloadsMessage;

  /// No description provided for @storagePlaybackActiveMessage.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放中不可清理播放缓存'**
  String get storagePlaybackActiveMessage;

  /// No description provided for @storageClearFailedMessage.
  ///
  /// In zh_CN, this message translates to:
  /// **'清理失败，请稍后重试'**
  String get storageClearFailedMessage;

  /// No description provided for @storageEmptyPlaybackSelection.
  ///
  /// In zh_CN, this message translates to:
  /// **'请先勾选要清理的缓存'**
  String get storageEmptyPlaybackSelection;

  /// No description provided for @storageEmptyDownloadSelection.
  ///
  /// In zh_CN, this message translates to:
  /// **'请先勾选要清理的下载文件'**
  String get storageEmptyDownloadSelection;

  /// No description provided for @storageSelectedPlaybackCleared.
  ///
  /// In zh_CN, this message translates to:
  /// **'已清理选中的播放缓存'**
  String get storageSelectedPlaybackCleared;

  /// No description provided for @storageSelectedDownloadsCleared.
  ///
  /// In zh_CN, this message translates to:
  /// **'已清理选中的下载文件'**
  String get storageSelectedDownloadsCleared;

  /// No description provided for @storageCacheResolutionFallback.
  ///
  /// In zh_CN, this message translates to:
  /// **'缓存'**
  String get storageCacheResolutionFallback;

  /// No description provided for @storageCacheVideoFallback.
  ///
  /// In zh_CN, this message translates to:
  /// **'缓存视频'**
  String get storageCacheVideoFallback;

  /// No description provided for @storageSeasonGroupTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'{seriesTitle} 第{season}季'**
  String storageSeasonGroupTitle(Object seriesTitle, int season);

  /// No description provided for @storageSpecialGroupTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'{seriesTitle} 特别篇'**
  String storageSpecialGroupTitle(Object seriesTitle);

  /// No description provided for @storagePromoteConverted.
  ///
  /// In zh_CN, this message translates to:
  /// **'已转为下载 {count} 项'**
  String storagePromoteConverted(int count);

  /// No description provided for @storagePromoteExisting.
  ///
  /// In zh_CN, this message translates to:
  /// **'已有下载 {count} 项'**
  String storagePromoteExisting(int count);

  /// No description provided for @storagePromoteUnavailable.
  ///
  /// In zh_CN, this message translates to:
  /// **'不可转换 {count} 项'**
  String storagePromoteUnavailable(int count);

  /// No description provided for @storageNoConvertibleCache.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前没有可转换的完整缓存'**
  String get storageNoConvertibleCache;

  /// No description provided for @storageClearItemTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'清理{title}'**
  String storageClearItemTitle(Object title);

  /// No description provided for @storageClearItemMessage.
  ///
  /// In zh_CN, this message translates to:
  /// **'将清理{title}，对应文件会被删除。是否继续？'**
  String storageClearItemMessage(Object title);

  /// No description provided for @storageClearItemSuccess.
  ///
  /// In zh_CN, this message translates to:
  /// **'{title}已清理'**
  String storageClearItemSuccess(Object title);

  /// No description provided for @storageClearItemRestricted.
  ///
  /// In zh_CN, this message translates to:
  /// **'{title}已部分清理，公共目录未授权'**
  String storageClearItemRestricted(Object title);

  /// No description provided for @storageActionCompleted.
  ///
  /// In zh_CN, this message translates to:
  /// **'{title}已完成'**
  String storageActionCompleted(Object title);

  /// No description provided for @storageActionFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'{title}失败，请稍后重试'**
  String storageActionFailed(Object title);

  /// No description provided for @storageClearBookmarksTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'清空书签'**
  String get storageClearBookmarksTitle;

  /// No description provided for @storageClearBookmarksSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'仅删除播放书签记录'**
  String get storageClearBookmarksSubtitle;

  /// No description provided for @storageClearBookmarksMessage.
  ///
  /// In zh_CN, this message translates to:
  /// **'将删除全部播放书签，此操作不可恢复。'**
  String get storageClearBookmarksMessage;

  /// No description provided for @storageClearSavedThemesTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'清空已保存主题'**
  String get storageClearSavedThemesTitle;

  /// No description provided for @storageClearSavedThemesSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'保留当前自定义配置'**
  String get storageClearSavedThemesSubtitle;

  /// No description provided for @storageClearSavedThemesMessage.
  ///
  /// In zh_CN, this message translates to:
  /// **'将删除已保存主题，但不会影响当前自定义配置。'**
  String get storageClearSavedThemesMessage;

  /// No description provided for @storageClearDynamicThemeTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'清空动态取色缓存'**
  String get storageClearDynamicThemeTitle;

  /// No description provided for @storageClearDynamicThemeSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'下次进入详情页会重新为图片取色'**
  String get storageClearDynamicThemeSubtitle;

  /// No description provided for @storageClearDynamicThemeMessage.
  ///
  /// In zh_CN, this message translates to:
  /// **'将删除本地保存的动态取色结果，之后再次进入详情页时会重新采样取色。'**
  String get storageClearDynamicThemeMessage;

  /// No description provided for @storageClearDanmakuSourcesTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'清空弹幕来源'**
  String get storageClearDanmakuSourcesTitle;

  /// No description provided for @storageClearDanmakuSourcesSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'删除已保存的弹幕来源记录'**
  String get storageClearDanmakuSourcesSubtitle;

  /// No description provided for @storageClearDanmakuSourcesMessage.
  ///
  /// In zh_CN, this message translates to:
  /// **'将删除已保存的弹幕来源记录。'**
  String get storageClearDanmakuSourcesMessage;

  /// No description provided for @storageClearLoginHistoryTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'清空登录历史'**
  String get storageClearLoginHistoryTitle;

  /// No description provided for @storageClearLoginHistorySubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'不会退出当前会话'**
  String get storageClearLoginHistorySubtitle;

  /// No description provided for @storageClearLoginHistoryMessage.
  ///
  /// In zh_CN, this message translates to:
  /// **'将删除历史登录记录，不会退出当前登录。'**
  String get storageClearLoginHistoryMessage;

  /// No description provided for @storageResetSettingsTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'重置设置'**
  String get storageResetSettingsTitle;

  /// No description provided for @storageResetSettingsSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'主题、播放器、截图、弹幕与平行窗口设置'**
  String get storageResetSettingsSubtitle;

  /// No description provided for @storageResetSettingsMessage.
  ///
  /// In zh_CN, this message translates to:
  /// **'将重置主题、播放器、截图、弹幕和平行窗口设置，不会清理缓存和用户文件。'**
  String get storageResetSettingsMessage;

  /// No description provided for @storageTotal.
  ///
  /// In zh_CN, this message translates to:
  /// **'总计'**
  String get storageTotal;

  /// No description provided for @storageNoUsageData.
  ///
  /// In zh_CN, this message translates to:
  /// **'暂无占用数据'**
  String get storageNoUsageData;

  /// No description provided for @storageUsageCategory.
  ///
  /// In zh_CN, this message translates to:
  /// **'占用分类'**
  String get storageUsageCategory;

  /// No description provided for @storageCategoryDetails.
  ///
  /// In zh_CN, this message translates to:
  /// **'分类详情'**
  String get storageCategoryDetails;

  /// No description provided for @storagePlaybackFiles.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放缓存'**
  String get storagePlaybackFiles;

  /// No description provided for @storageDownloadFiles.
  ///
  /// In zh_CN, this message translates to:
  /// **'下载文件'**
  String get storageDownloadFiles;

  /// No description provided for @storagePromoteSelected.
  ///
  /// In zh_CN, this message translates to:
  /// **'转为下载 ({count})'**
  String storagePromoteSelected(int count);

  /// No description provided for @storageClearSelected.
  ///
  /// In zh_CN, this message translates to:
  /// **'清理选中 ({count})'**
  String storageClearSelected(int count);

  /// No description provided for @storageNoPlaybackCache.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前没有可清理的播放缓存。'**
  String get storageNoPlaybackCache;

  /// No description provided for @storageNoDownloadFiles.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前没有可查看的本地下载文件。'**
  String get storageNoDownloadFiles;

  /// No description provided for @storageCompleteCache.
  ///
  /// In zh_CN, this message translates to:
  /// **'完整缓存'**
  String get storageCompleteCache;

  /// No description provided for @storageIncompleteCache.
  ///
  /// In zh_CN, this message translates to:
  /// **'未完整缓存'**
  String get storageIncompleteCache;

  /// No description provided for @storageCompletedCache.
  ///
  /// In zh_CN, this message translates to:
  /// **'已完整缓存'**
  String get storageCompletedCache;

  /// No description provided for @storageEnterManagement.
  ///
  /// In zh_CN, this message translates to:
  /// **'进入管理'**
  String get storageEnterManagement;

  /// No description provided for @storageEstimated.
  ///
  /// In zh_CN, this message translates to:
  /// **'估算'**
  String get storageEstimated;

  /// No description provided for @storageRestricted.
  ///
  /// In zh_CN, this message translates to:
  /// **'权限受限'**
  String get storageRestricted;

  /// No description provided for @commonApply.
  ///
  /// In zh_CN, this message translates to:
  /// **'应用'**
  String get commonApply;

  /// No description provided for @commonAll.
  ///
  /// In zh_CN, this message translates to:
  /// **'全部'**
  String get commonAll;

  /// No description provided for @commonAscending.
  ///
  /// In zh_CN, this message translates to:
  /// **'升序'**
  String get commonAscending;

  /// No description provided for @commonDescending.
  ///
  /// In zh_CN, this message translates to:
  /// **'降序'**
  String get commonDescending;

  /// No description provided for @screenshotGalleryTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'截图图库'**
  String get screenshotGalleryTitle;

  /// No description provided for @screenshotSelectedCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'已选中 {count} 张'**
  String screenshotSelectedCount(int count);

  /// No description provided for @screenshotUnknownResolution.
  ///
  /// In zh_CN, this message translates to:
  /// **'未知分辨率'**
  String get screenshotUnknownResolution;

  /// No description provided for @screenshotDeleteTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'删除截图'**
  String get screenshotDeleteTitle;

  /// No description provided for @screenshotDeleteContent.
  ///
  /// In zh_CN, this message translates to:
  /// **'将删除选中的 {count} 张截图，删除后无法恢复。'**
  String screenshotDeleteContent(int count);

  /// No description provided for @screenshotDeletedCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'已删除 {count} 张截图'**
  String screenshotDeletedCount(int count);

  /// No description provided for @screenshotDeleteNone.
  ///
  /// In zh_CN, this message translates to:
  /// **'没有删除任何截图'**
  String get screenshotDeleteNone;

  /// No description provided for @screenshotSourcePictures.
  ///
  /// In zh_CN, this message translates to:
  /// **'系统相册'**
  String get screenshotSourcePictures;

  /// No description provided for @screenshotSourceDcim.
  ///
  /// In zh_CN, this message translates to:
  /// **'相机目录'**
  String get screenshotSourceDcim;

  /// No description provided for @screenshotSourceApp.
  ///
  /// In zh_CN, this message translates to:
  /// **'应用目录'**
  String get screenshotSourceApp;

  /// No description provided for @screenshotSourceCustom.
  ///
  /// In zh_CN, this message translates to:
  /// **'自定义目录'**
  String get screenshotSourceCustom;

  /// No description provided for @screenshotSearchTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'搜索截图'**
  String get screenshotSearchTitle;

  /// No description provided for @screenshotSearchHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'输入截图名、目录或来源'**
  String get screenshotSearchHint;

  /// No description provided for @screenshotClearSearch.
  ///
  /// In zh_CN, this message translates to:
  /// **'清空搜索'**
  String get screenshotClearSearch;

  /// No description provided for @screenshotFilterSortTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'筛选与排序'**
  String get screenshotFilterSortTitle;

  /// No description provided for @screenshotSourceFilter.
  ///
  /// In zh_CN, this message translates to:
  /// **'来源筛选'**
  String get screenshotSourceFilter;

  /// No description provided for @screenshotSortStandard.
  ///
  /// In zh_CN, this message translates to:
  /// **'排序标准'**
  String get screenshotSortStandard;

  /// No description provided for @screenshotCurrentSortGroup.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前按 {field}{direction}分组'**
  String screenshotCurrentSortGroup(Object field, Object direction);

  /// No description provided for @screenshotSortDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'支持多级排序，排在最上面的规则优先级最高，页面分组也按它展示。'**
  String get screenshotSortDescription;

  /// No description provided for @screenshotAddSort.
  ///
  /// In zh_CN, this message translates to:
  /// **'添加排序'**
  String get screenshotAddSort;

  /// No description provided for @screenshotApplySort.
  ///
  /// In zh_CN, this message translates to:
  /// **'应用排序'**
  String get screenshotApplySort;

  /// No description provided for @screenshotMoveUpPriority.
  ///
  /// In zh_CN, this message translates to:
  /// **'上移优先级'**
  String get screenshotMoveUpPriority;

  /// No description provided for @screenshotMoveDownPriority.
  ///
  /// In zh_CN, this message translates to:
  /// **'下移优先级'**
  String get screenshotMoveDownPriority;

  /// No description provided for @screenshotDeleteRule.
  ///
  /// In zh_CN, this message translates to:
  /// **'删除规则'**
  String get screenshotDeleteRule;

  /// No description provided for @screenshotSearchEmpty.
  ///
  /// In zh_CN, this message translates to:
  /// **'没有找到和“{query}”相关的截图。'**
  String screenshotSearchEmpty(Object query);

  /// No description provided for @screenshotEmptyPictures.
  ///
  /// In zh_CN, this message translates to:
  /// **'系统相册里还没有截图。'**
  String get screenshotEmptyPictures;

  /// No description provided for @screenshotEmptyDcim.
  ///
  /// In zh_CN, this message translates to:
  /// **'相机目录里还没有截图。'**
  String get screenshotEmptyDcim;

  /// No description provided for @screenshotEmptyApp.
  ///
  /// In zh_CN, this message translates to:
  /// **'应用目录里还没有截图。'**
  String get screenshotEmptyApp;

  /// No description provided for @screenshotEmptyCustom.
  ///
  /// In zh_CN, this message translates to:
  /// **'自定义目录里还没有截图。'**
  String get screenshotEmptyCustom;

  /// No description provided for @screenshotEmptyDefault.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前没有可预览的截图。'**
  String get screenshotEmptyDefault;

  /// No description provided for @screenshotRefreshHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'下拉刷新后会重新扫描可访问目录。'**
  String get screenshotRefreshHint;

  /// No description provided for @screenshotAuthorizePublicDirectories.
  ///
  /// In zh_CN, this message translates to:
  /// **'授权公共目录'**
  String get screenshotAuthorizePublicDirectories;

  /// No description provided for @screenshotInfoCategory.
  ///
  /// In zh_CN, this message translates to:
  /// **'分类'**
  String get screenshotInfoCategory;

  /// No description provided for @screenshotInfoFormat.
  ///
  /// In zh_CN, this message translates to:
  /// **'格式'**
  String get screenshotInfoFormat;

  /// No description provided for @screenshotInfoSourceDirectory.
  ///
  /// In zh_CN, this message translates to:
  /// **'来源目录'**
  String get screenshotInfoSourceDirectory;

  /// No description provided for @screenshotInfoTakenAt.
  ///
  /// In zh_CN, this message translates to:
  /// **'拍摄时间'**
  String get screenshotInfoTakenAt;

  /// No description provided for @screenshotInfoFileSize.
  ///
  /// In zh_CN, this message translates to:
  /// **'文件大小'**
  String get screenshotInfoFileSize;

  /// No description provided for @screenshotInfoStorageType.
  ///
  /// In zh_CN, this message translates to:
  /// **'存储类型'**
  String get screenshotInfoStorageType;

  /// No description provided for @screenshotInfoResolution.
  ///
  /// In zh_CN, this message translates to:
  /// **'分辨率'**
  String get screenshotInfoResolution;

  /// No description provided for @screenshotManagedDirectory.
  ///
  /// In zh_CN, this message translates to:
  /// **'受管目录'**
  String get screenshotManagedDirectory;

  /// No description provided for @screenshotLocalFile.
  ///
  /// In zh_CN, this message translates to:
  /// **'本地文件'**
  String get screenshotLocalFile;

  /// No description provided for @screenshotLoading.
  ///
  /// In zh_CN, this message translates to:
  /// **'读取中'**
  String get screenshotLoading;

  /// No description provided for @screenshotUltraHdrNotice.
  ///
  /// In zh_CN, this message translates to:
  /// **'该文件为 Ultra HDR JPEG，应用内预览可能只显示 SDR 基底，相册中可按系统能力显示 HDR。'**
  String get screenshotUltraHdrNotice;

  /// No description provided for @screenshotFormatImage.
  ///
  /// In zh_CN, this message translates to:
  /// **'图片'**
  String get screenshotFormatImage;

  /// No description provided for @screenshotSortDate.
  ///
  /// In zh_CN, this message translates to:
  /// **'日期'**
  String get screenshotSortDate;

  /// No description provided for @screenshotSortFileName.
  ///
  /// In zh_CN, this message translates to:
  /// **'文件名'**
  String get screenshotSortFileName;

  /// No description provided for @screenshotSortSize.
  ///
  /// In zh_CN, this message translates to:
  /// **'大小'**
  String get screenshotSortSize;

  /// No description provided for @screenshotSortResolution.
  ///
  /// In zh_CN, this message translates to:
  /// **'分辨率'**
  String get screenshotSortResolution;

  /// No description provided for @screenshotSortDirectory.
  ///
  /// In zh_CN, this message translates to:
  /// **'目录'**
  String get screenshotSortDirectory;

  /// No description provided for @screenshotSortSource.
  ///
  /// In zh_CN, this message translates to:
  /// **'来源'**
  String get screenshotSortSource;

  /// No description provided for @screenshotDateToday.
  ///
  /// In zh_CN, this message translates to:
  /// **'今天'**
  String get screenshotDateToday;

  /// No description provided for @screenshotDateYesterday.
  ///
  /// In zh_CN, this message translates to:
  /// **'昨天'**
  String get screenshotDateYesterday;

  /// No description provided for @screenshotDateBeforeYesterday.
  ///
  /// In zh_CN, this message translates to:
  /// **'前天'**
  String get screenshotDateBeforeYesterday;

  /// No description provided for @screenshotMonthDay.
  ///
  /// In zh_CN, this message translates to:
  /// **'{month}月{day}日'**
  String screenshotMonthDay(int month, int day);

  /// No description provided for @screenshotSizeOver10Mb.
  ///
  /// In zh_CN, this message translates to:
  /// **'10 MB 以上'**
  String get screenshotSizeOver10Mb;

  /// No description provided for @screenshotSizeUnder100Kb.
  ///
  /// In zh_CN, this message translates to:
  /// **'100 KB 以下'**
  String get screenshotSizeUnder100Kb;

  /// No description provided for @bookmarkNoteDialogTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'书签备注'**
  String get bookmarkNoteDialogTitle;

  /// No description provided for @bookmarkNoteDialogHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'记录这个书签的作用，比如名场面、关键转折、复习点'**
  String get bookmarkNoteDialogHint;

  /// No description provided for @bookmarkNoteCollapse.
  ///
  /// In zh_CN, this message translates to:
  /// **'收起'**
  String get bookmarkNoteCollapse;

  /// No description provided for @bookmarkNoteExpand.
  ///
  /// In zh_CN, this message translates to:
  /// **'更多'**
  String get bookmarkNoteExpand;

  /// No description provided for @mpvEqEditorTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'高级均衡'**
  String get mpvEqEditorTitle;

  /// No description provided for @mpvEqEditorSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'上下拖动每个频段，细微调整整体音色。'**
  String get mpvEqEditorSubtitle;

  /// No description provided for @mpvEqReset.
  ///
  /// In zh_CN, this message translates to:
  /// **'归零'**
  String get mpvEqReset;

  /// No description provided for @themePresetMidnightSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'深夜影院感，层次稳重'**
  String get themePresetMidnightSubtitle;

  /// No description provided for @themePresetOceanSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'冷海风格，信息感更强'**
  String get themePresetOceanSubtitle;

  /// No description provided for @themePresetForestSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'自然绿调，观感更柔和'**
  String get themePresetForestSubtitle;

  /// No description provided for @themePresetGraphiteSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'中性石墨，适合长期使用'**
  String get themePresetGraphiteSubtitle;

  /// No description provided for @themePresetSunsetSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'暖调落日，氛围更明显'**
  String get themePresetSunsetSubtitle;

  /// No description provided for @themePresetAuroraSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'清亮极光，更偏轻快科技感'**
  String get themePresetAuroraSubtitle;

  /// No description provided for @themePresetLatteSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'奶白纸感，适合亮背景偏好'**
  String get themePresetLatteSubtitle;

  /// No description provided for @themeAccentBlue.
  ///
  /// In zh_CN, this message translates to:
  /// **'星蓝'**
  String get themeAccentBlue;

  /// No description provided for @themeAccentCyan.
  ///
  /// In zh_CN, this message translates to:
  /// **'冰青'**
  String get themeAccentCyan;

  /// No description provided for @themeAccentGreen.
  ///
  /// In zh_CN, this message translates to:
  /// **'松绿'**
  String get themeAccentGreen;

  /// No description provided for @themeAccentAmber.
  ///
  /// In zh_CN, this message translates to:
  /// **'琥珀'**
  String get themeAccentAmber;

  /// No description provided for @themeAccentRose.
  ///
  /// In zh_CN, this message translates to:
  /// **'赤霓'**
  String get themeAccentRose;

  /// No description provided for @themeAccentCoral.
  ///
  /// In zh_CN, this message translates to:
  /// **'珊瑚'**
  String get themeAccentCoral;

  /// No description provided for @themeAccentIndigo.
  ///
  /// In zh_CN, this message translates to:
  /// **'靛青'**
  String get themeAccentIndigo;

  /// No description provided for @themeAccentMint.
  ///
  /// In zh_CN, this message translates to:
  /// **'薄荷'**
  String get themeAccentMint;

  /// No description provided for @themeBackgroundNight.
  ///
  /// In zh_CN, this message translates to:
  /// **'夜幕'**
  String get themeBackgroundNight;

  /// No description provided for @themeBackgroundSlate.
  ///
  /// In zh_CN, this message translates to:
  /// **'石墨'**
  String get themeBackgroundSlate;

  /// No description provided for @themeBackgroundOcean.
  ///
  /// In zh_CN, this message translates to:
  /// **'深海'**
  String get themeBackgroundOcean;

  /// No description provided for @themeBackgroundMoss.
  ///
  /// In zh_CN, this message translates to:
  /// **'苔绿'**
  String get themeBackgroundMoss;

  /// No description provided for @themeBackgroundEmber.
  ///
  /// In zh_CN, this message translates to:
  /// **'余烬'**
  String get themeBackgroundEmber;

  /// No description provided for @themeBackgroundPearl.
  ///
  /// In zh_CN, this message translates to:
  /// **'珠雾'**
  String get themeBackgroundPearl;

  /// No description provided for @themeBackgroundLinen.
  ///
  /// In zh_CN, this message translates to:
  /// **'亚麻'**
  String get themeBackgroundLinen;

  /// No description provided for @themeBackgroundIvory.
  ///
  /// In zh_CN, this message translates to:
  /// **'奶白'**
  String get themeBackgroundIvory;

  /// No description provided for @themeDynamicModeOff.
  ///
  /// In zh_CN, this message translates to:
  /// **'关闭'**
  String get themeDynamicModeOff;

  /// No description provided for @themeDynamicModeDetailsAndPeople.
  ///
  /// In zh_CN, this message translates to:
  /// **'详情页和人物页'**
  String get themeDynamicModeDetailsAndPeople;

  /// No description provided for @themeDynamicIntensitySubtle.
  ///
  /// In zh_CN, this message translates to:
  /// **'轻柔'**
  String get themeDynamicIntensitySubtle;

  /// No description provided for @themeDynamicIntensityMedium.
  ///
  /// In zh_CN, this message translates to:
  /// **'中度'**
  String get themeDynamicIntensityMedium;

  /// No description provided for @themeDynamicIntensityVivid.
  ///
  /// In zh_CN, this message translates to:
  /// **'鲜明'**
  String get themeDynamicIntensityVivid;

  /// No description provided for @themeDynamicIntensityAdvanced.
  ///
  /// In zh_CN, this message translates to:
  /// **'高级'**
  String get themeDynamicIntensityAdvanced;

  /// No description provided for @themeDynamicBehaviorSubtle.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前页轻量取色，按钮和边框会跟随变化'**
  String get themeDynamicBehaviorSubtle;

  /// No description provided for @themeDynamicBehaviorMedium.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前页完整取色，推荐'**
  String get themeDynamicBehaviorMedium;

  /// No description provided for @themeDynamicBehaviorVivid.
  ///
  /// In zh_CN, this message translates to:
  /// **'高级取色，普通页面流可联动主屏'**
  String get themeDynamicBehaviorVivid;

  /// No description provided for @themeCurrentCustomTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前自定义'**
  String get themeCurrentCustomTitle;

  /// No description provided for @themeCurrentCustomSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'手动调整后的当前配方'**
  String get themeCurrentCustomSubtitle;

  /// No description provided for @themeSavedDefaultSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'已保存主题'**
  String get themeSavedDefaultSubtitle;

  /// No description provided for @themeColorHue.
  ///
  /// In zh_CN, this message translates to:
  /// **'色相'**
  String get themeColorHue;

  /// No description provided for @themeColorSaturation.
  ///
  /// In zh_CN, this message translates to:
  /// **'饱和度'**
  String get themeColorSaturation;

  /// No description provided for @themeColorValue.
  ///
  /// In zh_CN, this message translates to:
  /// **'明度'**
  String get themeColorValue;

  /// No description provided for @themeQuickColors.
  ///
  /// In zh_CN, this message translates to:
  /// **'快速颜色'**
  String get themeQuickColors;

  /// No description provided for @themePreviewCurrentAppearance.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前外观'**
  String get themePreviewCurrentAppearance;

  /// No description provided for @themePreviewPrimaryButton.
  ///
  /// In zh_CN, this message translates to:
  /// **'主按钮'**
  String get themePreviewPrimaryButton;

  /// No description provided for @themePreviewSelectedTab.
  ///
  /// In zh_CN, this message translates to:
  /// **'选中标签'**
  String get themePreviewSelectedTab;

  /// No description provided for @themePreviewMore.
  ///
  /// In zh_CN, this message translates to:
  /// **'更多'**
  String get themePreviewMore;

  /// No description provided for @themeSamplePage.
  ///
  /// In zh_CN, this message translates to:
  /// **'页面'**
  String get themeSamplePage;

  /// No description provided for @themeSampleCard.
  ///
  /// In zh_CN, this message translates to:
  /// **'卡片'**
  String get themeSampleCard;

  /// No description provided for @themeSampleBottomBar.
  ///
  /// In zh_CN, this message translates to:
  /// **'底栏'**
  String get themeSampleBottomBar;

  /// No description provided for @themeSampleContinuePlay.
  ///
  /// In zh_CN, this message translates to:
  /// **'继续播放'**
  String get themeSampleContinuePlay;

  /// No description provided for @themeSampleSecondaryAction.
  ///
  /// In zh_CN, this message translates to:
  /// **'次要操作'**
  String get themeSampleSecondaryAction;

  /// No description provided for @themeSampleSelected.
  ///
  /// In zh_CN, this message translates to:
  /// **'已选中'**
  String get themeSampleSelected;

  /// No description provided for @themeSampleUnselected.
  ///
  /// In zh_CN, this message translates to:
  /// **'未选中'**
  String get themeSampleUnselected;

  /// No description provided for @themeSampleViewDetails.
  ///
  /// In zh_CN, this message translates to:
  /// **'查看详情'**
  String get themeSampleViewDetails;

  /// No description provided for @themeFixedSectionTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'固定主题'**
  String get themeFixedSectionTitle;

  /// No description provided for @themeFixedSectionSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'官方预设，切换后立即作为全局主题生效。'**
  String get themeFixedSectionSubtitle;

  /// No description provided for @themeCustomSectionSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'自定义配色与已保存主题管理。'**
  String get themeCustomSectionSubtitle;

  /// No description provided for @themeCurrentCustomCardSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'编辑颜色分类与当前配方。'**
  String get themeCurrentCustomCardSubtitle;

  /// No description provided for @themeNoSavedThemesTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'还没有已保存主题'**
  String get themeNoSavedThemesTitle;

  /// No description provided for @themeNoSavedThemesSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'可在详情页更多菜单中保存当前主题。'**
  String get themeNoSavedThemesSubtitle;

  /// No description provided for @themeCustomBaseName.
  ///
  /// In zh_CN, this message translates to:
  /// **'自定义主题'**
  String get themeCustomBaseName;

  /// No description provided for @themeCustomRecipePageSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前自定义配方，可按颜色分类编辑并另存为自定义主题。'**
  String get themeCustomRecipePageSubtitle;

  /// No description provided for @themeCustomLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'自定义'**
  String get themeCustomLabel;

  /// No description provided for @themePaletteButton.
  ///
  /// In zh_CN, this message translates to:
  /// **'调色盘'**
  String get themePaletteButton;

  /// No description provided for @themeBackgroundControlTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'背景主色'**
  String get themeBackgroundControlTitle;

  /// No description provided for @themeBackgroundControlSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'控制页面底色、卡片层级、导航栏和整体氛围基调。'**
  String get themeBackgroundControlSubtitle;

  /// No description provided for @themeCustomBackgroundPickerTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'自定义背景色'**
  String get themeCustomBackgroundPickerTitle;

  /// No description provided for @themeAccentControlTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'主操作色'**
  String get themeAccentControlTitle;

  /// No description provided for @themeAccentControlSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'控制主按钮、进度条、确认动作和主要强调元素。'**
  String get themeAccentControlSubtitle;

  /// No description provided for @themeCustomAccentPickerTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'自定义主操作色'**
  String get themeCustomAccentPickerTitle;

  /// No description provided for @themeSelectionControlTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'选中色'**
  String get themeSelectionControlTitle;

  /// No description provided for @themeSelectionControlSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'控制选中态、边框高亮和标签状态。'**
  String get themeSelectionControlSubtitle;

  /// No description provided for @themeCustomSelectionPickerTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'自定义选中色'**
  String get themeCustomSelectionPickerTitle;

  /// No description provided for @themeLinkControlTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'链接高亮色'**
  String get themeLinkControlTitle;

  /// No description provided for @themeLinkControlSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'控制“更多”、跳转文本和轻量提示的强调色。'**
  String get themeLinkControlSubtitle;

  /// No description provided for @themeCustomLinkPickerTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'自定义链接色'**
  String get themeCustomLinkPickerTitle;

  /// No description provided for @themeRecipePresetLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'预设'**
  String get themeRecipePresetLabel;

  /// No description provided for @themeRecipeBackgroundLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'背景'**
  String get themeRecipeBackgroundLabel;

  /// No description provided for @themeRecipeAccentLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'主操作'**
  String get themeRecipeAccentLabel;

  /// No description provided for @themeRecipeSelectionLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'选中色'**
  String get themeRecipeSelectionLabel;

  /// No description provided for @themeRecipeLinkLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'链接色'**
  String get themeRecipeLinkLabel;

  /// No description provided for @themeRecipeCurrentTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前配方'**
  String get themeRecipeCurrentTitle;

  /// No description provided for @themeDynamicTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'动态取色主题'**
  String get themeDynamicTitle;

  /// No description provided for @themeDynamicSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'详情页和人物页可基于海报临时取色，退出后恢复当前主题。'**
  String get themeDynamicSubtitle;

  /// No description provided for @themeDynamicScopeDetailsAndPeople.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前范围: 详情页和人物页'**
  String get themeDynamicScopeDetailsAndPeople;

  /// No description provided for @themeDynamicScopeOff.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前范围: 已关闭'**
  String get themeDynamicScopeOff;

  /// No description provided for @themeDynamicDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'控制背景主色、面板层级、桥接渐变与环境色；按钮和链接保持固定颜色。'**
  String get themeDynamicDescription;

  /// No description provided for @themeDynamicDisabled.
  ///
  /// In zh_CN, this message translates to:
  /// **'详情页取色已关闭'**
  String get themeDynamicDisabled;

  /// No description provided for @themeDynamicPlayerNote.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放态不覆盖主屏主题；高级强度会联动普通页面。'**
  String get themeDynamicPlayerNote;

  /// No description provided for @mpvEqAllBandsReset.
  ///
  /// In zh_CN, this message translates to:
  /// **'已归零所有 EQ 频段'**
  String get mpvEqAllBandsReset;

  /// No description provided for @mpvEqPresetApplied.
  ///
  /// In zh_CN, this message translates to:
  /// **'已套用预设: {name}'**
  String mpvEqPresetApplied(Object name);

  /// No description provided for @mpvEqPresetSaved.
  ///
  /// In zh_CN, this message translates to:
  /// **'已保存 EQ 预设'**
  String get mpvEqPresetSaved;

  /// No description provided for @mpvEqPresetDeleted.
  ///
  /// In zh_CN, this message translates to:
  /// **'已删除预设: {name}'**
  String mpvEqPresetDeleted(Object name);

  /// No description provided for @mpvEqSavePresetTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'保存 EQ 预设'**
  String get mpvEqSavePresetTitle;

  /// No description provided for @mpvEqSavePresetHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'例如: 夜间对白 / 动漫人声'**
  String get mpvEqSavePresetHint;

  /// No description provided for @mpvEqMyPresetsTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'我的预设'**
  String get mpvEqMyPresetsTitle;

  /// No description provided for @mpvEqMyPresetsSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'把当前频段组合保存成多套预设，后面一键套用。'**
  String get mpvEqMyPresetsSubtitle;

  /// No description provided for @mpvEqSaveCurrent.
  ///
  /// In zh_CN, this message translates to:
  /// **'保存当前'**
  String get mpvEqSaveCurrent;

  /// No description provided for @mpvEqEmptyPresets.
  ///
  /// In zh_CN, this message translates to:
  /// **'还没有自定义 EQ 预设，调好以后可以直接保存。'**
  String get mpvEqEmptyPresets;

  /// No description provided for @mpvEqSummaryNeutral.
  ///
  /// In zh_CN, this message translates to:
  /// **'全部频段保持 0 dB。'**
  String get mpvEqSummaryNeutral;

  /// No description provided for @mpvEqApply.
  ///
  /// In zh_CN, this message translates to:
  /// **'套用'**
  String get mpvEqApply;

  /// No description provided for @homeTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'首页'**
  String get homeTitle;

  /// No description provided for @homeContinueWatching.
  ///
  /// In zh_CN, this message translates to:
  /// **'继续观看'**
  String get homeContinueWatching;

  /// No description provided for @favoriteTabEpisodes.
  ///
  /// In zh_CN, this message translates to:
  /// **'剧集'**
  String get favoriteTabEpisodes;

  /// No description provided for @favoriteTabPeople.
  ///
  /// In zh_CN, this message translates to:
  /// **'人物'**
  String get favoriteTabPeople;

  /// No description provided for @homeActionViewDetail.
  ///
  /// In zh_CN, this message translates to:
  /// **'查看影片详情'**
  String get homeActionViewDetail;

  /// No description provided for @homeActionRestartPlayback.
  ///
  /// In zh_CN, this message translates to:
  /// **'从头开始播放'**
  String get homeActionRestartPlayback;

  /// No description provided for @homeActionRemoveFromContinue.
  ///
  /// In zh_CN, this message translates to:
  /// **'从“继续观看”中移除'**
  String get homeActionRemoveFromContinue;

  /// No description provided for @homeRemovedFromContinue.
  ///
  /// In zh_CN, this message translates to:
  /// **'已从继续观看中移除'**
  String get homeRemovedFromContinue;

  /// No description provided for @homeLoginRequired.
  ///
  /// In zh_CN, this message translates to:
  /// **'请先到“设置”页登录 NAS，再返回影视页加载内容。'**
  String get homeLoginRequired;

  /// No description provided for @parallelWindowTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'平行窗口设置'**
  String get parallelWindowTitle;

  /// No description provided for @parallelWindowEnableTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'启用平行窗口'**
  String get parallelWindowEnableTitle;

  /// No description provided for @parallelWindowEnableSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'开启后，大屏设备的二级页面优先在副屏展开；关闭后使用单屏导航。'**
  String get parallelWindowEnableSubtitle;

  /// No description provided for @parallelWindowPrimarySideTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'主屏位置'**
  String get parallelWindowPrimarySideTitle;

  /// No description provided for @parallelWindowPrimaryLeftTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'左侧主屏'**
  String get parallelWindowPrimaryLeftTitle;

  /// No description provided for @parallelWindowPrimaryLeftSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'默认首页在左，右侧展开详情或设置。'**
  String get parallelWindowPrimaryLeftSubtitle;

  /// No description provided for @parallelWindowPrimaryRightTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'右侧主屏'**
  String get parallelWindowPrimaryRightTitle;

  /// No description provided for @parallelWindowPrimaryRightSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'右侧为主屏，左侧展开详情或设置。'**
  String get parallelWindowPrimaryRightSubtitle;

  /// No description provided for @parallelWindowPlaybackSideTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放主屏位置'**
  String get parallelWindowPlaybackSideTitle;

  /// No description provided for @parallelWindowPlaybackLeftTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'左侧为播放主屏'**
  String get parallelWindowPlaybackLeftTitle;

  /// No description provided for @parallelWindowPlaybackLeftSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'进入分屏播放后，左边保持播放器，右边放详情或首页。'**
  String get parallelWindowPlaybackLeftSubtitle;

  /// No description provided for @parallelWindowPlaybackRightTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'右侧为播放主屏'**
  String get parallelWindowPlaybackRightTitle;

  /// No description provided for @parallelWindowPlaybackRightSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'进入分屏播放后，右边保持播放器，左边放详情或首页。'**
  String get parallelWindowPlaybackRightSubtitle;

  /// No description provided for @parallelWindowSplitRatioTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'分屏比例'**
  String get parallelWindowSplitRatioTitle;

  /// No description provided for @parallelWindowSplitBalancedSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'默认，兼顾列表浏览和右侧详情。'**
  String get parallelWindowSplitBalancedSubtitle;

  /// No description provided for @parallelWindowSplitEqualSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'左右均衡，适合双侧并行操作。'**
  String get parallelWindowSplitEqualSubtitle;

  /// No description provided for @parallelWindowSplitFocusDetailSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'副屏更宽，适合详情和播放信息。'**
  String get parallelWindowSplitFocusDetailSubtitle;

  /// No description provided for @parallelWindowSplitFocusHomeSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'主屏稍宽，适合首页或列表操作。'**
  String get parallelWindowSplitFocusHomeSubtitle;

  /// No description provided for @parallelWindowDefaultFullscreenTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'默认播放全屏'**
  String get parallelWindowDefaultFullscreenTitle;

  /// No description provided for @parallelWindowDefaultFullscreenOnSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'点击播放后先进入全屏播放器，再由按钮切到分屏。'**
  String get parallelWindowDefaultFullscreenOnSubtitle;

  /// No description provided for @parallelWindowDefaultFullscreenOffSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'点击播放后优先保持平行窗口分屏，不先放大全屏。'**
  String get parallelWindowDefaultFullscreenOffSubtitle;

  /// No description provided for @parallelWindowImmersiveTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'平行窗口沉浸模式'**
  String get parallelWindowImmersiveTitle;

  /// No description provided for @parallelWindowImmersiveOnSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'进入平行窗口后隐藏状态栏，内容直接顶到屏幕顶部。'**
  String get parallelWindowImmersiveOnSubtitle;

  /// No description provided for @parallelWindowImmersiveOffSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'保留状态栏，使用常规分屏显示。'**
  String get parallelWindowImmersiveOffSubtitle;

  /// No description provided for @danmakuSpeedNormal.
  ///
  /// In zh_CN, this message translates to:
  /// **'正常'**
  String get danmakuSpeedNormal;

  /// No description provided for @danmakuSpeedFaster.
  ///
  /// In zh_CN, this message translates to:
  /// **'较快'**
  String get danmakuSpeedFaster;

  /// No description provided for @danmakuAreaOneTenth.
  ///
  /// In zh_CN, this message translates to:
  /// **'1/10屏'**
  String get danmakuAreaOneTenth;

  /// No description provided for @danmakuAreaOneQuarter.
  ///
  /// In zh_CN, this message translates to:
  /// **'1/4屏'**
  String get danmakuAreaOneQuarter;

  /// No description provided for @danmakuAreaThreeQuarters.
  ///
  /// In zh_CN, this message translates to:
  /// **'3/4屏'**
  String get danmakuAreaThreeQuarters;

  /// No description provided for @danmakuFontSmall.
  ///
  /// In zh_CN, this message translates to:
  /// **'较小'**
  String get danmakuFontSmall;

  /// No description provided for @danmakuFontSlightlySmall.
  ///
  /// In zh_CN, this message translates to:
  /// **'偏小'**
  String get danmakuFontSlightlySmall;

  /// No description provided for @danmakuFontStandard.
  ///
  /// In zh_CN, this message translates to:
  /// **'标准'**
  String get danmakuFontStandard;

  /// No description provided for @danmakuFontSlightlyLarge.
  ///
  /// In zh_CN, this message translates to:
  /// **'偏大'**
  String get danmakuFontSlightlyLarge;

  /// No description provided for @danmakuFontLarge.
  ///
  /// In zh_CN, this message translates to:
  /// **'较大'**
  String get danmakuFontLarge;

  /// No description provided for @danmakuSourceManagementTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'来源管理'**
  String get danmakuSourceManagementTitle;

  /// No description provided for @danmakuSourceManagementSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'统一管理网络弹幕和本地导入弹幕，支持按来源层级查看与手动删除。'**
  String get danmakuSourceManagementSubtitle;

  /// No description provided for @danmakuManagementTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'弹幕管理'**
  String get danmakuManagementTitle;

  /// No description provided for @danmakuSavedSourceCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前已保存 {count} 个弹幕来源'**
  String danmakuSavedSourceCount(int count);

  /// No description provided for @danmakuBasicSectionTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'基础'**
  String get danmakuBasicSectionTitle;

  /// No description provided for @danmakuBasicSectionSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'这些是全局默认值，不依赖当前播放页面。'**
  String get danmakuBasicSectionSubtitle;

  /// No description provided for @danmakuDefaultEnabledTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'默认开启弹幕'**
  String get danmakuDefaultEnabledTitle;

  /// No description provided for @danmakuDefaultEnabledSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'进入播放器时默认带着弹幕设置启动。'**
  String get danmakuDefaultEnabledSubtitle;

  /// No description provided for @danmakuPreviewEnabledTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'详情页预览弹幕'**
  String get danmakuPreviewEnabledTitle;

  /// No description provided for @danmakuPreviewEnabledSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'在非播放页展示弹幕预览时使用这项默认值。'**
  String get danmakuPreviewEnabledSubtitle;

  /// No description provided for @danmakuSourcePriorityTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'来源优先'**
  String get danmakuSourcePriorityTitle;

  /// No description provided for @danmakuSourcePrioritySubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'控制本地弹幕和网络弹幕同时可用时的默认选择。'**
  String get danmakuSourcePrioritySubtitle;

  /// No description provided for @danmakuPreferLocal.
  ///
  /// In zh_CN, this message translates to:
  /// **'本地优先'**
  String get danmakuPreferLocal;

  /// No description provided for @danmakuPreferNetwork.
  ///
  /// In zh_CN, this message translates to:
  /// **'网络优先'**
  String get danmakuPreferNetwork;

  /// No description provided for @danmakuDisplayStyleTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'显示样式'**
  String get danmakuDisplayStyleTitle;

  /// No description provided for @danmakuDisplayStyleSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'这些设置适合在非播放页提前调好，进播放器后直接沿用。'**
  String get danmakuDisplayStyleSubtitle;

  /// No description provided for @danmakuDisplayAreaTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'显示区域'**
  String get danmakuDisplayAreaTitle;

  /// No description provided for @danmakuOpacityTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'不透明度'**
  String get danmakuOpacityTitle;

  /// No description provided for @danmakuDensityTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'弹幕密度'**
  String get danmakuDensityTitle;

  /// No description provided for @danmakuFontSizeTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'字体大小'**
  String get danmakuFontSizeTitle;

  /// No description provided for @danmakuSpeedTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'弹幕速度'**
  String get danmakuSpeedTitle;

  /// No description provided for @danmakuTypeFilterTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'类型过滤'**
  String get danmakuTypeFilterTitle;

  /// No description provided for @danmakuTypeFilterSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'控制默认显示哪些弹幕类型。'**
  String get danmakuTypeFilterSubtitle;

  /// No description provided for @danmakuAvoidanceTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'防遮挡'**
  String get danmakuAvoidanceTitle;

  /// No description provided for @danmakuAvoidanceSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'这些默认规则更适合全局预先设定。'**
  String get danmakuAvoidanceSubtitle;

  /// No description provided for @commonRefresh.
  ///
  /// In zh_CN, this message translates to:
  /// **'刷新'**
  String get commonRefresh;

  /// No description provided for @playStatsTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放统计'**
  String get playStatsTitle;

  /// No description provided for @playStatsClearTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'清空播放统计'**
  String get playStatsClearTitle;

  /// No description provided for @playStatsClearContent.
  ///
  /// In zh_CN, this message translates to:
  /// **'这会删除本地播放历史和所有聚合统计数据。'**
  String get playStatsClearContent;

  /// No description provided for @playStatsClearTooltip.
  ///
  /// In zh_CN, this message translates to:
  /// **'清空统计'**
  String get playStatsClearTooltip;

  /// No description provided for @playStatsLoadFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'加载播放统计失败：{error}'**
  String playStatsLoadFailed(Object error);

  /// No description provided for @playStatsOverview.
  ///
  /// In zh_CN, this message translates to:
  /// **'总览'**
  String get playStatsOverview;

  /// No description provided for @playStatsTotalPlayedDuration.
  ///
  /// In zh_CN, this message translates to:
  /// **'总播放时长'**
  String get playStatsTotalPlayedDuration;

  /// No description provided for @playStatsTotalClicks.
  ///
  /// In zh_CN, this message translates to:
  /// **'总点击数'**
  String get playStatsTotalClicks;

  /// No description provided for @playStatsTotalViews.
  ///
  /// In zh_CN, this message translates to:
  /// **'总观看数'**
  String get playStatsTotalViews;

  /// No description provided for @playStatsTotalCompletedVideos.
  ///
  /// In zh_CN, this message translates to:
  /// **'总完播视频数'**
  String get playStatsTotalCompletedVideos;

  /// No description provided for @playStatsTotalCompletedSeasons.
  ///
  /// In zh_CN, this message translates to:
  /// **'总完播季数'**
  String get playStatsTotalCompletedSeasons;

  /// No description provided for @playStatsBackfillTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'后台补全'**
  String get playStatsBackfillTitle;

  /// No description provided for @playStatsBackfillRunning.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在后台补全年份、国家、类型和演职人员。'**
  String get playStatsBackfillRunning;

  /// No description provided for @playStatsAnimeList.
  ///
  /// In zh_CN, this message translates to:
  /// **'番剧列表'**
  String get playStatsAnimeList;

  /// No description provided for @playStatsNoAnimeStats.
  ///
  /// In zh_CN, this message translates to:
  /// **'还没有番剧播放统计。'**
  String get playStatsNoAnimeStats;

  /// No description provided for @playStatsUnnamedAnime.
  ///
  /// In zh_CN, this message translates to:
  /// **'未命名番剧'**
  String get playStatsUnnamedAnime;

  /// No description provided for @playStatsAnimeSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'季度 {seasonCount} / 未分组视频 {ungroupedCount}'**
  String playStatsAnimeSubtitle(int seasonCount, int ungroupedCount);

  /// No description provided for @playStatsMovieList.
  ///
  /// In zh_CN, this message translates to:
  /// **'电影列表'**
  String get playStatsMovieList;

  /// No description provided for @playStatsMovieSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'电影 / 历史 {historyCount} 条 / 观看数 {viewCount}'**
  String playStatsMovieSubtitle(int historyCount, int viewCount);

  /// No description provided for @playStatsOrphanVideos.
  ///
  /// In zh_CN, this message translates to:
  /// **'异常未归类视频'**
  String get playStatsOrphanVideos;

  /// No description provided for @playStatsOrphanSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'未匹配番剧或季度 / 历史 {historyCount} 条'**
  String playStatsOrphanSubtitle(int historyCount);

  /// No description provided for @playStatsUnlinkedHistory.
  ///
  /// In zh_CN, this message translates to:
  /// **'未关联历史'**
  String get playStatsUnlinkedHistory;

  /// No description provided for @playStatsCountItems.
  ///
  /// In zh_CN, this message translates to:
  /// **'共 {count} 条'**
  String playStatsCountItems(int count);

  /// No description provided for @playStatsYes.
  ///
  /// In zh_CN, this message translates to:
  /// **'是'**
  String get playStatsYes;

  /// No description provided for @playStatsNo.
  ///
  /// In zh_CN, this message translates to:
  /// **'否'**
  String get playStatsNo;

  /// No description provided for @playStatsDurationHours.
  ///
  /// In zh_CN, this message translates to:
  /// **'{hours} 小时 {minutes} 分钟 {seconds} 秒'**
  String playStatsDurationHours(int hours, int minutes, int seconds);

  /// No description provided for @playStatsDurationMinutes.
  ///
  /// In zh_CN, this message translates to:
  /// **'{minutes} 分钟 {seconds} 秒'**
  String playStatsDurationMinutes(int minutes, int seconds);

  /// No description provided for @playStatsDurationSeconds.
  ///
  /// In zh_CN, this message translates to:
  /// **'{seconds} 秒'**
  String playStatsDurationSeconds(int seconds);

  /// No description provided for @playStatsStartSourceManual.
  ///
  /// In zh_CN, this message translates to:
  /// **'手动打开'**
  String get playStatsStartSourceManual;

  /// No description provided for @playStatsStartSourceManualSwitch.
  ///
  /// In zh_CN, this message translates to:
  /// **'手动换集'**
  String get playStatsStartSourceManualSwitch;

  /// No description provided for @playStatsStartSourceAutoNext.
  ///
  /// In zh_CN, this message translates to:
  /// **'自动连播'**
  String get playStatsStartSourceAutoNext;

  /// No description provided for @playStatsStartSourceReplay.
  ///
  /// In zh_CN, this message translates to:
  /// **'重播'**
  String get playStatsStartSourceReplay;

  /// No description provided for @playStatsStartSourceSystemResume.
  ///
  /// In zh_CN, this message translates to:
  /// **'系统恢复'**
  String get playStatsStartSourceSystemResume;

  /// No description provided for @playStatsAnimeDetail.
  ///
  /// In zh_CN, this message translates to:
  /// **'番剧详情'**
  String get playStatsAnimeDetail;

  /// No description provided for @playStatsAnimeFields.
  ///
  /// In zh_CN, this message translates to:
  /// **'番剧字段'**
  String get playStatsAnimeFields;

  /// No description provided for @playStatsAnimeMetadata.
  ///
  /// In zh_CN, this message translates to:
  /// **'番剧元数据'**
  String get playStatsAnimeMetadata;

  /// No description provided for @playStatsSeasonList.
  ///
  /// In zh_CN, this message translates to:
  /// **'季度列表'**
  String get playStatsSeasonList;

  /// No description provided for @playStatsNoSeasonData.
  ///
  /// In zh_CN, this message translates to:
  /// **'没有季度数据。'**
  String get playStatsNoSeasonData;

  /// No description provided for @playStatsUnnamedSeason.
  ///
  /// In zh_CN, this message translates to:
  /// **'未命名季度'**
  String get playStatsUnnamedSeason;

  /// No description provided for @playStatsSeasonSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'剧集 {episodeCount} / 已完播 {completedCount}'**
  String playStatsSeasonSubtitle(int episodeCount, int completedCount);

  /// No description provided for @playStatsUngroupedVideos.
  ///
  /// In zh_CN, this message translates to:
  /// **'未归属到季度的视频'**
  String get playStatsUngroupedVideos;

  /// No description provided for @playStatsSeasonDetail.
  ///
  /// In zh_CN, this message translates to:
  /// **'季度详情'**
  String get playStatsSeasonDetail;

  /// No description provided for @playStatsSeasonFields.
  ///
  /// In zh_CN, this message translates to:
  /// **'季度字段'**
  String get playStatsSeasonFields;

  /// No description provided for @playStatsCredits.
  ///
  /// In zh_CN, this message translates to:
  /// **'演职人员'**
  String get playStatsCredits;

  /// No description provided for @playStatsEpisodeList.
  ///
  /// In zh_CN, this message translates to:
  /// **'剧集列表'**
  String get playStatsEpisodeList;

  /// No description provided for @playStatsNoEpisodeData.
  ///
  /// In zh_CN, this message translates to:
  /// **'没有剧集数据。'**
  String get playStatsNoEpisodeData;

  /// No description provided for @playStatsVideoDetail.
  ///
  /// In zh_CN, this message translates to:
  /// **'视频详情'**
  String get playStatsVideoDetail;

  /// No description provided for @playStatsMovieFields.
  ///
  /// In zh_CN, this message translates to:
  /// **'电影字段'**
  String get playStatsMovieFields;

  /// No description provided for @playStatsEpisodeFields.
  ///
  /// In zh_CN, this message translates to:
  /// **'剧集字段'**
  String get playStatsEpisodeFields;

  /// No description provided for @playStatsPlaybackHistory.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放历史'**
  String get playStatsPlaybackHistory;

  /// No description provided for @playStatsNoPlaybackHistory.
  ///
  /// In zh_CN, this message translates to:
  /// **'没有播放历史。'**
  String get playStatsNoPlaybackHistory;

  /// No description provided for @playStatsHistoryDetail.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放历史详情'**
  String get playStatsHistoryDetail;

  /// No description provided for @playStatsHistoryFields.
  ///
  /// In zh_CN, this message translates to:
  /// **'历史字段'**
  String get playStatsHistoryFields;

  /// No description provided for @playStatsUnnamedVideo.
  ///
  /// In zh_CN, this message translates to:
  /// **'未命名视频'**
  String get playStatsUnnamedVideo;

  /// No description provided for @playStatsVideoSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'历史 {historyCount} 条 / 观看数 {viewCount}'**
  String playStatsVideoSubtitle(int historyCount, int viewCount);

  /// No description provided for @playStatsHistoryEntrySubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'{startedAt} / 观看 {watchedDuration} / 完播 {completed}'**
  String playStatsHistoryEntrySubtitle(
    Object startedAt,
    Object watchedDuration,
    Object completed,
  );

  /// No description provided for @playStatsNoCreditSnapshot.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前没有记录到演职人员快照。'**
  String get playStatsNoCreditSnapshot;

  /// No description provided for @playStatsPageIndicator.
  ///
  /// In zh_CN, this message translates to:
  /// **'第 {currentPage} 页 / 共 {pageCount} 页'**
  String playStatsPageIndicator(int currentPage, int pageCount);

  /// No description provided for @playStatsPreviousPage.
  ///
  /// In zh_CN, this message translates to:
  /// **'上一页'**
  String get playStatsPreviousPage;

  /// No description provided for @playStatsNextPage.
  ///
  /// In zh_CN, this message translates to:
  /// **'下一页'**
  String get playStatsNextPage;

  /// No description provided for @playStatsFieldAnimeId.
  ///
  /// In zh_CN, this message translates to:
  /// **'番剧 ID'**
  String get playStatsFieldAnimeId;

  /// No description provided for @playStatsFieldTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'标题'**
  String get playStatsFieldTitle;

  /// No description provided for @playStatsFieldClickCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'点击数'**
  String get playStatsFieldClickCount;

  /// No description provided for @playStatsFieldViewCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'观看数'**
  String get playStatsFieldViewCount;

  /// No description provided for @playStatsFieldTotalPlayedDuration.
  ///
  /// In zh_CN, this message translates to:
  /// **'累计播放时长'**
  String get playStatsFieldTotalPlayedDuration;

  /// No description provided for @playStatsFieldForwardSeekCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'快进次数'**
  String get playStatsFieldForwardSeekCount;

  /// No description provided for @playStatsFieldBackwardSeekCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'回退次数'**
  String get playStatsFieldBackwardSeekCount;

  /// No description provided for @playStatsFieldWatchedEpisodeCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'已观看正片集数'**
  String get playStatsFieldWatchedEpisodeCount;

  /// No description provided for @playStatsFieldCompletedEpisodeCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'已完播正片集数'**
  String get playStatsFieldCompletedEpisodeCount;

  /// No description provided for @playStatsFieldCompletedSeasonCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'已完播季数'**
  String get playStatsFieldCompletedSeasonCount;

  /// No description provided for @playStatsFieldLastPlayedAt.
  ///
  /// In zh_CN, this message translates to:
  /// **'上次播放时间'**
  String get playStatsFieldLastPlayedAt;

  /// No description provided for @playStatsFieldYear.
  ///
  /// In zh_CN, this message translates to:
  /// **'年份'**
  String get playStatsFieldYear;

  /// No description provided for @playStatsFieldCountryFirstValue.
  ///
  /// In zh_CN, this message translates to:
  /// **'国家首值'**
  String get playStatsFieldCountryFirstValue;

  /// No description provided for @playStatsFieldCountryCodes.
  ///
  /// In zh_CN, this message translates to:
  /// **'国家地区代码'**
  String get playStatsFieldCountryCodes;

  /// No description provided for @playStatsFieldCountryNames.
  ///
  /// In zh_CN, this message translates to:
  /// **'国家地区中文'**
  String get playStatsFieldCountryNames;

  /// No description provided for @playStatsFieldGenreIds.
  ///
  /// In zh_CN, this message translates to:
  /// **'类型 ID'**
  String get playStatsFieldGenreIds;

  /// No description provided for @playStatsFieldGenreNames.
  ///
  /// In zh_CN, this message translates to:
  /// **'类型中文'**
  String get playStatsFieldGenreNames;

  /// No description provided for @playStatsFieldSeasonId.
  ///
  /// In zh_CN, this message translates to:
  /// **'季度 ID'**
  String get playStatsFieldSeasonId;

  /// No description provided for @playStatsFieldTotalEpisodeCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'总正片集数'**
  String get playStatsFieldTotalEpisodeCount;

  /// No description provided for @playStatsFieldWatchedEpisodeCountShort.
  ///
  /// In zh_CN, this message translates to:
  /// **'已观看集数'**
  String get playStatsFieldWatchedEpisodeCountShort;

  /// No description provided for @playStatsFieldCompletedEpisodeCountShort.
  ///
  /// In zh_CN, this message translates to:
  /// **'已完播集数'**
  String get playStatsFieldCompletedEpisodeCountShort;

  /// No description provided for @playStatsFieldIsSeasonCompleted.
  ///
  /// In zh_CN, this message translates to:
  /// **'是否季完播'**
  String get playStatsFieldIsSeasonCompleted;

  /// No description provided for @playStatsFieldVideoId.
  ///
  /// In zh_CN, this message translates to:
  /// **'视频 ID'**
  String get playStatsFieldVideoId;

  /// No description provided for @playStatsFieldAnimeTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'番剧标题'**
  String get playStatsFieldAnimeTitle;

  /// No description provided for @playStatsFieldSeasonTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'季度标题'**
  String get playStatsFieldSeasonTitle;

  /// No description provided for @playStatsFieldVideoKind.
  ///
  /// In zh_CN, this message translates to:
  /// **'视频种类'**
  String get playStatsFieldVideoKind;

  /// No description provided for @playStatsFieldCountsTowardCompletion.
  ///
  /// In zh_CN, this message translates to:
  /// **'是否计入季完播'**
  String get playStatsFieldCountsTowardCompletion;

  /// No description provided for @playStatsFieldMediaDuration.
  ///
  /// In zh_CN, this message translates to:
  /// **'媒体总时长'**
  String get playStatsFieldMediaDuration;

  /// No description provided for @playStatsFieldAutoPlayCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'自动连播次数'**
  String get playStatsFieldAutoPlayCount;

  /// No description provided for @playStatsFieldMaxProgress.
  ///
  /// In zh_CN, this message translates to:
  /// **'最大播放进度'**
  String get playStatsFieldMaxProgress;

  /// No description provided for @playStatsFieldLastProgress.
  ///
  /// In zh_CN, this message translates to:
  /// **'最后播放进度'**
  String get playStatsFieldLastProgress;

  /// No description provided for @playStatsFieldLastPosition.
  ///
  /// In zh_CN, this message translates to:
  /// **'最后播放位置'**
  String get playStatsFieldLastPosition;

  /// No description provided for @playStatsFieldCompleted.
  ///
  /// In zh_CN, this message translates to:
  /// **'是否完播'**
  String get playStatsFieldCompleted;

  /// No description provided for @playStatsFieldMetadataEnriched.
  ///
  /// In zh_CN, this message translates to:
  /// **'元数据已补全'**
  String get playStatsFieldMetadataEnriched;

  /// No description provided for @playStatsFieldHistoryId.
  ///
  /// In zh_CN, this message translates to:
  /// **'历史 ID'**
  String get playStatsFieldHistoryId;

  /// No description provided for @playStatsFieldStartSource.
  ///
  /// In zh_CN, this message translates to:
  /// **'开始来源'**
  String get playStatsFieldStartSource;

  /// No description provided for @playStatsFieldStartedAt.
  ///
  /// In zh_CN, this message translates to:
  /// **'开始时间'**
  String get playStatsFieldStartedAt;

  /// No description provided for @playStatsFieldEndedAt.
  ///
  /// In zh_CN, this message translates to:
  /// **'结束时间'**
  String get playStatsFieldEndedAt;

  /// No description provided for @playStatsFieldWatchedDuration.
  ///
  /// In zh_CN, this message translates to:
  /// **'观看时长'**
  String get playStatsFieldWatchedDuration;

  /// No description provided for @playStatsFieldMaxPosition.
  ///
  /// In zh_CN, this message translates to:
  /// **'最大播放位置'**
  String get playStatsFieldMaxPosition;

  /// No description provided for @playStatsFieldCountedAsView.
  ///
  /// In zh_CN, this message translates to:
  /// **'是否计入观看'**
  String get playStatsFieldCountedAsView;

  /// No description provided for @playStatsFieldCountedAsCompleted.
  ///
  /// In zh_CN, this message translates to:
  /// **'是否计入完播'**
  String get playStatsFieldCountedAsCompleted;

  /// No description provided for @playStatsFieldOpDetected.
  ///
  /// In zh_CN, this message translates to:
  /// **'已识别 OP'**
  String get playStatsFieldOpDetected;

  /// No description provided for @playStatsFieldEdDetected.
  ///
  /// In zh_CN, this message translates to:
  /// **'已识别 ED'**
  String get playStatsFieldEdDetected;

  /// No description provided for @playStatsFieldOpSkipped.
  ///
  /// In zh_CN, this message translates to:
  /// **'已跳过 OP'**
  String get playStatsFieldOpSkipped;

  /// No description provided for @playStatsFieldEdSkipped.
  ///
  /// In zh_CN, this message translates to:
  /// **'已跳过 ED'**
  String get playStatsFieldEdSkipped;

  /// No description provided for @playStatsFieldOpNotSkipped.
  ///
  /// In zh_CN, this message translates to:
  /// **'未跳过 OP'**
  String get playStatsFieldOpNotSkipped;

  /// No description provided for @playStatsFieldEdNotSkipped.
  ///
  /// In zh_CN, this message translates to:
  /// **'未跳过 ED'**
  String get playStatsFieldEdNotSkipped;

  /// No description provided for @playStatsFieldOpPlayedDuration.
  ///
  /// In zh_CN, this message translates to:
  /// **'OP 播放时长'**
  String get playStatsFieldOpPlayedDuration;

  /// No description provided for @playStatsFieldEdPlayedDuration.
  ///
  /// In zh_CN, this message translates to:
  /// **'ED 播放时长'**
  String get playStatsFieldEdPlayedDuration;

  /// No description provided for @playStatsFieldPersonId.
  ///
  /// In zh_CN, this message translates to:
  /// **'人员 ID'**
  String get playStatsFieldPersonId;

  /// No description provided for @playStatsFieldName.
  ///
  /// In zh_CN, this message translates to:
  /// **'姓名'**
  String get playStatsFieldName;

  /// No description provided for @playStatsFieldRole.
  ///
  /// In zh_CN, this message translates to:
  /// **'角色'**
  String get playStatsFieldRole;

  /// No description provided for @playStatsFieldJob.
  ///
  /// In zh_CN, this message translates to:
  /// **'工种'**
  String get playStatsFieldJob;

  /// No description provided for @playStatsFieldOrder.
  ///
  /// In zh_CN, this message translates to:
  /// **'排序'**
  String get playStatsFieldOrder;

  /// No description provided for @commonRetry.
  ///
  /// In zh_CN, this message translates to:
  /// **'重试'**
  String get commonRetry;

  /// No description provided for @playStatsReportDetailData.
  ///
  /// In zh_CN, this message translates to:
  /// **'详细数据'**
  String get playStatsReportDetailData;

  /// No description provided for @playStatsReportRangeTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'观影战报时间范围'**
  String get playStatsReportRangeTitle;

  /// No description provided for @playStatsReportSwitching.
  ///
  /// In zh_CN, this message translates to:
  /// **'切换中'**
  String get playStatsReportSwitching;

  /// No description provided for @playStatsReportBackfillingMetadata.
  ///
  /// In zh_CN, this message translates to:
  /// **'正在补全类型、国家地区、年份和演职人员数据'**
  String get playStatsReportBackfillingMetadata;

  /// No description provided for @playStatsReportLoadFailedTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'加载播放统计失败'**
  String get playStatsReportLoadFailedTitle;

  /// No description provided for @playStatsReportUnknownError.
  ///
  /// In zh_CN, this message translates to:
  /// **'未知错误'**
  String get playStatsReportUnknownError;

  /// No description provided for @playStatsReportErrorMessage.
  ///
  /// In zh_CN, this message translates to:
  /// **'错误信息：{error}'**
  String playStatsReportErrorMessage(Object error);

  /// No description provided for @playStatsReportActivityTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'活跃趋势'**
  String get playStatsReportActivityTitle;

  /// No description provided for @playStatsReportActivitySubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'按天观察播放时长变化，看看这段时间里哪几天看得最久。'**
  String get playStatsReportActivitySubtitle;

  /// No description provided for @playStatsReportDailyDurationTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'每日播放时长'**
  String get playStatsReportDailyDurationTitle;

  /// No description provided for @playStatsReportDailyDurationSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'看最近一段时间里，哪几天看得最久。'**
  String get playStatsReportDailyDurationSubtitle;

  /// No description provided for @playStatsReportContentTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'内容偏好'**
  String get playStatsReportContentTitle;

  /// No description provided for @playStatsReportContentSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'用播放时长加权，看看你最近更偏好的内容类型与人物。'**
  String get playStatsReportContentSubtitle;

  /// No description provided for @playStatsReportContentShare.
  ///
  /// In zh_CN, this message translates to:
  /// **'内容占比'**
  String get playStatsReportContentShare;

  /// No description provided for @playStatsReportAffinityTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'演职人员亲和榜'**
  String get playStatsReportAffinityTitle;

  /// No description provided for @playStatsReportBehaviorTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'观看行为'**
  String get playStatsReportBehaviorTitle;

  /// No description provided for @playStatsReportBehaviorSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'统计来源、完播率、快进回退以及 OP/ED 的观看习惯。'**
  String get playStatsReportBehaviorSubtitle;

  /// No description provided for @playStatsReportStartSource.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放来源'**
  String get playStatsReportStartSource;

  /// No description provided for @playStatsReportCountTimes.
  ///
  /// In zh_CN, this message translates to:
  /// **'{count} 次'**
  String playStatsReportCountTimes(int count);

  /// No description provided for @playStatsReportCompletionRate.
  ///
  /// In zh_CN, this message translates to:
  /// **'完播率'**
  String get playStatsReportCompletionRate;

  /// No description provided for @playStatsReportSessionRatio.
  ///
  /// In zh_CN, this message translates to:
  /// **'{completed}/{total} 次会话'**
  String playStatsReportSessionRatio(int completed, int total);

  /// No description provided for @playStatsReportTotalActions.
  ///
  /// In zh_CN, this message translates to:
  /// **'总操作数'**
  String get playStatsReportTotalActions;

  /// No description provided for @playStatsReportSeekSummary.
  ///
  /// In zh_CN, this message translates to:
  /// **'快进 {forwardCount} · 回退 {backwardCount}'**
  String playStatsReportSeekSummary(int forwardCount, int backwardCount);

  /// No description provided for @playStatsReportIntroOp.
  ///
  /// In zh_CN, this message translates to:
  /// **'片头 OP'**
  String get playStatsReportIntroOp;

  /// No description provided for @playStatsReportOutroEd.
  ///
  /// In zh_CN, this message translates to:
  /// **'片尾 ED'**
  String get playStatsReportOutroEd;

  /// No description provided for @playStatsReportRankingTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'排行与回看'**
  String get playStatsReportRankingTitle;

  /// No description provided for @playStatsReportRankingSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'保留最近活跃内容、继续观看线索和当前最常看的内容。'**
  String get playStatsReportRankingSubtitle;

  /// No description provided for @playStatsReportAnimeRankingTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'剧集榜'**
  String get playStatsReportAnimeRankingTitle;

  /// No description provided for @playStatsReportAnimeRankingSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'按剧集聚合后的总观看时长排行'**
  String get playStatsReportAnimeRankingSubtitle;

  /// No description provided for @playStatsReportVideoRankingTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'单集 / 视频榜'**
  String get playStatsReportVideoRankingTitle;

  /// No description provided for @playStatsReportVideoRankingSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'按具体视频或单集聚合的观看时长排行'**
  String get playStatsReportVideoRankingSubtitle;

  /// No description provided for @playStatsReportRecentHistoryTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'最近观看'**
  String get playStatsReportRecentHistoryTitle;

  /// No description provided for @playStatsReportRecentHistorySubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'最近发生的播放记录时间线'**
  String get playStatsReportRecentHistorySubtitle;

  /// No description provided for @playStatsReportDurationHoursMinutes.
  ///
  /// In zh_CN, this message translates to:
  /// **'{hours} 小时 {minutes} 分钟'**
  String playStatsReportDurationHoursMinutes(int hours, int minutes);

  /// No description provided for @playStatsReportDurationHours.
  ///
  /// In zh_CN, this message translates to:
  /// **'{hours} 小时'**
  String playStatsReportDurationHours(int hours);

  /// No description provided for @playStatsReportDurationMinutes.
  ///
  /// In zh_CN, this message translates to:
  /// **'{minutes} 分钟'**
  String playStatsReportDurationMinutes(int minutes);

  /// No description provided for @playStatsReportWeekdayMon.
  ///
  /// In zh_CN, this message translates to:
  /// **'一'**
  String get playStatsReportWeekdayMon;

  /// No description provided for @playStatsReportWeekdayTue.
  ///
  /// In zh_CN, this message translates to:
  /// **'二'**
  String get playStatsReportWeekdayTue;

  /// No description provided for @playStatsReportWeekdayWed.
  ///
  /// In zh_CN, this message translates to:
  /// **'三'**
  String get playStatsReportWeekdayWed;

  /// No description provided for @playStatsReportWeekdayThu.
  ///
  /// In zh_CN, this message translates to:
  /// **'四'**
  String get playStatsReportWeekdayThu;

  /// No description provided for @playStatsReportWeekdayFri.
  ///
  /// In zh_CN, this message translates to:
  /// **'五'**
  String get playStatsReportWeekdayFri;

  /// No description provided for @playStatsReportWeekdaySat.
  ///
  /// In zh_CN, this message translates to:
  /// **'六'**
  String get playStatsReportWeekdaySat;

  /// No description provided for @playStatsReportWeekdaySun.
  ///
  /// In zh_CN, this message translates to:
  /// **'日'**
  String get playStatsReportWeekdaySun;

  /// No description provided for @playStatsReportStartSourceManual.
  ///
  /// In zh_CN, this message translates to:
  /// **'手动播放'**
  String get playStatsReportStartSourceManual;

  /// No description provided for @playStatsReportStartSourceManualSwitch.
  ///
  /// In zh_CN, this message translates to:
  /// **'手动切换'**
  String get playStatsReportStartSourceManualSwitch;

  /// No description provided for @playStatsReportStartSourceReplay.
  ///
  /// In zh_CN, this message translates to:
  /// **'重新播放'**
  String get playStatsReportStartSourceReplay;

  /// No description provided for @playStatsReportHistorySubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'{startedAt} · 观看 {watchedDuration}'**
  String playStatsReportHistorySubtitle(
    Object startedAt,
    Object watchedDuration,
  );

  /// No description provided for @playStatsReportHistoryMeta.
  ///
  /// In zh_CN, this message translates to:
  /// **'{source} · 观看 {watchedDuration} · {startedAt}'**
  String playStatsReportHistoryMeta(
    Object source,
    Object watchedDuration,
    Object startedAt,
  );

  /// No description provided for @playStatsReportMovieWatchedSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'电影 · 观看 {watchedDuration}'**
  String playStatsReportMovieWatchedSubtitle(Object watchedDuration);

  /// No description provided for @playStatsReportWatchedDuration.
  ///
  /// In zh_CN, this message translates to:
  /// **'观看 {watchedDuration}'**
  String playStatsReportWatchedDuration(Object watchedDuration);

  /// No description provided for @playStatsReportFrequentPerson.
  ///
  /// In zh_CN, this message translates to:
  /// **'常看人物'**
  String get playStatsReportFrequentPerson;

  /// No description provided for @playStatsReportProgress.
  ///
  /// In zh_CN, this message translates to:
  /// **'进度 {progress}'**
  String playStatsReportProgress(Object progress);

  /// No description provided for @playStatsReportOccupationDirector.
  ///
  /// In zh_CN, this message translates to:
  /// **'导演'**
  String get playStatsReportOccupationDirector;

  /// No description provided for @playStatsReportOccupationProducer.
  ///
  /// In zh_CN, this message translates to:
  /// **'制片'**
  String get playStatsReportOccupationProducer;

  /// No description provided for @playStatsReportOccupationExecutiveProducer.
  ///
  /// In zh_CN, this message translates to:
  /// **'监制'**
  String get playStatsReportOccupationExecutiveProducer;

  /// No description provided for @playStatsReportOccupationWriter.
  ///
  /// In zh_CN, this message translates to:
  /// **'编剧'**
  String get playStatsReportOccupationWriter;

  /// No description provided for @playStatsReportOccupationOriginal.
  ///
  /// In zh_CN, this message translates to:
  /// **'原作'**
  String get playStatsReportOccupationOriginal;

  /// No description provided for @playStatsReportOccupationComposer.
  ///
  /// In zh_CN, this message translates to:
  /// **'作曲'**
  String get playStatsReportOccupationComposer;

  /// No description provided for @playStatsReportOccupationMusic.
  ///
  /// In zh_CN, this message translates to:
  /// **'音乐'**
  String get playStatsReportOccupationMusic;

  /// No description provided for @playStatsReportOccupationEditor.
  ///
  /// In zh_CN, this message translates to:
  /// **'剪辑'**
  String get playStatsReportOccupationEditor;

  /// No description provided for @playStatsReportOccupationCinematography.
  ///
  /// In zh_CN, this message translates to:
  /// **'摄影'**
  String get playStatsReportOccupationCinematography;

  /// No description provided for @playStatsReportOccupationVoice.
  ///
  /// In zh_CN, this message translates to:
  /// **'配音'**
  String get playStatsReportOccupationVoice;

  /// No description provided for @playStatsReportOccupationActor.
  ///
  /// In zh_CN, this message translates to:
  /// **'演员'**
  String get playStatsReportOccupationActor;

  /// No description provided for @playStatsReportOccupationCrew.
  ///
  /// In zh_CN, this message translates to:
  /// **'幕后'**
  String get playStatsReportOccupationCrew;

  /// No description provided for @playStatsReportOccupationSound.
  ///
  /// In zh_CN, this message translates to:
  /// **'音效'**
  String get playStatsReportOccupationSound;

  /// No description provided for @playStatsReportOccupationArt.
  ///
  /// In zh_CN, this message translates to:
  /// **'美术'**
  String get playStatsReportOccupationArt;

  /// No description provided for @playStatsReportOccupationVisualEffects.
  ///
  /// In zh_CN, this message translates to:
  /// **'特效'**
  String get playStatsReportOccupationVisualEffects;

  /// No description provided for @playStatsReportHeroTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'{range}观影战报'**
  String playStatsReportHeroTitle(Object range);

  /// No description provided for @playStatsReportActiveDays.
  ///
  /// In zh_CN, this message translates to:
  /// **'活跃天数'**
  String get playStatsReportActiveDays;

  /// No description provided for @playStatsReportTotalDuration.
  ///
  /// In zh_CN, this message translates to:
  /// **'累计 {duration}'**
  String playStatsReportTotalDuration(Object duration);

  /// No description provided for @playStatsReportClickCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'播放次数'**
  String get playStatsReportClickCount;

  /// No description provided for @playStatsReportClickCountDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'统计这段时间里，你主动点开播放或手动切换内容的次数。'**
  String get playStatsReportClickCountDescription;

  /// No description provided for @playStatsReportClickCountDetail.
  ///
  /// In zh_CN, this message translates to:
  /// **'更接近你发起了多少次播放，不包含自动连播或系统恢复。'**
  String get playStatsReportClickCountDetail;

  /// No description provided for @playStatsReportViewCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'观看次数'**
  String get playStatsReportViewCount;

  /// No description provided for @playStatsReportViewCountDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'只统计达到有效观看门槛的播放记录，用来看你真正进入观看状态了多少次。'**
  String get playStatsReportViewCountDescription;

  /// No description provided for @playStatsReportViewCountDetail.
  ///
  /// In zh_CN, this message translates to:
  /// **'剧集需看满 20%，电影需看满 10%。'**
  String get playStatsReportViewCountDetail;

  /// No description provided for @playStatsReportCompletedVideos.
  ///
  /// In zh_CN, this message translates to:
  /// **'完播视频'**
  String get playStatsReportCompletedVideos;

  /// No description provided for @playStatsReportCompletedVideosDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'统计被判定为完整看完的具体视频条目数，更接近你真正看完了多少集或多少部片。'**
  String get playStatsReportCompletedVideosDescription;

  /// No description provided for @playStatsReportCompletedVideosDetail.
  ///
  /// In zh_CN, this message translates to:
  /// **'通常需要看满约 80%，并且结尾不是一拖而过，才会记入完播。'**
  String get playStatsReportCompletedVideosDetail;

  /// No description provided for @playStatsReportCompletedSeasons.
  ///
  /// In zh_CN, this message translates to:
  /// **'完播季度'**
  String get playStatsReportCompletedSeasons;

  /// No description provided for @playStatsReportCompletedSeasonsDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'统计在当前时间范围内，被判定为整季看完的季度数量。'**
  String get playStatsReportCompletedSeasonsDescription;

  /// No description provided for @playStatsReportCompletedSeasonsDetail.
  ///
  /// In zh_CN, this message translates to:
  /// **'只有计入季完播的正片都完成后，这一季才会记作 1 个完播季度。'**
  String get playStatsReportCompletedSeasonsDetail;

  /// No description provided for @playStatsReportMetadataCoverage.
  ///
  /// In zh_CN, this message translates to:
  /// **'元数据覆盖'**
  String get playStatsReportMetadataCoverage;

  /// No description provided for @playStatsReportMetadataCoverageDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'反映这批内容里，类型、国家地区、年份和演职人员等信息补全得有多完整。'**
  String get playStatsReportMetadataCoverageDescription;

  /// No description provided for @playStatsReportMetadataCoverageDetail.
  ///
  /// In zh_CN, this message translates to:
  /// **'覆盖越高，下面的偏好分析和亲和榜越完整、越可靠。'**
  String get playStatsReportMetadataCoverageDetail;

  /// No description provided for @playStatsReportNoTrendData.
  ///
  /// In zh_CN, this message translates to:
  /// **'暂无播放趋势数据'**
  String get playStatsReportNoTrendData;

  /// No description provided for @playStatsReportNoViewCountData.
  ///
  /// In zh_CN, this message translates to:
  /// **'暂无观看次数数据'**
  String get playStatsReportNoViewCountData;

  /// No description provided for @playStatsReportBarTooltip.
  ///
  /// In zh_CN, this message translates to:
  /// **'{month}/{day}\n{count} 次'**
  String playStatsReportBarTooltip(int month, int day, int count);

  /// No description provided for @playStatsReportNoHeatmapData.
  ///
  /// In zh_CN, this message translates to:
  /// **'暂无活跃时段数据'**
  String get playStatsReportNoHeatmapData;

  /// No description provided for @playStatsReportHeatmapTooltip.
  ///
  /// In zh_CN, this message translates to:
  /// **'周{weekday} {hour}:00\n{count} 次 / {duration}'**
  String playStatsReportHeatmapTooltip(
    Object weekday,
    Object hour,
    int count,
    Object duration,
  );

  /// No description provided for @playStatsReportHeatmapLow.
  ///
  /// In zh_CN, this message translates to:
  /// **'少'**
  String get playStatsReportHeatmapLow;

  /// No description provided for @playStatsReportHeatmapHigh.
  ///
  /// In zh_CN, this message translates to:
  /// **'多'**
  String get playStatsReportHeatmapHigh;

  /// No description provided for @playStatsReportNoSeekActions.
  ///
  /// In zh_CN, this message translates to:
  /// **'本时间段几乎没有快进或回退操作'**
  String get playStatsReportNoSeekActions;

  /// No description provided for @playStatsReportNoDetectionRecord.
  ///
  /// In zh_CN, this message translates to:
  /// **'{label} 暂无检测记录'**
  String playStatsReportNoDetectionRecord(Object label);

  /// No description provided for @playStatsReportOpEdDetectedSkipped.
  ///
  /// In zh_CN, this message translates to:
  /// **'检测 {detectedCount} 次 · 跳过 {skippedCount} 次'**
  String playStatsReportOpEdDetectedSkipped(
    int detectedCount,
    int skippedCount,
  );

  /// No description provided for @playStatsReportSkipped.
  ///
  /// In zh_CN, this message translates to:
  /// **'跳过'**
  String get playStatsReportSkipped;

  /// No description provided for @playStatsReportWatchedCompletely.
  ///
  /// In zh_CN, this message translates to:
  /// **'完整观看'**
  String get playStatsReportWatchedCompletely;

  /// No description provided for @playStatsReportNoDistributionData.
  ///
  /// In zh_CN, this message translates to:
  /// **'暂无分布数据'**
  String get playStatsReportNoDistributionData;

  /// No description provided for @playStatsReportMetadataBackfilling.
  ///
  /// In zh_CN, this message translates to:
  /// **'相关元数据还在补全中'**
  String get playStatsReportMetadataBackfilling;

  /// No description provided for @playStatsReportNoRankingData.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前没有足够的排行数据'**
  String get playStatsReportNoRankingData;

  /// No description provided for @playStatsReportNoRecentHistory.
  ///
  /// In zh_CN, this message translates to:
  /// **'最近还没有新的观看记录'**
  String get playStatsReportNoRecentHistory;

  /// No description provided for @playStatsReportJumpPageTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'跳转页码'**
  String get playStatsReportJumpPageTitle;

  /// No description provided for @playStatsReportJumpPageDescription.
  ///
  /// In zh_CN, this message translates to:
  /// **'输入 1 到 {pageCount} 之间的页码'**
  String playStatsReportJumpPageDescription(int pageCount);

  /// No description provided for @playStatsReportPageNumberLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'页码'**
  String get playStatsReportPageNumberLabel;

  /// No description provided for @playStatsReportPageNumberHint.
  ///
  /// In zh_CN, this message translates to:
  /// **'例如 {page}'**
  String playStatsReportPageNumberHint(int page);

  /// No description provided for @playStatsReportJumpPageAction.
  ///
  /// In zh_CN, this message translates to:
  /// **'跳转'**
  String get playStatsReportJumpPageAction;

  /// No description provided for @playStatsReportPageIndicator.
  ///
  /// In zh_CN, this message translates to:
  /// **'第 {currentPage} / {pageCount} 页'**
  String playStatsReportPageIndicator(int currentPage, int pageCount);

  /// No description provided for @playStatsReportJumpPage.
  ///
  /// In zh_CN, this message translates to:
  /// **'跳页'**
  String get playStatsReportJumpPage;

  /// No description provided for @playStatsReportFirstPage.
  ///
  /// In zh_CN, this message translates to:
  /// **'第一页'**
  String get playStatsReportFirstPage;

  /// No description provided for @playStatsReportLastPage.
  ///
  /// In zh_CN, this message translates to:
  /// **'最后页'**
  String get playStatsReportLastPage;

  /// No description provided for @playStatsReportNoContinueWatching.
  ///
  /// In zh_CN, this message translates to:
  /// **'目前没有适合继续观看的内容'**
  String get playStatsReportNoContinueWatching;

  /// No description provided for @playStatsReportLastWatchedAt.
  ///
  /// In zh_CN, this message translates to:
  /// **'上次观看 {time}'**
  String playStatsReportLastWatchedAt(Object time);

  /// No description provided for @playStatsReportEmptyTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'还没有可展示的观影战报'**
  String get playStatsReportEmptyTitle;

  /// No description provided for @playStatsReportEmptySubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'开始播放内容后，这里会自动生成趋势、偏好、行为和回看报表。'**
  String get playStatsReportEmptySubtitle;

  /// No description provided for @playStatsReportUnnamedEpisode.
  ///
  /// In zh_CN, this message translates to:
  /// **'未命名剧集'**
  String get playStatsReportUnnamedEpisode;

  /// No description provided for @playStatsReportAnimeRankSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'观看 {sessionCount} 次 · 完整观看 {viewCount} 次'**
  String playStatsReportAnimeRankSubtitle(int sessionCount, int viewCount);

  /// No description provided for @playStatsReportUnknownPerson.
  ///
  /// In zh_CN, this message translates to:
  /// **'未知人物'**
  String get playStatsReportUnknownPerson;

  /// No description provided for @bookmarkManagerLegacyBookmark.
  ///
  /// In zh_CN, this message translates to:
  /// **'旧书签'**
  String get bookmarkManagerLegacyBookmark;

  /// No description provided for @bookmarkManagerUnnamedWork.
  ///
  /// In zh_CN, this message translates to:
  /// **'未命名作品'**
  String get bookmarkManagerUnnamedWork;

  /// No description provided for @bookmarkManagerSpecialSeason.
  ///
  /// In zh_CN, this message translates to:
  /// **'特别篇'**
  String get bookmarkManagerSpecialSeason;

  /// No description provided for @bookmarkManagerSeasonLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'第{season}季'**
  String bookmarkManagerSeasonLabel(int season);

  /// No description provided for @bookmarkManagerEpisodeLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'第{episode}集'**
  String bookmarkManagerEpisodeLabel(int episode);

  /// No description provided for @bookmarkManagerUnnamedEpisode.
  ///
  /// In zh_CN, this message translates to:
  /// **'未命名剧集'**
  String get bookmarkManagerUnnamedEpisode;

  /// No description provided for @bookmarkManagerEditNoteTitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'编辑书签备注'**
  String get bookmarkManagerEditNoteTitle;

  /// No description provided for @bookmarkManagerNoEpisodeBookmarks.
  ///
  /// In zh_CN, this message translates to:
  /// **'该集下已经没有书签'**
  String get bookmarkManagerNoEpisodeBookmarks;

  /// No description provided for @bookmarkManagerNoteAction.
  ///
  /// In zh_CN, this message translates to:
  /// **'备注'**
  String get bookmarkManagerNoteAction;

  /// No description provided for @danmakuManagerLegacySource.
  ///
  /// In zh_CN, this message translates to:
  /// **'旧来源'**
  String get danmakuManagerLegacySource;

  /// No description provided for @danmakuManagerUnnamedItem.
  ///
  /// In zh_CN, this message translates to:
  /// **'未命名条目'**
  String get danmakuManagerUnnamedItem;

  /// No description provided for @danmakuManagerSourceCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'共 {count} 个来源'**
  String danmakuManagerSourceCount(int count);

  /// No description provided for @danmakuManagerNetworkDanmaku.
  ///
  /// In zh_CN, this message translates to:
  /// **'网络弹幕'**
  String get danmakuManagerNetworkDanmaku;

  /// No description provided for @danmakuManagerLocalImport.
  ///
  /// In zh_CN, this message translates to:
  /// **'本地导入'**
  String get danmakuManagerLocalImport;

  /// No description provided for @danmakuManagerCommentCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'{count} 条'**
  String danmakuManagerCommentCount(int count);

  /// No description provided for @danmakuManagerUnnamedSource.
  ///
  /// In zh_CN, this message translates to:
  /// **'未命名弹幕来源'**
  String get danmakuManagerUnnamedSource;

  /// No description provided for @mediaEpisodeCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'共{count}集'**
  String mediaEpisodeCount(int count);

  /// No description provided for @mediaSeasonCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'共{count}季'**
  String mediaSeasonCount(int count);

  /// No description provided for @mediaWorkCount.
  ///
  /// In zh_CN, this message translates to:
  /// **'共{count} 个作品'**
  String mediaWorkCount(int count);

  /// No description provided for @fileInfoLocationLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'文件位置'**
  String get fileInfoLocationLabel;

  /// No description provided for @fileInfoSizeLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'文件大小'**
  String get fileInfoSizeLabel;

  /// No description provided for @fileInfoCreatedAtLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'文件创建日期'**
  String get fileInfoCreatedAtLabel;

  /// No description provided for @fileInfoAddedAtLabel.
  ///
  /// In zh_CN, this message translates to:
  /// **'添加日期'**
  String get fileInfoAddedAtLabel;

  /// No description provided for @fileInfoToggleToFriendly.
  ///
  /// In zh_CN, this message translates to:
  /// **'转换'**
  String get fileInfoToggleToFriendly;

  /// No description provided for @fileInfoStorageSpace.
  ///
  /// In zh_CN, this message translates to:
  /// **'存储空间{volumeNo}'**
  String fileInfoStorageSpace(Object volumeNo);

  /// No description provided for @fileInfoStorageSpaceFile.
  ///
  /// In zh_CN, this message translates to:
  /// **'存储空间{volumeNo}/{name} 的文件'**
  String fileInfoStorageSpaceFile(Object volumeNo, Object name);

  /// No description provided for @fnConnectNasAddressFailed.
  ///
  /// In zh_CN, this message translates to:
  /// **'FN Connect 登录失败，未能解析 NAS 地址'**
  String get fnConnectNasAddressFailed;

  /// No description provided for @playerHostInvalidArgs.
  ///
  /// In zh_CN, this message translates to:
  /// **'当前播放器参数错误'**
  String get playerHostInvalidArgs;

  /// No description provided for @themeSaveDefaultBase.
  ///
  /// In zh_CN, this message translates to:
  /// **'自定义主题'**
  String get themeSaveDefaultBase;

  /// No description provided for @themeSaveName.
  ///
  /// In zh_CN, this message translates to:
  /// **'{base}主题色'**
  String themeSaveName(Object base);

  /// No description provided for @storageSeriesGroupSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'{seasonCount} 季 · {entryCount} 集 · {size} · 最近 {time}'**
  String storageSeriesGroupSubtitle(
    int seasonCount,
    int entryCount,
    Object size,
    Object time,
  );

  /// No description provided for @storageSeasonGroupSubtitle.
  ///
  /// In zh_CN, this message translates to:
  /// **'{entryCount} 集 · {size} · 最近 {time}'**
  String storageSeasonGroupSubtitle(int entryCount, Object size, Object time);

  /// No description provided for @storageGroupedPageSummary.
  ///
  /// In zh_CN, this message translates to:
  /// **'{totalCount} 个作品 · 每页 {pageSize} 个'**
  String storageGroupedPageSummary(int totalCount, int pageSize);

  /// No description provided for @storageUnknownWork.
  ///
  /// In zh_CN, this message translates to:
  /// **'未知作品'**
  String get storageUnknownWork;

  /// No description provided for @storageUngroupedSeason.
  ///
  /// In zh_CN, this message translates to:
  /// **'未分季'**
  String get storageUngroupedSeason;

  /// No description provided for @storageSeasonNumberSpaced.
  ///
  /// In zh_CN, this message translates to:
  /// **'第 {season} 季'**
  String storageSeasonNumberSpaced(int season);

  /// No description provided for @storageEpisodeTitleWithNumber.
  ///
  /// In zh_CN, this message translates to:
  /// **'第 {episode} 集 {title}'**
  String storageEpisodeTitleWithNumber(int episode, Object title);

  /// No description provided for @storageUnknownEpisode.
  ///
  /// In zh_CN, this message translates to:
  /// **'未知集数'**
  String get storageUnknownEpisode;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.countryCode) {
          case 'CN':
            return AppLocalizationsZhCn();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
