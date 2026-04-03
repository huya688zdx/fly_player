import '../api/feiniu_api.dart';
import 'app_exception.dart';

class LoginErrorResolver {
  LoginErrorResolver._();

  static const String genericFailure = '登录失败，请重试';
  static const String invalidServerAddress = '服务器地址格式不正确';
  static const String invalidCredentials = '用户名或密码错误';
  static const String accountDisabled = '账号已被禁用，请联系管理员';
  static const String accountLocked = '登录失败次数过多，请稍后再试';
  static const String networkUnavailable = '无法连接到服务器，请检查地址、端口和网络';
  static const String secureConnectionFailed = 'HTTPS 连接失败，请检查证书配置或改用可访问地址';
  static const String ipv6Unavailable = '当前网络无法访问该 IPv6 地址，请更换网络或使用其他地址';
  static const String serviceUnavailable = '服务器暂时不可用，请稍后重试';
  static const String fnConnectUnreachable =
      'FN Connect 可用地址当前都无法连接，请检查网络环境或改用可直连地址';
  static const String fnConnectUnavailable = 'FN Connect 登录失败，请稍后重试';

  static String resolve(Object error) {
    final raw = _readableMessage(error);
    if (_isFriendlyChinese(raw)) {
      return raw;
    }

    final message = raw.toLowerCase();
    final appError = _extractAppException(error);
    final status = appError?.httpStatus;
    final code = appError?.code;

    if (code == -2 || code == -15 || status == 401 || status == 403) {
      return invalidCredentials;
    }

    if (_containsAny(message, const <String>[
      'password incorrect',
      'incorrect password',
      'wrong password',
      'password error',
      'invalid password',
      'invalid credentials',
      'bad credentials',
      'username or password',
      'user name or password',
      'auth failed',
      'unauthorized',
      'forbidden',
      '401',
      '账号或密码',
      '密码错误',
      '用户名或密码',
      '登录失败，请检查账号密码',
    ])) {
      return invalidCredentials;
    }

    if (_containsAny(message, const <String>[
      'account disabled',
      'user disabled',
      'disabled account',
      '账号禁用',
      '账号已禁用',
      '用户已禁用',
    ])) {
      return accountDisabled;
    }

    if (_containsAny(message, const <String>[
      'account locked',
      'user locked',
      'too many attempts',
      'too many requests',
      'rate limit',
      '登录次数过多',
      '尝试次数过多',
      '账号锁定',
    ])) {
      return accountLocked;
    }

    if (_containsAny(message, const <String>[
      'invalid uri',
      'invalid argument',
      'formatexception',
      'format exception',
      'url format',
      '地址格式',
      'invalid url',
    ])) {
      return invalidServerAddress;
    }

    if (_containsAny(message, const <String>[
      'ssl',
      'certificate',
      'handshake',
      'cert',
      '证书',
      '握手失败',
      '基础连接已经关闭',
      '意外的数据包格式',
      'https',
    ])) {
      return secureConnectionFailed;
    }

    if (message.contains('ipv6') &&
        _containsAny(message, const <String>[
          'network',
          'not available',
          'not supported',
          '无法',
          '不可用',
        ])) {
      return ipv6Unavailable;
    }

    if (_containsAny(message, const <String>[
      'socketexception',
      'connection refused',
      'connection failed',
      'connection aborted',
      'connection reset',
      'network is unreachable',
      'failed host lookup',
      'host lookup',
      'timed out',
      'timeout',
      'network error',
      'socket error',
      'no route to host',
      'connection closed before full header was received',
      '无法连接到远程服务器',
      '积极拒绝',
      '无法连接',
    ])) {
      return networkUnavailable;
    }

    if (status == 404 ||
        _containsAny(message, const <String>[
          'status code of 404',
          '404 not found',
          'api not found',
          'not found',
        ])) {
      return '服务器地址不正确，或接口不存在';
    }

    if ((status != null && status >= 500) ||
        _containsAny(message, const <String>[
          '500',
          '502',
          '503',
          '504',
          'bad gateway',
          'service unavailable',
          'internal server error',
          'gateway timeout',
        ])) {
      return serviceUnavailable;
    }

    if (_containsAny(message, const <String>[
      'none of them were reachable',
      'direct api address',
      'relay-only',
      'web-only',
      'relay access is web-only',
    ])) {
      return fnConnectUnreachable;
    }

    if (message.contains('fn connect')) {
      return fnConnectUnavailable;
    }

    return genericFailure;
  }

  static AppException? _extractAppException(Object error) {
    if (error is FnConnectLoginException) {
      return error.error;
    }
    if (error is AppException) {
      return error;
    }
    return null;
  }

  static String _readableMessage(Object error) {
    if (error is FnConnectLoginException) {
      return error.error.message.trim();
    }
    if (error is AppException) {
      return error.message.trim();
    }
    if (error is String) {
      return error.trim();
    }
    return error.toString().replaceFirst('Exception: ', '').trim();
  }

  static bool _containsAny(String value, List<String> needles) {
    for (final needle in needles) {
      if (value.contains(needle)) {
        return true;
      }
    }
    return false;
  }

  static bool _isFriendlyChinese(String value) {
    if (!_containsChinese(value) || _looksLikeMojibake(value)) {
      return false;
    }
    final lower = value.toLowerCase();
    if (_containsAny(lower, const <String>[
      '握手失败',
      '基础连接已经关闭',
      '无法连接到远程服务器',
      '积极拒绝',
      '超时',
      '证书',
      '连接',
      'network',
      'timeout',
      'ssl',
      'socket',
    ])) {
      return false;
    }
    return true;
  }

  static bool _containsChinese(String value) {
    return RegExp(r'[\u4e00-\u9fff]').hasMatch(value);
  }

  static bool _looksLikeMojibake(String value) {
    if (value.contains('�')) {
      return true;
    }
    var suspiciousHits = 0;
    for (final token in const <String>[
      '锛',
      '鎿',
      '璇',
      '鐧',
      '瀵',
      '鍚',
      '缃',
      '寮',
      '辫',
      '妫',
      '鏌',
      '銆',
      '鍔',
      '濈',
      '鐢',
      '绛',
      '褰',
      '鏈',
      '娌',
      '鍙',
    ]) {
      if (value.contains(token)) {
        suspiciousHits += 1;
        if (suspiciousHits >= 2) {
          return true;
        }
      }
    }
    return false;
  }
}
