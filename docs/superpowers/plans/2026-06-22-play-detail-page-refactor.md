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
  - ✅ 铺开(`0aee640`):成功分支 + 加载分支的 logo、演职员头像图源全改走 resolver
    (`resolveRef`/`resolvePath`),飞牛逐字节等价、analyze 净。详情页唯一剩下的内联
    `imageCandidates` 是下载 sheet 的 `previewUrls`(属播放/下载半身,按约束保留)。
    至此 resolver 已是详情页**图源单一入口**(背景 / 取色 / logo / 头像)。
  - ✅ 收口(`e58add6`):`_buildNeutralBody` 的 logo + 头像也改走 resolver(原内联 url 列表)。
    **至此 resolver 是全页图源唯一入口(背景/取色/logo/头像,飞牛+Emby 两分支)。实机已过**
    (飞牛不变、Emby 正常)。

### S2-2~S2-5 光栅化:**重评——前人已基本做掉,不再硬拆**

实读现状(`62642e9` 后):
- 背景 `ImmersiveDetailBackground` 已**深度优化**:外层 `RepaintBoundary`(页级 `2942` 再包一层)+
  组件内 `RepaintBoundary`;滚动只重建廉价 `Transform`,`Image` 子树按 sig 缓存复用不重建;
  `cacheWidth` 约束解码;低清铺底防首帧 raster 尖峰;`api_key` 自鉴权放行。
- 入场动画(`_sectionReveal` 的 `Opacity`/`Transform`、各 `FadeTransition`)是 `TweenAnimationBuilder`
  **一次性**动画,settle 到 `opacity:1.0` 后 Flutter 自动短路、**稳态无 saveLayer**。
- 前景 `pageBody` 在 boundary 化背景之上 crossfade。

结论:**S2-2~S2-5 预设的光栅化坏味大多不存在**,硬拆只增 churn、且动画精细、风险>收益。
**暂不做**;若实机抓到具体掉帧/jank 再针对性处理。

- **S2-6 统一两分支(唯一剩余实质项)**:飞牛成功分支(`else` @ ~`2346`,深绑 `_data!`/流/选择器/
  动作条/文件视频信息)与中立 `_buildNeutralBody` 仍是两条渲染路。统一 = 让成功分支容忍 `_data==null`
  (播放半身全部 `_data!=null` 守卫、展示半身读 `_detail`),删 `_neutralDisplayOnly` + `_buildNeutralBody`。
  - **风险**:这是**改飞牛渲染路径**的大改(~370 行成功分支),违反"飞牛逐像素不变"的概率高,
    收益是可维护性/"一页两后端",**非 perf**。重复代码仅约 90 行。
  - **做法**:必须**单独会话** + 每步飞牛逐像素核对;先抽展示区共享 builder(hero/meta/描述/演职员),
    两分支同调,再逐步让成功分支吃 null `_data`。**未经实机确认不删旧路**。
  - **用户拍板**:做,但**分步 + 每步逐像素核对**(每步实机确认飞牛不变后才进下一步)。
  - ✅ **步骤1 演职员 sliver(`a7ec510`)**:抽 `_buildCreditsSliver`(复刻飞牛树:`_sectionReveal` +
    `Container` 内边距 + `CreditsSection`;`colors` 由调用方传 builder 作用域值——`DynamicPageThemeScope`
    改写子树主题,不可在 helper 内重取)。飞牛逐字节等价;Emby 顺带获得同一入场动画(统一)。
    门控留调用点。**实机已过(2026-06-23,飞牛详情页与改前无差别)**。
  - ✅ **步骤2 描述 sliver(`2445ad8`)**:抽 `_buildDescriptionSliver`(复刻飞牛树:`_descriptionPopController`
    的 `AnimatedBuilder` 入场 + `Container` 内边距 + `DetailDescriptionSection`;`text` 同时喂正文与「展开全文」
    浮层内容,`colors` 由调用方传 builder 作用域值)。飞牛逐字节等价(传未 trim 的 `detail.overview` +
    `overlayTitle: detailTitle`、无门控恒显);Emby 顺带获得控制器入场(call site 保留 `if(overview.trim().isNotEmpty)`
    空判 + 传已 trim 文案 + `overlayTitle: title`)。analyze 净。**实机已过(2026-06-23,飞牛不变)**。
  - ✅ **步骤3 hero sliver(`3376424`)**:抽 `_buildHeroSliver`(复刻飞牛树:`FadeTransition(_headerTitleOpacity)`
    入场 + `DetailHeroOverlay`,`useSoftGradient: true` 恒定)。飞牛逐字节等价(剧集态 `titleFontSize`/小
    `bottomInset`/副标题照传);Emby 顺带获得标题淡入(`_headerFadeController` 在中立加载路径已 `forward`)。
    analyze 净。**实机已过(2026-06-23,飞牛 hero 不变)**。
    - **注**:**meta 行不在本步**——飞牛 meta(`FadeTransition(_headerMetaOpacity)` + `_asyncFadeSwitcher`)
      深嵌在播放半身的 `AnimatedSize`/`ConstrainedBox`/`Column`(与 `DetailSelectorRow`/`PlayActionBar` 同列),
      不是可分离 sliver;中立 meta 是独立 `Container` + 占位播放按钮。两者结构不同,meta 收敛留到最后一步
      (成功分支吃 null `_data`)一并处理。
  - ⏳ **最后一步 待做**:成功分支吃 null `_data`(播放半身全 `_data!=null` 守卫、meta 区与中立合流)→
    删 `_neutralDisplayOnly`/`_buildNeutralBody`。**这是改飞牛渲染路径的最大一步,务必逐像素核对**。

阶段二每步只做一块、单测/实机核对飞牛不变,再提交。

## 约束(全程)

- 飞牛日常主路径每步逐像素不变;不动下载/play stats/播放器深层 mixin。
- `lib/media_backend` 不构造 `MpvMediaSource`;UI 不写 `if(isEmby)`(数据/导航层按 kind 分支)。
- 每个小任务 **pathspec 提交**;提交前查 `git status --short`/`--cached`;不夹带 Codex 未提交文件
  (`MpvPlaybackController.kt`/`HANDOFF.md`/`.codex-remote-attachments/`);不提交真实凭据。
- 上下文偏长时输出压缩摘要并停,分多窗口推进。
