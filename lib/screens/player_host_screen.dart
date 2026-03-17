import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../player/models/player_host_launch_args.dart';
import '../player/mpv_player_page.dart';
import '../providers/nas_provider.dart';
import '../services/player_host_bridge.dart';
import '../theme/app_theme.dart';
import 'connection_screen.dart';

class PlayerHostScreen extends StatefulWidget {
  const PlayerHostScreen({super.key});

  @override
  State<PlayerHostScreen> createState() => _PlayerHostScreenState();
}

class _PlayerHostScreenState extends State<PlayerHostScreen> {
  static const MethodChannel _stateChannel = MethodChannel(
    'fly_player/player_host_state',
  );

  late final Future<PlayerHostLaunchArgs?> _argsFuture =
      PlayerHostBridge.consumeInitialPlayerArgs();
  String? _layoutModeOverride;
  PlayerHostLaunchArgs? _playerArgsOverride;

  @override
  void initState() {
    super.initState();
    _stateChannel.setMethodCallHandler(_handleStateMethodCall);
  }

  @override
  void dispose() {
    _stateChannel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _handleStateMethodCall(MethodCall call) async {
    if (call.method != 'replaceSource') return;
    final rawArgs = call.arguments;
    if (rawArgs is! Map<Object?, Object?>) return;
    final args = PlayerHostLaunchArgs.fromPlatformMap(rawArgs);
    if (args == null || !mounted) return;
    setState(() {
      _playerArgsOverride = args;
      _layoutModeOverride = args.layoutMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NasProvider>();
    final colors = context.appColors;
    if (!provider.isReady) {
      return Scaffold(
        backgroundColor: colors.backgroundBase,
        body: Center(child: CircularProgressIndicator(color: colors.accent)),
      );
    }
    if (!provider.isConfigured) {
      return const ConnectionScreen();
    }
    return FutureBuilder<PlayerHostLaunchArgs?>(
      future: _argsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            backgroundColor: colors.backgroundBase,
            body: Center(
              child: CircularProgressIndicator(color: colors.accent),
            ),
          );
        }
        final args = _playerArgsOverride ?? snapshot.data;
        if (args == null) {
          return _PlayerHostError(message: '当前播放器参数错误');
        }
        return MpvPlayerPage(
          title: args.title,
          source: args.source,
          parallelLayoutToggleEnabled: args.fromParallelHost,
          parallelLayoutMode: _layoutModeOverride ?? args.layoutMode,
          onParallelLayoutModeChanged: (nextMode) {
            if (!mounted) return;
            setState(() => _layoutModeOverride = nextMode);
          },
          onCloseRequested: (result) async {
            final closed = await PlayerHostBridge.finishPlayerActivity(
              result,
            );
            if (!closed && context.mounted) {
              Navigator.of(context).maybePop(result);
            }
          },
        );
      },
    );
  }
}

class _PlayerHostError extends StatelessWidget {
  final String message;

  const _PlayerHostError({required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      body: Center(
        child: Text(
          message,
          style: TextStyle(color: colors.textSecondary, fontSize: 16),
        ),
      ),
    );
  }
}
