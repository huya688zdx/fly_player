# Refresh 正式资源与候选生成

## 当前正式版（2026-09-14）

已采用用户确认的“欲伸又止→自抱→蜷缩→青鸟飞远”连接修订版：512×512透明WebP，30 FPS时间轴共261格、8.7秒，持帧合并后119个编码画面，无限循环。正式资源是 `assets/refresh/shoujo_bird_loading.webp`，系统减少动态效果时使用同目录 `shoujo_bird_loading_static.png`。静态图直接取正式时间轴第190格（从0开始，青鸟展翼），保留原512画布，没有重新缩放或定位。

来源包为 `青鸟_收茧接点修订_20260914.zip`，保留完整原稿、局部蒙版、提示词、锁定后段和生成脚本。解压后，在 `bluebird_motion_redesign_20260913/revision_02` 运行 `python prepare_revisions.py`，再在上一层运行 `python build_draft_preview.py`。采用的输出为 `revision_02/preview/完整故事_连接修订_透明.webp`；复制到正式WebP路径时不重新编码、不改时序。新增收茧连接稿已包含在本版，后166格出翼与原片飞远保持不变。

`BirdLoader` 直接使用素材时长，无需额外控制器同步；七秒控制器属于独立的 `BirdGlyph`。同名资源替换后应重新启动App，避免沿用旧图片缓存。相关验证运行 `flutter test test/widgets/bird_loader_test.dart`，其中直接解码正式WebP并检查尺寸、完整时长和循环信息；普通播放器用的MP4仅作为浅色底预览，不打包进App。

## 历史 reworked 候选生成

以下入口仍用于历史候选复现，不能用其输出覆盖上面的正式版。

Python 3.11+；实际渲染需要 `opencv-python`、`numpy`、`Pillow`。在独立虚拟环境安装这些依赖，不需要修改 Flutter 依赖。`--help` 与 `--check-inputs` 不导入渲染依赖。

输入为 assets/refresh 下三张已提交图集（human_performance_00_25、closure_08_reworked、wing_unfold_00_04），以及两段拥有使用权限的原始视频。第一段使用 472..546 帧，第二段使用 247..359 帧；视频还应支持旧素材回归中检查的 420 帧。裁剪区域保持 `(510, 0, 1410, 900)`，不改变原动画帧序、画质或正式播放器资源。

```powershell
python tool/build_288_refresh_preview.py --source-video '输入/video-1.mp4' --source-video-2 '输入/video-2.mp4' --output-dir 'build/refresh-preview' --check-inputs
python tool/build_288_refresh_preview.py --source-video '输入/video-1.mp4' --source-video-2 '输入/video-2.mp4' --output-dir 'build/refresh-preview'
```

`--asset-root` 可指定图集目录。检查命令只验证文件存在并输出 SHA256；不表示内容可解码或艺术效果通过。缺少原片时停止实际生成，不下载私人素材，也不以合成视频替代原片。

所有输出统一写到明确指定的目录：预览 PNG、contact PNG、MP4、候选 reworked WebP、候选 static PNG、timeline CSV。正式 `shoujo_bird_loading.webp` / `shoujo_bird_loading_static.png` 不被此脚本替换；候选资源需要人工验收后另行集成。

旧 `tool.test_build_288_refresh_preview` 的真实素材回归可在隔离进程设置 `FLY_REFRESH_SOURCE_VIDEO`、`FLY_REFRESH_SOURCE_VIDEO_2`、`FLY_REFRESH_OUTPUT_DIR` 后运行；输出目录需已有生成的候选文件。缺少素材/依赖时标 BLOCKED，不能把 CLI 路径测试视为素材重生通过。
