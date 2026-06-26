# Emby 详情页版本 / 音轨 / 字幕选择器接入

> 2026-06-24。承接 Emby 中立详情体(`play_detail_page._buildNeutralBody`,覆盖电影 + 单集)。
> 用户拍板:**选择器 + 状态**——三选择器都接,版本切换实时换显示的文件/视频信息,音轨/字幕
> 列出各轨并记录选中态,为日后 Emby 播放预留接口。**本轮不接实际播放**(播放按钮维持占位)。

## 现状

飞牛详情页三选择器(`DetailResolutionSection` 版本 chip + `DetailSelectorRow` 音轨/字幕标签 +
音轨/字幕 sheet)**直接喂播放**(`_selectedStreamIndex`/`_selectedAudioGuid`/`_selectedSubtitleGuid`
→ `MpvMediaSource`)。Emby 中立体当前只有 meta + 占位播放 + 描述 + 演职员 + 单 source 文件信息
(`_sourceInfo`,`getItemSourceInfo` 取首个 MediaSource)+ 链接。

**复用面**:`DetailResolutionSection`/`DetailSelectorRow`/`ResolutionSelector` 纯展示无耦合;
音轨/字幕 sheet 底层 `TrackOptionSheet.show`(`TrackOptionSheetItem{id,title,subtitle}`)中立,
飞牛 `PlayDetailSheetController` 只是把飞牛 track 适配过去——可直接用中立数据调。

Emby 数据齐:`MediaSources[]`(多版本)+ 每源 `MediaStreams[]`(video/audio/subtitle,带 Index)。

## 打法(数据层 + UI,飞牛零影响)

### 数据层
- **新中立模型** `lib/media_backend/detail/media_source_version.dart`:
  `MediaSourceVersion{id,label,badges,info(复用 MediaSourceInfo),audioTracks,subtitleTracks,
  defaultAudioId,defaultSubtitleId}` + `MediaTrackOption{id,label,summary,isExternal}`。
- **Emby mapper** `mapEmbySourceVersions(item)`:全 `MediaSources[]` → 版本;每源 `MediaStreams`
  既拼展示流(复用现有 `_videoStream`/`_audioStream`/`_subtitleStream` 进 info)又拼可选轨
  (id=stream Index 串)。版本 label = 分辨率/Name;badges 取视频流分辨率 + HDR。
- **接口** `MediaBackend.getItemSourceVersions(itemId)` → `List<MediaSourceVersion>`。飞牛返
  `const []`(走自有路径);Emby 用 `getItem(fields:'MediaSources,DateCreated')` + mapper。

### UI(`play_detail_page` 中立体)
- 状态 `_neutralVersions`/`_neutralSelectedVersionIndex`/`_neutralSelectedAudioId`/
  `_neutralSelectedSubtitleId`/`_neutralAudio|SubtitleExpanded`。
- `_loadNeutral` 改取 `getItemSourceVersions`;选中 index=0,音轨/字幕初始化为版本默认;
  `_sourceInfo` 由选中版本派生。
- 渲染:版本选择器(`DetailResolutionSection`,>1 版本才显示)+ 选择器行(`DetailSelectorRow`,
  有轨才显示)+ 文件信息区用选中版本 info。
- 中立 sheet `_showNeutralAudioSheet`/`_showNeutralSubtitleSheet` 经 `TrackOptionSheet.show`。

### 约束
- 飞牛分支整段不进(中立体早返回门控),逐像素不变。
- `lib/media_backend` 不构造 `MpvMediaSource`/不导航/不碰 BuildContext;UI 不写 `if(isEmby)`。
- 选中态仅记录(本轮无播放消费),为 getPlayback 预留。
- pathspec 提交;不夹带 Codex 未提交文件;不提交真实凭据(脱敏 fixture)。

## 阶段
- A 数据层(模型 + mapper + 接口 + 飞牛空实现 + Emby 实现)+ 单测。
- B UI(状态 + _loadNeutral + 渲染 + sheet)。
- C 实机验证(电影 + 单集:版本切换换信息、音轨/字幕列轨记选中;飞牛零回归)。
