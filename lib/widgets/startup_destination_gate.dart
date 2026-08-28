import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/startup_preferences_provider.dart';
import 'package:fly_player/widgets/common/bird_loader.dart';

class StartupDestinationGate extends StatefulWidget {
  const StartupDestinationGate({
    super.key,
    required this.child,
    this.posterBrowseRouteName = '/screen/poster-browse',
    this.decisionReady = true,
    this.canOpenDestination = true,
  });

  final Widget child;
  final String posterBrowseRouteName;
  final bool decisionReady;
  final bool canOpenDestination;

  @override
  State<StartupDestinationGate> createState() => _StartupDestinationGateState();
}

class _StartupDestinationGateState extends State<StartupDestinationGate> {
  bool _decisionApplied = false;
  bool _openingDestination = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeApplyDecision();
  }

  @override
  void didUpdateWidget(covariant StartupDestinationGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeApplyDecision();
  }

  void _maybeApplyDecision() {
    final preferences = context.read<StartupPreferencesProvider>();
    if (_decisionApplied || !preferences.isReady || !widget.decisionReady) {
      return;
    }

    _decisionApplied = true;
    if (!preferences.openPosterHomeOnStartup || !widget.canOpenDestination) {
      return;
    }

    _openingDestination = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_openPosterBrowse());
    });
  }

  Future<void> _openPosterBrowse() async {
    try {
      await Navigator.of(context).pushNamed(widget.posterBrowseRouteName);
    } finally {
      if (mounted) setState(() => _openingDestination = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preferences = context.watch<StartupPreferencesProvider>();
    if (!preferences.isReady || _openingDestination) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: BirdLoader(size: 140, style: BirdLoaderStyle.logo)),
      );
    }
    return widget.child;
  }
}
