import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueNotifier;

import '../play_stats/fly_sync_identity.dart';
import '../play_stats/play_stats_database.dart';
import '../play_stats/play_stats_service.dart';
import '../secure_credential_store.dart';
import 'fly_data_api.dart';
import 'fly_data_sync_store.dart';
import 'fly_login_history_store.dart';

class FlyDataSession {
  FlyDataSession({
    required this.serverUrl,
    required this.userId,
    required this.username,
    required this.deviceId,
    required this.deviceName,
    required this.token,
    required this.installationId,
    this.serviceInstanceId = '',
    this.role = 'user',
    this.addresses = const [],
    this.fnEntryToken = '',
  });
  final String serverUrl,
      userId,
      username,
      deviceId,
      deviceName,
      token,
      installationId;
  final String serviceInstanceId;
  final String role;
  final List<String> addresses;
  final String fnEntryToken;
  // 从捕获的会话创建客户端，避免并发切换账号时读取别的入口令牌。
  FlyDataApi createApi({
    int? maxResponseBytes,
    Duration receiveTimeout = const Duration(seconds: 60),
  }) => FlyDataApi(
    serverUrl,
    token: token,
    fnEntryToken: fnEntryToken,
    maxResponseBytes: maxResponseBytes,
    receiveTimeout: receiveTimeout,
  );
  String get accountKey =>
      '${serviceInstanceId.isEmpty ? serverUrl : serviceInstanceId}|$userId';
  String get deviceKey => '$installationId:$deviceId';
  Map<String, dynamic> toJson() => {
    'server_url': serverUrl,
    'user_id': userId,
    'username': username,
    'device_id': deviceId,
    'device_name': deviceName,
    'token': token,
    'installation_id': installationId,
    'service_instance_id': serviceInstanceId,
    'role': role,
    'addresses': addresses,
    'fn_entry_token': fnEntryToken,
  };
  factory FlyDataSession.fromJson(Map<String, dynamic> row) => FlyDataSession(
    serverUrl: row['server_url'] as String,
    userId: row['user_id'] as String,
    username: row['username'] as String,
    deviceId: row['device_id'] as String,
    deviceName: row['device_name'] as String,
    token: row['token'] as String,
    installationId: row['installation_id'] as String,
    serviceInstanceId: row['service_instance_id'] as String? ?? '',
    role: row['role'] as String? ?? 'user',
    addresses: (row['addresses'] as List? ?? []).cast<String>(),
    fnEntryToken: row['fn_entry_token'] as String? ?? '',
  );
}

/// Independent data account. No NAS auth, player heartbeats or media requests.
class FlyDataService {
  FlyDataService({required this.database, required this.drainWrites});
  static final instance = FlyDataService(
    database: PlayStatsService.instance.database,
    drainWrites: PlayStatsService.instance.drainForManualSync,
  );
  static const _sessionKey = 'fly_data_service_session_v1';
  static const _installationKey = 'fly_data_service_installation_v1';
  final PlayStatsDatabase database;
  final Future<void> Function() drainWrites;
  FlyDataSession? _session;
  final ValueNotifier<String> accountChanges = ValueNotifier('');
  FlyDataSession? get session => _session;
  set session(FlyDataSession? value) {
    _session = value;
    accountChanges.value = value == null
        ? ''
        : '${value.accountKey}|${value.deviceKey}|${value.serverUrl}';
  }

  /// Authentication can succeed even when optional history storage fails.
  String? loginHistoryWarning;
  bool _busy = false;
  FlyDataSyncStore get store => FlyDataSyncStore(database);
  String get currentScope => database is SqflitePlayStatsDatabase
      ? (database as SqflitePlayStatsDatabase).ownerScope
      : '';
  String get _scopeToken =>
      '$currentScope:${database is SqflitePlayStatsDatabase ? (database as SqflitePlayStatsDatabase).scopeGeneration : 0}';
  String get scopeIdentity => _scopeToken;

  Future<void> restoreSession() async {
    final result = await SecureCredentialStore.read(_sessionKey);
    if (result.isUnavailable) {
      throw const SecureCredentialUnavailableException(_sessionKey);
    }
    if (result.status == SecureCredentialReadStatus.value) {
      final restored = FlyDataSession.fromJson(
        Map<String, dynamic>.from(jsonDecode(result.value) as Map),
      );
      final install = await SecureCredentialStore.read(_installationKey);
      if (install.isUnavailable || install.value != restored.installationId) {
        throw StateError('此设备无法验证保存的登录身份，请重新登录数据服务。');
      }
      session = restored;
    }
  }

  Future<void> login({
    required String serverUrl,
    required String username,
    required String password,
    required String deviceName,
    bool rememberPassword = true,
    String? expectedInstanceId,
    String fnEntryToken = '',
  }) => _exclusive(() async {
    loginHistoryWarning = null;
    final url = normalizeServerUrl(serverUrl);
    var install = await SecureCredentialStore.read(_installationKey);
    if (install.isUnavailable) {
      throw const SecureCredentialUnavailableException(_installationKey);
    }
    if (install.status == SecureCredentialReadStatus.missing) {
      await SecureCredentialStore.write(_installationKey, newFlySyncId());
      install = await SecureCredentialStore.read(_installationKey);
    }
    final api = FlyDataApi(url, fnEntryToken: fnEntryToken);
    try {
      final identity = await api.get('/system/identity');
      final instanceId = identity['service_instance_id'] as String? ?? '';
      if (instanceId.isEmpty) throw StateError('此地址不是支持统一账号的飞翔服务。');
      if (expectedInstanceId != null && instanceId != expectedInstanceId) {
        throw StateError('该地址的飞翔服务身份已改变，未发送密码。');
      }
      final response = await api.post('/auth/login', {
        'username': username.trim(),
        'password': password,
        'device_name': deviceName.trim(),
        'platform': Platform.operatingSystem,
        'installation_id': install.value,
        'client': 'fly',
      });
      final user = response['user'] as Map;
      final device = response['device'] as Map;
      if (response['service_instance_id'] != instanceId) {
        throw StateError('登录期间服务实例已改变，请核对地址。');
      }
      final next = FlyDataSession(
        serverUrl: url,
        userId: user['id'] as String,
        username: user['username'] as String,
        deviceId: device['id'] as String,
        deviceName: device['name'] as String,
        token: response['access_token'] as String,
        installationId: install.value,
        serviceInstanceId: response['service_instance_id'] as String? ?? '',
        role: user['role'] as String? ?? 'user',
        addresses: [url],
        fnEntryToken: isFlyFnApplicationUrl(url) ? fnEntryToken : '',
      );
      await drainWrites();
      await _migrateAccountOwner('$url|${next.userId}', next.accountKey);
      await SecureCredentialStore.write(_sessionKey, jsonEncode(next.toJson()));
      session = next;
      try {
        await FlyLoginHistoryStore.save(
          _loginHistoryEntry(
            next,
            rememberPassword: rememberPassword,
            password: password,
          ),
        );
      } catch (_) {
        loginHistoryWarning = '已登录，登录记录或记住密码未能保存。';
      }
    } finally {
      api.close();
    }
  });

  FlyLoginHistoryEntry _loginHistoryEntry(
    FlyDataSession current, {
    bool rememberPassword = false,
    String password = '',
  }) => FlyLoginHistoryEntry(
    serverUrl: current.serverUrl,
    username: current.username,
    deviceName: current.deviceName,
    serviceInstanceId: current.serviceInstanceId,
    updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
    rememberPassword: rememberPassword,
    password: rememberPassword ? password : '',
  );

  Future<void> _migrateAccountOwner(String previousKey, String nextKey) async {
    if (previousKey == nextKey) return;
    await database.transaction((txn) async {
      final old = await txn.query(
        'fly_sync_state',
        where: 'account_key = ?',
        whereArgs: [previousKey],
      );
      final collision = await txn.query(
        'fly_sync_state',
        where: 'account_key = ?',
        whereArgs: [nextKey],
      );
      if (old.isNotEmpty && collision.isNotEmpty) {
        throw StateError('旧账号与统一账号都有同步状态，请先核对待重试记录。');
      }
      await txn.update(
        'fly_sync_state',
        {'account_key': nextKey},
        where: 'account_key = ?',
        whereArgs: [previousKey],
      );
      await txn.update(
        'fly_datasets',
        {'confirmed_account': nextKey},
        where: 'confirmed_account = ?',
        whereArgs: [previousKey],
      );
    });
  }

  Future<void> _migrateKnownAliases(FlyDataSession current) async {
    if (current.serviceInstanceId.isEmpty) return;
    for (final address in {...current.addresses, current.serverUrl}) {
      await _migrateAccountOwner(
        '$address|${current.userId}',
        current.accountKey,
      );
    }
  }

  /// Probe with no bearer first. Aliases of one service share account identity.
  Future<void> switchAddress(String value) => _switchAddress(value);

  Future<void> renewFnAccess(String entryToken) =>
      _switchAddress(_requireSession().serverUrl, fnEntryToken: entryToken);

  Future<void> _switchAddress(
    String value, {
    String? fnEntryToken,
  }) => _exclusive(() async {
    final previous = _requireSession();
    final url = normalizeServerUrl(value);
    final entryToken = isFlyFnApplicationUrl(url)
        ? fnEntryToken ??
              (url == previous.serverUrl ? previous.fnEntryToken : '')
        : '';
    final probe = FlyDataApi(url, fnEntryToken: entryToken);
    late final String instanceId;
    try {
      instanceId =
          (await probe.get('/system/identity'))['service_instance_id']
              as String? ??
          '';
    } finally {
      probe.close();
    }
    if (instanceId.isEmpty ||
        (previous.serviceInstanceId.isNotEmpty &&
            instanceId != previous.serviceInstanceId)) {
      throw StateError('该地址属于另一个飞翔实例，未发送已保存的令牌。');
    }
    if (previous.serviceInstanceId.isEmpty && url != previous.serverUrl) {
      throw StateError('请先通过旧登录地址核验并迁移账号，再添加新地址。');
    }
    final api = FlyDataApi(
      url,
      token: previous.token,
      fnEntryToken: entryToken,
    );
    try {
      final me = await api.get('/me');
      if (me['service_instance_id'] != instanceId ||
          (me['user'] as Map)['id'] != previous.userId) {
        throw StateError('地址的账号身份不一致。');
      }
    } finally {
      api.close();
    }
    // Background verification of the current address must not invalidate
    // in-flight reads. The account and token are unchanged, and /me has still
    // verified them; only a changed address, instance or address set needs saving.
    if (previous.serverUrl == url &&
        previous.fnEntryToken == entryToken &&
        previous.serviceInstanceId == instanceId &&
        previous.addresses.contains(url)) {
      return;
    }
    final next = FlyDataSession.fromJson({
      ...previous.toJson(),
      'server_url': url,
      'fn_entry_token': entryToken,
      'service_instance_id': instanceId,
      'addresses': {...previous.addresses, previous.serverUrl, url}.toList(),
    });
    if (previous.accountKey != next.accountKey) {
      await drainWrites();
      await database.transaction((txn) async {
        final collision = await txn.query(
          'fly_sync_state',
          where: 'account_key = ?',
          whereArgs: [next.accountKey],
        );
        final old = await txn.query(
          'fly_sync_state',
          where: 'account_key = ?',
          whereArgs: [previous.accountKey],
        );
        if (collision.isNotEmpty && old.isNotEmpty) {
          throw StateError('旧账号与新账号都有同步状态，需要先处理待重试记录。');
        }
        // Rename only local owner keys; pending JSON and all fact IDs stay intact.
        await txn.update(
          'fly_sync_state',
          {'account_key': next.accountKey},
          where: 'account_key = ?',
          whereArgs: [previous.accountKey],
        );
        await txn.update(
          'fly_datasets',
          {'confirmed_account': next.accountKey},
          where: 'confirmed_account = ?',
          whereArgs: [previous.accountKey],
        );
      });
    }
    await SecureCredentialStore.write(_sessionKey, jsonEncode(next.toJson()));
    session = next;
    try {
      await FlyLoginHistoryStore.updateAddress(
        _loginHistoryEntry(previous),
        _loginHistoryEntry(next),
      );
      loginHistoryWarning = null;
    } catch (_) {
      loginHistoryWarning = '地址已切换，登录记录未能更新。';
    }
  });

  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    bool patch = false,
  }) async {
    final current = _requireSession();
    if (current.serviceInstanceId.isEmpty) {
      throw StateError('请先核验旧服务地址完成统一账号迁移。');
    }
    final api = current.createApi();
    try {
      final result = body == null
          ? await api.get(path, query: query)
          : patch
          ? await api.patch(path, body)
          : await api.post(path, body);
      if (!identical(session, current)) throw StateError('账号或服务地址已改变，请重新操作。');
      return result;
    } finally {
      api.close();
    }
  }

  Future<Uint8List> imageBytes(String mediaId) async {
    final current = _requireSession();
    if (current.serviceInstanceId.isEmpty) throw StateError('请先核验飞翔服务实例。');
    final api = current.createApi();
    try {
      final bytes = await api.imageBytes(mediaId);
      if (!identical(current, session)) throw StateError('账号已改变。');
      return bytes;
    } finally {
      api.close();
    }
  }

  Future<void> syncStoredBinding(String bindingId) => _exclusive(() async {
    final current = _requireSession();
    final scope = PlayStatsService.scopeForBinding(
      current.accountKey,
      bindingId,
    );
    if (scope == currentScope) return;
    final closed = SqflitePlayStatsDatabase(createWriteEpoch: false);
    await closed.bindOwnerScope(scope);
    if (!await closed.exists) return;
    try {
      final db = await closed.rawDatabase;
      final owned = await db.query(
        'fly_datasets',
        where: 'confirmed_account=?',
        whereArgs: [current.accountKey],
        limit: 1,
      );
      if (owned.isEmpty || !identical(current, session)) return;
      final uploader = FlyDataService(
        database: closed,
        drainWrites: () async {},
      )..session = current;
      await uploader.syncNow();
    } finally {
      await closed.bindOwnerScope('');
    }
  });

  Future<void> logout() => _exclusive(() async {
    final current = session;
    try {
      if (current != null) {
        final api = current.createApi();
        try {
          await api.post('/auth/logout', <String, dynamic>{});
        } finally {
          api.close();
        }
      }
    } finally {
      try {
        await SecureCredentialStore.delete(_sessionKey);
      } finally {
        session = null;
      }
    }
  });

  Future<List<Map<String, dynamic>>> remoteDatasets() async {
    final current = _requireSession();
    final api = current.createApi();
    try {
      final response = await api.get('/sync/datasets');
      return (response['items'] as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
    } finally {
      api.close();
    }
  }

  Future<int> adopt(Map<String, dynamic> dataset) => _exclusive(() async {
    final current = _requireSession();
    final scope = _scopeToken;
    final api = current.createApi();
    try {
      final rows = await _history(api, dataset['id'] as String, details: true);
      final identities = await _identities(api, dataset['id'] as String);
      rows.addAll(identities.where((row) => row['tombstoned'] == true));
      await drainWrites();
      await _migrateKnownAliases(current);
      _checkScope(scope);
      final scoped = FlyDataSyncStore.fromDatabase(
        await database.rawDatabase,
        ownerScope: currentScope,
      );
      _checkScope(scope);
      return await scoped.adoptDataset(current.accountKey, dataset, rows);
    } finally {
      api.close();
    }
  });

  /// UI requires an explicit checkbox first. Check all server datasets for
  /// overlapping IDs before accepting a claim that the old history is new.
  Future<void> confirmCurrentScope() => _exclusive(() async {
    final current = _requireSession();
    final scope = _scopeToken;
    await drainWrites();
    await _migrateKnownAliases(current);
    _checkScope(scope);
    final scoped = FlyDataSyncStore.fromDatabase(
      await database.rawDatabase,
      ownerScope: currentScope,
    );
    _checkScope(scope);
    final ids = await scoped.unlinkedRecordIds(current.accountKey);
    final api = current.createApi();
    try {
      final datasets = await api.get('/sync/datasets');
      for (final dataset in datasets['items'] as List) {
        final rows = await _identities(api, dataset['id'] as String);
        if (rows.any((row) => ids.contains(row['origin_record_id']))) {
          throw StateError(
            '服务器数据集「${dataset['label']}」已有相同历史 ID。请先选择它并关联，避免重复统计。',
          );
        }
      }
      _checkScope(scope);
      await scoped.confirmUnlinked(current.accountKey);
    } finally {
      api.close();
    }
  });

  Future<Map<String, dynamic>> syncNow() => _exclusive(() async {
    final current = _requireSession();
    final scope = _scopeToken;
    await drainWrites();
    await _migrateKnownAliases(current);
    _checkScope(scope);
    final scoped = FlyDataSyncStore.fromDatabase(
      await database.rawDatabase,
      ownerScope: currentScope,
    );
    _checkScope(scope);
    final api = current.createApi();
    try {
      final old = await scoped.state(current.accountKey);
      String streamId;
      if (old != null && old['installation_id'] == current.deviceKey) {
        streamId = old['stream_id'] as String;
      } else {
        if (old?['pending_json'] != null) {
          throw StateError('恢复的待重试快照属于其他设备，请在原设备完成重试。');
        }
        streamId =
            (await api.post('/sync/streams', {'id': newFlySyncId()}))['id']
                as String;
      }
      _checkScope(scope);
      // This creates and durably stores the complete packet in one transaction.
      // No HTTP call is made while that transaction is open.
      final packet = await scoped.preparePacket(
        accountKey: current.accountKey,
        installationId: current.deviceKey,
        streamId: streamId,
      );
      final decoded = jsonDecode(packet) as Map;
      final local = await (await scoped.database.rawDatabase).query(
        'fly_datasets',
      );
      final remote = await api.get('/sync/datasets');
      final registered = {for (final row in remote['items'] as List) row['id']};
      for (final manifest in decoded['manifest']['datasets'] as List) {
        final retired = (remote['items'] as List).any(
          (row) => row['id'] == manifest['id'] && row['status'] == 'retired',
        );
        if (retired) {
          throw StateError('快照包含服务端已退役的来源，删除屏障已阻止上传。请在网页核对该来源，不能改成新来源重新上传。');
        }
        if (registered.contains(manifest['id'])) continue;
        final row = local.firstWhere((row) => row['id'] == manifest['id']);
        await api.post('/sync/datasets', {
          'id': row['id'],
          'label': row['label'],
          'origin_kind': row['origin_kind'],
          'source_schema_version': row['source_schema_version'],
        });
      }
      _checkScope(scope);
      final receipt = await api.post('/sync/batches', packet);
      _checkScope(scope);
      await scoped.acceptReceipt(current.accountKey, receipt);
      return receipt;
    } finally {
      api.close();
    }
  });

  Future<List<Map<String, dynamic>>> _history(
    FlyDataApi api,
    String datasetId, {
    bool details = false,
  }) async {
    final rows = <Map<String, dynamic>>[];
    String? cursor;
    do {
      final page = await api.get(
        '/history',
        query: {
          'dataset_id': datasetId,
          'limit': 200,
          if (cursor != null) 'cursor': cursor,
        },
      );
      for (final item in page['items'] as List) {
        rows.add(
          details
              ? await api.get('/history/${item['id']}')
              : Map<String, dynamic>.from(item as Map),
        );
      }
      cursor = page['next_cursor'] as String?;
    } while (cursor != null);
    return rows;
  }

  Future<List<Map<String, dynamic>>> _identities(
    FlyDataApi api,
    String datasetId,
  ) async {
    final rows = <Map<String, dynamic>>[];
    String? cursor;
    do {
      final page = await api.get(
        '/sync/datasets/$datasetId/identities',
        query: {'limit': 200, if (cursor != null) 'cursor': cursor},
      );
      rows.addAll(
        (page['items'] as List).map(
          (row) => Map<String, dynamic>.from(row as Map),
        ),
      );
      cursor = page['next_cursor'] as String?;
    } while (cursor != null);
    return rows;
  }

  FlyDataSession _requireSession() =>
      session ?? (throw StateError('请先登录飞翔数据服务。'));
  void _checkScope(String expected) {
    if (_scopeToken != expected) throw StateError('媒体帐号范围已改变，请重新打开同步页面。');
  }

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    if (_busy) throw StateError('另一项数据服务操作正在进行。');
    _busy = true;
    try {
      return await action();
    } finally {
      _busy = false;
    }
  }
}
