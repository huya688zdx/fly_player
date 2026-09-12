import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/services/play_stats/play_stats_database.dart';
// The sqflite global factory setter checks this concrete internal interface.
// ignore: implementation_imports, depend_on_referenced_packages
import 'package:sqflite_common/src/factory.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test(
    'scope switch during asynchronous open closes old handle and returns current database',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'fly_scope_open_',
      );
      final original = databaseFactoryFfi;
      await original.setDatabasesPath(directory.path);
      final delayed = _DelayedFactory(original);
      databaseFactory = delayed;
      final database = SqflitePlayStatsDatabase();
      Database? current;
      try {
        await database.bindOwnerScope('scope-a');
        final pending = database.rawDatabase;
        await delayed.entered.future;
        await database.bindOwnerScope('scope-b');
        delayed.resume.complete();
        final returned = await pending;
        current = await database.rawDatabase;
        expect(current.path, endsWith('play_stats_scope_b.db'));
        expect(identical(returned, current), isTrue);
        expect(delayed.oldHandle!.isOpen, isFalse);
      } finally {
        await current?.close();
        databaseFactory = original;
        await directory.delete(recursive: true);
      }
    },
  );
}

class _DelayedFactory implements SqfliteDatabaseFactory {
  _DelayedFactory(this.delegate);
  final DatabaseFactory delegate;
  final entered = Completer<void>();
  final resume = Completer<void>();
  Database? oldHandle;
  @override
  Future<String> getDatabasesPath() => delegate.getDatabasesPath();
  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async {
    if (path.endsWith('play_stats_scope_a.db')) {
      entered.complete();
      await resume.future;
      return oldHandle = await delegate.openDatabase(path, options: options);
    }
    return delegate.openDatabase(path, options: options);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
