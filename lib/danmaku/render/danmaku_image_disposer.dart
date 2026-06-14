import 'dart:ui' as ui;

/// 延迟销毁弹幕/遮罩 [ui.Image]。
///
/// 直接 `image.dispose()` 可能撞上仍在途的合成帧对该纹理的引用（GPU 侧尚未用完），
/// 延后一小段再销毁可避免偶发的纹理已毁崩溃。
class DanmakuImageDisposer {
  static const Duration _disposeDelay = Duration(milliseconds: 260);

  static void deferDispose(ui.Image? image) {
    if (image == null) return;
    Future<void>.delayed(_disposeDelay, image.dispose);
  }
}
