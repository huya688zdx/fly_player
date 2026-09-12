# MNN Windows 运行库

- 版本：3.6.1
- 来源：https://github.com/alibaba/MNN/releases/tag/3.6.1
- 发行包：`mnn_3.6.1_windows_x64_cpu_opencl_vulkan_avx512.zip`
- 许可证：Apache-2.0，见 `LICENSE.txt`
- `MNN.dll` SHA-256：`37CFA56CA1BFD632677BF5EB642DF73B1BE3026D25825A0F4AF0BAA105FA6DAE`
- `MNN.lib` SHA-256：`41CD488E78522CD9B1327087A4F4DD0E303C91F6C88C118285BE842FFB49B12B`

项目只链接 CPU 推理所需的动态库。弹幕分割模型继续复用
`android/app/src/full/assets/models/mnn_seg/isnet-anime-512-fp16.mnn`，Windows
构建时由 CMake 安装到可执行文件的 `data/models`，不在仓库中保存第二份模型。
该模型对应 SkyTNT `anime-segmentation` 的 ISNet Anime（Apache-2.0），本地文件
SHA-256 为
`57DE559ABEC57DE497FE14846D4AAFAE5920C5901452ABA04852682E2B872764`。
仓库中没有生成该 MNN 文件的导出脚本，因此这里只复用并校验现有产物，不声称
能够从上游权重完全复现这次 FP16 转换。
