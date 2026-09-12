# Refresh 候选动画生成

Python 3.11+；实际渲染需要 `opencv-python`、`numpy`、`Pillow`。在独立虚拟环境安装这些依赖，不需要修改 Flutter 依赖。`--help` 与 `--check-inputs` 不导入渲染依赖。

输入为 assets/refresh 下三张已提交图集（human_performance_00_25、closure_08_reworked、wing_unfold_00_04），以及两段拥有使用权限的原始视频。第一段使用 472..546 帧，第二段使用 247..359 帧；视频还应支持旧素材回归中检查的 420 帧。裁剪区域保持 `(510, 0, 1410, 900)`，不改变原动画帧序、画质或正式播放器资源。

```powershell
python tool/build_288_refresh_preview.py --source-video '输入/video-1.mp4' --source-video-2 '输入/video-2.mp4' --output-dir 'build/refresh-preview' --check-inputs
python tool/build_288_refresh_preview.py --source-video '输入/video-1.mp4' --source-video-2 '输入/video-2.mp4' --output-dir 'build/refresh-preview'
```

`--asset-root` 可指定图集目录。检查命令只验证文件存在并输出 SHA256；不表示内容可解码或艺术效果通过。缺少原片时停止实际生成，不下载私人素材，也不以合成视频替代原片。

所有输出统一写到明确指定的目录：预览 PNG、contact PNG、MP4、候选 reworked WebP、候选 static PNG、timeline CSV。正式 `shoujo_bird_loading.webp` / `shoujo_bird_loading_static.png` 不被此脚本替换；候选资源需要人工验收后另行集成。

旧 `tool.test_build_288_refresh_preview` 的真实素材回归可在隔离进程设置 `FLY_REFRESH_SOURCE_VIDEO`、`FLY_REFRESH_SOURCE_VIDEO_2`、`FLY_REFRESH_OUTPUT_DIR` 后运行；输出目录需已有生成的候选文件。缺少素材/依赖时标 BLOCKED，不能把 CLI 路径测试视为素材重生通过。
