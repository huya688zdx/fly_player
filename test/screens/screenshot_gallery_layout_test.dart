import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/screens/screenshot_preview_screen.dart';

void main() {
  test('截图图库列数会根据可用宽度限制在两到四列', () {
    expect(screenshotGalleryColumnCount(320), 2);
    expect(screenshotGalleryColumnCount(500), 2);
    expect(screenshotGalleryColumnCount(700), 4);
    expect(screenshotGalleryColumnCount(1080), 4);
  });
}
