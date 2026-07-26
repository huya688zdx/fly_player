import '../l10n/generated/app_localizations.dart';
import '../utils/media_language_mapper.dart';

/// 音轨语言展示文案的 UI 侧组装器。
///
/// [MediaLanguageMapper] 只提供语言无关的原始 code -> 语言名映射，不产出任何
/// 用户可见的完整文案；"XX音频" 这类拼接一律由本函数在 UI 层经 l10n 模板完成，
/// 模型/store/provider 层禁止直接拼出该文案。
String audioTrackLabel(AppLocalizations l10n, String audioLanguage) {
  final name = MediaLanguageMapper.languageName(audioLanguage);
  if (name.isEmpty) return '';
  return l10n.audioTrackLanguageLabel(name);
}
