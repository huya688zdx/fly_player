// 完整用户可见文案（如"XX音频"这类拼接）只能经 lib/ui/ 下的 helper 组装；
// code 规整（normalizeLanguageCode 等）、语言名查表（languageName/subtitleLabel）
// 允许模型/store 等层直接 import 调用，但模型层禁止拼出用户可见的完整文案。
class MediaLanguageMapper {
  MediaLanguageMapper._();

  static final Map<String, String> _languageNameMap = {
    'ara': '\u963f\u62c9\u4f2f\u8bed',
    'ar': '\u963f\u62c9\u4f2f\u8bed',
    'bul': '\u4fdd\u52a0\u5229\u4e9a\u8bed',
    'bg': '\u4fdd\u52a0\u5229\u4e9a\u8bed',
    'cat': '\u52a0\u6cf0\u7f57\u5c3c\u4e9a\u8bed',
    'ca': '\u52a0\u6cf0\u7f57\u5c3c\u4e9a\u8bed',
    'ces': '\u6377\u514b\u8bed',
    'cze': '\u6377\u514b\u8bed',
    'cs': '\u6377\u514b\u8bed',
    'jpn': '\u65e5\u8bed',
    'ja': '\u65e5\u8bed',
    'jp': '\u65e5\u8bed',
    'chi': '\u4e2d\u6587',
    'zho': '\u4e2d\u6587',
    'zh': '\u4e2d\u6587',
    'cmn': '\u4e2d\u6587',
    'eng': '\u82f1\u8bed',
    'en': '\u82f1\u8bed',
    'dan': '\u4e39\u9ea6\u8bed',
    'da': '\u4e39\u9ea6\u8bed',
    'nld': '\u8377\u5170\u8bed',
    'dut': '\u8377\u5170\u8bed',
    'nl': '\u8377\u5170\u8bed',
    'ell': '\u5e0c\u814a\u8bed',
    'gre': '\u5e0c\u814a\u8bed',
    'el': '\u5e0c\u814a\u8bed',
    'est': '\u7231\u6c99\u5c3c\u4e9a\u8bed',
    'et': '\u7231\u6c99\u5c3c\u4e9a\u8bed',
    'fin': '\u82ac\u5170\u8bed',
    'fi': '\u82ac\u5170\u8bed',
    'fra': '\u6cd5\u8bed',
    'fre': '\u6cd5\u8bed',
    'fr': '\u6cd5\u8bed',
    'heb': '\u5e0c\u4f2f\u6765\u8bed',
    'he': '\u5e0c\u4f2f\u6765\u8bed',
    'hin': '\u5370\u5730\u8bed',
    'hi': '\u5370\u5730\u8bed',
    'hrv': '\u514b\u7f57\u5730\u4e9a\u8bed',
    'hr': '\u514b\u7f57\u5730\u4e9a\u8bed',
    'hun': '\u5308\u7259\u5229\u8bed',
    'hu': '\u5308\u7259\u5229\u8bed',
    'ind': '\u5370\u5c3c\u8bed',
    'id': '\u5370\u5c3c\u8bed',
    'ita': '\u610f\u5927\u5229\u8bed',
    'it': '\u610f\u5927\u5229\u8bed',
    'kor': '\u97e9\u8bed',
    'ko': '\u97e9\u8bed',
    'lav': '\u62c9\u8131\u7ef4\u4e9a\u8bed',
    'lv': '\u62c9\u8131\u7ef4\u4e9a\u8bed',
    'lit': '\u7acb\u9676\u5b9b\u8bed',
    'lt': '\u7acb\u9676\u5b9b\u8bed',
    'msa': '\u9a6c\u6765\u8bed',
    'may': '\u9a6c\u6765\u8bed',
    'ms': '\u9a6c\u6765\u8bed',
    'nob': '\u632a\u5a01\u8bed',
    'nno': '\u632a\u5a01\u8bed',
    'nor': '\u632a\u5a01\u8bed',
    'nb': '\u632a\u5a01\u8bed',
    'nn': '\u632a\u5a01\u8bed',
    'no': '\u632a\u5a01\u8bed',
    'pol': '\u6ce2\u5170\u8bed',
    'pl': '\u6ce2\u5170\u8bed',
    'por': '\u8461\u8404\u7259\u8bed',
    'pt': '\u8461\u8404\u7259\u8bed',
    'ron': '\u7f57\u9a6c\u5c3c\u4e9a\u8bed',
    'rum': '\u7f57\u9a6c\u5c3c\u4e9a\u8bed',
    'ro': '\u7f57\u9a6c\u5c3c\u4e9a\u8bed',
    'rus': '\u4fc4\u8bed',
    'ru': '\u4fc4\u8bed',
    'slk': '\u65af\u6d1b\u4f10\u514b\u8bed',
    'slo': '\u65af\u6d1b\u4f10\u514b\u8bed',
    'sk': '\u65af\u6d1b\u4f10\u514b\u8bed',
    'slv': '\u65af\u6d1b\u6587\u5c3c\u4e9a\u8bed',
    'sl': '\u65af\u6d1b\u6587\u5c3c\u4e9a\u8bed',
    'spa': '\u897f\u73ed\u7259\u8bed',
    'es': '\u897f\u73ed\u7259\u8bed',
    'srp': '\u585e\u5c14\u7ef4\u4e9a\u8bed',
    'sr': '\u585e\u5c14\u7ef4\u4e9a\u8bed',
    'swe': '\u745e\u5178\u8bed',
    'sv': '\u745e\u5178\u8bed',
    'tha': '\u6cf0\u8bed',
    'th': '\u6cf0\u8bed',
    'tur': '\u571f\u8033\u5176\u8bed',
    'tr': '\u571f\u8033\u5176\u8bed',
    'ukr': '\u4e4c\u514b\u5170\u8bed',
    'uk': '\u4e4c\u514b\u5170\u8bed',
    'vie': '\u8d8a\u5357\u8bed',
    'vi': '\u8d8a\u5357\u8bed',
    'deu': '\u5fb7\u8bed',
    'ger': '\u5fb7\u8bed',
    'de': '\u5fb7\u8bed',
    'mul': '\u591a\u79cd\u8bed\u8a00',
    'multi': '\u591a\u79cd\u8bed\u8a00',
  };

  static final Map<String, String> _languageAliasToCode = {
    'arabic': 'ara',
    'ara': 'ara',
    'ar': 'ara',
    '\u963f\u62c9\u4f2f\u8bed': 'ara',
    'bulgarian': 'bul',
    'bul': 'bul',
    'bg': 'bul',
    '\u4fdd\u52a0\u5229\u4e9a\u8bed': 'bul',
    'catalan': 'cat',
    'cat': 'cat',
    'ca': 'cat',
    '\u52a0\u6cf0\u7f57\u5c3c\u4e9a\u8bed': 'cat',
    'czech': 'ces',
    'ces': 'ces',
    'cze': 'ces',
    'cs': 'ces',
    '\u6377\u514b\u8bed': 'ces',
    'danish': 'dan',
    'dan': 'dan',
    'da': 'dan',
    '\u4e39\u9ea6\u8bed': 'dan',
    'dutch': 'nld',
    'nld': 'nld',
    'dut': 'nld',
    'nl': 'nld',
    '\u8377\u5170\u8bed': 'nld',
    'english': 'eng',
    'eng': 'eng',
    'en': 'eng',
    '\u82f1\u8bed': 'eng',
    '\u82f1\u6587': 'eng',
    'estonian': 'est',
    'est': 'est',
    'et': 'est',
    '\u7231\u6c99\u5c3c\u4e9a\u8bed': 'est',
    'finnish': 'fin',
    'fin': 'fin',
    'fi': 'fin',
    '\u82ac\u5170\u8bed': 'fin',
    'french': 'fra',
    'fra': 'fra',
    'fre': 'fra',
    'fr': 'fra',
    '\u6cd5\u8bed': 'fra',
    'german': 'deu',
    'deu': 'deu',
    'ger': 'deu',
    'de': 'deu',
    '\u5fb7\u8bed': 'deu',
    'greek': 'ell',
    'ell': 'ell',
    'gre': 'ell',
    'el': 'ell',
    '\u5e0c\u814a\u8bed': 'ell',
    'hebrew': 'heb',
    'heb': 'heb',
    'he': 'heb',
    '\u5e0c\u4f2f\u6765\u8bed': 'heb',
    'hindi': 'hin',
    'hin': 'hin',
    'hi': 'hin',
    '\u5370\u5730\u8bed': 'hin',
    'croatian': 'hrv',
    'hrv': 'hrv',
    'hr': 'hrv',
    '\u514b\u7f57\u5730\u4e9a\u8bed': 'hrv',
    'hungarian': 'hun',
    'hun': 'hun',
    'hu': 'hun',
    '\u5308\u7259\u5229\u8bed': 'hun',
    'indonesian': 'ind',
    'ind': 'ind',
    'id': 'ind',
    '\u5370\u5c3c\u8bed': 'ind',
    'italian': 'ita',
    'ita': 'ita',
    'it': 'ita',
    '\u610f\u5927\u5229\u8bed': 'ita',
    'japanese': 'jpn',
    'jpn': 'jpn',
    'ja': 'jpn',
    'jp': 'jpn',
    '\u65e5\u8bed': 'jpn',
    '\u65e5\u6587': 'jpn',
    '\u65e5\u672c\u8bed': 'jpn',
    'korean': 'kor',
    'kor': 'kor',
    'ko': 'kor',
    '\u97e9\u8bed': 'kor',
    '\u97e9\u6587': 'kor',
    '\u671d\u9c9c\u8bed': 'kor',
    '\u671d\u9c9c\u6587': 'kor',
    'latvian': 'lav',
    'lav': 'lav',
    'lv': 'lav',
    '\u62c9\u8131\u7ef4\u4e9a\u8bed': 'lav',
    'lithuanian': 'lit',
    'lit': 'lit',
    'lt': 'lit',
    '\u7acb\u9676\u5b9b\u8bed': 'lit',
    'malay': 'msa',
    'msa': 'msa',
    'may': 'msa',
    'ms': 'msa',
    '\u9a6c\u6765\u8bed': 'msa',
    'norwegian': 'nor',
    'nor': 'nor',
    'nob': 'nor',
    'nno': 'nor',
    'nb': 'nor',
    'nn': 'nor',
    'no': 'nor',
    '\u632a\u5a01\u8bed': 'nor',
    'polish': 'pol',
    'pol': 'pol',
    'pl': 'pol',
    '\u6ce2\u5170\u8bed': 'pol',
    'portuguese': 'por',
    'por': 'por',
    'pt': 'por',
    '\u8461\u8404\u7259\u8bed': 'por',
    'romanian': 'ron',
    'ron': 'ron',
    'rum': 'ron',
    'ro': 'ron',
    '\u7f57\u9a6c\u5c3c\u4e9a\u8bed': 'ron',
    'russian': 'rus',
    'rus': 'rus',
    'ru': 'rus',
    '\u4fc4\u8bed': 'rus',
    'serbian': 'srp',
    'srp': 'srp',
    'sr': 'srp',
    '\u585e\u5c14\u7ef4\u4e9a\u8bed': 'srp',
    'slovak': 'slk',
    'slk': 'slk',
    'slo': 'slk',
    'sk': 'slk',
    '\u65af\u6d1b\u4f10\u514b\u8bed': 'slk',
    'slovenian': 'slv',
    'slv': 'slv',
    'sl': 'slv',
    '\u65af\u6d1b\u6587\u5c3c\u4e9a\u8bed': 'slv',
    'spanish': 'spa',
    'spa': 'spa',
    'es': 'spa',
    '\u897f\u73ed\u7259\u8bed': 'spa',
    'swedish': 'swe',
    'swe': 'swe',
    'sv': 'swe',
    '\u745e\u5178\u8bed': 'swe',
    'thai': 'tha',
    'tha': 'tha',
    'th': 'tha',
    '\u6cf0\u8bed': 'tha',
    'turkish': 'tur',
    'tur': 'tur',
    'tr': 'tur',
    '\u571f\u8033\u5176\u8bed': 'tur',
    'ukrainian': 'ukr',
    'ukr': 'ukr',
    'uk': 'ukr',
    '\u4e4c\u514b\u5170\u8bed': 'ukr',
    'vietnamese': 'vie',
    'vie': 'vie',
    'vi': 'vie',
    '\u8d8a\u5357\u8bed': 'vie',
    'chinese': 'zho',
    'chi': 'zho',
    'zho': 'zho',
    'zh': 'zho',
    'cmn': 'zho',
    '\u4e2d\u6587': 'zho',
    '\u7b80\u4f53\u4e2d\u6587': 'zho',
    '\u7b80\u4e2d': 'zho',
    '\u7b80\u4f53': 'zho',
    '\u7e41\u4f53\u4e2d\u6587': 'zho',
    '\u7e41\u4e2d': 'zho',
    '\u7e41\u4f53': 'zho',
    'traditional chinese': 'zho',
    'simplified chinese': 'zho',
    'trad': 'zho',
    'traditional': 'zho',
    'simp': 'zho',
    'simplified': 'zho',
    'cht': 'zho',
    'chs': 'zho',
    'multi': 'mul',
    'mul': 'mul',
    '\u591a\u8bed\u8a00': 'mul',
    '\u591a\u79cd\u8bed\u8a00': 'mul',
  };

  static void mergeLanguageMap(Map<String, String> mapping) {
    for (final entry in mapping.entries) {
      final rawKey = entry.key.trim().toLowerCase();
      final value = _normalizeLanguageValue(entry.value);
      if (rawKey.isEmpty || value.isEmpty) continue;
      final key = normalizeLanguageCode(rawKey) ?? rawKey;
      _languageNameMap[key] = value;
      _languageAliasToCode.putIfAbsent(rawKey, () => key);
    }
  }

  static String _normalizeLanguageValue(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    if (value == '未确定的语言') return '';
    return value;
  }

  static String languageName(String raw) {
    final key = raw.trim().toLowerCase();
    if (key.isEmpty || key == 'zz-unknow' || key == 'unknown' || key == 'und') {
      return '';
    }
    final normalizedKey = normalizeLanguageCode(key);
    if (normalizedKey == null) return '';
    return _languageNameMap[normalizedKey] ?? _languageNameMap[key] ?? '';
  }

  static String subtitleLabel(String raw) {
    return languageName(raw);
  }

  static String? normalizeLanguageCode(String raw) {
    final key = raw.trim().toLowerCase();
    if (key.isEmpty || key == 'zz-unknow' || key == 'unknown' || key == 'und') {
      return null;
    }
    return _languageAliasToCode[key] ??
        (_languageNameMap.containsKey(key) ? key : null);
  }

  static String? inferLanguageCodeFromText(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final normalizedCode = normalizeLanguageCode(value);
    if (normalizedCode != null) {
      return normalizedCode;
    }
    final lower = value.toLowerCase();
    final tokens = lower
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    for (final token in tokens) {
      final code = normalizeLanguageCode(token);
      if (code != null) {
        return code;
      }
    }
    for (final entry in _languageAliasToCode.entries) {
      final alias = entry.key;
      if (alias.codeUnits.any((unit) => unit > 127) && value.contains(alias)) {
        return entry.value;
      }
    }
    return null;
  }
}
