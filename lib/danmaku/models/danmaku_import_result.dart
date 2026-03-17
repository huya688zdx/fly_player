import 'danmaku_comment.dart';

class DanmakuImportResult {
  final String sourceLabel;
  final List<DanmakuComment> comments;

  const DanmakuImportResult({
    required this.sourceLabel,
    required this.comments,
  });
}
