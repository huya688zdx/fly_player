import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/danmaku/models/danmaku_settings.dart';
import 'package:fly_player/desktop/playback/external_player_subtitles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File danmaku;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'fly_external_subtitles_',
    );
    danmaku = File('${directory.path}/comments.json');
    await danmaku.writeAsString(
      jsonEncode({
        'commentsCompact': [
          ['1', 1000, r'滚动{\pos(1,1)}', 0, 0xffff0000],
          ['2', 1000, r'滚动{\pos(1,1)}', 0, 0xffff0000],
          ['3', 1000, '顶部', 1, 0xffffffff],
          ['4', 1000, '底部', 2, 0xffffffff],
        ],
      }),
    );
  });
  tearDown(() async => directory.delete(recursive: true));

  test('关闭影片字幕会生成空字幕轨，仍可独立启用弹幕', () async {
    final closed = await ExternalPlayerSubtitles.prepare(
      directory: directory,
      subtitlePath: '${directory.path}/不应读取的字幕.ass',
      settings: DanmakuSettings.defaults.copyWith(enabled: false),
      disableSubtitles: true,
    );
    expect(await File(closed!).readAsString(), isNot(contains('Dialogue:')));
    final withDanmaku = await ExternalPlayerSubtitles.prepare(
      directory: directory,
      subtitlePath: '${directory.path}/不应读取的字幕.ass',
      danmakuPath: danmaku.path,
      settings: DanmakuSettings.defaults.copyWith(enabled: true),
      disableSubtitles: true,
    );
    expect(await File(withDanmaku!).readAsString(), contains('Dialogue:'));
  });

  test('保留原 ASS 样式和字幕，按原分辨率合并去重后的三类弹幕', () async {
    const originalStyle =
        'Style: FlyPlayerDanmaku,Arial,40,&H00FFFFFF,&H00FFFFFF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,0,2,20,20,20,1';
    const originalEvent =
        r'Dialogue: 0,0:00:01.00,0:00:04.00,FlyPlayerDanmaku,,0,0,0,,{\i1}原字幕';
    final subtitle = File('${directory.path}/original.ass');
    await subtitle.writeAsString('''[Script Info]
Title: 保留原字幕
ScriptType: v4.00+
PlayResX: 1920
PlayResY: 1080
[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
$originalStyle
[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
$originalEvent
''');
    final result = await ExternalPlayerSubtitles.prepare(
      directory: directory,
      subtitlePath: subtitle.path,
      danmakuPath: danmaku.path,
      settings: DanmakuSettings.defaults.copyWith(
        bottomEnabled: true,
        speed: 2,
      ),
    );
    final output = await File(result!).readAsString();
    expect(output, contains('PlayResX: 1920\nPlayResY: 1080'));
    expect(output, contains(originalStyle));
    expect(output, contains(originalEvent));
    expect(output, contains('Style: FlyPlayerDanmaku1,'));
    expect(output, contains(r'\move(1920.00,'));
    expect(output, contains(r'\fs33.00'));
    expect(output, contains(r'\alpha&H26&\c&H0000FF&'));
    expect(output, contains(r'滚动｛＼pos(1,1)｝'));
    expect(output, contains('0:00:01.00,0:00:05.50,FlyPlayerDanmaku1'));
    expect(
      RegExp(r'^Dialogue:', multiLine: true).allMatches(output),
      hasLength(4),
    );
  });

  test('VTT 的零时长条目不阻止其余字幕与弹幕合并', () async {
    final subtitle = File('${directory.path}/selected.vtt');
    await subtitle.writeAsString(
      'WEBVTT\n\n00:00:01.000 --> 00:00:01.000\n无显示时长\n\n'
      '00:00:02.000 --> 00:00:04.000\n正常字幕\n',
    );
    final result = await ExternalPlayerSubtitles.prepare(
      directory: directory,
      subtitlePath: subtitle.path,
      danmakuPath: danmaku.path,
      settings: DanmakuSettings.defaults.copyWith(enabled: true),
    );
    final output = await File(result!).readAsString();
    expect(output, contains('正常字幕'));
    expect(output, contains('FlyPlayerDanmaku'));
    expect(output, isNot(contains('无显示时长')));
  });

  test('位图字幕与弹幕无法合并时明确报错，原字幕保持原样', () async {
    final subtitle = File('${directory.path}/bitmap.sup');
    await subtitle.writeAsBytes([0x50, 0x47]);
    await expectLater(
      ExternalPlayerSubtitles.prepare(
        directory: directory,
        subtitlePath: subtitle.path,
        danmakuPath: danmaku.path,
        settings: DanmakuSettings.defaults,
      ),
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          '错误说明',
          contains('暂不支持'),
        ),
      ),
    );
    expect(await subtitle.readAsBytes(), [0x50, 0x47]);
    expect(await File('${directory.path}/playback.ass').exists(), isFalse);
  });
}
