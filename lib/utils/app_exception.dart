import 'package:dio/dio.dart';

enum AppExceptionKind { noData, unauthorized, transient, fatal }

class AppException implements Exception {
  final AppExceptionKind kind;
  final String action;
  final String message;
  final int? code;
  final int? httpStatus;
  final Object? cause;
  final StackTrace? stackTrace;

  const AppException({
    required this.kind,
    required this.action,
    required this.message,
    this.code,
    this.httpStatus,
    this.cause,
    this.stackTrace,
  });

  factory AppException.from(
    Object error, {
    required String action,
    AppExceptionKind fallbackKind = AppExceptionKind.fatal,
  }) {
    if (error is AppException) return error;
    if (error is DioException) {
      return AppException.fromDio(error, action: action);
    }
    final text = error.toString();
    return AppException(
      kind: _kindFromMessage(text, fallback: fallbackKind),
      action: action,
      message: text,
      cause: error,
    );
  }

  factory AppException.fromDio(
    DioException error, {
    required String action,
    AppExceptionKind fallbackKind = AppExceptionKind.transient,
  }) {
    final status = error.response?.statusCode;
    final message = _messageFromDio(error);
    return AppException(
      kind: _kindFromHttpStatus(status, fallback: fallbackKind),
      action: action,
      message: message,
      httpStatus: status,
      cause: error,
      stackTrace: error.stackTrace,
    );
  }

  factory AppException.api({
    required String action,
    required String message,
    int? code,
    int? httpStatus,
    Object? cause,
    StackTrace? stackTrace,
  }) {
    return AppException(
      kind: _kindFromApi(code: code, httpStatus: httpStatus, message: message),
      action: action,
      message: message,
      code: code,
      httpStatus: httpStatus,
      cause: cause,
      stackTrace: stackTrace,
    );
  }

  bool get isNoData => kind == AppExceptionKind.noData;
  bool get isUnauthorized => kind == AppExceptionKind.unauthorized;
  bool get isTransient => kind == AppExceptionKind.transient;
  bool get isFatal => kind == AppExceptionKind.fatal;

  @override
  String toString() {
    return 'AppException(kind: $kind, action: $action, code: $code, '
        'httpStatus: $httpStatus, message: $message)';
  }

  static String _messageFromDio(DioException error) {
    final responseData = error.response?.data;
    if (responseData is Map<String, dynamic>) {
      final backendMessage = responseData['message'] ?? responseData['msg'];
      if (backendMessage != null && '$backendMessage'.trim().isNotEmpty) {
        return '$backendMessage';
      }
    }
    return error.message ?? error.error?.toString() ?? 'Request failed';
  }

  static AppExceptionKind _kindFromApi({
    int? code,
    int? httpStatus,
    required String message,
  }) {
    if (code == -6 || httpStatus == 404) {
      return AppExceptionKind.noData;
    }
    if (code == -2 || httpStatus == 401 || httpStatus == 403) {
      return AppExceptionKind.unauthorized;
    }
    if (httpStatus != null && httpStatus >= 500) {
      return AppExceptionKind.transient;
    }
    return _kindFromMessage(message, fallback: AppExceptionKind.fatal);
  }

  static AppExceptionKind _kindFromHttpStatus(
    int? httpStatus, {
    required AppExceptionKind fallback,
  }) {
    if (httpStatus == 401 || httpStatus == 403) {
      return AppExceptionKind.unauthorized;
    }
    if (httpStatus == 404) {
      return AppExceptionKind.noData;
    }
    if (httpStatus != null && httpStatus >= 500) {
      return AppExceptionKind.transient;
    }
    return fallback;
  }

  static AppExceptionKind _kindFromMessage(
    String message, {
    required AppExceptionKind fallback,
  }) {
    final text = message.toLowerCase();
    if (text.contains('not found') ||
        text.contains('code=-6') ||
        text.contains('library not exist') ||
        text.contains('no data')) {
      return AppExceptionKind.noData;
    }
    if (text.contains('auth failed') ||
        text.contains('unauthorized') ||
        text.contains('forbidden') ||
        text.contains('401')) {
      return AppExceptionKind.unauthorized;
    }
    if (text.contains('timeout') ||
        text.contains('socket') ||
        text.contains('connection') ||
        text.contains('network')) {
      return AppExceptionKind.transient;
    }
    return fallback;
  }
}
