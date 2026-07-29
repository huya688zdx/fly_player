import 'package:fly_player/screens/poster_browse/poster_browse_enrichment_commit_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PosterBrowseEnrichmentCommitPolicy', () {
    test('同一加载会话但焦点已变化时仍提交展示，不应用焦点副作用', () {
      final decision = PosterBrowseEnrichmentCommitPolicy.resolve(
        requestLoadGeneration: 4,
        currentLoadGeneration: 4,
        requestFocusGeneration: 7,
        currentFocusGeneration: 8,
      );

      expect(decision.commitDisplay, isTrue);
      expect(decision.applyFocusEffects, isFalse);
    });

    test('同一加载会话且焦点未变化时提交展示并应用焦点副作用', () {
      final decision = PosterBrowseEnrichmentCommitPolicy.resolve(
        requestLoadGeneration: 4,
        currentLoadGeneration: 4,
        requestFocusGeneration: 8,
        currentFocusGeneration: 8,
      );

      expect(decision.commitDisplay, isTrue);
      expect(decision.applyFocusEffects, isTrue);
    });

    test('旧加载会话既不提交展示也不应用焦点副作用', () {
      final decision = PosterBrowseEnrichmentCommitPolicy.resolve(
        requestLoadGeneration: 3,
        currentLoadGeneration: 4,
        requestFocusGeneration: 8,
        currentFocusGeneration: 8,
      );

      expect(decision.commitDisplay, isFalse);
      expect(decision.applyFocusEffects, isFalse);
    });
  });
}
