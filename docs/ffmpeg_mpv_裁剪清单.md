# FFmpeg / mpv 精简编译清单（arm64-v8a，给远程编译用）

> 目标：在不丢失实际播放能力的前提下，缩小 `libavcodec.so`(11.6M) / `libavfilter.so`(4.1M) /
> `libavformat.so`(2.7M) / `libswscale.so`(0.9M) / `libmpv.so`(11.5M) 等原生库体积。
> 预计可省 **~10–18MB**。
>
> 适用工程：mpv-android（https://github.com/jarnedemeulemeester/libmpv-android 或
> 官方 mpv-android buildscripts）。本 App 通过 `MPV_ANDROID_DIR` / gradle 属性
> `mpvAndroidDir` 指向其 `app/src/main/jniLibs`，编译产物替换进
> `android/app/src/main/jniLibs/arm64-v8a/` 即可。

---

## 0. 本 App 的真实播放需求（裁剪不能破坏这些）

> 这些是从代码与功能确认过的硬需求，**白名单必须覆盖**，否则会出现「某片源打不开」。

- **视频**：H.264(AVC)、H.265(HEVC)、AV1、VP9、VP8、MPEG-4/MPEG-2（老片）。需支持 4K / HDR / 10bit / 高码率。
- **硬解优先**：Android MediaCodec（h264/hevc/av1/vp9/vp8/mpeg2/mpeg4 的 `*_mediacodec`）。
  硬解不依赖 ffmpeg 软解码器体积，但软解 fallback 仍需保留对应 software decoder（兼容性开关「软件解码」要能用）。
- **音频**：AAC、AC-3、E-AC-3、DTS、TrueHD、FLAC、ALAC、MP3、Opus、Vorbis、PCM 系列。
  需支持**音频直通（passthrough）**：AC3 / E-AC3 / DTS / TrueHD 直通输出（直通走 spdif，
  但解码 fallback 仍需保留这些 decoder）。
- **封装(demux)**：mkv/webm、mp4/mov、ts/m2ts(mpegts)、avi、flv、hls、mpegdash、wav、flac、ogg、aac、mp3、subtitle 容器。
- **字幕**：ASS/SSA、SRT(subrip)、WebVTT、MicroDVD、PGS(hdmv_pgs)、VobSub(dvdsub)、mov_text。
- **网络**：播放有两条路径（已确认 `PlaybackSourceResolver.prepare()` 有「走本地代理」和
  「直连远程」两个分支）：
  1. 多数情况走本地代理 `http://127.0.0.1`（OkHttp 在 Kotlin 层连 NAS/网盘，ffmpeg 只看到本地 http）。
  2. **部分情况 mpv 直连远程原始 URL**（如网盘 https 直链、HLS 转码流）——这条路 ffmpeg
     必须自己处理 **https/tls**。
  因此 ffmpeg **必须保留 file + http + https + tcp + tls + hls** 协议；其余（rtmp/rtsp/smb/ftp/udp...）可全砍。
- **⚠️ TLS 后端（关键，别漏）**：`--enable-protocol=https/tls` 在 Android 上需要一个 TLS 后端库，
  否则 https 协议编不出来 → **网盘 https 直链播放会失败**。确保 ffmpeg configure 带上
  `--enable-openssl`（推荐，mpv-android buildscripts 一般已带 openssl）或 `--enable-mbedtls`
  或 `--enable-gnutls` 之一，并链接对应库。编完用 `ffmpeg -protocols` 或检查 build log
  确认 `https`、`tls` 在已启用协议列表里。
- **图片/封面**：mjpeg、png（部分容器内封面），保留这两个 image decoder 即可。

---

## 1. FFmpeg configure 裁剪参数

> 思路：`--disable-everything` 全关，再用白名单精确开回。**只开 decoder/parser/demuxer/protocol，
> 全关 encoder/muxer/device/filter(除必需)**。
> 放进 mpv-android buildscripts 里 ffmpeg 的 configure 段（通常是 `buildscripts/scripts/ffmpeg.sh`
> 或 `ffmpeg/configure` 调用处）。

```sh
# ---- 总开关：先全关 ----
--disable-everything
--disable-programs           # 不要 ffmpeg/ffplay/ffprobe 可执行
--disable-doc
--disable-debug
--disable-encoders           # NAS 播放器不编码，全砍编码器（省不少）
--disable-muxers             # 不写文件，全砍封装器
--disable-devices            # 无采集设备
--disable-postproc           # 一般用不到
--disable-avdevice
# 注意：--disable-network 不能加！mpv 走 http 代理取流需要 protocol。

# ---- TLS 后端（https 必需，三选一，别全漏）----
--enable-openssl             # 推荐；mpv-android buildscripts 通常已带 openssl
# 或 --enable-mbedtls / --enable-gnutls（看工具链带哪个）
# 漏了 TLS 后端 → https 协议编不出 → 网盘 https 直链播放失败！

# ---- 协议（本地代理 + 远程直连都要支持）----
--enable-protocol=file
--enable-protocol=http
--enable-protocol=https        # 网盘 https 直链直连必需
--enable-protocol=tcp
--enable-protocol=tls          # https 依赖
--enable-protocol=crypto       # HLS 加密分片
--enable-protocol=hls          # 网盘转码流常用
--enable-protocol=httpproxy

# ---- 解析器 parsers（解复用/seek 需要）----
--enable-parser=h264
--enable-parser=hevc
--enable-parser=av1
--enable-parser=vp9
--enable-parser=vp8
--enable-parser=mpeg4video
--enable-parser=mpegvideo
--enable-parser=aac
--enable-parser=aac_latm
--enable-parser=ac3
--enable-parser=dca            # DTS
--enable-parser=flac
--enable-parser=opus
--enable-parser=vorbis
--enable-parser=mjpeg
--enable-parser=png
--enable-parser=cook
--enable-parser=mlp            # TrueHD/MLP

# ---- 视频解码器（软解 fallback）----
--enable-decoder=h264
--enable-decoder=hevc
--enable-decoder=av1
--enable-decoder=libdav1d      # 若工程带 dav1d，AV1 软解更快；没有就删这行
--enable-decoder=vp9
--enable-decoder=vp8
--enable-decoder=mpeg4
--enable-decoder=mpeg2video
--enable-decoder=mpeg1video
--enable-decoder=mjpeg
--enable-decoder=png
# 硬解（MediaCodec，体积几乎为 0，但必须显式开）
--enable-decoder=h264_mediacodec
--enable-decoder=hevc_mediacodec
--enable-decoder=av1_mediacodec
--enable-decoder=vp9_mediacodec
--enable-decoder=vp8_mediacodec
--enable-decoder=mpeg4_mediacodec
--enable-decoder=mpeg2_mediacodec
--enable-hwaccel=h264_mediacodec
--enable-hwaccel=hevc_mediacodec
--enable-hwaccel=av1_mediacodec
--enable-hwaccel=vp9_mediacodec

# ---- 音频解码器 ----
--enable-decoder=aac
--enable-decoder=aac_latm
--enable-decoder=ac3
--enable-decoder=eac3
--enable-decoder=dca           # DTS / DTS-HD
--enable-decoder=truehd
--enable-decoder=mlp
--enable-decoder=flac
--enable-decoder=alac
--enable-decoder=mp3
--enable-decoder=mp2
--enable-decoder=opus
--enable-decoder=vorbis
--enable-decoder=pcm_s16le
--enable-decoder=pcm_s16be
--enable-decoder=pcm_s24le
--enable-decoder=pcm_s32le
--enable-decoder=pcm_f32le
--enable-decoder=pcm_u8
--enable-decoder=pcm_bluray
--enable-decoder=pcm_dvd

# ---- 音频直通需要的「bitstream 透传」----
# 直通本质是不解码直接送原始码流，但 ffmpeg 仍需识别这些编码：
# ac3/eac3/dca/truehd 上面已开 decoder，直通由 mpv 的 --audio-spdif 控制，无需额外 encoder。

# ---- 字幕解码器 ----
--enable-decoder=ass
--enable-decoder=ssa
--enable-decoder=subrip        # SRT
--enable-decoder=srt
--enable-decoder=webvtt
--enable-decoder=movtext       # mp4 内嵌字幕
--enable-decoder=microdvd
--enable-decoder=pgssub        # PGS (蓝光；codec 长名为 hdmv_pgs_subtitle)
--enable-decoder=dvdsub        # VobSub
--enable-decoder=dvbsub
--enable-decoder=text

# ---- 封装解复用 demuxers ----
--enable-demuxer=matroska      # mkv/webm
--enable-demuxer=mov           # mp4/mov/m4a/m4v
--enable-demuxer=mpegts        # ts/m2ts
--enable-demuxer=mpegtsraw
--enable-demuxer=avi
--enable-demuxer=flv
--enable-demuxer=hls
--enable-demuxer=dash
--enable-demuxer=wav
--enable-demuxer=flac
--enable-demuxer=ogg
--enable-demuxer=aac
--enable-demuxer=ac3
--enable-demuxer=eac3
--enable-demuxer=dts
--enable-demuxer=mp3
--enable-demuxer=mpegvideo
--enable-demuxer=mpegps
--enable-demuxer=h264          # 裸流
--enable-demuxer=hevc
--enable-demuxer=srt
--enable-demuxer=ass
--enable-demuxer=webvtt
--enable-demuxer=subrip
--enable-demuxer=microdvd
--enable-demuxer=sup           # 裸 SUP/PGS 外挂字幕
--enable-demuxer=image2        # 封面图

# ---- demuxer 探测必需的额外解码 ----
--enable-decoder=mjpeg         # 已开
--enable-bsf=aac_adtstoasc     # ts→mp4 提取 aac 时需要
--enable-bsf=h264_mp4toannexb
--enable-bsf=hevc_mp4toannexb
--enable-bsf=extract_extradata
--enable-bsf=vp9_superframe
--enable-bsf=pgs_frame_merge   # 合并 PGS display set，供外挂 SUP/PGS 解码

# ---- 滤镜（mpv 视频处理依赖一部分 swscale/必需 filter）----
# mpv 自己有 vo=gpu 做缩放/色彩，ffmpeg filter 大多用不到。
# 但保留 scale（部分路径需要）与 swscale 库（不能 disable）。
--enable-filter=scale
--enable-filter=aresample
--enable-filter=format
--enable-filter=null
--enable-filter=anull
# 其余 filter 已被 --disable-everything 关掉。

# ---- 库级开关 ----
--enable-swscale
--enable-swresample
--enable-avformat
--enable-avcodec
--enable-avfilter            # 上面只开了几个 filter，库还是要 enable
--enable-avutil
# 若工程默认带这些外部库，按需保留/移除（影响 libmpv 大小）：
#   --enable-libdav1d   AV1 软解（推荐留，HDR AV1 软解更稳）
#   --disable-libaom    AV1 编码器，无用，砍
#   --disable-vapoursynth
#   --disable-lcms2     （若不需要 icc 色彩管理可砍，mpv HDR 一般用内置）
```

---

## 2. mpv configure 裁剪（meson 选项）

mpv-android 里 mpv 的 meson 配置，按需关掉用不到的大件：

```
-Dlibmpv=true            # 必须，App 用的是 libmpv
-Dcplayer=false          # 不要命令行 mpv 可执行
-Dmanpage-build=false
-Dhtml-build=false
-Dlua=disabled           # 没用 lua 脚本就关（mpv-android OSD 不依赖）
-Djavascript=disabled
-Dlcms2=disabled         # 若不需要 icc，可关
-Dlibarchive=disabled    # 不播压缩包内媒体
-Drubberband=disabled    # 不用变速保调音高滤镜（mpv 默认 scaletempo 够用）
-Dvapoursynth=disabled
-Ddvbin=disabled
-Dcdda=disabled
-Ddvdnav=disabled
-Dvulkan=enabled         # 渲染保留（vo=gpu-next/vulkan，本机用 Impeller Vulkan）
-Dgl=enabled
```

> ⚠️ 不要关 `--enable-libass`（mpv 的 ASS/SSA 字幕渲染依赖 libass），否则字幕挂。
> libass 本身不大，保留。

---

## 3. 编译与回填步骤

1. 在 mpv-android buildscripts 里按上面参数改 ffmpeg 的 configure 段和 mpv 的 meson 段。
2. 只编 arm64-v8a：`./buildall.sh --arch arm64` 或对应工程的单 ABI 命令。
3. 产出的 `.so` 替换进本仓库：
   ```
   android/app/src/main/jniLibs/arm64-v8a/
     libavcodec.so libavformat.so libavfilter.so libavutil.so
     libswscale.so libswresample.so libmpv.so
   ```
   （`libc++_shared.so`、`libplayer.so` 不用换。）
4. 本仓库重新打包：`flutter build apk --release --flavor lite`。

---

## 4. 必须回归测试的片源（验证没砍过头）

编译完成后，**逐一播放验证**，任何一个打不开就是白名单漏了对应 decoder/demuxer：

- [ ] H.264 mp4（最常见）
- [ ] HEVC/H.265 mkv，10bit HDR
- [ ] AV1 webm/mkv
- [ ] VP9 webm
- [ ] 老片 MPEG-2 ts / MPEG-4 avi
- [ ] 音轨：AC3 / E-AC3 / **DTS** / **TrueHD** / AAC / FLAC / Opus
- [ ] **音频直通**：开直通输出播 DTS/TrueHD 片源
- [ ] 字幕：内封 ASS、外挂 SRT、**PGS（蓝光内封图形字幕）**、VobSub、WebVTT
- [ ] HLS/m3u8 流（若有此类源）
- [ ] **网盘 https 直链播放**（不走本地代理那条路 → 验证 https/tls 后端没漏）
- [ ] **网盘转码流 / 在线播放**（验证直连远程的网络路径完整）
- [ ] 封面/缩略图正常显示

---

## 5. 体积预期与风险

| 项 | 预期 |
|---|---|
| libavcodec.so | 11.6M → ~5–7M（砍掉全部 encoder + 冷门 decoder） |
| libavformat.so | 2.7M → ~1.5M（砍 muxer + 冷门 demuxer/protocol） |
| libavfilter.so | 4.1M → ~0.5–1M（只留 4 个 filter） |
| **合计省** | **~8–12M**，激进些可到 15M+ |

**风险**：白名单漏项 → 某格式打不开。一旦回归测试发现打不开，对照清单把缺的
`--enable-decoder=xxx` / `--enable-demuxer=xxx` 补回重编即可。
保守起见，**第一版可只砍 encoder/muxer/device/冷门 protocol（最安全、收益已有一半），
decoder/demuxer 全留**，确认稳定后再逐步收窄 decoder 白名单。
