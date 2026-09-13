import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/widgets/fly_assistant_panel.dart';

void main() {
  testWidgets(
    'context is carried into run and model markup remains plain text',
    (tester) async {
      final sent = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlyAssistantPanel(
              mediaId: 'media1',
              isCurrent: () => true,
              request: (path, {body, query}) async {
                if (path == '/assistant/context') {
                  return {
                    'media': {'id': 'media1', 'title': '当前一集'},
                    'file_context': {'identity_state': 'unresolved'},
                    'capabilities': {'assistant': true},
                  };
                }
                if (body != null) {
                  sent.add(Map<String, dynamic>.from(body as Map));
                }
                return {
                  'id': 'run1',
                  'status': 'completed',
                  'answer': '<script>execute()</script>',
                  'evidence': [
                    {'title': '真实来源标题', 'url': 'https://example.org/source'},
                  ],
                  'budget': {'model_calls': 1},
                };
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('当前一集'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '这一集有什么资源？');
      await tester.tap(find.text('查找资料'));
      await tester.pumpAndSettle();
      expect(sent.single['media_id'], 'media1');
      expect(sent.single.containsKey('max_model_calls'), isFalse);
      expect(find.text('<script>execute()</script>'), findsOneWidget);
      expect(find.text('真实来源标题'), findsOneWidget);
    },
  );

  testWidgets('cancel running work and reject late account response', (
    tester,
  ) async {
    bool current = true;
    final paths = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FlyAssistantPanel(
            mediaId: 'media1',
            isCurrent: () => current,
            request: (path, {body, query}) async {
              paths.add(path);
              if (path == '/assistant/context') {
                return {
                  'media': {'id': 'media1', 'title': '原账号节目'},
                };
              }
              if (path.endsWith('/cancel')) {
                return {'id': 'run1', 'status': 'cancelled'};
              }
              return {'id': 'run1', 'status': 'running'};
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '资源');
    await tester.tap(find.text('查找资料'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消任务'));
    await tester.pumpAndSettle();
    expect(paths, contains('/assistant/runs/run1/cancel'));
    current = false;
    await tester.tap(find.text('查找资料'));
    await tester.pumpAndSettle();
    expect(paths.where((p) => p == '/assistant/runs').length, 1);
  });
}
