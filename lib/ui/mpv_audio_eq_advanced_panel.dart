import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../playback/settings/mpv_audio_eq_preset_store.dart';
import '../playback/settings/mpv_settings_store.dart';
import '../theme/app_theme.dart';
import 'adaptive_text.dart';
import 'mpv_audio_eq_editor.dart';
import 'package:fly_player/widgets/common/bird_loader.dart';

class MpvAudioEqAdvancedPanel extends StatefulWidget {
  final Map<String, String> settings;
  final Future<void> Function(Map<String, String> patch) onApplyPatch;
  final ValueChanged<String>? onMessage;

  const MpvAudioEqAdvancedPanel({
    super.key,
    required this.settings,
    required this.onApplyPatch,
    this.onMessage,
  });

  @override
  State<MpvAudioEqAdvancedPanel> createState() =>
      _MpvAudioEqAdvancedPanelState();
}

class _MpvAudioEqAdvancedPanelState extends State<MpvAudioEqAdvancedPanel> {
  static const Duration _liveApplyInterval = Duration(milliseconds: 48);

  final MpvAudioEqPresetStore _presetStore = const MpvAudioEqPresetStore();
  late Map<String, double> _values = _readBandValues(widget.settings);
  List<MpvAudioEqPresetEntry> _presets = const <MpvAudioEqPresetEntry>[];
  bool _loadingPresets = true;
  Timer? _pendingLiveApplyTimer;
  MapEntry<String, double>? _pendingLiveApplyEntry;
  DateTime _lastLiveApplyAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _liveApplyInFlight = false;

  @override
  void initState() {
    super.initState();
    _loadPresets();
  }

  @override
  void dispose() {
    _pendingLiveApplyTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MpvAudioEqAdvancedPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      _values = _readBandValues(widget.settings);
    }
  }

  Future<void> _loadPresets() async {
    final presets = await _presetStore.load();
    if (!mounted) return;
    setState(() {
      _presets = presets;
      _loadingPresets = false;
    });
  }

  Map<String, double> _readBandValues(Map<String, String> settings) {
    return <String, double>{
      for (final band in MpvSettingsCatalog.audioEqBands)
        band.key: MpvSettingsCatalog.audioEqBandValue(band.key, settings),
    };
  }

  Map<String, String> _currentBandPatch() {
    return <String, String>{
      MpvSettingsCatalog.audioEqKey: MpvSettingsCatalog.audioEqCustomValue,
      for (final band in MpvSettingsCatalog.audioEqBands)
        band.key: MpvSettingsCatalog.normalizeAudioEqBandValue(
          _values[band.key] ?? 0,
        ),
    };
  }

  Future<void> _applyBandValue(String key, double value) async {
    final normalized = MpvSettingsCatalog.normalizeAudioEqBandValue(value);
    await widget.onApplyPatch(<String, String>{
      MpvSettingsCatalog.audioEqKey: MpvSettingsCatalog.audioEqCustomValue,
      key: normalized,
    });
  }

  void _handleBandChanged(MapEntry<String, double> entry) {
    setState(() {
      _values = <String, double>{..._values, entry.key: entry.value};
    });
    _pendingLiveApplyEntry = entry;
    _scheduleLiveApply();
  }

  Future<void> _handleBandChangeEnd(MapEntry<String, double> entry) async {
    _pendingLiveApplyEntry = entry;
    await _flushLiveApply(force: true);
  }

  void _scheduleLiveApply() {
    _pendingLiveApplyTimer?.cancel();
    if (_liveApplyInFlight || _pendingLiveApplyEntry == null) {
      return;
    }
    final remaining =
        _liveApplyInterval - DateTime.now().difference(_lastLiveApplyAt);
    if (remaining <= Duration.zero) {
      unawaited(_flushLiveApply());
      return;
    }
    _pendingLiveApplyTimer = Timer(remaining, () {
      unawaited(_flushLiveApply());
    });
  }

  Future<void> _flushLiveApply({bool force = false}) async {
    if (_liveApplyInFlight) return;
    final pending = _pendingLiveApplyEntry;
    if (pending == null) return;
    if (!force) {
      final remaining =
          _liveApplyInterval - DateTime.now().difference(_lastLiveApplyAt);
      if (remaining > Duration.zero) {
        _pendingLiveApplyTimer?.cancel();
        _pendingLiveApplyTimer = Timer(remaining, () {
          unawaited(_flushLiveApply());
        });
        return;
      }
    }
    _pendingLiveApplyTimer?.cancel();
    _pendingLiveApplyTimer = null;
    _pendingLiveApplyEntry = null;
    _liveApplyInFlight = true;
    _lastLiveApplyAt = DateTime.now();
    try {
      await _applyBandValue(pending.key, pending.value);
    } finally {
      _liveApplyInFlight = false;
      if (mounted) {
        _scheduleLiveApply();
      }
    }
  }

  Future<void> _resetBands() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _values = <String, double>{
        for (final band in MpvSettingsCatalog.audioEqBands) band.key: 0,
      };
    });
    await widget.onApplyPatch(_currentBandPatch());
    widget.onMessage?.call(l10n.mpvEqAllBandsReset);
  }

  Future<void> _applyPreset(MpvAudioEqPresetEntry preset) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _values = <String, double>{
        for (final band in MpvSettingsCatalog.audioEqBands)
          band.key: MpvSettingsCatalog.audioEqBandValue(band.key, preset.bands),
      };
    });
    await widget.onApplyPatch(<String, String>{
      MpvSettingsCatalog.audioEqKey: MpvSettingsCatalog.audioEqCustomValue,
      ...preset.bands,
    });
    widget.onMessage?.call(l10n.mpvEqPresetApplied(preset.name));
  }

  Future<void> _savePreset() async {
    final l10n = AppLocalizations.of(context);
    final name = await _showPresetNameDialog(context);
    if (!mounted || name == null) return;
    final presets = await _presetStore.savePreset(
      name: name,
      bands: _currentBandPatch(),
    );
    if (!mounted) return;
    setState(() => _presets = presets);
    widget.onMessage?.call(l10n.mpvEqPresetSaved);
  }

  Future<void> _deletePreset(MpvAudioEqPresetEntry preset) async {
    final l10n = AppLocalizations.of(context);
    final presets = await _presetStore.deletePreset(preset.id);
    if (!mounted) return;
    setState(() => _presets = presets);
    widget.onMessage?.call(l10n.mpvEqPresetDeleted(preset.name));
  }

  Future<String?> _showPresetNameDialog(BuildContext context) async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          final colors = dialogContext.appColors;
          final l10n = AppLocalizations.of(dialogContext);
          return AlertDialog(
            backgroundColor: dialogContext.appModalBackgroundColor,
            title: Text(
              l10n.mpvEqSavePresetTitle,
              style: TextStyle(color: colors.textPrimary),
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 20,
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                hintText: l10n.mpvEqSavePresetHint,
                hintStyle: TextStyle(color: colors.textMuted),
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: () {
                  final trimmed = controller.text.trim();
                  if (trimmed.isEmpty) return;
                  Navigator.of(dialogContext).pop(trimmed);
                },
                child: Text(l10n.commonSave),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        MpvAudioEqEditor(
          values: _values,
          onChanged: _handleBandChanged,
          onChangeEnd: _handleBandChangeEnd,
          onReset: _resetBands,
        ),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: colors.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          l10n.mpvEqMyPresetsTitle,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: AdaptiveText.roleSize(15.5),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          l10n.mpvEqMyPresetsSubtitle,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: AdaptiveText.roleSize(13),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _savePreset,
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: Text(l10n.mpvEqSaveCurrent),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_loadingPresets)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: BirdLoader(size: 96),
                  ),
                )
              else if (_presets.isEmpty)
                Text(
                  l10n.mpvEqEmptyPresets,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: AdaptiveText.roleSize(13.2),
                    height: 1.45,
                  ),
                )
              else
                Column(
                  children: _presets
                      .map(
                        (preset) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _EqPresetTile(
                            preset: preset,
                            onApply: () => _applyPreset(preset),
                            onDelete: () => _deletePreset(preset),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EqPresetTile extends StatelessWidget {
  final MpvAudioEqPresetEntry preset;
  final VoidCallback onApply;
  final VoidCallback onDelete;

  const _EqPresetTile({
    required this.preset,
    required this.onApply,
    required this.onDelete,
  });

  String _summary(AppLocalizations l10n) {
    final labels = <String>[];
    for (final band in MpvSettingsCatalog.audioEqBands) {
      final raw = preset.bands[band.key] ?? '0';
      final value = double.tryParse(raw) ?? 0;
      if (value.abs() < 0.05) continue;
      labels.add(
        '${band.label} ${MpvSettingsCatalog.formatAudioEqBandValue(value)}',
      );
      if (labels.length == 3) break;
    }
    return labels.isEmpty ? l10n.mpvEqSummaryNeutral : labels.join(' / ');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.backgroundElevated,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  preset.name,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: AdaptiveText.roleSize(14.8),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _summary(l10n),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: AdaptiveText.roleSize(12.8),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TextButton(onPressed: onApply, child: Text(l10n.mpvEqApply)),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
            color: colors.textMuted,
            tooltip: l10n.commonDelete,
          ),
        ],
      ),
    );
  }
}
