# 原生壳「切集后新集没有弹幕」问题交接（给 Codex 刨根）

> 写给接手的 agent：本文区分「已用真机 logcat 验证的事实」与「待证的假设」。**一切以你自己跑命令/读代码的结果为准**，不要盲信本文结论。先复现、先看证据，再动手。

## 1. 症状（用户原话 + 复现）

- 后端是 **Emby**（`http://100.125.130.96:8096/Videos/<itemId>/stream.mkv?...api_key=...` 直链）。播放走 **原生壳** `NativePlayerActivity`（非 Flutter 播放器）。
- **壳内切集**（自动下一集 / 选集面板手动跳集）后，**新一集没有弹幕**。
- 但**退出播放器、从详情页重新进同一集**，**就有弹幕**。
- ⟹ 内容本身**能**匹配到弹幕（全新启动那条路成功）；**是壳内切集这条路没去取 / 没取到弹幕**。这是 bug，不是「内容匹配不到」。

## 2. 已用 logcat 验证的事实（真机，2026-06-27 ~15:28–15:30，进程 pid 5469）

诊断日志 tag：`[DANMAKU][NATIVE_PREFETCH]`（`I/flutter`），是本次会话临时加在 `lib/services/native_danmaku_prefetch.dart` 的 `debugPrint`（**未提交**，见 §5）。

- **全新启动某集（item 2489, e=1, series=比宇宙更遥远的地方）**：
  ```
  [DANMAKU][NATIVE_PREFETCH] in series="比宇宙更遥远的地方" s=1 e=1 tmdb="" item="2489" media="mediasource_2489" season="2488"
  [DANMAKU][NATIVE_PREFETCH] online gate: autoBlocked=false seriesTitleEmpty=false
  [DANMAKU][NATIVE_PREFETCH] online result=true
  ```
  → 弹幕正常。这条路是 `NativePlayerBridge.maybeLaunch`（`lib/services/native_player_bridge.dart:436`）**直接**调 `resolveToFile`（:452）。
- **退出后再次启动同集（2489）**：
  ```
  [DANMAKU][NATIVE_PREFETCH] in ... item="2489" ...
  [DANMAKU][NATIVE_PREFETCH] mediaKey=v2|item=2489|media=mediasource_2489|season=2488|s=1|e=1 activeKey=132570001 savedCount=1
  [DANMAKU][NATIVE_PREFETCH] active source loaded=true type=danDanPlay sourceKey=132570001
  ```
  → 命中本次会话已登记的激活源（见 §4「已落地修复」里的 saveSource）。
- **壳内切到下一集（item 2489 → 2490），~15:29:41**（全 tag dump 证据）：
  ```
  V/mpv ... Opening http://.../Videos/2490/stream.mkv?...MediaSourceId=mediasource_2490...
  D/NativePlayerActivity applySubtitleByGuid match guid=emby:sub:2490:mediasource_2490:2 ...
  D/FlyPlayerMpv sub-add path=...fly_player_emby_sub_2490_mediasource_2490_2.ass
  D/FlyPlayerDanmaku [DANMAKU][NATIVE] view_frame_rate_vote reason=clear ...
  ```
  - 视频**确实切到 2490**（mpv 打开 2490 URL）、字幕也换成 2490 的；
  - `view_frame_rate_vote reason=clear` ⟹ **本会话已加的 `clearDanmaku()` 触发了**（即 `applyLoadArgs` 收到 `danmakuPayload == null`）；
  - **整个切集过程没有任何 `[DANMAKU][NATIVE_PREFETCH] in` 行**，也没有 `resolvePlayback`/`danmakuFile` 痕迹 ⟹ **`resolveToFile` 对 2490 从未执行**。

> 结论（已验证）：壳内切集时，**新集的 `resolveToFile` 根本没被调用**，所以没有弹幕。全新启动走 `maybeLaunch` 会调 `resolveToFile`，所以有。

## 3. 矛盾点 / 待查的核心（这是 Codex 要刨的）

切集的反向通道链路（按代码**应该**会调 resolveToFile，但实测没调）：

```
NativePlayerActivity.requestEpisode(itemGuid)            // 5562
  → NativePlayerReverseBridge.dispatch("resolvePlayback")
  → native_player_bridge.dart:138 case 'resolvePlayback' → onResolvePlayback(...)
  → (Emby) tv_season_detail_page.dart:2240 _bindEmbyNativePlayerReentry.onResolvePlayback
  → TvSeasonPlaybackLauncher.resolveForNative(...)        // tv_season_playback_launcher.dart:114
       └─ AsyncActionGuard.run('tv_season_resolve:<guid>', settle 300ms, action: {
            _resolveWithProvider(...)  // Emby 分支：isFeiniu=false，跳过本地下载分支
            → 若 resolved==null return null（但视频切成功⟹resolved!=null）
            → NativeDanmakuPrefetch.resolveToFile(...)   // :206 ← 应在此 log `in`
            → return {loadArgs, danmakuFile?}
          })
  → 回到 native applyEpisodeResult(result)               // 5627：读 map["danmakuFile"] 文件
  → applyLoadArgs(loadArgs, danmakuPayload)              // 2215：仅 danmakuPayload!=null 才 setDanmakuPayload，否则 clearDanmaku（本会话新增 else 分支）
```

**矛盾**：Emby 分支下 `resolveForNative` 只要 `resolved != null`（视频切成功证明它非空）就一定会执行到 `resolveToFile`（:206），就一定打印 `in`。但实测**没有** `in`。两种可能（需 Codex 证实是哪个）：

- **假设 A：切集根本没调 `resolveForNative`。** 也许 Emby 壳内切集用 `episodes` 载荷里的直链 URL（`Videos/<itemId>/stream.mkv` 对 Emby 是可由 itemId 直接拼的）直接换源，绕过了 `resolvePlayback`/resolve。要查：`requestEpisode` 的预载命中分支（5566 `nextEpisodePreloadResult`）、`episodeResolveArgs`、选集面板点击到底走没走 `resolvePlayback`、`_neutralNativeEpisodesPayload`/`EmbyNativePickerSupport.nativeEpisodePayload` 每集载荷含哪些字段。
- **假设 B：`resolveForNative` 被调了，但 `AsyncActionGuard` 短路了 action。** `lib/utils/async_action_guard.dart` 的 `_inFlight` 是 **static、跨 Activity 存活**（详情页 Flutter engine 常驻）。若 `tv_season_resolve:2490` 已有在途/未清的 future（如预载 `preloadNextEpisodeIfNeeded` 先发了一次 + 实际切集又发一次，300ms settle 内），第二次直接返回旧 future、**不跑 action ⟹ 不 log `in`**。但反过来：第一次（预载）跑 action 时**应该**也 log 了 `in`——实测两次会话里都**没有** 2490 的 `in`，所以单纯 settle 去重解释不通，需要查清在途 future 的来源/是否 action 真没跑。

> 关键判别：在 `resolveForNative` 入口（`AsyncActionGuard.run` 之前）和 native `requestEpisode`/`applyEpisodeResult` 各加一条 log（resolveForNative 是否被调、guardRunning 真假、applyEpisodeResult 收到的 `danmakuFile` 是否非空），复现一次即可区分 A/B：
> - 入口 log 出现但无 `in` → 假设 B（AsyncActionGuard 短路）；
> - 入口 log 都没有 → 假设 A（切集没走 resolve）。

## 4. 与本问题相关的上下文（本会话已落地、已 commit 的改动）

这些是**本会话已提交**的修复，构成当前行为，别重复做、也别误判为 bug 源：

- `fix(danmaku): 切集时清掉上一集弹幕，避免串台`（HEAD 附近 commit `6618921`）：`applyLoadArgs` 新增 else 分支——**真的切了集**（itemGuid 变，排除同集切画质/版本/音轨字幕）但 `effectiveDanmaku==null` 时调 `playerSurface.clearDanmaku()`+复位 sourceKey。**就是它让切集后从「串台显示上一集弹幕」变成「显示无弹幕」**。日志里的 `view_frame_rate_vote reason=clear` 即此。
- `fix(danmaku): 在线自动匹配的弹幕登记进弹幕源库`（commit `17dde95`）：`native_danmaku_prefetch._resolveOnlineToFile` 命中后 `store.saveSource(...)`（之前只注入不登记）。日志里第二次启动 `activeKey=132570001 active source loaded=true` 即此生效。
- 另有 `setSpeed`/媒体会话抖动/弹幕跟随倍速三个 commit，与本问题无关。

设计约束（已知）：弹幕保存源 `DanmakuSavedSourceStore` 的 `mediaKey` 含 `e=<episodeNumber>`，**按集存、不跨集**。原生壳手动搜的源存在**原生 prefs**（`KEY_DANMAKU_SOURCES`，含 animeTitle/episodeId），与 Flutter 的 `DanmakuSavedSourceStore` **不互通**。详见记忆 `native-shell-danmaku-episode-switch.md`。

## 5. 当前工作区状态（未提交）

- `lib/services/native_danmaku_prefetch.dart`：**临时诊断日志**（`[DANMAKU][NATIVE_PREFETCH] in` @~51、`online gate` @~111、`online result` @~128）。Codex 可保留/扩展，定位后清理。
- 其余 `M` 文件（`lib/main.dart`、`lib/pages/{play_detail,tv_detail,tv_season_detail}_page.dart`、`lib/widgets/common/liquid_glass.dart`、`lib/widgets/settings/theme/theme_settings_panels.dart`、`lib/screens/media_list_screen_widgets.dart`、`android/.../NativePlayerActivity.kt`、`MpvPlaybackController.kt`）多为**用户其它在进行的工作**，与本问题无关，**切勿夹带提交**。先 `git status`/`git diff` 核对再说。

## 6. 关键文件:行 速查

- `lib/services/native_danmaku_prefetch.dart:36` `resolveToFile`（取源优先级：激活源→本地导入→在线自动匹配→随片下载兜底）；`_resolveOnlineToFile` 在线匹配 + saveSource。
- `lib/services/native_player_bridge.dart:436` `maybeLaunch`（全新启动取弹幕，:452 调 resolveToFile）；`:138` `resolvePlayback` case。
- `lib/controllers/tv_season_playback_launcher.dart:114` `resolveForNative`（切集取弹幕，:206 调 resolveToFile）；`:249` `_resolveWithProvider`；`:37` `open`（全新启动）。
- `lib/pages/tv_season_detail_page.dart:2240` Emby 反向通道 onResolvePlayback；`:2295` 飞牛版。
- `lib/utils/async_action_guard.dart`：static `_inFlight` 去重 + settle。
- `android/.../NativePlayerActivity.kt`：`requestEpisode`@5562、`applyEpisodeResult`@5627、`applyLoadArgs`@2215、`preloadNextEpisodeIfNeeded`、`onNewIntent`@~2130。

## 7. 验证方法（复现 + 抓日志）

设备已连（`adb devices` 有设备）。复现：起播某集（有弹幕）→ **壳内**切到下一集/别的集 → 观察无弹幕。抓：
```
adb logcat -c
adb logcat -v time flutter:I FlyPlayerDanmaku:D FlyPlayerMpv:D NativePlayerActivity:D *:S
```
看切集瞬间有没有 `[DANMAKU][NATIVE_PREFETCH] in`、`resolveForNative ENTER`（若加）、以及视频是否换到新 itemId。对比「全新启动」与「壳内切集」两条路 resolveToFile 是否被调。
