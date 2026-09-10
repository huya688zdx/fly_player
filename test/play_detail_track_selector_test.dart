import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/l10n/generated/app_localizations_zh.dart';

import 'package:fly_player/models/stream_track_data.dart';
import 'package:fly_player/utils/play_detail_track_selector.dart';

AudioTrackOption _audio(String language) => AudioTrackOption(
  mediaGuid: 'media-1',
  guid: 'audio-$language',
  title: '',
  codecName: 'aac',
  profile: '',
  language: language,
  audioType: '',
  channelLayout: 'stereo',
  channels: 2,
  sampleRate: 48000,
  bps: 0,
  index: 0,
  isDefault: 0,
);

void main() {
  String title(String language) => PlayDetailTrackSelector.audioOptionTitle(
    _audio(language),
    l10n: AppLocalizationsZh(),
  );

  test('详情页音轨语言代码显示为语言名称', () {
    expect(title('jpn'), '日语');
    expect(title('eng'), '英语');
    expect(title('fre'), '法语');
    expect(title('per'), '波斯语');
  });

  test('保留自定义语言代码，空值和未知标记显示未知', () {
    expect(title('qaa'), 'qaa');
    expect(title(''), '未知');
    expect(title('und'), '未知');
    expect(title('unknown'), '未知');
    expect(title('zz-unknow'), '未知');
  });
}
