import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../media_backend/media_backend_kind.dart';
import '../media_backend/media_backend_registry.dart';
import '../services/login_history_store.dart';
import '../utils/app_confirm_dialog.dart';

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
    final entries = await LoginHistoryStore.remove(entry);
    if (!mounted) return;
    setState(() {
      _entries = entries;
    });
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
    await LoginHistoryStore.clear();
    if (!mounted) return;
    setState(() {
      _entries = const <LoginHistoryEntry>[];
    });
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
///
/// 目前是占位假图：飞牛 / Emby 各一种配色与字母。后续用户提供真实 logo 后，
/// 只需把下面这处 placeholder 换成 `Image.asset('assets/.../xxx.png')` 即可。
class BackendLogo extends StatelessWidget {
  const BackendLogo({super.key, required this.kind, this.size = 40});

  final MediaBackendKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final descriptor = MediaBackendRegistry.descriptorFor(kind);
    final serverFamily = kind.isServerFamily;
    // TODO(logo): 替换为真实 logo 图片资源。
    // return Image.asset(
    //   serverFamily ? 'assets/images/login/server_logo.png'
    //                : 'assets/images/login/feiniu_logo.png',
    //   width: size, height: size,
    // );
    final background = serverFamily
        ? const Color(0xFF1F3A2E)
        : const Color(0xFF1E3354);
    final foreground = serverFamily
        ? const Color(0xFF52C41A)
        : const Color(0xFF6AA7FF);
    final badgeText = descriptor?.badgeText ?? 'FN';
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: foreground.withValues(alpha: 0.32)),
      ),
      child: Text(
        badgeText,
        style: TextStyle(
          color: foreground,
          fontSize: serverFamily ? 18 : 15,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
