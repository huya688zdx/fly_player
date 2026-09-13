# 登录记录与启动恢复验证

基线：`8bc3b14`。功能源码：`22b5a74`（包含 `28f0111`、`ea6021b`、`3da657f`）。

## 改动

- 飞翔登录增加“记住密码”和“登录记录”，默认回填最近一次成功登录，最多保存 10 条；选记录只回填，点击登录才请求认证。
- 密码由现有 Android Keystore / Windows DPAPI 凭据层保存。历史元数据不保存密码或 token；取消记住、清除记录会删除相应密码。
- 已知服务身份在发送密码前核验；修改回填账号或地址会清空密码。仅移动密码光标也不能绕过这一限制。
- 持久保存主动选择的飞翔/媒体登录模式；返回飞翔、成功登录、主动激活绑定和退出账号均更新模式。本地模式重启不自动套用飞翔绑定或清空直连。
- 退出账号撤销当前会话，保留登录记录。记录保存失败不会把已成功认证的会话当成失败。
- 弹窗沿用 PC DesktopFloatingPanel 和 Android TrackOptionSheet；没有新增旧数据关联界面。

## 已验证

- 19 个测试文件，共 **153 项通过，无跳过**。涵盖记录存取、密码撤销、并发操作、跨服务身份、迟到回调、两种模式重建、真实 loopback HTTP 激活绑定、离线会话和既有登录路由。
- 9 个变更 Dart 文件 `flutter analyze --no-pub` 通过；`git diff --check` 通过。
- Windows Release 增量构建成功，耗时 **58.2 秒**。完整测试包：`build/windows/x64-mask-p0-integrated/bundle-login-history/`；运行其中 `Start-FlyPlayer.ps1`。`BUILD-EVIDENCE.json` 记录源码和产物哈希；旧测试包未覆盖。
- 两个平台尺寸的登录/记录浮窗组件渲染用例通过，四张 PNG 位于 `build/login-history-evidence/`，已检查桌面浮窗和手机表单。字体为测试载入的微软雅黑；这些是组件渲染，不是实机截图。
- 本机现存 Windows 会话/安装标识可解密且匹配，已选媒体绑定及令牌具备恢复条件。只检查存在性及结构，没有输出秘密，也没有据此声称远端 token 仍有效。
- Flutter、SDK、包缓存、临时文件和构建产物均复用 E 盘环境。没有修改原播放器 native 遮罩代码或依赖锁文件。

测试日志与文件列表：`.task-tmp/login-history-final-tests.log`、`.task-tmp/login-history-test-files.txt`、`.task-tmp/login-history-analysis-final.log`。

## 实机边界与回退

未验收 Android 实机安装、Windows GUI 关闭重开、真实 NAS 登录或两端实际播放。冷启动结论来自持久存储和控制器重建测试，不以构建/渲染替代实机验收。已过期或被服务端撤销的会话仍需重新认证。

旧测试包 `build/windows/x64-mask-p0-integrated/bundle-concise/` 保留，可关闭新版后从旧包启动。代码回退应反向撤销上述四个功能提交，保留其他任务成果，不重置工作区或删除用户存储。
