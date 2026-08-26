import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../media_backend/media_backend_kind.dart';
import '../media_backend/media_backend_registry.dart';
import '../services/login_history_store.dart';
import '../theme/app_theme.dart';
import '../utils/app_confirm_dialog.dart';
import '../utils/app_top_tip.dart';
import '../utils/swallowed_error_logger.dart';

/// 统一的登录历史页面：飞牛与 Emby 历史共用一个列表，每行用后端 logo 区分。
///
/// 点击某条记录 → `Navigator.pop(entry)` 回传给登录页用于回填表单并切换后端。
class LoginHistoryScreen extends StatefulWidget {
  const LoginHistoryScreen({super.key, required this.entries});

  final List<LoginHistoryEntry> entries;

  @override
  State<LoginHistoryScreen> createState() => _LoginHistoryScreenState();
}

class _LoginHistoryScreenState extends State<LoginHistoryScreen> {
  late List<LoginHistoryEntry> _entries = List.of(widget.entries);

  Future<void> _delete(LoginHistoryEntry entry) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showAppConfirmDialog(
      context,
      title: l10n.connectionDeleteHistoryConfirmTitle,
      content: l10n.connectionDeleteHistoryConfirmContent,
      cancelText: l10n.commonCancel,
      confirmText: l10n.commonDelete,
    );
    if (!confirmed) return;
    try {
      final entries = await LoginHistoryStore.remove(entry);
      if (!mounted) return;
      setState(() {
        _entries = entries;
      });
    } catch (error, stackTrace) {
      _reportPersistFailure(
        action: 'delete login history entry',
        error: error,
        stackTrace: stackTrace,
        l10n: l10n,
      );
    }
  }

  Future<void> _clear() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showAppConfirmDialog(
      context,
      title: l10n.connectionClearHistoryConfirmTitle,
      content: l10n.connectionClearHistoryConfirmContent,
      cancelText: l10n.commonCancel,
      confirmText: l10n.commonClear,
    );
    if (!confirmed) return;
    try {
      await LoginHistoryStore.clear();
      if (!mounted) return;
      setState(() {
        _entries = const <LoginHistoryEntry>[];
      });
    } catch (error, stackTrace) {
      _reportPersistFailure(
        action: 'clear login history',
        error: error,
        stackTrace: stackTrace,
        l10n: l10n,
      );
    }
  }

  /// 持久化操作（删除/清空登录历史）可能因安全存储不可用而抛异常，
  /// 此时保留原列表状态，仅记录日志并向用户提示失败，避免界面显示与实际存储脱节。
  /// 日志写入是 best-effort，不得阻塞用户提示。
  void _reportPersistFailure({
    required String action,
    required Object error,
    required StackTrace stackTrace,
    required AppLocalizations l10n,
  }) {
    unawaited(
      logSwallowedError(action: action, error: error, stackTrace: stackTrace),
    );
    if (!mounted) return;
    AppTopTip().show(
      context,
      message: l10n.commonOperationFailedRetryLater,
      color: context.appColors.danger,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF08111A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C1825),
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(
          l10n.connectionLoginHistory,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          if (_entries.isNotEmpty)
            TextButton(
              onPressed: _clear,
              child: Text(
                l10n.connectionClear,
                style: const TextStyle(color: Color(0xFF8FB7FF)),
              ),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _entries.isEmpty
            ? Center(
                child: Text(
                  l10n.connectionNoLoginHistory,
                  style: const TextStyle(
                    color: Color(0xFF9EADBE),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                itemCount: _entries.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final entry = _entries[index];
                  return _LoginHistoryTile(
                    entry: entry,
                    onTap: () => Navigator.of(context).pop(entry),
                    onDelete: () => _delete(entry),
                  );
                },
              ),
      ),
    );
  }
}

class _LoginHistoryTile extends StatelessWidget {
  const _LoginHistoryTile({
    required this.entry,
    required this.onTap,
    required this.onDelete,
  });

  final LoginHistoryEntry entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final descriptor = MediaBackendRegistry.descriptorFor(entry.kind);
    final backendName = descriptor?.displayName ?? l10n.connectionFeiniuNas;
    final subtitle = entry.userName.isEmpty
        ? backendName
        : (descriptor == null
              ? entry.userName
              : '${entry.userName} · $backendName');
    return Material(
      color: const Color(0xFF232D3A),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              BackendLogo(kind: entry.kind),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.baseUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF9EADBE),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFF7C8DA5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 历史行首的后端 logo。
class BackendLogo extends StatelessWidget {
  const BackendLogo({super.key, required this.kind, this.size = 40});

  final MediaBackendKind kind;
  final double size;

  String get _assetName => kind.isServerFamily
      ? MediaBackendRegistry.requireDescriptor(kind).logoAsset
      : 'lib/img/feiniu_Logo.png';

  String get _semanticLabel => kind.isServerFamily
      ? MediaBackendRegistry.requireDescriptor(kind).displayName
      : '飞牛影视';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _semanticLabel,
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.asset(
          _assetName,
          key: ValueKey<String>('backend_logo_${kind.name}'),
          width: size,
          height: size,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
