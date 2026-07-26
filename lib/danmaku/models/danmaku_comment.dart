import 'package:flutter/material.dart';

enum DanmakuCommentType { scroll, top, bottom }

class DanmakuComment {
  final String id;
  final int timeMs;
  final String text;
  final DanmakuCommentType type;
  final Color color;

  const DanmakuComment({
    required this.id,
    required this.timeMs,
    required this.text,
    required this.type,
    this.color = Colors.white,
  });
}
