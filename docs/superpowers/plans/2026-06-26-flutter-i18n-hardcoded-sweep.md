# Flutter 层硬编码文案 i18n 普查（推到以后）

> 2026-06-26。用户拍板:**禁用 `_t(path, fallback)` 间接层,一律改成 `AppLocalizations.of(context).xxx`;
> Flutter 层散落的硬编码中文也要全部走 i18n**。原话:「这个是不成熟的」「所有用了的都要替换掉」
> 「flutter层硬编码的也替换成i18n」。本轮已收口 `_t` 消除(见下「已完成」),**广义硬编码普查
> 范围开放、量大,本轮先推到以后**,按区逐块做。

## 规范（已确立，见记忆 i18n-no-t-indirection）

- 直接 `final l10n = AppLocalizations.of(context); ... l10n.getterName`,**禁止**再引入 `_t` /
  `AppLocalizationLookup` / 任何「path 字符串 + 硬编码 fallback」间接层。
- 新文案:`lib/l10n/app_zh_CN.arb`(模板)+ `lib/l10n/app_zh.arb` **两个都加** `"key": "中文"`,
  再 `flutter gen-l10n`(配置 `l10n.yaml`,输出 `lib/l10n/generated/app_localizations.dart`,
  仅 zh / zh_CN 两 locale)。
- 动态 path → 本地 `switch (key)` 直接映射 getter + 兜底,不要字符串拼 path。

## 已完成（2026-06-26，工作区，analyze 净 + 165 测试过）

- 消除全部 **9 处 `String _t(`** 定义及约 **250 处调用**:
  - 自带 switch 版:`play_detail_page` / `tv_detail_page` / `tv_season_detail_page`。
  - 包装 `AppLocalizationLookup.text` 版:`category_items` / `favorite_items` / `media_list` /
    `person_detail` / `search_screen` 及其 part/widget(`*_sheets`/`*_widgets`)。
  - 首参 context 版:`widgets/common/app_error_state`。
- **删除** `lib/utils/app_localization_lookup.dart`(123 行共享查表,已无人引用)。
- `video_info_section.dart` 硬编码(`视频信息/视频/音频/字幕/查看全部`)→ l10n。
- 新增 ARB key:`detailVideoInfoTitle`、`detailVideoInfoViewAll`、`detailFeatureComingSoon`、
  `personWorks`(前几个原本藏在 `_t` 的 fallback 里 = 隐藏硬编码)。

## 待做：广义硬编码普查（按区逐块）

> 量化第一步:`grep -rnP "['\"][\\x{4e00}-\\x{9fff}]" lib/ | grep -v l10n | grep -v arb`
> 大致框出散落中文字面量规模,再按区切。

建议顺序(每区:扫描 → 补 ARB key → 替换 → `flutter gen-l10n` → `flutter analyze` + 相关单测):
1. **player mixins**(`lib/player/page_parts/**`,约 20 个 mixin,弹幕/设置/字幕/音轨抽屉等
   面板文案最密集)。
2. **widgets**(`lib/widgets/**`,详情/通用组件里仍有硬编码标题/占位/按钮文案)。
3. **screens 余量**(`lib/screens/**`,`_t` 已清,但仍可能有直接写死的 `Text('中文')`)。
4. **controllers / services 抛给 UI 的文案**(若有面向用户的字符串)。
5. **native 侧 toast/通知**(Kotlin,若走 Flutter 文案则一并;纯原生字符串另算)。

## 脚本经验（批量替换 `_t` 时踩过，复用时注意）

- 删方法体:命名参数默认值 `const {}` 的空括号会坑朴素大括号平衡器——**先平衡圆括号过完签名
  `) {`,再从方法体 `{` 平衡大括号**,否则只删到参数括号、留孤立 body。
- 多参 / 插值 getter 的参数提取要在**顶层 `,` 或 `}` 停**(用括号深度),贪婪 `.+?\}` 会把下一个
  参数串进来,产出 `foo(a, 'k': b, c)` 之类畸形;`flutter analyze` 能抓双逗号/缺标识符。
- 不同 `_t` 签名并存:多数 `_t(path, fallback)`(arg0=path),`app_error_state` 是
  `_t(context, path, fallback)`(arg0=context)——脚本按 arg0 取 path 会失配,需识别签名。

## 约束

- 飞牛日常主路径**逐像素不变**:`_t('x','fb')` → `l10n.x` 渲染同串,无视觉变化;普查阶段同理
  (只换取值通道,文案不动)。
- 不夹带 Codex 未提交文件;`play_detail_page`/`video_info_section` 与 Emby 摊子强耦合,提交随
  那摊延后(见 `public-media-frontend-status.md` 末尾)。其余 i18n 改动技术上可独立提交。
- pathspec 提交、提交前 `git diff --cached --name-only` 复核。
