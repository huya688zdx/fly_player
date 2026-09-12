import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/services/fly_data/fly_media_address_selector.dart';

Map<String, dynamic> address(
  String url, {
  String purpose = 'client_lan',
  int priority = 0,
}) => {'purpose': purpose, 'base_url': url, 'priority': priority};

void main() {
  const lan = 'http://192.0.2.1:8096';
  const remote = 'https://media.example';
  late List<String> probes;
  late Set<String> rejected;
  Future<void> verify({
    required String address,
    required String kind,
    required String expectedId,
    required Duration timeout,
  }) async {
    probes.add(address);
    expect(kind, 'emby');
    expect(expectedId, 'instance-a');
    expect(timeout, lessThanOrEqualTo(const Duration(seconds: 3)));
    expect(timeout, greaterThan(Duration.zero));
    if (rejected.contains(address)) {
      throw StateError('synthetic sensitive response');
    }
  }

  setUp(() {
    probes = [];
    rejected = {};
  });

  test('reuse the still-authorized preferred address before LAN', () async {
    final selected = await selectFlyMediaAddress(
      addresses: [
        address(lan),
        address(remote, purpose: 'client_remote', priority: 10),
      ],
      kind: 'emby',
      expectedId: 'instance-a',
      preferredAddress: '$remote/',
      verify: verify,
    );
    expect(selected, remote);
    expect(probes, [remote]);
  });

  test('failed LAN falls back to verified remote', () async {
    rejected.add(lan);
    final selected = await selectFlyMediaAddress(
      addresses: [
        address(lan),
        address(remote, purpose: 'client_remote', priority: 10),
      ],
      kind: 'emby',
      expectedId: 'instance-a',
      verify: verify,
    );
    expect(selected, remote);
    expect(probes, [lan, remote]);
  });

  test('removed preferred address is never probed', () async {
    final selected = await selectFlyMediaAddress(
      addresses: [address(remote)],
      kind: 'emby',
      expectedId: 'instance-a',
      preferredAddress: lan,
      verify: verify,
    );
    expect(selected, remote);
    expect(probes, [remote]);
  });

  test('NAS API and unsupported purposes cannot be candidates', () async {
    final selected = await selectFlyMediaAddress(
      addresses: [
        address(lan, purpose: 'nas_api'),
        address('https://unknown.example', purpose: 'future'),
        address(remote, purpose: 'vpn'),
      ],
      kind: 'emby',
      expectedId: 'instance-a',
      preferredAddress: lan,
      verify: verify,
    );
    expect(selected, remote);
    expect(probes, [remote]);
  });

  test(
    'sort ascending priority stably and deduplicate normalized URLs',
    () async {
      rejected.addAll([lan, remote]);
      await expectLater(
        selectFlyMediaAddress(
          addresses: [
            address('$remote/', priority: 4),
            address(lan, priority: 2),
            address(remote, priority: 4),
            address('$lan/', priority: 2),
          ],
          kind: 'emby',
          expectedId: 'instance-a',
          verify: verify,
        ),
        throwsStateError,
      );
      expect(probes, [lan, remote]);
    },
  );

  test('equal priority retains authorization order', () async {
    rejected.add(remote);
    final selected = await selectFlyMediaAddress(
      addresses: [address(remote), address(lan)],
      kind: 'emby',
      expectedId: 'instance-a',
      verify: verify,
    );
    expect(selected, lan);
    expect(probes, [remote, lan]);
  });

  test('explicit authorized address is the only candidate', () async {
    final selected = await selectFlyMediaAddress(
      addresses: [address(lan), address(remote)],
      kind: 'emby',
      expectedId: 'instance-a',
      preferredAddress: lan,
      explicitAddress: '$remote/',
      verify: verify,
    );
    expect(selected, remote);
    expect(probes, [remote]);
  });

  test('failed explicit address never falls back or leaks response', () async {
    rejected.add(remote);
    await expectLater(
      selectFlyMediaAddress(
        addresses: [address(lan), address(remote)],
        kind: 'emby',
        expectedId: 'instance-a',
        explicitAddress: remote,
        verify: verify,
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message.toString(),
          'safe message',
          isNot(contains('synthetic sensitive response')),
        ),
      ),
    );
    expect(probes, [remote]);
  });

  test(
    'explicit address outside fresh authorization never gets probed',
    () async {
      await expectLater(
        selectFlyMediaAddress(
          addresses: [address(lan)],
          kind: 'emby',
          expectedId: 'instance-a',
          explicitAddress: remote,
          verify: verify,
        ),
        throwsStateError,
      );
      expect(probes, isEmpty);
    },
  );

  test(
    'missing expected identity requires reauthorization before any probe',
    () async {
      await expectLater(
        selectFlyMediaAddress(
          addresses: [address(lan)],
          kind: 'emby',
          expectedId: ' ',
          verify: verify,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message.toString(),
            'reauthorize',
            contains('重新授权'),
          ),
        ),
      );
      expect(probes, isEmpty);
    },
  );

  test('all failures expose a concise safe error', () async {
    rejected.addAll([lan, remote]);
    await expectLater(
      selectFlyMediaAddress(
        addresses: [address(lan), address(remote)],
        kind: 'emby',
        expectedId: 'instance-a',
        verify: verify,
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message.toString(),
          'safe message',
          allOf(
            isNot(contains('synthetic')),
            isNot(contains(lan)),
            isNot(contains(remote)),
          ),
        ),
      ),
    );
    expect(probes, [lan, remote]);
  });

  for (final unsafe in [
    'https://user:password@media.example',
    'file:///tmp/media',
    'https://media.example?token=secret',
    'https://media.example#secret',
    'https://media.example/../admin',
    'https://media.example/./admin',
    ' https://media.example',
    'https://media.example\\admin',
    'http://media.example:0',
  ]) {
    test('invalid base URL is not probed: $unsafe', () async {
      final selected = await selectFlyMediaAddress(
        addresses: [address(unsafe), address(remote)],
        kind: 'emby',
        expectedId: 'instance-a',
        verify: verify,
      );
      expect(selected, remote);
      expect(probes, [remote]);
    });
  }

  test(
    'schema overflow is rejected without starting an unbounded scan',
    () async {
      await expectLater(
        selectFlyMediaAddress(
          addresses: List.generate(
            17,
            (i) => address('https://media-$i.example'),
          ),
          kind: 'emby',
          expectedId: 'instance-a',
          verify: verify,
        ),
        throwsStateError,
      );
      expect(probes, isEmpty);
    },
  );
}
