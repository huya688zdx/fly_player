# 图片鉴权与私网 TLS 修复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 CGNAT 私网图片 TLS 校验失败，并阻止首页/收藏页把飞牛 token 发送到 Emby/Jellyfin 图片主机。

**Architecture:** TLS 修复只扩展 `PrivateNetworkHttpOverrides` 的 RFC 6598 私网识别，不放宽公网证书。图片鉴权修复不修改 `MediaLibraryItem`，而是在页面状态中按条目 ID 并行保存由原始 `MediaImageRef` 生成的 `MediaImageRequest`；渲染优先使用中立请求，飞牛旧数据继续走原有回退。

**Tech Stack:** Dart、Flutter、`HttpOverrides`、`Image.network`、`flutter_test`、Gradle Android Full Profile。

---

## 文件结构

- 修改 `lib/utils/private_network_http_overrides.dart`：识别 RFC 6598 CGNAT IPv4 私网段。
- 修改 `test/utils/private_network_http_overrides_test.dart`：锁定 CGNAT 范围上下边界。
- 修改 `lib/screens/media_list_screen.dart`：保存首页 catalog/item 的中立图片请求，并在会话重置时清理。
- 修改 `lib/screens/media_list_screen_widgets.dart`：首页渲染优先使用保存请求，分类海报簇不再接收 token。
- 修改 `lib/screens/favorite_items_screen.dart`：保存收藏条目的中立图片请求并提供安全解析入口。
- 新建 `test/ui/media_image_request_bridge_test.dart`：覆盖公共后端图片请求不附加飞牛 token、保留后端 headers，以及飞牛旧数据回退。

### Task 1: 支持 CGNAT 私网图片证书

**Files:**
- Modify: `test/utils/private_network_http_overrides_test.dart:5-27`
- Modify: `lib/utils/private_network_http_overrides.dart:40-57`

- [ ] **Step 1: 写失败的边界测试**

在现有测试中加入：

```dart
expect(allowed('100.64.0.1'), isTrue);
expect(allowed('100.125.130.96'), isTrue);
expect(allowed('100.127.255.254'), isTrue);
expect(allowed('100.63.255.255'), isFalse);
expect(allowed('100.128.0.0'), isFalse);
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `flutter test test/utils/private_network_http_overrides_test.dart`

Expected: 至少 `100.64.0.1`、`100.125.130.96`、`100.127.255.254` 断言失败。

- [ ] **Step 3: 实现最小范围判断**

在 IPv4 分支中增加 RFC 6598 判断：

```dart
(first == 100 && second >= 64 && second <= 127)
```

完整返回条件保持已有 RFC1918 判断并追加该条件，不修改公网域名、注册 NAS host 或 IPv6 逻辑。

- [ ] **Step 4: 运行测试并确认通过**

Run: `flutter test test/utils/private_network_http_overrides_test.dart`

Expected: `All tests passed!`

- [ ] **Step 5: 静态分析并提交**

Run: `flutter analyze lib/utils/private_network_http_overrides.dart test/utils/private_network_http_overrides_test.dart`

Expected: `No issues found!`

Commit:

```bash
git add lib/utils/private_network_http_overrides.dart test/utils/private_network_http_overrides_test.dart
git commit -m "fix(image-tls): 支持 CGNAT 私网图片证书"
```

### Task 2: 保留公共后端图片请求并阻止飞牛 token 外泄

**Files:**
- Create: `test/ui/media_image_request_bridge_test.dart`
- Modify: `lib/screens/media_list_screen.dart:79-83,200-291,293-479`
- Modify: `lib/screens/media_list_screen_widgets.dart:307-462,519-777`
- Modify: `lib/screens/favorite_items_screen.dart:79-86,439-479,511-599,720-766`

- [ ] **Step 1: 抽出可测试的请求选择函数并写失败测试**

在 `lib/ui/detail_artwork_resolver.dart` 新增纯函数：

```dart
MediaImageRequest preferPreservedImageRequest({
  required MediaImageRequest? preserved,
  required List<String> fallbackUrls,
  required String fallbackToken,
}) {
  if (preserved != null && !preserved.isEmpty) return preserved;
  return mediaImageRequestForUrls(fallbackUrls, token: fallbackToken);
}
```

在新测试文件覆盖：

```dart
test('保存的服务器族请求不会附加飞牛 token', () {
  const preserved = MediaImageRequest(
    urls: <String>['https://emby.example/image?api_key=E'],
    selfAuthenticated: true,
  );
  final request = preferPreservedImageRequest(
    preserved: preserved,
    fallbackUrls: const <String>['https://emby.example/image?api_key=E'],
    fallbackToken: 'FN_TOKEN',
  );
  expect(request.headers, isEmpty);
  expect(request.selfAuthenticated, isTrue);
});

test('保存的 FNOS headers 原样保留', () {
  const preserved = MediaImageRequest(
    urls: <String>['https://host.fnos.net/image'],
    headers: <String, String>{'Cookie': 'entry-token=ENTRY'},
  );
  final request = preferPreservedImageRequest(
    preserved: preserved,
    fallbackUrls: const <String>[],
    fallbackToken: 'FN_TOKEN',
  );
  expect(request.headers, <String, String>{'Cookie': 'entry-token=ENTRY'});
});

test('无保存请求时保持飞牛旧数据回退', () {
  final request = preferPreservedImageRequest(
    preserved: null,
    fallbackUrls: const <String>['http://nas.local/image'],
    fallbackToken: 'FN_TOKEN',
  );
  expect(request.headers['Authorization'], 'FN_TOKEN');
  expect(request.headers['Trim-MC-token'], 'FN_TOKEN');
});
```

- [ ] **Step 2: 运行新测试并确认失败**

Run: `flutter test test/ui/media_image_request_bridge_test.dart`

Expected: FAIL，因为 `preferPreservedImageRequest` 尚不存在。

- [ ] **Step 3: 实现纯函数并让测试通过**

按 Step 1 的签名实现函数，不做 URL host 猜测；保存请求是权威，只有缺失时才使用旧 token 回退。

Run: `flutter test test/ui/media_image_request_bridge_test.dart test/ui/detail_artwork_resolver_test.dart`

Expected: `All tests passed!`

- [ ] **Step 4: 首页保存原始请求**

在 `_MediaListScreenState` 增加：

```dart
Map<String, MediaImageRequest> _catalogImageRequests = <String, MediaImageRequest>{};
Map<String, MediaImageRequest> _itemImageRequests = <String, MediaImageRequest>{};
```

新增只接收原始 ref 的 helper：

```dart
MediaImageRequest _requestForRefs(List<MediaImageRef> refs) {
  final provider = context.read<NasProvider>();
  return DetailArtworkResolver(
    baseUrl: provider.baseUrl,
    token: provider.token,
  ).resolveRefs(refs);
}
```

加载公共后端 `MediaCatalog` / `MediaItemCard` 时，在转换成 `MediaItem` / `MediaLibraryItem` 之前按 ID 保存：

```dart
catalogRequests[catalog.id] = _requestForRefs(<MediaImageRef>[
  catalog.primaryImage,
  ...catalog.posters,
]);
itemRequests[card.id] = _requestForRefs(<MediaImageRef>[
  card.primaryImage,
  ...card.posters,
]);
```

仅在一次加载成功后与列表状态一起替换映射；会话未配置、后端切换或重置数据时清空映射。飞牛 API 返回的旧模型不写映射。

- [ ] **Step 5: 首页渲染优先使用保存请求**

继续观看和分类条目调用：

```dart
final images = preferPreservedImageRequest(
  preserved: _itemImageRequests[item.guid],
  fallbackUrls: urls,
  fallbackToken: token,
);
```

`_CategoryPosterCard` / `_PosterCluster` 将 `posterUrls + token` 改为 `List<MediaImageRequest> images`，每张 `_PosterImage` 直接接收对应请求。分类请求按 `category.id` 取得；缺失时才由旧路径构造。

普通海报 `MediaPosterCard` 同样传入选择后的请求。

- [ ] **Step 6: 收藏页保存原始请求**

增加：

```dart
final Map<String, MediaImageRequest> _itemImageRequests = <String, MediaImageRequest>{};
```

非飞牛查询返回 `MediaItemCard` 时，在映射旧模型前同步生成请求：

```dart
final resolver = DetailArtworkResolver(
  baseUrl: context.read<NasProvider>().baseUrl,
  token: context.read<NasProvider>().token,
);
final newRequests = <String, MediaImageRequest>{
  for (final card in result.items)
    card.id: resolver.resolveRefs(<MediaImageRef>[
      card.primaryImage,
      ...card.posters,
    ]),
};
```

重置分页时替换当前条目请求，加载更多时合并；飞牛路径清除对应服务器族映射。`_posterImages` 改为调用 `preferPreservedImageRequest`，保存请求优先，旧飞牛候选回退。

- [ ] **Step 7: 运行定向测试与分析**

Run:

```bash
flutter test test/ui/media_image_request_bridge_test.dart test/ui/detail_artwork_resolver_test.dart test/utils/private_network_http_overrides_test.dart
flutter analyze lib/ui/detail_artwork_resolver.dart lib/screens/media_list_screen.dart lib/screens/media_list_screen_widgets.dart lib/screens/favorite_items_screen.dart test/ui/media_image_request_bridge_test.dart
```

Expected: 所有测试通过；分析 `No issues found!`。

- [ ] **Step 8: 全量分析与 Full Profile 构建**

Run:

```bash
flutter analyze
android/gradlew.bat -p android :app:assembleFullProfile
```

Expected: `No issues found!`；`BUILD SUCCESSFUL`。

- [ ] **Step 9: 提交 token 泄露修复**

```bash
git add lib/ui/detail_artwork_resolver.dart lib/screens/media_list_screen.dart lib/screens/media_list_screen_widgets.dart lib/screens/favorite_items_screen.dart test/ui/media_image_request_bridge_test.dart
git commit -m "fix(image-auth): 保留跨后端图片鉴权请求"
```
