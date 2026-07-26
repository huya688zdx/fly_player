# Phase N 网络源 Plan B 真机验证

## 前置

1. 构建并安装 full debug 包。
2. 开启“主体穿透遮挡”和“网络源预计算遮罩”。
3. 开启日志：

```powershell
adb shell setprop log.tag.FlyPlayerDanmaku VERBOSE
adb logcat -c
adb logcat FlyPlayerMaskPipeline:D FlyPlayerFrameExtract:D FlyPlayerDanmaku:V '*:S'
```

## NAS / 飞牛代理

1. 播放一集经 `http://127.0.0.1:<port>/...` 本地代理加载的 NAS 视频。
2. 拖到 60 秒以后，确认日志出现 `FlyPlayerFrameExtract: open ok`；日志会主动去掉 query，避免令牌泄露。
3. 确认随后出现 `frame target=... got=...` 和 `planb2 pts=...`；首次取帧应在 5 秒内完成。
4. 随机 seek 三次，确认每次都能继续产生目标 PTS 附近的帧。
5. 关闭“网络源预计算遮罩”，确认播放继续且改走实时遮罩；重新开启后允许当前源重试。

代理的 Range 语义由 `NativeMpvProxyServer` 提供：范围请求返回 `206`，并携带 `Accept-Ranges: bytes` 与 `Content-Range`。本步骤通过 `extractFrameAt(60s)` 实际验证 MediaExtractor 能使用该语义 seek，而不只检查响应头。

## Emby / fnos

1. 播放一集需要 entry-token 的 Emby/fnos 视频。
2. 确认 `open ok` 且能产出 60 秒附近帧，证明 `MpvSource.headers`（包括 Cookie）已传给 MediaExtractor；日志不得打印 header 值。
3. 若打开失败、首帧为空或首帧超过 5 秒，确认出现 `planb2 network source disabled`，随后实时遮罩仍继续工作。

## 验收记录

记录机型、源类型、首次取帧耗时、三次 seek 是否继续产帧、失败回退是否可用。Phase R 必须等本页两类网络源均完成真机验证后才能执行。
