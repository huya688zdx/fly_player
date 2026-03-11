class CapabilityBadgeMapper {
  static String normalize(String raw) {
    final s = raw.trim();
    final u = s.toUpperCase();
    if (u.isEmpty) return '';

    if (u.contains('DOLBY') && u.contains('VISION')) return 'DOLBY VISION';
    if (u.contains('DOLBY') && u.contains('ATMOS')) return 'DOLBY ATMOS';
    if (u.contains('DTS')) return 'DTS';
    if (u.contains('HDR')) return 'HDR';
    if (u.contains('SDR')) return 'SDR';
    if (u.contains('4K') || u.contains('2160')) return '4K';
    if (u.contains('1080')) return '1080';
    if (u.contains('720')) return '720';
    if (u.contains('480')) return '480';
    if (u.contains('STEREO') || u == 'OTHERS') return 'STEREO';
    if (u.contains('DOLBY')) return 'DOLBY';
    return s;
  }

  static String? badgeAsset(String normalizedLabel) {
    switch (normalizedLabel) {
      case '4K':
        return 'assets/icons/badge_4k.svg';
      case '1080':
        return 'assets/icons/badge_1080.svg';
      case '720':
        return 'assets/icons/badge_720.svg';
      case '480':
        return 'assets/icons/badge_480.svg';
      case 'SDR':
        return 'assets/icons/badge_sdr.svg';
      case 'HDR':
        return 'assets/icons/badge_hdr.svg';
      case 'DTS':
        return 'assets/icons/icons-dts.svg';
      case 'DOLBY':
        return 'assets/icons/a-dolbyatmos.svg';
      case 'DOLBY VISION':
        return 'assets/icons/Dolby_Vision.svg';
      case 'DOLBY ATMOS':
        return 'assets/icons/a-dolbyatmos.svg';
      case 'STEREO':
        return 'assets/icons/badge_stereo.svg';
      default:
        return null;
    }
  }
}
