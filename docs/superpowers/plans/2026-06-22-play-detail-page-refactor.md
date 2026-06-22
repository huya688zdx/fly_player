# play_detail_page 重构计划（公有化 + 拆分 + 光栅化优化）

> 2026-06-22。用户授权:「可以拆解这个页面,里面写得不好/需优化光栅化的都可以改,当一次重构」。
> 起因:Emby 详情若另起页面就违背公有化初衷(前端共用)。废弃独立 `MediaDetailScreen`,
> 让 Emby 复用这张真详情页。
> 前序:Emby 详情首光 Task 1~3(`EmbyApi.getItem`/`mapEmbyItemDetail`/`getItemDetail`)已就位、可复用。

## 现状诊断(为什么不能直接换)

`play_detail_page` ~7790 行,单个巨型 `build`,问题:
1. **整页绑死飞牛 `PlayInfoData _data`**(`info.item`=飞牛 `PlayItem`);`_detail`(中立 MediaDetail)
   只是从 `_data` 派生。`_data==null` 时成功分支直接 `_data!` 崩。
2. **图源到处自拼飞牛相对路径 + NAS token**:背景 `_persistentHeroPath()`+`ApiUrlHelper.imageCandidates`、
   动态取色 `_dynamicThemePathForPlayItem`、logo `DetailHeroLogoTitle`、头像 `CreditsSection`。
   Emby 是带 `api_key` 的完整直链,走不了这套拼接。
3. **展示半身与播放半身交织**:meta 行、`DetailSelectorRow`(字幕/音轨/能力角标)、`PlayActionBar`、
   `DetailResolutionSection`、文件/视频信息全读 `_data`/流。
4. **光栅化**:巨型 build 嵌套 sliver;入场动画用 `Opacity`+`Transform` 包大子树(触发 saveLayer/
   全子树合成);部分区块缺 `RepaintBoundary`;图片缓存尺寸部分未约束。

## 总目标

一张**中立模型驱动**的详情页同时服务飞牛 + Emby,巨型 build 拆成内聚子组件,补光栅化优化。
飞牛是日常主路径,**每步必须保持飞牛逐像素不变 + 可单独提交回滚**。

---

## 阶段一:公有化(让 Emby 复用真页面,飞牛 build 路径零改动)

策略:Emby 态 `_data=null`、`_detail` 由 `backend.getItemDetail()` 建,成功分支用
**同一批页面组件**组一个 `_detail` 驱动的展示体;飞牛分支(`_data!=null`)全程守卫、不动。

- **S1-1**:`_load` 按 `backend.capabilities.kind` 分支。Emby → `backend.getItemDetail()` 设 `_detail`、
  `_data` 留 null、置 `_neutralDisplayOnly=true`;飞牛分支原样。
- **S1-2**:页级背景 + 动态取色块:`_neutralDisplayOnly` 时图源直接喂 `_detail` 完整直链
  (绕开 `ApiUrlHelper.imageCandidates`/NAS token),否则飞牛原逻辑。
- **S1-3**:成功 build 顶部 `if (_neutralDisplayOnly) return _buildNeutralBody(...)`——复用
  `DetailHeroOverlay`/`DetailMetaLines`/`PlayActionBar`(占位禁用)/`DetailDescriptionSection`/
  `CreditsSection`,logo/头像用完整直链。**飞牛成功分支整段不动**。
  - 配套:放宽 `DetailHeroLogoTitle` 的空 token 闸为 `api_key=` 自鉴权放行(同 MediaPosterCard)。
- **S1-4**:`media_list_screen._openItemDetail` 非飞牛 → push `PlayDetailScreen`(改回真页面);
  删除独立 `MediaDetailScreen` + 其测试;保留已放宽的 `ImmersiveDetailBackground`/`CreditsSection` 闸。
- **S1-5**:实机验证(Emby 进真页面、看起来与飞牛一致、播放占位;飞牛零回归)+ 看板。

阶段一结束:Emby 用真页面、外观与飞牛一致,飞牛 build 路径未动(零回归)。

---

## 阶段二:重构(拆分巨型 build + 光栅化,飞牛 + Emby 双绿)

每步行为保持、单独提交。把成功分支逐块抽成内聚子组件,顺手补 perf:

- **S2-1 图源中立化**:抽 `DetailArtworkResolver`(UI helper):`MediaImageRef`/路径 → urls+headers,
  完整 http 直链直接用(+ref.headers),否则按飞牛路径走 `imageCandidates`+NAS token。先在背景接入、
  飞牛验证逐像素一致,再铺开。**这是让飞牛成功分支也能读 `_detail` 图、最终统一两分支的钥匙**。
  - ✅ 已落:`lib/ui/detail_artwork_resolver.dart` + 单测(8 例,JVM 过);背景 hero(`62642e9`)
    与动态取色图源(`abb0bcd`)两后端均经 resolver,飞牛输出逐字节等价、`flutter analyze` 净。
    **待实机**:Emby 进真页面背景/取色正常 + 飞牛背景逐像素不变。
  - ⏳ 待铺开:logo(`DetailHeroLogoTitle`)、海报、演职员头像(`CreditsSection`)三处图源仍内联
    `imageCandidates`,后续切片逐处改走 resolver(为 S2-6 统一铺路)。
- **S2-2 Hero 区抽组件** `_DetailHeroSection`(背景叠加 + logo 标题 + 副标题),包 `RepaintBoundary`。
- **S2-3 信息块抽组件** `_DetailInfoBlock`(meta + 选择器 + 动作条 + 画质 + playError),
  把入场动画的 `Opacity`/`Transform` 收进局部、缩小 saveLayer 作用域。
- **S2-4 次级区块**(文件/视频/链接/演职员 sliver)各抽组件 + `RepaintBoundary` + const 化。
- **S2-5 图片缓存**:逐项约束 `cacheWidth/Height`(海报/头像/logo),避免大纹理上传尖峰。
- **S2-6 统一两分支**:飞牛成功分支改读 `_detail` + resolver(等价替换),最终删掉 `_neutralDisplayOnly`
  双路,真正一套 build 两后端共用。逐字段等价、逐像素核对后才删旧路。

阶段二每步只做一块、单测/实机核对飞牛不变,再提交。

## 约束(全程)

- 飞牛日常主路径每步逐像素不变;不动下载/play stats/播放器深层 mixin。
- `lib/media_backend` 不构造 `MpvMediaSource`;UI 不写 `if(isEmby)`(数据/导航层按 kind 分支)。
- 每个小任务 **pathspec 提交**;提交前查 `git status --short`/`--cached`;不夹带 Codex 未提交文件
  (`MpvPlaybackController.kt`/`HANDOFF.md`/`.codex-remote-attachments/`);不提交真实凭据。
- 上下文偏长时输出压缩摘要并停,分多窗口推进。
