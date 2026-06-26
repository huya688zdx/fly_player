# Emby 摊子延后提交 + 实机验证清单（推到以后）

> 2026-06-26。本轮 Emby 收尾的若干改动**功能在工作区已生效**(`flutter analyze` 净、单测过),
> 但**提交受阻**(与 Codex 未提交的 `media_backend_connection.entryToken` / `emby_api.dart` 拦截器
> 强耦合,`implements` 又强制各后端覆写),整体并入「待 Codex 提交后随之干净提交」的 Emby 摊子。
> 同时多项已提交/已生效的修复**待实机复验**。集中成清单,以后逐条收口。

## A. 待 Codex 落地后再干净提交的工作区改动

> 前置:Codex 提交 `media_backend_connection`(`entryToken` getter)+ `emby_api.dart`(entry-token
> 拦截器)。届时用 stash 隔离 dance 把下列一并 pathspec 提交;提交前 `git diff --cached --name-only`
> 复核别夹带 Codex 文件。

1. **进度 PlaySessionId**(`emby_api.dart`):每 itemId 稳定 32 位 hex,塞进 `_playStateBody`,
   Start/Progress/Stopped 复用;会话授权头带 Token。已实机验证进度生效。
2. **收藏 / 已看抽象 + Emby 接入**:
   - `MediaBackend.setItemFavorite/setItemWatched`(默认不支持)+ `MediaBackendCapabilities`
     `supportsFavorite/supportsWatched`(飞牛全开、Emby 开这俩、下载关)。
   - 飞牛后端委托 `FeiniuApi.setFavorite/setWatched`;Emby 后端走新 `EmbyApi.setFavorite/setWatched`
     (`POST`/`DELETE` `FavoriteItems`/`PlayedItems`、`api_key` 自鉴权)。
   - 详情页:飞牛 `_toggleFavorite/_toggleWatched` 迁去走 `backend.setItem*`(已看后 refresh 按
     `kind==feiniu` 门控);Emby 中立分支改用 `PlayActionBar`(进度条+主键+三圆键),收藏/已看按
     能力位接、下载 `detailDownloadUnavailable` 提示。删 `_toggleNeutral*` 与 `play_detail_item_actions`
     未用 import。
3. **视频信息块统一**:`VideoInfoSection` 后端中立化(`VideoInfoLines.fromFeiniu` 逐字不变 /
   `fromSource` 从 `MediaSourceInfo`),飞牛逐像素不变;Emby 从 `MediaSourceInfoSection` 换成
   `VideoInfoSection`(紧凑三行 + 查看全部),「查看全部」底部弹窗复用 `MediaSourceInfoSection`。
4. **i18n 改动里与上面强耦合的**:`play_detail_page.dart` + `video_info_section.dart` 的 `_t` 消除
   随这摊一起;其余 i18n(tv 页 / 6 screen / app_error_state / ARB / 删 `app_localization_lookup.dart`)
   技术上**可独立先提交**(不依赖 Emby 摊子)。

> 涉及文件:`media_backend.dart` / `media_backend_capabilities.dart` / `feiniu_media_backend.dart` /
> `emby_media_backend.dart` / `emby_api.dart` / `play_detail_page.dart` / `video_info_section.dart`
> + 模型 `media_source_version.dart`(`durationSeconds`,已提交 5fe13de)。

## B. 待实机复验（已提交 / 已生效，未真机确认）

- [ ] 季详情页(点季卡进的「里面的页面」)播放键显示 = 最新进度集数(`282c1ee`,走
      `resolveSeriesNextUpEpisode`/continue-watching)。
- [ ] Emby 电影详情页(`5fe13de`):①返回按钮 ②时长随版本(两个 1080p)切换变化
      ③续看进度条 + 「继续播放/重播」文案。
- [ ] 收藏 / 已看 三圆键(工作区):点收藏 → Emby `FavoriteItems` 回写、点已看 → `PlayedItems`
      回写,飞牛同键无回归。
- [ ] 视频信息块:飞牛三行 + 查看全部观感不变;Emby 同样式 + 查看全部弹出完整文件/逐流。
- [ ] 详情页进播放器有选集 / 下一集(`96e1413`/`31acd0c`);外挂字幕下载 + sub-add。

## C. 其余既有缺口（更远）

- 转码 HLS(大子系统)。
- entry-token 过期重抓。
- Emby 下载队列(当前 `supportsDownloadTasks=false`,详情页下载键走「不可用」提示)。
- Flutter 层硬编码 i18n 普查(见 `2026-06-26-flutter-i18n-hardcoded-sweep.md`)。
