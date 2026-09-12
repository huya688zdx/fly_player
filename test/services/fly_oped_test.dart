import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/services/fly_data/fly_oped.dart';

Map<String, dynamic> publication({
  String context = 'load-1',
  int generation = 0,
}) => {
  'playback_context_id': context,
  'generation': generation,
  'status': 'published',
  'file_context': {
    'source_ref': {
      'binding_id': 'binding',
      'remote_item_id': 'episode',
      'remote_media_source_id': null,
    },
    'identity_state': 'verified',
    'file_revision_id': 'file-1',
    'media_coordinate_id': 'coord-1',
    'duration_ms': 120000,
  },
  'set_revision': 'set-1',
  'segments': [
    {
      'id': 'ed',
      'kind': 'ed',
      'start_ms': 90000,
      'end_ms': 110000,
      'skip_policy': 'auto',
    },
  ],
  'protected_ranges': [
    {'start_ms': 110000, 'end_ms': 120000},
  ],
};

void main() {
  const source = FlySourceRef(bindingId: 'binding', remoteItemId: 'episode');
  FlyOpedSet? parse(Map<String, dynamic> data) => FlyOpedSet.parse(
    data,
    source: source,
    contextId: 'load-1',
    generation: 0,
  );
  test('published ED ends before protected post credits', () {
    final set = parse(publication())!;
    expect(set.at(100000)?.endMs, 110000);
    expect(set.at(110000), isNull);
    expect(set.at(100000, enabled: false), isNull);
  });
  test(
    'fresh authorization must preserve pinned revision and exact target',
    () {
      final set = parse(publication())!;
      expect(set.samePublication(parse(publication())!), isTrue);
      expect(
        set.samePublication(parse({...publication(), 'set_revision': 'set2'})!),
        isFalse,
      );
      final changed = publication();
      (changed['segments'] as List).first['end_ms'] = 105000;
      expect(set.samePublication(parse(changed)!), isFalse);
    },
  );
  test('unresolved identity, stale context and stale seek are rejected', () {
    final data = publication();
    (data['file_context'] as Map)['identity_state'] = 'unresolved';
    expect(parse(data), isNull);
    expect(parse(publication(context: 'old')), isNull);
    expect(parse(publication(generation: 1)), isNull);
  });
  test(
    'overlap with protected content and malformed entire sets fail closed',
    () {
      final data = publication();
      (data['segments'] as List).first['end_ms'] = 115000;
      expect(parse(data), isNull);
      expect(
        parse({
          ...publication(),
          'segments': [
            {
              'id': 'bad',
              'kind': 'op',
              'start_ms': 0,
              'end_ms': 900000,
              'skip_policy': 'auto',
            },
          ],
        }),
        isNull,
      );
    },
  );
  test(
    'entry by resume or seek only prompts, normal crossing may auto once',
    () {
      final policy = FlyOpedPlaybackPolicy();
      final set = parse(publication())!;
      expect(policy.observe(set, 95000), isNull);
      policy.userSeek();
      expect(policy.observe(set, 95000), isNull);
      expect(policy.observe(set, 96000), isNull);
      final normal = FlyOpedPlaybackPolicy();
      expect(normal.observe(set, 89000), isNull);
      expect(normal.observe(set, 90000)?.id, 'ed');
      expect(normal.observe(set, 91000), isNull);
      final afterSeek = FlyOpedPlaybackPolicy()..userSeek();
      expect(afterSeek.observe(set, 89000), isNull);
      expect(afterSeek.observe(set, 90000)?.id, 'ed');
    },
  );
  test(
    'intent only settles from a new position sample after engine acceptance',
    () {
      final action = FlyOpedAction(
        set: parse(publication())!,
        segment: parse(publication())!.segments.first,
        generation: 0,
        positionMs: 95000,
        actionId: 'action',
      );
      expect(
        action.sample(positionMs: 110000, engineAccepted: false, generation: 1),
        isNull,
      );
      action.expectedGeneration = 1;
      expect(
        action.sample(positionMs: 110501, engineAccepted: true, generation: 1),
        isNull,
      );
      expect(
        action.sample(positionMs: 95000, engineAccepted: true, generation: 1),
        isNull,
      );
      expect(
        action.sample(positionMs: 110010, engineAccepted: true, generation: 1),
        'settled',
      );
      expect(
        action.sample(positionMs: 110020, engineAccepted: true, generation: 1),
        isNull,
      );
      expect(action.event('intent')['target_ms'], 110000);
      expect(action.event('settled')['position_ms'], 110010);
    },
  );
  test('intervening user seek cancels action rather than counting success', () {
    final set = parse(publication())!;
    final action = FlyOpedAction(
      set: set,
      segment: set.segments.first,
      generation: 0,
      positionMs: 95000,
      actionId: 'action',
    )..expectedGeneration = 1;
    expect(
      action.sample(positionMs: 110000, engineAccepted: true, generation: 2),
      'cancelled',
    );
    expect(action.finish('settled'), isNull);
  });
}
