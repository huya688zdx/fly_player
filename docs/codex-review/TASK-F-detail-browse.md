# TASK F —— 详情页与媒体浏览页评审

> 先完整阅读 `docs/codex-review/00-review-constraints.md`（约束标准 + 工作协议），再开工。
> findings 写入 `docs/codex-review/findings/F.md`，编号前缀 `F-`。

## 范围（约 1.9 万行）

1. `lib/pages/` 全部 7 个文件（`play_detail_page.dart` ~3.5k、`tv_season_detail_page.dart` ~3.3k、`tv_detail_page.dart` ~2.1k、`media_collection_detail_page.dart` ~1.3k 等）
2. `lib/screens/` 浏览类：
   - `media_list_screen.dart`、`media_list_screen_actions.dart`、`media_list_screen_widgets.dart`
   - `category_items_screen.dart`、`search_screen.dart`
   - `favorite_items_screen.dart`、`favorite_items_screen_sheets.dart`、`favorite_items_screen_widgets.dart`
   - `person_detail_screen.dart`、`media_info_screen.dart`、`detail_route_bodies.dart`
   - `detail_host_screen.dart`（通道部分归 TASK C，UI/路由部分归你）

## 本区域重点检查项

1. **[C2]/[C3] 后端耦合**——本任务第一优先级（这批页面正处于多后端迁移中）：
   - 每个页面 grep `feiniu_api` / `FeiniuApi` 直接调用点，逐个上报；
   - 数据获取是否已走 `lib/media_backend/` 抽象；`_fetch` 数据层分流的页面，检查分流点之外还有没有后端 if/else 泄漏（图片 URL 拼接、题材行、动作按钮是常见泄漏点）；
   - 显示逻辑应走 UI presenter 而非写在模型/页面里的后端判断。
2. **[M2] 详情页三兄弟重复度**：`play_detail_page` / `tv_detail_page` / `tv_season_detail_page` 合计 ~9k 行——系统性对比三者，列出重复的区块（头部海报区、演职员行、相似推荐等）与可抽取的公共组件清单。这是本任务最有价值的产出之一。
3. **[M1] 超大文件**：3k+ 行的页面给出具体拆分切面。
4. **列表/网格性能**：[P2] 懒加载、[P3] 海报图解码尺寸、滚动中触发的网络请求有没有防抖/取消；进入详情页的首帧关键路径上有没有可延后的请求。
5. **图片与 Hero**：hero 动画 + 图片加载的跳闪防护（此前修过 deferArtwork 双重门控问题，检查有没有同类残留）；`palette_generator` 取色的触发时机（不能阻塞首帧）。
6. **分页加载**：媒体列表分页的边界（重复请求、并发翻页、到底判断）。
7. 通用项全查：[M3] i18n、[M4]、[P4]、[P6]、[P7]。

## 完成标准

第一轮逐文件 + 第二轮自复核（见 00 文档第 7 节协议），最后更新 PROGRESS.md 中 TASK F 状态为 DONE。
