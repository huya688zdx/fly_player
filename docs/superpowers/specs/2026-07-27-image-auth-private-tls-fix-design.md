# 图片鉴权与私网 TLS 修复设计

## 范围

本次只处理两个已确认的重要问题：

1. 飞牛/服务器返回的 CGNAT 图片地址（`100.64.0.0/10`）使用自签名或不完整证书链时，API 可登录但 `Image.network` TLS 校验失败。
2. 首页和收藏页把公共后端 `MediaImageRef` 降级为字符串后，渲染层可能把当前飞牛 token 作为 header 发送到 Emby/Jellyfin 图片主机。

不在本次修改旧业务模型、缓存格式、详情导航或 `resolveRefs` 的多 header 表达。

## 私网 TLS

`PrivateNetworkHttpOverrides` 继续只为明确的私网或已注册 NAS 主机接受不受系统信任的证书。IPv4 私网范围增加 RFC 6598 CGNAT `100.64.0.0/10`，覆盖飞牛返回的 `100.125.130.96`。范围之外的公网 IP 和域名仍执行系统 TLS 校验。

边界测试锁定：

- 允许：`100.64.0.1`、`100.125.130.96`、`100.127.255.254`
- 拒绝：`100.63.255.255`、`100.128.0.0`

## 跨后端图片请求

保持 `MediaLibraryItem` 不变。首页和收藏页在将公共 `MediaCatalog` / `MediaItemCard` 桥接成旧 UI 模型时，同时按 catalog ID 或 item GUID 保存 `MediaImageRequest`：

- 首页：catalog 图片请求映射、条目图片请求映射；
- 收藏页：条目图片请求映射；
- 请求由原始 `MediaImageRef` 经 `DetailArtworkResolver` 生成，保留 URL、headers 和 `selfAuthenticated`；
- 渲染优先使用映射中的中立请求；仅飞牛旧数据或缓存缺少映射时，回退现有 `baseUrl + token` 逻辑；
- 后端切换、页面重置及收藏重新加载时清理对应映射，避免跨会话串用。

分类海报簇直接消费 `List<MediaImageRequest>`，不再下传 token。服务器族图片请求不得新增 `Authorization` 或 `Trim-MC-token`；后端提供的 FNOS cookie 等 headers 必须原样保留。

## 验证

1. 私网范围单元测试。
2. resolver/桥接纯逻辑测试：服务器族请求不含飞牛 token，原始 headers 和自鉴权标志保留，飞牛回退不变。
3. 相关定向测试。
4. `flutter analyze`。
5. `:app:assembleFullProfile`。

两项修复分别提交，便于回滚和定位。
