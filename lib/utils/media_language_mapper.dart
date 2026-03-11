class MediaLanguageMapper {
  MediaLanguageMapper._();

  static final Map<String, String> _languageNameMap = {
    'jpn': '\u65e5\u8bed',
    'ja': '\u65e5\u8bed',
    'jp': '\u65e5\u8bed',
    'chi': '\u4e2d\u6587',
    'zho': '\u4e2d\u6587',
    'zh': '\u4e2d\u6587',
    'cmn': '\u4e2d\u6587',
    'eng': '\u82f1\u8bed',
    'en': '\u82f1\u8bed',
    'fra': '\u6cd5\u8bed',
    'fre': '\u6cd5\u8bed',
    'fr': '\u6cd5\u8bed',
    'kor': '\u97e9\u8bed',
    'ko': '\u97e9\u8bed',
    'spa': '\u897f\u73ed\u7259\u8bed',
    'es': '\u897f\u73ed\u7259\u8bed',
    'deu': '\u5fb7\u8bed',
    'ger': '\u5fb7\u8bed',
    'de': '\u5fb7\u8bed',
    'mul': '\u591a\u79cd\u8bed\u8a00',
    'multi': '\u591a\u79cd\u8bed\u8a00',
  };

  static void mergeLanguageMap(Map<String, String> mapping) {
    for (final entry in mapping.entries) {
      final key = entry.key.trim().toLowerCase();
      final value = _normalizeLanguageValue(entry.value);
      if (key.isEmpty || value.isEmpty) continue;
      _languageNameMap[key] = value;
    }
  }

  static String _normalizeLanguageValue(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    if (value == '未确定的语言') return '未知';
    return value;
  }

  static String languageName(String raw) {
    final key = raw.trim().toLowerCase();
    if (key.isEmpty || key == 'zz-unknow' || key == 'unknown') {
      return '\u672a\u77e5';
    }
    return _languageNameMap[key] ?? '\u672a\u77e5';
  }

  static String audioLabel(String raw) {
    final name = languageName(raw);
    if (name == '\u672a\u77e5') return '\u672a\u77e5\u97f3\u9891';
    return '$name\u97f3\u9891';
  }

  static String subtitleLabel(String raw) {
    final name = languageName(raw);
    if (name == '\u672a\u77e5') return '\u672a\u77e5\u8bed\u8a00';
    return name;
  }
}
