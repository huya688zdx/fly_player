# 海报浏览短横屏溢出修复实施计划

**目标：** 依据真机 `853 × 384` 日志修正短横屏高度预算，不改变正常高度布局。

## Task 1：建立真机尺寸回归测试

- 修改 `test/poster_browse/poster_browse_large_layout_test.dart`。
- 使用 `853 × 384`、`TextScaler.linear(1.08)`、长标题和季集副标题。
- 先运行用例并确认因现有 `44px` 外层溢出而失败。

## Task 2：最小化修复布局

- 修改 `lib/screens/poster_browse/poster_browse_large_layout.dart`。
- 海报轨恢复为 `264px`。
- 高度低于 `600px` 时不构建媒体信息面板。
- 高度低于 `412px` 时使用上下 `8px` 和轨道前 `8px` 间距。
- 重新运行回归用例并确认通过。

## Task 3：验证

- 运行海报浏览大屏、海报卡和方向控制测试。
- 运行 `flutter analyze` 和 `git diff --check`。
- 在连接真机上安装调试包，复现横屏页面，检查日志和截图中不再出现溢出。
