import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 在任何数据库访问前初始化 Windows/Linux 的 SQLite，并使用应用数据目录。
Future<void> initializeSqliteRuntime() async {
  if (!Platform.isWindows && !Platform.isLinux) return;
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final support = await getApplicationSupportDirectory();
  await databaseFactory.setDatabasesPath(p.join(support.path, 'databases'));
}
