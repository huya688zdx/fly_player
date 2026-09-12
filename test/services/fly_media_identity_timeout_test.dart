import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/services/fly_data/fly_media_identity.dart';
import 'package:fly_player/services/fly_data/fly_media_address_selector.dart';

class _NetworkBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  _NetworkBinding();

  test('timeout aborts and closes an actual hanging HTTP socket', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final received = Completer<void>();
    final disconnected = Completer<void>();
    final sockets = <Socket>[];
    server.listen((socket) {
      sockets.add(socket);
      socket.listen(
        (bytes) {
          if (!received.isCompleted) received.complete();
          // Keep both headers and body pending until the probe cancels.
        },
        onDone: () {
          if (!disconnected.isCompleted) disconnected.complete();
        },
        onError: (Object _) {
          if (!disconnected.isCompleted) disconnected.complete();
        },
      );
    });
    try {
      final timer = Stopwatch()..start();
      final probe = verifyFlyMediaAddress(
        address: 'http://127.0.0.1:${server.port}',
        kind: 'emby',
        expectedId: 'instance-a',
        timeout: const Duration(milliseconds: 150),
      );
      await expectLater(probe, throwsStateError);
      expect(received.isCompleted, isTrue);
      await disconnected.future.timeout(const Duration(seconds: 1));
      expect(timer.elapsed, lessThan(const Duration(seconds: 2)));
    } finally {
      for (final socket in sockets) {
        socket.destroy();
      }
      await server.close();
    }
  });

  test(
    'public verification rejects wrong instance and never sends credentials',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requests = 0;
      server.listen((request) async {
        requests++;
        expect(request.uri.path, '/System/Info/Public');
        expect(request.headers.value('authorization'), isNull);
        expect(request.headers.value('cookie'), isNull);
        expect(request.headers.value('x-emby-token'), isNull);
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'Id': 'other-instance', 'detail': 'private response'}),
        );
        await request.response.close();
      });
      try {
        await expectLater(
          selectFlyMediaAddress(
            addresses: [
              {
                'purpose': 'client_lan',
                'base_url': 'http://127.0.0.1:${server.port}',
                'priority': 0,
              },
            ],
            kind: 'emby',
            expectedId: 'instance-a',
          ),
          throwsStateError,
        );
        expect(requests, 1);
      } finally {
        await server.close(force: true);
      }
    },
  );

  test('deadline closes a response body that keeps delivering bytes', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final disconnected = Completer<void>();
    final sockets = <Socket>[];
    final tickers = <Timer>[];
    server.listen((socket) {
      sockets.add(socket);
      var started = false;
      Timer? ticker;
      void ended() {
        ticker?.cancel();
        if (!disconnected.isCompleted) disconnected.complete();
      }

      socket.listen(
        (bytes) {
          if (started) return;
          started = true;
          socket.write(
            'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 100000\r\n\r\n',
          );
          ticker = Timer.periodic(
            const Duration(milliseconds: 10),
            (_) => socket.write(' '),
          );
          tickers.add(ticker!);
        },
        onDone: ended,
        onError: (Object _) => ended(),
      );
    });
    try {
      await expectLater(
        verifyFlyMediaAddress(
          address: 'http://127.0.0.1:${server.port}',
          kind: 'emby',
          expectedId: 'instance-a',
          timeout: const Duration(milliseconds: 150),
        ),
        throwsStateError,
      );
      await disconnected.future.timeout(const Duration(seconds: 1));
    } finally {
      for (final timer in tickers) {
        timer.cancel();
      }
      for (final socket in sockets) {
        socket.destroy();
      }
      await server.close();
    }
  });

  test(
    'automatic scan stops at total budget and cancels every open socket',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      final disconnected = <Completer<void>>[];
      server.listen((socket) {
        sockets.add(socket);
        final closed = Completer<void>();
        disconnected.add(closed);
        void ended() {
          if (!closed.isCompleted) closed.complete();
        }

        socket.listen((_) {}, onDone: ended, onError: (Object _) => ended());
      });
      try {
        final clock = Stopwatch()..start();
        await expectLater(
          selectFlyMediaAddress(
            addresses: List.generate(
              8,
              (index) => {
                'purpose': 'client_lan',
                'base_url': 'http://127.0.0.1:${server.port}/candidate-$index',
                'priority': index,
              },
            ),
            kind: 'emby',
            expectedId: 'instance-a',
          ),
          throwsStateError,
        );
        expect(clock.elapsed, lessThan(const Duration(seconds: 14)));
        expect(sockets.length, inInclusiveRange(1, 4));
        await Future.wait(
          disconnected.map((closed) => closed.future),
        ).timeout(const Duration(seconds: 1));
      } finally {
        for (final socket in sockets) {
          socket.destroy();
        }
        await server.close();
      }
    },
    timeout: const Timeout(Duration(seconds: 18)),
  );

  test('identity probe refuses redirects to a different endpoint', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var forwarded = 0;
    server.listen((request) async {
      if (request.uri.path == '/System/Info/Public') {
        request.response.statusCode = 302;
        request.response.headers.set('location', '/followed');
      } else {
        forwarded++;
        request.response.write(jsonEncode({'Id': 'instance-a'}));
      }
      await request.response.close();
    });
    try {
      await expectLater(
        verifyFlyMediaAddress(
          address: 'http://127.0.0.1:${server.port}',
          kind: 'emby',
          expectedId: 'instance-a',
        ),
        throwsStateError,
      );
      expect(forwarded, 0);
    } finally {
      await server.close(force: true);
    }
  });
}
