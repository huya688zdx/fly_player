import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../playback/playback_host.dart';
import '../../playback/playback_source.dart';
import '../../providers/media_backend_provider.dart';
import '../../providers/nas_provider.dart';
import '../../services/native_reentry_support.dart';
import '../../theme/app_theme.dart';
import '../desktop_floating_panel.dart';

/// 一次用户点击的所有异步准备共用此凭据，取消后不可再次启动。
class DesktopPlaybackLaunchRequest {
  DesktopPlaybackLaunchRequest(this.context, this.title)
    : scope = playbackSessionScope(context);

  final BuildContext context;
  final String title;
  final String scope;
  bool cancelled = false;
  MpvMediaSource? pendingSource;
  Future<void> Function()? onCancel;
  OverlayEntry? _entry;
  Future<void>? _cancellation;

  bool get isCurrent =>
      !cancelled && context.mounted && playbackSessionScope(context) == scope;

  Future<void> cancel() {
    if (cancelled) return _cancellation ?? Future<void>.value();
    cancelled = true;
    _entry?.markNeedsBuild();
    return _cancellation = Future<void>.sync(() async {
      try {
        await onCancel?.call();
      } catch (error) {
        // 启动流程仍会检查取消状态并在 finally 中继续清理。
        debugPrint('取消起播时播放器退出失败：$error');
      }
    });
  }

  void _show(BuildContext anchor) {
    if (!anchor.mounted || _entry != null) return;
    final overlay = Overlay.maybeOf(anchor, rootOverlay: true);
    if (overlay == null) return;
    _entry = OverlayEntry(
      builder: (context) {
        final colors = context.appColors;
        final size = MediaQuery.sizeOf(context);
        return Positioned(
          top: size.height < 240 ? 4 : MediaQuery.paddingOf(context).top + 64,
          left: 12,
          right: 12,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: DesktopFloatingPanel(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.accent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          cancelled ? '正在取消，等待清理…' : '正在准备：$title',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: cancelled ? null : () => unawaited(cancel()),
                        child: const Text('取消加载'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_entry!);
  }

  void _hide() {
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }
}

/// 从解析片源前占用到启动或取消清理结束；重复点击不排队。
class DesktopPlaybackLaunchGuard {
  static DesktopPlaybackLaunchRequest? _active;

  static Future<T?> run<T>(
    BuildContext context, {
    required String title,
    required Future<T?> Function(DesktopPlaybackLaunchRequest request) action,
    required bool Function(String scope, String playLink) sourceInUse,
  }) async {
    if (!context.mounted) return null;
    final active = _active;
    if (active != null) {
      active._show(context);
      return null;
    }
    final request = DesktopPlaybackLaunchRequest(
      context,
      title.trim().isEmpty ? '所选影片' : title,
    );
    // 在 await 之前保存账号引用，页面退出后仍能释放迟到的片源。
    final nas = context.read<NasProvider>();
    final provider = context.read<MediaBackendProvider>();
    final legacy = provider.backend.capabilities.usesLegacyFeiniuFlow;
    final nasUrl = nas.baseUrl;
    final nasUser = nas.userName;
    final kind = provider.sessionProvider?.currentKind;
    final connection = provider.sessionProvider?.currentConnection;
    bool accountIsCurrent() =>
        nas.baseUrl == nasUrl &&
        nas.userName == nasUser &&
        provider.sessionProvider?.currentKind == kind &&
        provider.sessionProvider?.currentConnection?.serverUrl ==
            connection?.serverUrl &&
        provider.sessionProvider?.currentConnection?.userId ==
            connection?.userId &&
        provider.sessionProvider?.currentConnection?.userName ==
            connection?.userName;
    _active = request;
    request._show(context);
    try {
      final result = await action(request);
      return request.isCurrent ? result : null;
    } catch (_) {
      if (request.isCurrent) rethrow;
      return null;
    } finally {
      try {
        await request._cancellation;
        final link = request.pendingSource?.playLink?.trim() ?? '';
        bool canRelease() =>
            accountIsCurrent() && !sourceInUse(request.scope, link);
        if (legacy && link.isNotEmpty && canRelease()) {
          await NativeReentrySupport.releaseServerSession(
            nas,
            link,
            isCurrent: canRelease,
          );
        }
      } finally {
        request._hide();
        if (identical(_active, request)) _active = null;
      }
    }
  }
}
