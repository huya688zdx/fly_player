import '../../playback/settings/mpv_settings_store.dart';

abstract final class DesktopMpvRuntime {
  static int volumeMax(Map<String, String> settings) {
    if (settings[MpvSettingsCatalog.audioHighFidelityKey] == 'on') return 100;
    return int.tryParse(
          settings[MpvSettingsCatalog.volumeGainKey] ?? '',
        )?.clamp(100, 200) ??
        100;
  }

  static String audioChannels(Map<String, String> settings) {
    return switch (settings[MpvSettingsCatalog.channelMixKey]) {
      'stereo' => 'stereo',
      'surround' => '5.1',
      _ => 'auto-safe',
    };
  }

  static String passthroughCodecs(Map<String, String> settings) {
    final value = settings[MpvSettingsCatalog.audioPassthroughKey] ?? 'off';
    return value == 'off' ? '' : 'ac3,eac3,dts,dts-hd,truehd';
  }

  static String audioFilters(Map<String, String> settings) {
    if (settings[MpvSettingsCatalog.audioHighFidelityKey] == 'on' ||
        passthroughCodecs(settings).isNotEmpty) {
      return '';
    }
    final filters = <String>[];
    switch (settings[MpvSettingsCatalog.audioEqKey]) {
      case 'soft':
        filters
          ..add('lavfi=[equalizer=f=120:t=q:w=1.0:g=1.2]')
          ..add('lavfi=[equalizer=f=2400:t=q:w=1.0:g=1.0]');
      case 'clarity':
        filters
          ..add('lavfi=[equalizer=f=160:t=q:w=1.0:g=-1.0]')
          ..add('lavfi=[equalizer=f=2800:t=q:w=1.1:g=2.4]')
          ..add('lavfi=[equalizer=f=6800:t=q:w=1.1:g=1.4]');
      case 'cinema':
        filters
          ..add('lavfi=[equalizer=f=90:t=q:w=1.0:g=1.4]')
          ..add('lavfi=[equalizer=f=2200:t=q:w=1.0:g=1.2]')
          ..add('lavfi=[equalizer=f=5600:t=q:w=1.0:g=0.8]');
      case MpvSettingsCatalog.audioEqCustomValue:
        for (final band in MpvSettingsCatalog.audioEqBands) {
          final gain = MpvSettingsCatalog.audioEqBandValue(band.key, settings);
          if (gain.abs() < 0.05) continue;
          filters.add(
            'lavfi=[equalizer=f=${band.frequency}:t=q:w=1.0:g=${gain.toStringAsFixed(1)}]',
          );
        }
    }
    switch (settings[MpvSettingsCatalog.audioBassBoostKey]) {
      case 'low':
        filters.add('lavfi=[bass=g=3:f=110:w=0.6]');
      case 'medium':
        filters.add('lavfi=[bass=g=5:f=105:w=0.7]');
    }
    switch (settings[MpvSettingsCatalog.audioVoiceEnhanceKey]) {
      case 'low':
        filters
          ..add('lavfi=[highpass=f=120]')
          ..add('lavfi=[equalizer=f=2600:t=q:w=1.1:g=1.8]')
          ..add('lavfi=[equalizer=f=4200:t=q:w=1.0:g=1.0]');
      case 'medium':
        filters
          ..add('lavfi=[highpass=f=140]')
          ..add('lavfi=[equalizer=f=2600:t=q:w=1.0:g=2.6]')
          ..add('lavfi=[equalizer=f=4200:t=q:w=1.0:g=1.5]');
    }
    switch (settings[MpvSettingsCatalog.dynamicRangeKey]) {
      case 'low':
        filters.add(
          'lavfi=[acompressor=threshold=-20dB:ratio=2.0:attack=20:release=250]',
        );
      case 'medium':
        filters.add(
          'lavfi=[acompressor=threshold=-24dB:ratio=3.0:attack=15:release=220]',
        );
    }
    switch (settings[MpvSettingsCatalog.audioLimiterKey]) {
      case 'light':
        filters.add('lavfi=[alimiter=limit=0.95:attack=5:release=45]');
      case 'strong':
        filters.add('lavfi=[alimiter=limit=0.90:attack=3:release=60]');
    }
    return filters.join(',');
  }
}
