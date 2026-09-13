import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/services/fly_data/fly_data_api.dart';

void main() {
  test('限长流式 NAS 请求保留安全错误码，拒绝超长错误体', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final api = FlyDataApi(
      'http://127.0.0.1:${server.port}',
      maxResponseBytes: 64,
    );
    server.listen((request) async {
      request.response.statusCode = HttpStatus.notFound;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'error': {
            'code': 'NOT_FOUND',
            'message': request.uri.path.endsWith('/large')
                ? 'x' * 20000
                : 'private detail',
          },
        }),
      );
      await request.response.close();
    });
    try {
      await expectLater(
        api.get('/missing'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'safe code',
            '数据服务拒绝请求：NOT_FOUND',
          ),
        ),
      );
      await expectLater(
        api.get('/large'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'safe generic message',
            '数据服务连接失败，请检查地址和网络后手动重试。',
          ),
        ),
      );
    } finally {
      api.close();
      await server.close(force: true);
    }
  });

  test('限长 JSON 接口接受正常响应，拒绝分块超限与其他格式', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final api = FlyDataApi(
      'http://127.0.0.1:${server.port}',
      maxResponseBytes: 64,
    );
    server.listen((request) async {
      request.response.headers.contentType = request.uri.path.endsWith('/html')
          ? ContentType.html
          : ContentType.json;
      request.response.headers.chunkedTransferEncoding = true;
      request.response.write(
        jsonEncode({
          'value': request.uri.path.endsWith('/large') ? 'x' * 256 : 'ok',
        }),
      );
      await request.response.close();
    });
    try {
      expect(await api.get('/normal'), {'value': 'ok'});
      await expectLater(api.get('/large'), throwsStateError);
      await expectLater(api.get('/html'), throwsStateError);
    } finally {
      api.close();
      await server.close(force: true);
    }
  });
}
