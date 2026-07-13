import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../playback/settings/mpv_settings_store.dart';
import '../theme/app_theme.dart';

class MpvAudioEqEditor extends StatelessWidget {
  final Map<String, double> values;
  final ValueChanged<MapEntry<String, double>> onChanged;
  final ValueChanged<MapEntry<String, double>> onChangeEnd;
  final VoidCallback? onReset;
  final String? title;
  final String? subtitle;

  const MpvAudioEqEditor({
    super.key,
    required this.values,
    required this.onChanged,
    required this.onChangeEnd,
    this.onReset,
    this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final resolvedTitle = title ?? l10n.mpvEqEditorTitle;
    final resolvedSubtitle = subtitle ?? l10n.mpvEqEditorSubtitle;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: colors.surface.withValues(alpha: 0.72),
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
                      resolvedTitle,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      resolvedSubtitle,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              if (onReset != null)
                TextButton.icon(
                  onPressed: onReset,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: Text(l10n.mpvEqReset),
                ),
            ],
          ),
          const SizedBox(height: 18),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 320),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: MpvSettingsCatalog.audioEqBands
                    .map(
                      (band) => SizedBox(
                        width: 72,
                        child: _MpvAudioEqBandSlider(
                          band: band,
                          value: values[band.key] ?? 0,
                          onChanged: (value) =>
                              onChanged(MapEntry(band.key, value)),
                          onChangeEnd: (value) =>
                              onChangeEnd(MapEntry(band.key, value)),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MpvAudioEqBandSlider extends StatelessWidget {
  final MpvAudioEqBand band;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _MpvAudioEqBandSlider({
    required this.band,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final displayValue = MpvSettingsCatalog.formatAudioEqBandValue(value);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            height: 16,
            width: double.infinity,
            child: Center(
              child: Text(
                displayValue,
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: value.abs() < 0.05
                      ? colors.textSecondary
                      : colors.accentStrong,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 52,
            height: 220,
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: colors.accent,
                  inactiveTrackColor: colors.borderStrong,
                  thumbColor: colors.textPrimary,
                  overlayColor: colors.accentSoft,
                  trackHeight: 6,
                ),
                child: Slider(
                  value: value.clamp(
                    MpvSettingsCatalog.audioEqBandMinDb,
                    MpvSettingsCatalog.audioEqBandMaxDb,
                  ),
                  min: MpvSettingsCatalog.audioEqBandMinDb,
                  max: MpvSettingsCatalog.audioEqBandMaxDb,
                  divisions:
                      ((MpvSettingsCatalog.audioEqBandMaxDb -
                                  MpvSettingsCatalog.audioEqBandMinDb) /
                              MpvSettingsCatalog.audioEqBandStepDb)
                          .round(),
                  onChanged: onChanged,
                  onChangeEnd: onChangeEnd,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${band.label} Hz',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
