import 'dart:async';

import 'package:flutter/foundation.dart';

import '../media_backend/media_backend_kind.dart';
import '../media_backend/session/media_backend_connection.dart';
import '../services/media_backend_connection_store.dart';

class BackendSessionProvider extends ChangeNotifier {
  BackendSessionProvider({bool autoLoad = true}) {
    if (autoLoad) {
      unawaited(load());
    }
  }

  MediaBackendConnectionSnapshot? _snapshot;
  bool _isReady = false;

  bool get isReady => _isReady;
  MediaBackendKind get currentKind =>
      _snapshot?.activeKind ?? MediaBackendKind.feiniu;
  MediaBackendConnection? get currentConnection => _snapshot?.activeConnection;
  bool get isConfigured => currentConnection?.isAuthenticated ?? false;

  Future<void> load() async {
    _snapshot = await MediaBackendConnectionStore.load();
    _isReady = true;
    notifyListeners();
  }

  Future<void> saveActive(MediaBackendConnection connection) async {
    await MediaBackendConnectionStore.saveActive(connection);
    _snapshot = await MediaBackendConnectionStore.load();
    _isReady = true;
    notifyListeners();
  }
}
