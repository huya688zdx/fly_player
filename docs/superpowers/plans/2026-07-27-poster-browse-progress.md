# 大屏海报浏览页 — 执行进度报告

> **2026-07-27 终态更新（本文档下方"已完成/剩余工作"为早期快照，以本节为准）**
>
> **A-H 全部执行组收口**。最终状态：
> - 功能全部落在分支 `poster-browse`（worktree `F:\fly_play_poster_browse`），HEAD `a65cb7e`。分支相对 main(3748b04) 含：98b47f6（小屏横屏布局自适应+三档尺寸回归测试，修终审 Critical C-1）、a65cb7e（meta 定高裁剪 P-1/P-3）。此前 E/F/G 组 9 个 commit 已并入 main（merge 73c5a10）。
> - 验证：干净环境全量 `flutter analyze` 零告警、`flutter test` 499/499 绿（后又 17/17 poster_browse + 172 media_backend 复验）、`flutter build apk --debug` 出 full/lite 双 flavor APK。
> - 整体终审 Approved：跨层字段链路闭合、端到端链路闭合、方向锁与 reentry 复核通过；终审发现的 C-1（360dp 横屏按钮点不到）已修并有 57 档高度扫描+反向验证的回归护栏。
> - **唯一未完成动作：`git merge poster-browse` 回 main。** 被另一会话阻塞：其"图片鉴权 MediaImageRequest 重构"有未提交改动压在 `poster_browse_screen.dart`（把 `DynamicPageThemeScope` 的 `token:` 参数适配为 `imageHeaders:`）。**待其提交后在主目录执行 `git merge poster-browse --no-edit`**；若该行冲突，保留对方的 `imageHeaders: backdrop.headers` 写法。合并后 `git worktree remove F:\fly_play_poster_browse` + `git branch -d poster-browse`。
> - 实机验收清单（合并后执行，三后端各过一遍）：①入口进出横竖屏往返 5 次不卡横屏（含详情页内被系统回收的异常路径）；②行构成与空行隐藏（飞牛"最近添加"排序不生效→整行消失）；③焦点切换 300ms 节流不闪、快速滑动背景不逐帧闪；④评分两处显示/缺失隐藏；⑤同 guid 进详情配色零闪；⑥剧集起播后原生壳选集面板/进度回写/画质重解析正常（reentry 修复实证，必测）；⑦连点两次"详情"不双开；⑧弱网纯 ambient 色底无糊图；⑨360dp 高横屏手机：按钮可点、进度条完整、紧凑档观感（缩略图 44-50/标题 20pt/meta 单行裁剪）；⑩压暗值 0x59 观感（亮暗 backdrop 两端）；⑪播放返回后继续观看进度条不刷新（已知遗留，看是否需补）；⑫翻行瞬间行名/条目 300ms 错配观感。

计划文档：`docs/superpowers/plans/2026-07-26-poster-browse.md`（12 任务，按 A-H 八个执行组子代理驱动执行）
设计规格：`docs/superpowers/specs/2026-07-26-poster-browse-design.md`

## 已完成（全部经"实现 → 规格审查 → 质量审查"三段流程收口）

### 在 main 分支（F:\fly_play_recovered，截至 1a69f64）

| 组 | 计划任务 | Commit | 内容 |
| --- | --- | --- | --- |
| A | T1+T2 | a46f49f, 839b6ff | `MediaItemCard` 加 `overview`/`genres`；Emby/飞牛 mapper 填充；`_cardFields` 加 Genres |
| B | T3+T4 | 738bedf, ab821f7, 08d394e | `MediaBackend.getLatestItems` 默认空实现；Emby `DateCreated` 倒序；飞牛 `create_time DESC` 全局查询（失败降级+logSwallowedError）；Jellyfin 继承零代码 |
| C | T5 | 1438f63 | l10n 六个 key（两 arb 同步，gen-l10n 通过） |
| D | T6+T7 | bac45e0, aebbf3d, 1a69f64 | 行组装纯函数；`PosterBrowseLoader`（三源并行+降级日志）；`cardFromLibraryItem` 飞牛旁路映射；7 条单测 |

### 在 poster-browse 分支（worktree F:\fly_play_poster_browse，基于 1a69f64）

| 组 | 计划任务 | Commit | 内容 |
| --- | --- | --- | --- |
| E | T8+T9 | f86771e, 5257e37, 9a1a6f4 | 焦点 300ms 节流（防误用+3 测试）；缩略图条（固定占位+AnimatedScale 不挤邻项、cacheWidth 限宽、评分角标、进度条、Semantics） |
| F | T10 | 0c94c60, 4bdde27, 86a6acd | `PosterBrowseScreen` 完整页面。两轮修复已含：**剧集起播 reentry 绑定/解绑**（TvSeasonPlaybackLauncher 不自绑，须按 tv_detail_page 姿势 bind）、预取 ResizeImage 与渲染侧同缓存键、NasProvider select 依赖化、半露行点击自动切行、竖横屏往返 finally 双保险 |

测试基线：`flutter test test/media_backend/` 167 项、`flutter test test/poster_browse/` 12 项全绿；analyze 无告警。

### 中断时在途

- 组F 质量审查代理（工程质量维度：650 行单文件结构 / 生命周期竞态 / 双背景过渡合成成本 / 时钟 30s 全页 setState）结果未回。**恢复时先看它的结论再决定是否补修。**

## 剩余工作（按序）

1. **组F 收口**：等/重跑质量审查结论；如有 Important 以上问题按三段流程修复复核。
2. **组G = 计划 Task 11**（在 worktree 做）：
   - `lib/main.dart`：`/screen/poster-browse` 路由 + `PosterBrowseRoute`（`_ProviderGate` 包 `PosterBrowseScreen`），参照 `/screen/search` case（main.dart:504-509）与 Route 类区（:796-829）
   - `lib/screens/media_list_screen_widgets.dart`：AppBar actions 搜索键前加入口图标（`if (!widget.secondaryHost)`，tooltip 用 `posterBrowseEntryTooltip`，`pushNamed('/screen/poster-browse')`）；**该文件有 GBK 乱码注释，用精确锚点**
   - `test/media_backend/multi_backend_abstraction_boundary_test.dart` 的 `publicBoundaryFiles` 加 poster_browse_screen.dart 与 poster_browse_loader.dart
   - ⚠️ main.dart / media_list_screen_widgets.dart 是共享热点文件，可能与另一会话的改动冲突——合并时留意
3. **合并**：`poster-browse` 分支 merge 回 `main`（worktree 与 main 都在动，先 `git -C F:\fly_play_recovered pull` 不需要——本地仓库，直接在主目录 `git merge poster-browse`；冲突预期集中在 main.dart/media_list_screen_widgets.dart，若组G 之前 main 又动了这两个文件）；合并后删 worktree：`git worktree remove F:\fly_play_poster_browse`，删分支。
4. **组H = 计划 Task 12**：主目录 `flutter analyze` + `flutter test`（全量）+ `flutter build apk --debug`；整体终审代理过一遍全部 poster-browse commit；然后按计划 Task 12 Step 3 的 8 条实机验收清单三后端手测。
5. **实机验收**（需要真机，用户参与）：验收清单见计划文档 Task 12 Step 3——重点：横竖屏往返不卡横屏、剧集起播后原生壳进度回写/选集正常（reentry 修复的实证）、飞牛"最近添加"若服务器不认 create_time 排序则整行隐藏、弱网纯色底无糊图。

## 已知遗留（非阻塞，验收时留意）

- 翻行瞬间"新行标签 + 旧条目标题"约 300ms 错配（节流设计的固有表现，实机看观感再定）。
- Emby"最近添加"用 Series.DateCreated 排序：老剧更新新集不会浮到行首（接口 doc 已注明取舍）。
- 组E 质量审查建议的"聚焦放大在真机快速切换下的观感"未实测。

## 执行流程备忘（恢复时照此继续）

- 每组：实现代理（携完整任务文本）→ 规格审查代理（独立读 diff 核验）→ 质量审查代理（Strengths/Issues/verdict）→ 有 Important+ 就打回原实现代理修、审查复核，直到 Approved。
- 共享工作区曾与另一会话两次碰撞（捎带提交/切分支），故组E 起全部改在 worktree `F:\fly_play_poster_browse`（分支 poster-browse）执行；恢复后组G/H 也在 worktree 做，最后合并。
- pre-commit 钩子会 dart format 导致首次 commit 偶尔不落地：重新 `git add` 再提交即可。
