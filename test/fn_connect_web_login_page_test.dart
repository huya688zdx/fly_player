import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/screens/fn_connect_web_login_page.dart';
import 'package:fly_player/screens/fn_web_login_bridge_script.dart';
import 'package:fly_player/utils/private_network_http_overrides.dart';

void main() {
  testWidgets(
    '关闭登录页后不再创建等待环境初始化的 Windows WebView',
    (tester) async {
      const channel = MethodChannel('io.jns.webview.win');
      final environmentReady = Completer<void>();
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        if (call.method == 'initializeEnvironment') {
          await environmentReady.future;
        }
        return null;
      });
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
      });
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: FnConnectWebLoginPage(
            fnConnectId: 'test',
            userName: 'user',
            password: 'password',
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(calls, <String>['initializeEnvironment']);
      await tester.pumpWidget(const SizedBox.shrink());
      environmentReady.complete();
      await tester.pump();
      expect(calls, <String>['initializeEnvironment']);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  group('FnConnectWebLoginEntry', () {
    test('有 relay host 时仍从官方页兜底，relay 只作为 OAuth 配置候选', () {
      final entry = FnConnectWebLoginEntry.resolve(
        fnConnectId: 'geqian688',
        relayHosts: const <String>[' relay.example.com ', 'backup.example.com'],
      );

      expect(entry.initialUrl, 'https://5ddd.com/geqian688');
      expect(entry.relayBaseUrls, const <String>[
        'https://relay.example.com',
        'https://backup.example.com',
      ]);
      expect(entry.cookieHosts, const <String>[
        'relay.example.com',
        'backup.example.com',
        '5ddd.com',
        'fnos.net',
      ]);
    });

    test('relay host 可包含协议和路径，最终只保留 origin', () {
      final entry = FnConnectWebLoginEntry.resolve(
        fnConnectId: 'geqian688',
        relayHosts: const <String>['https://relay.example.com/foo/bar'],
      );

      expect(entry.relayBaseUrls, const <String>['https://relay.example.com']);
      expect(entry.cookieHosts.first, 'relay.example.com');
    });

    test('没有 relay host 时回退到官方 FN Connect 入口', () {
      final entry = FnConnectWebLoginEntry.resolve(
        fnConnectId: 'geqian688',
        relayHosts: const <String>[],
      );

      expect(entry.initialUrl, 'https://5ddd.com/geqian688');
      expect(entry.relayBaseUrls, isEmpty);
      expect(entry.cookieHosts, const <String>['5ddd.com', 'fnos.net']);
    });
  });

  group('FnConnectWebLoginSessionPolicy', () {
    test('默认保留 WebView 登录态，避免每次重新输入 FN 账号密码', () {
      expect(FnConnectWebLoginSessionPolicy.preserveCookiesByDefault, isTrue);
    });
  });

  test('FN 网页桥接只报告页面，不再无签名获取影视配置', () {
    final script = FnWebLoginBridgeScript.build(
      bridgeName: 'FnConnectBridge',
      userName: 'user',
      password: 'password',
      probeFnConnectOauth: true,
      useWindowsWebViewMessage: true,
    );

    expect(script, contains("post({ type: 'cookie' })"));
    expect(script, isNot(contains("fetch('/v/api/v1/sys/config'")));
  });

  testWidgets(
    'NAS 桌面上报后通过带签名配置请求进入影视授权页',
    (tester) async {
      await tester.runAsync(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final baseUrl = 'http://127.0.0.1:${server.port}';
        final requests = <HttpRequest>[];
        server.listen((request) async {
          requests.add(request);
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'code': 0,
              'data': {
                'nas_oauth': {'app_id': 'media-app', 'url': '://'},
              },
            }),
          );
          await request.response.close();
        });
        final previousOverrides = HttpOverrides.current;
        HttpOverrides.global = PrivateNetworkHttpOverrides();
        final messenger = tester.binding.defaultBinaryMessenger;
        const root = MethodChannel('io.jns.webview.win');
        const view = MethodChannel('io.jns.webview.win/1');
        const events = MethodChannel('io.jns.webview.win/1/events');
        final signin = Completer<String>();
        Future<void> emit(String type, Object value) async {
          await messenger.handlePlatformMessage(
            events.name,
            const StandardMethodCodec().encodeSuccessEnvelope({
              'type': type,
              'value': value,
            }),
            (_) {},
          );
        }

        messenger.setMockMethodCallHandler(
          root,
          (call) async => call.method == 'initialize' ? {'textureId': 1} : null,
        );
        messenger.setMockMethodCallHandler(events, (_) async => null);
        messenger.setMockMethodCallHandler(view, (call) async {
          if (call.method == 'loadUrl' && call.arguments == baseUrl) {
            await emit('loadingStateChanged', 2);
          } else if (call.method == 'loadUrl' &&
              call.arguments.toString().startsWith('$baseUrl/signin?')) {
            if (!signin.isCompleted) signin.complete(call.arguments as String);
          }
          return null;
        });
        addTearDown(() async {
          HttpOverrides.global = previousOverrides;
          for (final channel in [root, view, events]) {
            messenger.setMockMethodCallHandler(channel, null);
          }
          await server.close(force: true);
        });
        await tester.pumpWidget(
          const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: FnConnectWebLoginPage(
              fnConnectId: 'test',
              userName: '',
              password: '',
            ),
          ),
        );
        await tester.pump();
        await emit('urlChanged', '$baseUrl/');
        await emit(
          'webMessageReceived',
          jsonEncode({
            'type': 'cookie',
            'pageUrl': '$baseUrl/',
            'cookie': 'mode=relay',
          }),
        );
        final result = await signin.future.timeout(const Duration(seconds: 3));
        expect(requests, hasLength(1));
        expect(requests.single.uri.path, '/v/api/v1/sys/config');
        expect(requests.single.headers.value('authx'), contains('sign='));
        expect(Uri.parse(result).queryParameters['client_id'], 'media-app');
        expect(
          Uri.parse(result).queryParameters['redirect_uri'],
          '$baseUrl/v/oauth/result',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
