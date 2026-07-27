# 原生播放壳文案交 Flutter 管理(i18n 下发通道)

日期:2026-07-27。目标:原生安卓播放页面(NativePlayerActivity 及 mpv/ 播放链路)的用户可见文案统一由 Flutter l10n 管理,Kotlin 侧不再自行维护文案内容。

## 架构

```
lib/l10n/app_zh_CN.arb / app_zh.arb        ← 权威源(native* 前缀 486 个 key)
        │ flutter gen-l10n
lib/services/native_player_localized_strings.dart
        │ buildNativePlayerLocalizedStrings(l10n) → Map<资源条目名, 文案模板>
NativePlayerBridge.launch()  →  loadArgs["localizedStrings"]        (启动注入)
bindReentry loadPlayerGlobalSettings 回包["localizedStrings"]       (前台恢复刷新)
        │
NativeLocalizedStrings.install*()          ← Kotlin 单例(同进程全局)
Context.localizedString(R.string.x, args)  ← 全部原调用点由 getString 改为此扩展
        │ map 命中 → String.format(模板, args)
        └ 未命中/异常 → context.getString(x)   (res/values/strings.xml 冻结为兜底)
```

## 关键决策

- **key = Android 资源条目名**(如 `player_text_0001`),Kotlin 用 `getResourceEntryName(id)` 动态解析,不维护第二张 key 表。
- **arb 值保留 Android 位置格式原样**(`%1$s`/`%1$d`/`%%`),arb 中都是无占位符的简单 getter,Flutter 自身不消费这些文案;Kotlin `String.format` 套参,与 `getString(id, args)` 行为一致。
- **strings.xml 不删、冻结为兜底**:下发时序空窗(冷启动早期)、回包异常、格式化失败时保证有文案可显示;文案修改一律改 arb(权威源),strings.xml 只在新增条目时同步加兜底。
- 仓库当前仅 zh / zh_CN 两个 locale,未臆造 en;系统语言不受支持时回退 `lookupAppLocalizations(Locale('zh'))`。
- 语言切换时机:每次启动播放随 loadArgs 注入;播放中切语言,依赖原生壳前台恢复时的 `loadPlayerGlobalSettings` 刷新。

## 新增文案流程

1. `android/app/src/main/res/values/strings.xml` 加兜底条目(中文);
2. `lib/l10n/app_zh_CN.arb` 与 `app_zh.arb` 加 `native<CamelCase条目名>` key;
3. `lib/services/native_player_localized_strings.dart` 映射表加一行;
4. Kotlin 侧用 `localizedString(R.string.新条目)` 取文案(禁止 getString / 内联字符串)。

批量镜像生成脚本(一次性迁移用):scratchpad `gen_native_strings.py`,从 strings.xml 生成 arb 条目 + Dart 映射表,含 ICU 危险字符与 key 冲突校验。
