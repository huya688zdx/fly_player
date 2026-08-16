import 'package:flutter_test/flutter_test.dart';

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
  test('localizes audio language codes for detail page display', () {
    expect(PlayDetailTrackSelector.audioOptionTitle(_audio('jpn')), '日语');
    expect(PlayDetailTrackSelector.audioOptionTitle(_audio('eng')), '英语');
    expect(PlayDetailTrackSelector.audioOptionTitle(_audio('fre')), '法语');
    expect(PlayDetailTrackSelector.audioOptionTitle(_audio('per')), '波斯语');
  });

  test('keeps custom language codes but hides explicit unknown markers', () {
    expect(PlayDetailTrackSelector.audioOptionTitle(_audio('qaa')), 'qaa');
    expect(PlayDetailTrackSelector.audioOptionTitle(_audio('und')), '');
    expect(PlayDetailTrackSelector.audioOptionTitle(_audio('unknown')), '');
  });
}
