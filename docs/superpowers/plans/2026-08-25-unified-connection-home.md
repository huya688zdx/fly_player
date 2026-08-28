# 飞翔播放器统一连接首页实施计划

> **For agentic workers:** Execute these steps inline unless the user explicitly requests another workflow. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将连接首页改造成深海雾蓝的一体登录卡，在手机与平板上统一飞牛影视、Emby、Jellyfin 的布局与地址规则，并同步更新登录历史 Logo 和产品名称。

**Architecture:** 保留现有 provider、API、登录历史存储和认证流程，只重构连接页的展示层与地址输入边界。新增一个无状态地址规范化工具；连接页继续为每个后端保留独立表单状态，并通过固定尺寸骨架和轻量选中态动画消除切换抖动。

**Tech Stack:** Flutter、Dart、Provider、flutter_test、Flutter l10n、Android XML resources

---

## 文件结构

- Create: `lib/utils/connection_server_address.dart`
  - 只负责连接页服务器地址的统一规范化；不改变 `ApiUrlHelper` 或 `EmbyApi` 的全局默认协议。
- Create: `test/utils/connection_server_address_test.dart`
  - 纯函数测试，覆盖空值、裸域名、裸 IP、显式 HTTP/HTTPS 和 Emby Web 路径。
- Modify: `lib/screens/connection_screen.dart`
  - 统一登录卡、固定骨架、服务切换动画、飞牛更多选项、地址接入和响应式布局。
- Modify: `test/screens/connection_backend_selection_test.dart`
  - 服务名、独立表单状态、主按钮几何稳定性和响应式尺寸测试。
- Modify: `test/screens/connection_feiniu_compatibility_test.dart`
  - 移除旧协议分段控件断言，新增默认空地址、访问码更多选项和完整 URL 提交测试。
- Modify: `test/screens/connection_emby_authentication_test.dart`
  - 验证裸地址补 HTTPS，同时保留 Emby/Jellyfin 认证行为。
- Modify: `test/connection_login_persistence_test.dart`
  - 保持登录数据与历史回填仍可恢复真实地址。
- Modify: `lib/screens/login_history_screen.dart`
  - 将文字头像替换为项目现有的后端 Logo。
- Modify: `test/screens/login_history_screen_test.dart`
  - 断言真实 Logo、长地址省略、点击回填和删除行为。
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_zh_CN.arb`
  - 产品名、更多选项文案和中性地址提示。
- Modify: `lib/l10n/generated/app_localizations.dart`
- Modify: `lib/l10n/generated/app_localizations_zh.dart`
  - 由 `flutter gen-l10n` 生成。
- Modify: `lib/main.dart`
  - 更新无本地化环境下的应用标题回退值。
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `android/app/src/main/res/values/strings.xml`
  - Android 桌面名称使用字符串资源“飞翔播放器”。

## 执行约束

- 代码调查与修改由 Luna 执行，主代理只负责设计一致性、diff 审阅和最终质量验收。
- 不使用 `git add -A`、`git add .`、`git reset --hard` 或跨文件恢复命令。
- 每次提交只暂存任务列出的文件；工作区其他二进制、原生播放器和下载模块改动保持原样。
- 若开始执行时 `lib/screens/connection_screen.dart` 的 diff 已出现 Luna 本轮以外的新来源，立即停止恢复步骤并报告，不猜测恢复边界。

---

### Task 1: 精确恢复连接页视觉实验

**Files:**
- Restore: `lib/screens/connection_screen.dart`
- Verify only: entire working tree status

- [ ] **Step 1: 记录连接页与全工作区当前状态**

Run:

```powershell
git status --short
git diff --stat -- lib/screens/connection_screen.dart
git diff -- lib/screens/connection_screen.dart
```

Expected:

- `lib/screens/connection_screen.dart` 显示 Luna 本轮约 310 行新增、195 行删除的视觉实验。
- 其他脏文件同时存在，但本任务不触碰它们。

- [ ] **Step 2: 确认该文件在 Luna 开始前没有用户未提交修改**

核对设计阶段调查记录：Luna 开始前的 `git status --short` 不包含 `lib/screens/connection_screen.dart`。若当前 diff 中出现设计阶段之后的额外修改，停止本任务；否则继续。

- [ ] **Step 3: 只恢复连接页到 HEAD**

Run:

```powershell
git restore --source=HEAD --worktree -- lib/screens/connection_screen.dart
```

Expected: 命令无错误输出。

- [ ] **Step 4: 验证恢复范围**

Run:

```powershell
git status --short -- lib/screens/connection_screen.dart
git diff --exit-code -- lib/screens/connection_screen.dart
git status --short
```

Expected:

- 前两条命令无输出且退出码为 0。
- 全工作区其他既有修改仍在，未被恢复或暂存。

- [ ] **Step 5: 运行连接页基线测试**

Run:

```powershell
flutter test test/screens/connection_backend_selection_test.dart
flutter test test/screens/connection_feiniu_compatibility_test.dart
flutter test test/screens/connection_emby_authentication_test.dart
flutter test test/connection_login_persistence_test.dart
flutter test test/screens/login_history_screen_test.dart
```

Expected: 五个测试文件均以 `All tests passed!` 结束。若 HEAD 基线已有失败，记录精确测试名并停止，不把基线失败归因于新设计。

---

### Task 2: 统一服务器地址规则并清除个人域名默认值

**Files:**
- Create: `lib/utils/connection_server_address.dart`
- Create: `test/utils/connection_server_address_test.dart`
- Modify: `lib/screens/connection_screen.dart`
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_zh_CN.arb`
- Modify: `test/screens/connection_feiniu_compatibility_test.dart`
- Modify: `test/screens/connection_emby_authentication_test.dart`
- Modify: `test/connection_login_persistence_test.dart`

- [ ] **Step 1: 写地址纯函数的失败测试**

Create `test/utils/connection_server_address_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/utils/connection_server_address.dart';

void main() {
  group('normalizeConnectionServerAddress', () {
    test('空地址保持为空', () {
      expect(normalizeConnectionServerAddress('  '), isEmpty);
    });

    test('裸域名默认补 HTTPS', () {
      expect(
        normalizeConnectionServerAddress('nas.example.com'),
        'https://nas.example.com',
      );
    });

    test('裸 IP 和端口默认补 HTTPS', () {
      expect(
        normalizeConnectionServerAddress('100.125.130.96:8096'),
        'https://100.125.130.96:8096',
      );
    });

    test('显式 HTTP 不自动升级', () {
      expect(
        normalizeConnectionServerAddress('http://nas.example.com:5667'),
        'http://nas.example.com:5667',
      );
    });

    test('显式 HTTPS 保留路径', () {
      expect(
        normalizeConnectionServerAddress(
          'https://nas.example.com/media',
        ),
        'https://nas.example.com/media',
      );
    });

    test('服务器族清除 Web 客户端路径', () {
      expect(
        normalizeConnectionServerAddress(
          'emby.example.com/web/index.html',
          stripEmbyWebClientPath: true,
        ),
        'https://emby.example.com',
      );
    });
  });
}
```

- [ ] **Step 2: 运行纯函数测试并确认红灯**

Run:

```powershell
flutter test test/utils/connection_server_address_test.dart
```

Expected: FAIL，错误为 `connection_server_address.dart` 不存在或 `normalizeConnectionServerAddress` 未定义。

- [ ] **Step 3: 实现最小地址规范化工具**

Create `lib/utils/connection_server_address.dart`:

```dart
import '../api/emby_api.dart';
import 'api_url_helper.dart';

String normalizeConnectionServerAddress(
  String raw, {
  bool stripEmbyWebClientPath = false,
}) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';

  final hasExplicitScheme = RegExp(
    r'^https?://',
    caseSensitive: false,
  ).hasMatch(trimmed);
  final candidate = hasExplicitScheme ? trimmed : 'https://$trimmed';
  final normalized = stripEmbyWebClientPath
      ? EmbyApi.normalizeServerUrl(candidate)
      : ApiUrlHelper.normalizeBaseUrl(candidate);
  final uri = Uri.tryParse(normalized);

  if (uri == null ||
      uri.host.isEmpty ||
      (uri.scheme.toLowerCase() != 'http' &&
          uri.scheme.toLowerCase() != 'https')) {
    return '';
  }
  return normalized;
}
```

- [ ] **Step 4: 运行纯函数测试并确认绿灯**

Run:

```powershell
flutter test test/utils/connection_server_address_test.dart
```

Expected: `All tests passed!`。

- [ ] **Step 5: 写首次地址为空和中性提示的失败测试**

在 `test/screens/connection_feiniu_compatibility_test.dart` 的现有连接页测试组中加入：

```dart
testWidgets('首次进入不预填真实服务器地址', (tester) async {
  await _pumpConnectionScreen(tester, baseUrl: '');

  final field = tester.widget<TextField>(
    find.byKey(const Key('connectionServerAddressField')),
  );
  expect(field.controller!.text, isEmpty);
  expect(field.decoration!.hintText, isNot(contains('geqian688')));
  expect(field.decoration!.hintText, isNot(contains('feiniu.geqian.sbs')));
});
```

该测试复用文件中现有的 `_pumpConnectionScreen`；实现必须给服务器输入框增加稳定键 `connectionServerAddressField`。

- [ ] **Step 6: 运行单个新测试并确认红灯**

Run:

```powershell
flutter test test/screens/connection_feiniu_compatibility_test.dart --plain-name "首次进入不预填真实服务器地址"
```

Expected: FAIL，原因是输入框缺少稳定键或提示仍包含个人域名。

- [ ] **Step 7: 将连接页接入统一地址规则**

在 `lib/screens/connection_screen.dart`：

1. 导入工具：

```dart
import '../utils/connection_server_address.dart';
```

2. `initState()` 中只回填 provider 的真实保存值，不再拆分协议：

```dart
_baseUrlController.text = provider.sourceBaseUrl;
```

3. 飞牛提交保留 FN Connect ID 特殊处理，普通地址走统一函数：

```dart
String _normalizeBaseUrlInput(String raw) {
  final trimmed = raw.trim();
  final fnConnectId = FeiniuApi.extractFnConnectIdFromInput(trimmed);
  if (fnConnectId != null) return fnConnectId;
  return normalizeConnectionServerAddress(trimmed);
}
```

4. Emby/Jellyfin 提交使用：

```dart
final baseUrl = normalizeConnectionServerAddress(
  form.baseUrl.text,
  stripEmbyWebClientPath: true,
);
```

5. 历史回填使用完整地址：

```dart
_baseUrlController.text = entry.baseUrl;
```

6. 删除 `_baseUrlScheme`、`_schemeForLogin()`、`_selectBaseUrlScheme()`、`_syncBaseUrlScheme()`、`_displayBaseUrlForLogin()` 和 `_buildProtocolSelector()` 及其调用。

7. 给服务器地址 `TextField` 设置：

```dart
key: const Key('connectionServerAddressField'),
```

- [ ] **Step 8: 更新中性地址提示和相关测试**

在 `lib/l10n/app_zh.arb` 与 `lib/l10n/app_zh_CN.arb` 中将：

```json
"connectionServerExample": "例如：https://feiniu.geqian.sbs:5667"
```

替换为：

```json
"connectionServerExample": "例如：https://nas.example.com"
```

在 `test/screens/connection_feiniu_compatibility_test.dart` 删除 `SegmentedButton<String>`、HTTP/HTTPS selected 值和协议同步断言，改为完整 URL 提交断言。在 `test/screens/connection_emby_authentication_test.dart` 断言裸 Emby/Jellyfin 地址最终以 `https://` 提交；在 `test/connection_login_persistence_test.dart` 保留已保存完整地址与历史地址原样回填的断言。

- [ ] **Step 9: 运行地址和登录兼容测试**

Run:

```powershell
flutter gen-l10n
dart format lib/utils/connection_server_address.dart test/utils/connection_server_address_test.dart lib/screens/connection_screen.dart test/screens/connection_feiniu_compatibility_test.dart test/screens/connection_emby_authentication_test.dart test/connection_login_persistence_test.dart
flutter test test/utils/connection_server_address_test.dart
flutter test test/screens/connection_feiniu_compatibility_test.dart
flutter test test/screens/connection_emby_authentication_test.dart
flutter test test/connection_login_persistence_test.dart
```

Expected: 四条测试命令均以 `All tests passed!` 结束。

- [ ] **Step 10: 提交地址规则改动**

Run:

```powershell
git add -- lib/utils/connection_server_address.dart test/utils/connection_server_address_test.dart lib/screens/connection_screen.dart test/screens/connection_feiniu_compatibility_test.dart test/screens/connection_emby_authentication_test.dart test/connection_login_persistence_test.dart lib/l10n/app_zh.arb lib/l10n/app_zh_CN.arb lib/l10n/generated/app_localizations.dart lib/l10n/generated/app_localizations_zh.dart
git diff --cached --check
git commit -m "fix: 统一连接地址输入规则"
```

Expected: 只提交列出的地址规则、测试和本地化生成文件。

---

### Task 3: 建立统一固定骨架与丝滑服务切换

**Files:**
- Modify: `lib/screens/connection_screen.dart`
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_zh_CN.arb`
- Modify: `test/screens/connection_backend_selection_test.dart`
- Modify: `test/screens/connection_feiniu_compatibility_test.dart`

- [ ] **Step 1: 写完整服务名、几何稳定和独立状态测试**

在 `test/screens/connection_backend_selection_test.dart` 加入：

```dart
testWidgets('三种服务完整显示且主按钮位置稳定', (tester) async {
  await _pumpConnectionScreen(tester, baseUrl: '');

  expect(find.text('飞牛影视'), findsOneWidget);
  expect(find.text('Emby'), findsOneWidget);
  expect(find.text('Jellyfin'), findsOneWidget);

  final button = find.byKey(const Key('connectionSubmitButton'));
  final feiniuRect = tester.getRect(button);

  await tester.tap(find.text('Emby'));
  await tester.pumpAndSettle();
  final embyRect = tester.getRect(button);

  await tester.tap(find.text('Jellyfin'));
  await tester.pumpAndSettle();
  final jellyfinRect = tester.getRect(button);

  expect(embyRect.top, closeTo(feiniuRect.top, 1));
  expect(jellyfinRect.top, closeTo(feiniuRect.top, 1));
  expect(embyRect.left, closeTo(feiniuRect.left, 1));
  expect(jellyfinRect.left, closeTo(feiniuRect.left, 1));
  expect(embyRect.width, closeTo(feiniuRect.width, 1));
  expect(jellyfinRect.width, closeTo(feiniuRect.width, 1));
});
```

并加入独立状态测试：分别在 Emby 与 Jellyfin 输入服务器、账号、密码，切换两次后按字段键断言各自文本仍保留。给三类字段使用包含后端名的稳定键，例如 `serverAddress_emby`、`userName_emby`、`password_emby`。

- [ ] **Step 2: 写飞牛更多选项的失败测试**

在 `test/screens/connection_feiniu_compatibility_test.dart` 加入：

```dart
testWidgets('飞牛更多选项展开并在切换服务后收起', (tester) async {
  await _pumpConnectionScreen(tester, baseUrl: '');

  expect(find.byKey(const Key('feiniuAccessCodeField')), findsNothing);

  await tester.tap(find.byKey(const Key('feiniuAdvancedOptionsButton')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('feiniuAccessCodeField')), findsOneWidget);

  await tester.tap(find.text('Emby'));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('feiniuAccessCodeField')), findsNothing);

  await tester.tap(find.text('飞牛影视'));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('feiniuAccessCodeField')), findsNothing);
});
```

- [ ] **Step 3: 运行新测试并确认红灯**

Run:

```powershell
flutter test test/screens/connection_backend_selection_test.dart --plain-name "三种服务完整显示且主按钮位置稳定"
flutter test test/screens/connection_feiniu_compatibility_test.dart --plain-name "飞牛更多选项展开并在切换服务后收起"
```

Expected:

- 第一个测试因缺少 `connectionSubmitButton` 或按钮位置变化而失败。
- 第二个测试因缺少更多选项按钮而失败。

- [ ] **Step 4: 增加飞牛高级选项状态和本地化文案**

在 `_ConnectionScreenState` 增加：

```dart
bool _showFeiniuAdvanced = false;
```

在 `_selectBackend()` 的 `setState` 中加入：

```dart
if (next != MediaBackendKind.feiniu) {
  _showFeiniuAdvanced = false;
}
```

在两份 ARB 新增：

```json
"connectionMoreOptions": "更多选项",
"connectionCollapseOptions": "收起更多选项"
```

运行：

```powershell
flutter gen-l10n
```

Expected: 本地化生成文件包含 `connectionMoreOptions` 和 `connectionCollapseOptions` getter。

- [ ] **Step 5: 将访问码放入飞牛更多选项**

在固定选项行中使用：

```dart
if (_selectedBackend == MediaBackendKind.feiniu)
  Align(
    alignment: Alignment.centerRight,
    child: TextButton(
      key: const Key('feiniuAdvancedOptionsButton'),
      onPressed: () {
        setState(() {
          _showFeiniuAdvanced = !_showFeiniuAdvanced;
        });
      },
      child: Text(
        _showFeiniuAdvanced
            ? l10n.connectionCollapseOptions
            : l10n.connectionMoreOptions,
      ),
    ),
  )
else
  const SizedBox(width: 1),
```

访问码字段只在飞牛展开时插入：

```dart
if (_selectedBackend == MediaBackendKind.feiniu &&
    _showFeiniuAdvanced)
  _GlassField(
    key: const Key('feiniuAccessCodeFieldContainer'),
    textFieldKey: const Key('feiniuAccessCodeField'),
    controller: _accessCodeController,
    labelText: l10n.connectionAccessCodeOptional,
    hintText: '',
    leadingIcon: Icons.key_rounded,
    obscureText: _obscureAccessCode,
    textInputAction: TextInputAction.done,
    onSubmitted: (_) => _submit(),
    suffix: IconButton(
      tooltip: l10n.connectionAccessCodeOptional,
      onPressed: () {
        setState(() {
          _obscureAccessCode = !_obscureAccessCode;
        });
      },
      icon: Icon(
        _obscureAccessCode
            ? Icons.visibility_off_outlined
            : Icons.visibility_outlined,
      ),
    ),
  ),
```

- [ ] **Step 6: 将服务切换器改为固定三等分滑动选中态**

在 `_BackendSelector` 内使用固定三等分 Stack；选中背景只平移，不改变父级尺寸：

```dart
final animationDuration = MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : const Duration(milliseconds: 180);

LayoutBuilder(
  builder: (context, constraints) {
    final index = backends.indexWhere((item) => item.kind == selected);
    final alignment = switch (index) {
      0 => Alignment.centerLeft,
      1 => Alignment.center,
      _ => Alignment.centerRight,
    };

    return Stack(
      children: [
        AnimatedAlign(
          alignment: alignment,
          duration: animationDuration,
          curve: Curves.easeOutCubic,
          child: SizedBox(
            width: constraints.maxWidth / backends.length,
            height: 48,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.appColors.selectionSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: context.appColors.borderSubtle,
                ),
              ),
            ),
          ),
        ),
        Row(
          children: [
            for (final backend in backends)
              Expanded(
                child: InkWell(
                  onTap: () => onChanged(backend.kind),
                  child: SizedBox(
                    height: 48,
                    child: Center(
                      child: Text(
                        backend.displayName(l10n),
                        maxLines: 1,
                        overflow: TextOverflow.visible,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  },
)
```

服务项继续显示现有真实 Logo 与完整名称，不得加入发光阴影。

- [ ] **Step 7: 固定表单骨架和错误区域**

在 `_ConnectionScreenState` 增加固定错误状态，并在每次提交开始时清空、校验或网络失败时写入现有本地化错误文案：

```dart
String? _inlineError;

void _setInlineError(String? message) {
  if (!mounted) return;
  setState(() {
    _inlineError = message;
  });
}
```

在 `_submitWithUnifiedErrors()` 与 `_verifyServerConnection()` 开始处调用：

```dart
_setInlineError(null);
```

将这两个流程中原先只调用 `_showTopTip()` 的失败分支同步改为 `_setInlineError(message)`；成功后保持为空。原有异常分类和本地化消息选择逻辑不变。

`_buildForm()` 的顺序固定为标题、三个主字段、选项行、固定错误区、主按钮和次操作。主按钮增加稳定键：

```dart
_SubmitButton(
  key: const Key('connectionSubmitButton'),
  isSubmitting: _isSubmitting,
  label: l10n.connectionLogin,
  onPressed: _isSubmitting ? null : _submit,
)
```

固定错误区域使用：

```dart
SizedBox(
  height: 36,
  child: AnimatedSwitcher(
    duration: const Duration(milliseconds: 120),
    child: _inlineError == null
        ? const SizedBox.shrink()
        : Align(
            key: ValueKey<String>(_inlineError!),
            alignment: Alignment.centerLeft,
            child: Text(
              _inlineError!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
  ),
)
```

服务切换只对标题和输入内容使用 120ms 交叉淡化；不得使用 `AnimatedSize`、`Spacer` 或因服务类型不同而变化的主字段空白高度。

- [ ] **Step 8: 应用深海雾蓝视觉令牌**

只使用 `context.appColors` 已有令牌：

```dart
final colors = context.appColors;
final panelColor = colors.surface;
final fieldColor = colors.surfaceSubtle;
final borderColor = colors.borderSubtle;
final selectedColor = colors.selectionSoft;
final primaryText = colors.textPrimary;
final secondaryText = colors.textSecondary;
final mutedText = colors.textMuted;
```

主按钮使用低饱和主题强调色，禁止高饱和绿底、青绿到蓝色渐变和霓虹阴影。Logo 保持原资源颜色，作为页面主要彩色元素。

- [ ] **Step 9: 运行统一骨架测试**

Run:

```powershell
flutter gen-l10n
dart format lib/screens/connection_screen.dart test/screens/connection_backend_selection_test.dart test/screens/connection_feiniu_compatibility_test.dart
flutter test test/screens/connection_backend_selection_test.dart
flutter test test/screens/connection_feiniu_compatibility_test.dart
```

Expected: 两个测试文件均以 `All tests passed!` 结束；测试日志无 overflow 异常。

- [ ] **Step 10: 提交统一表单改动**

Run:

```powershell
git add -- lib/screens/connection_screen.dart test/screens/connection_backend_selection_test.dart test/screens/connection_feiniu_compatibility_test.dart lib/l10n/app_zh.arb lib/l10n/app_zh_CN.arb lib/l10n/generated/app_localizations.dart lib/l10n/generated/app_localizations_zh.dart
git diff --cached --check
git commit -m "feat: 重设计统一连接首页"
```

Expected: 提交只包含连接页、相关测试和本地化生成文件。

---

### Task 4: 增加手机与平板响应式布局

**Files:**
- Modify: `lib/screens/connection_screen.dart`
- Modify: `test/screens/connection_backend_selection_test.dart`

- [ ] **Step 1: 写多尺寸和大字体失败测试**

在 `test/screens/connection_backend_selection_test.dart` 增加：

```dart
testWidgets('手机与平板尺寸均无溢出', (tester) async {
  for (final size in const <Size>[
    Size(360, 800),
    Size(390, 844),
    Size(600, 900),
    Size(839, 1000),
    Size(840, 600),
    Size(1200, 800),
  ]) {
    await tester.binding.setSurfaceSize(size);
    await _pumpConnectionScreen(tester, baseUrl: '');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: '尺寸 $size 溢出');
    expect(
      find.byKey(const Key('connectionSubmitButton')),
      findsOneWidget,
    );
    if (size.width >= 840) {
      expect(
        find.byKey(const Key('connectionWideBrandPane')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('connectionWideFormPane')),
        findsOneWidget,
      );
    } else {
      expect(
        find.byKey(const Key('connectionWideBrandPane')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('connectionWideFormPane')),
        findsNothing,
      );
    }
  }

  addTearDown(() => tester.binding.setSurfaceSize(null));
});
```

增加大字体测试：

```dart
testWidgets('窄屏大字体保持可滚动且无溢出', (tester) async {
  await tester.binding.setSurfaceSize(const Size(320, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await _pumpConnectionScreen(
    tester,
    baseUrl: '',
    textScaler: const TextScaler.linear(1.6),
  );
  await tester.pumpAndSettle();

  expect(tester.takeException(), isNull);
  expect(find.byType(SingleChildScrollView), findsOneWidget);
});
```

- [ ] **Step 2: 运行响应式测试并确认红灯**

Run:

```powershell
flutter test test/screens/connection_backend_selection_test.dart --plain-name "手机与平板尺寸均无溢出"
flutter test test/screens/connection_backend_selection_test.dart --plain-name "窄屏大字体保持可滚动且无溢出"
```

Expected: FAIL，原因是旧布局不存在 `connectionWideBrandPane` 与 `connectionWideFormPane`。

- [ ] **Step 3: 实现单栏与双栏响应式根布局**

在保留现有 `Listener`、`GestureDetector` 和 `SafeArea` 的前提下，将主体提取为：

```dart
Widget _buildResponsiveConnectionBody(
  BuildContext context,
  ThemeData theme,
  AppLocalizations l10n,
) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final isWide = constraints.maxWidth >= 840;
      final minHeight = math.max(0.0, constraints.maxHeight - 40);
      final formColumn = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BackendSelector(
            l10n: l10n,
            selected: _selectedBackend,
            onChanged: _selectBackend,
          ),
          const SizedBox(height: 12),
          _buildForm(theme, l10n),
        ],
      );

      final content = isWide
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 280,
                  child: _LogoHeader(title: l10n.connectionAppName),
                ),
                const SizedBox(width: 32),
                SizedBox(width: 460, child: formColumn),
              ],
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _LogoHeader(title: l10n.connectionAppName),
                    const SizedBox(height: 18),
                    formColumn,
                  ],
                ),
              ),
            );

      return SingleChildScrollView(
        keyboardDismissBehavior:
            ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: content,
        ),
      );
    },
  );
}
```

在文件顶部加入：

```dart
import 'dart:math' as math;
```

- [ ] **Step 4: 增加平板结构键并断言布局切换**

给宽屏左栏与右栏分别添加：

```dart
key: const Key('connectionWideBrandPane')
```

```dart
key: const Key('connectionWideFormPane')
```

在测试中设置 `Size(840, 600)` 后断言两者存在；设置 `Size(839, 1000)` 后断言两者不存在，且登录卡宽度不超过 500 逻辑像素。

- [ ] **Step 5: 运行响应式测试**

Run:

```powershell
dart format lib/screens/connection_screen.dart test/screens/connection_backend_selection_test.dart
flutter test test/screens/connection_backend_selection_test.dart
```

Expected: `All tests passed!`，所有尺寸的 `tester.takeException()` 均为 null。

- [ ] **Step 6: 提交响应式布局**

Run:

```powershell
git add -- lib/screens/connection_screen.dart test/screens/connection_backend_selection_test.dart
git diff --cached --check
git commit -m "feat: 适配连接页平板布局"
```

Expected: 提交只包含连接页和其响应式测试。

---

### Task 5: 登录历史使用真实服务 Logo

**Files:**
- Modify: `lib/screens/login_history_screen.dart`
- Modify: `test/screens/login_history_screen_test.dart`

- [ ] **Step 1: 写真实 Logo 失败测试**

在 `test/screens/login_history_screen_test.dart` 的现有历史列表测试组加入：

```dart
testWidgets('历史列表使用真实后端 Logo', (tester) async {
  await tester.pumpWidget(
    host(<LoginHistoryEntry>[
      feiniuEntry,
      embyEntry,
      const LoginHistoryEntry(
        kind: MediaBackendKind.jellyfin,
        baseUrl: 'https://jellyfin.example.test',
        userName: 'alice',
        password: 'pw',
        rememberPassword: true,
        updatedAtMillis: 0,
      ),
    ]),
  );
  await tester.pumpAndSettle();

  expect(
    find.byKey(const ValueKey<String>('backend_logo_feiniu')),
    findsOneWidget,
  );
  expect(
    find.byKey(const ValueKey<String>('backend_logo_emby')),
    findsOneWidget,
  );
  expect(
    find.byKey(const ValueKey<String>('backend_logo_jellyfin')),
    findsOneWidget,
  );
  expect(find.text('FN'), findsNothing);
  expect(find.text('E'), findsNothing);
  expect(find.text('JF'), findsNothing);
});
```

- [ ] **Step 2: 运行新测试并确认红灯**

Run:

```powershell
flutter test test/screens/login_history_screen_test.dart --plain-name "历史列表使用真实后端 Logo"
```

Expected: FAIL，原因是三个 `backend_logo_*` 键不存在，旧实现仍显示文字头像。

- [ ] **Step 3: 将 BackendLogo 替换为真实资源**

在 `lib/screens/login_history_screen.dart` 用以下实现替换当前 `BackendLogo`：

```dart
class BackendLogo extends StatelessWidget {
  const BackendLogo({
    super.key,
    required this.kind,
    this.size = 40,
  });

  final MediaBackendKind kind;
  final double size;

  String get _assetName {
    return switch (kind) {
      MediaBackendKind.feiniu => 'lib/img/feiniu_Logo.png',
      MediaBackendKind.emby => 'lib/img/Emby_logo.png',
      MediaBackendKind.jellyfin => 'lib/img/jellyfin_logo.png',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: kind.name,
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.asset(
          _assetName,
          key: ValueKey<String>('backend_logo_${kind.name}'),
          width: size,
          height: size,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
```

删除 `descriptor?.badgeText`、文字前景/背景颜色和旧文字头像注释。保留历史行地址现有的 `maxLines: 1` 与 `TextOverflow.ellipsis`。

- [ ] **Step 4: 验证点击、删除和长地址行为未回退**

在同一测试文件运行现有历史条目回传、删除失败提示、长地址布局测试；若缺少 Jellyfin 回填覆盖，新增一条 Jellyfin 历史并断言返回的 `kind == MediaBackendKind.jellyfin`。

Run:

```powershell
dart format lib/screens/login_history_screen.dart test/screens/login_history_screen_test.dart
flutter test test/screens/login_history_screen_test.dart
```

Expected: `All tests passed!`，日志无 RenderFlex overflow。

- [ ] **Step 5: 提交历史 Logo 改动**

Run:

```powershell
git add -- lib/screens/login_history_screen.dart test/screens/login_history_screen_test.dart
git diff --cached --check
git commit -m "feat: 使用后端 Logo 展示登录历史"
```

Expected: 提交只包含历史页面和其测试。

---

### Task 6: 全局用户可见产品名改为飞翔播放器

**Files:**
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_zh_CN.arb`
- Modify: `lib/l10n/generated/app_localizations.dart`
- Modify: `lib/l10n/generated/app_localizations_zh.dart`
- Modify: `lib/main.dart`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `android/app/src/main/res/values/strings.xml`
- Modify: `test/screens/connection_backend_selection_test.dart`

- [ ] **Step 1: 写连接页产品名失败测试**

在 `test/screens/connection_backend_selection_test.dart` 加入：

```dart
testWidgets('连接页使用统一产品名', (tester) async {
  await _pumpConnectionScreen(tester, baseUrl: '');

  expect(find.text('飞翔播放器'), findsOneWidget);
  expect(find.text('飞牛播放器'), findsNothing);
});
```

- [ ] **Step 2: 运行新测试并确认红灯**

Run:

```powershell
flutter test test/screens/connection_backend_selection_test.dart --plain-name "连接页使用统一产品名"
```

Expected: FAIL，当前连接页仍显示“飞牛播放器”。

- [ ] **Step 3: 更新 Flutter 用户可见名称**

在两份 ARB 中设置：

```json
"appTitle": "飞翔播放器",
"connectionAppName": "飞翔播放器"
```

在 `lib/main.dart` 的 `MaterialApp` fallback 中设置：

```dart
title: '飞翔播放器',
```

Run:

```powershell
flutter gen-l10n
```

Expected: 生成的中文本地化文件返回“飞翔播放器”。

- [ ] **Step 4: 更新 Android 桌面名称**

在 `android/app/src/main/AndroidManifest.xml` 将 application label 改为：

```xml
android:label="@string/app_name"
```

在 `android/app/src/main/res/values/strings.xml` 的 `<resources>` 内加入：

```xml
<string name="app_name">飞翔播放器</string>
```

- [ ] **Step 5: 审计剩余旧名称**

Run:

```powershell
rg -n '飞牛播放器|Fly Player|android:label="fly_player"' lib android/app/src/main/AndroidManifest.xml android/app/src/main/res/values
```

Expected:

- 连接页、设置/关于页、本地化标题和 Android label 不再出现旧产品名。
- API client name、日志前缀、内部协议标识若不是用户可见内容则保持不变，并在执行记录中列出，不做无关重命名。

- [ ] **Step 6: 运行改名测试与 Android 资源检查**

Run:

```powershell
dart format lib/main.dart test/screens/connection_backend_selection_test.dart
flutter test test/screens/connection_backend_selection_test.dart
flutter analyze
```

Expected: 测试以 `All tests passed!` 结束，`flutter analyze` 报告 `No issues found!`。

- [ ] **Step 7: 提交产品改名**

Run:

```powershell
git add -- lib/l10n/app_zh.arb lib/l10n/app_zh_CN.arb lib/l10n/generated/app_localizations.dart lib/l10n/generated/app_localizations_zh.dart lib/main.dart android/app/src/main/AndroidManifest.xml android/app/src/main/res/values/strings.xml test/screens/connection_backend_selection_test.dart
git diff --cached --check
git commit -m "feat: 更新产品名为飞翔播放器"
```

Expected: 提交只包含用户可见名称和相应测试，不修改包名或 applicationId。

---

### Task 7: 全量质量审阅与构建验证

**Files:**
- Review: all files changed by Tasks 2–6
- Modify only if verification finds a scoped defect

- [ ] **Step 1: 审阅提交和工作区边界**

Run:

```powershell
git log --oneline -5
git status --short
git diff b87c5fc..HEAD --stat
git diff b87c5fc..HEAD -- lib/screens/connection_screen.dart lib/screens/login_history_screen.dart lib/utils/connection_server_address.dart
```

Expected:

- `b87c5fc` 之后的实现提交分别对应地址、统一表单、响应式、历史 Logo 和产品改名；若实际合并提交，文件边界仍须与本计划一致。
- 原先与播放器、下载、二进制库相关的脏文件仍未被这些提交暂存。
- 不存在与本需求无关的重构。

- [ ] **Step 2: 检查格式和静态分析**

Run:

```powershell
dart format --output=none --set-exit-if-changed lib/main.dart lib/screens/connection_screen.dart lib/screens/login_history_screen.dart lib/utils/connection_server_address.dart test/utils/connection_server_address_test.dart test/screens/connection_backend_selection_test.dart test/screens/connection_feiniu_compatibility_test.dart test/screens/connection_emby_authentication_test.dart test/connection_login_persistence_test.dart test/screens/login_history_screen_test.dart
flutter analyze
```

Expected:

- `dart format` 退出码为 0。
- `flutter analyze` 输出 `No issues found!`。

- [ ] **Step 3: 运行相关测试**

Run:

```powershell
flutter test test/utils/connection_server_address_test.dart
flutter test test/screens/connection_backend_selection_test.dart
flutter test test/screens/connection_feiniu_compatibility_test.dart
flutter test test/screens/connection_emby_authentication_test.dart
flutter test test/connection_login_persistence_test.dart
flutter test test/screens/login_history_screen_test.dart
```

Expected: 六个测试文件均以 `All tests passed!` 结束，无 overflow、未处理异常或异步泄漏。

- [ ] **Step 4: 运行全量 Flutter 测试**

Run:

```powershell
flutter test
```

Expected: 退出码为 0，输出末尾为 `All tests passed!`。

- [ ] **Step 5: 构建 Debug APK**

Run:

```powershell
flutter build apk --debug
```

Expected: 退出码为 0，并生成 `build/app/outputs/flutter-apk/app-debug.apk`。若 Android 工具链环境缺失，必须报告精确错误，不得用分析或测试结果替代构建成功声明。

- [ ] **Step 6: 主代理执行视觉与规格逐项审阅**

按 `docs/superpowers/specs/2026-08-25-connection-home-redesign-design.md` 逐项确认：

```text
手机：紧凑单栏，完整显示三个服务名和登录按钮。
竖屏平板：登录卡限宽居中。
横屏平板：品牌左栏 + 固定宽度登录卡右栏。
切换：卡片、主字段、错误区和登录按钮不移动。
地址：默认空；裸地址补 HTTPS；显式 HTTP 保留。
访问码：仅飞牛更多选项展开后出现。
历史：使用真实后端 Logo，不显示文字头像。
命名：用户可见产品名统一为飞翔播放器。
配色：深海雾蓝、低饱和、无霓虹和高饱和绿色主按钮。
```

任何一项不满足都退回对应任务修复并重跑相关验证。

- [ ] **Step 7: 输出最终交付记录**

最终报告必须列出：

```text
实际修改文件。
四条核心行为变化：统一表单、地址规则、平板布局、历史 Logo/改名。
每条验证命令、退出码与测试结果。
未解决风险或环境限制。
未触碰的工作区既有脏文件。
```

不得在缺少新鲜命令输出时使用“完成”“通过”“已修复”等结论性表述。
