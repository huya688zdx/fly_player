import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../ui/adaptive_text.dart';
import 'theme_settings_helpers.dart';

class ThemeSettingsColorPickerDialog extends StatefulWidget {
  final String title;
  final Color initialColor;
  final List<Color> quickColors;

  const ThemeSettingsColorPickerDialog({
    super.key,
    required this.title,
    required this.initialColor,
    required this.quickColors,
  });

  @override
  State<ThemeSettingsColorPickerDialog> createState() =>
      _ThemeSettingsColorPickerDialogState();
}

class _ThemeSettingsColorPickerDialogState
    extends State<ThemeSettingsColorPickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initialColor);

  Color get _currentColor => _hsv.toColor();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AlertDialog(
      title: Text(
        widget.title,
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: AdaptiveText.roleSize(17, role: AdaptiveFontRole.title),
          fontWeight: FontWeight.w700,
        ),
      ),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                height: 92,
                decoration: BoxDecoration(
                  color: _currentColor,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: themeSettingsVisibleBorderFor(_currentColor),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  themeSettingsColorHex(_currentColor),
                  style: TextStyle(
                    color: themeSettingsForegroundOn(_currentColor),
                    fontWeight: FontWeight.w700,
                    fontSize: AdaptiveText.roleSize(15),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _ThemeSettingsPickerSlider(
                label: '色相',
                value: _hsv.hue,
                min: 0,
                max: 360,
                activeColor: _currentColor,
                onChanged: (value) =>
                    setState(() => _hsv = _hsv.withHue(value)),
              ),
              const SizedBox(height: 10),
              _ThemeSettingsPickerSlider(
                label: '饱和度',
                value: _hsv.saturation,
                min: 0,
                max: 1,
                activeColor: _currentColor,
                onChanged: (value) =>
                    setState(() => _hsv = _hsv.withSaturation(value)),
              ),
              const SizedBox(height: 10),
              _ThemeSettingsPickerSlider(
                label: '明度',
                value: _hsv.value,
                min: 0,
                max: 1,
                activeColor: _currentColor,
                onChanged: (value) =>
                    setState(() => _hsv = _hsv.withValue(value)),
              ),
              const SizedBox(height: 14),
              Text(
                '快速颜色',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: widget.quickColors
                    .map(
                      (color) => InkWell(
                        onTap: () =>
                            setState(() => _hsv = HSVColor.fromColor(color)),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: themeSettingsVisibleBorderFor(color),
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_currentColor),
          child: const Text('应用'),
        ),
      ],
    );
  }
}

class _ThemeSettingsPickerSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final Color activeColor;
  final ValueChanged<double> onChanged;

  const _ThemeSettingsPickerSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.activeColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              max == 1 ? value.toStringAsFixed(2) : value.round().toString(),
              style: TextStyle(
                color: colors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        Slider(
          min: min,
          max: max,
          value: value.clamp(min, max),
          activeColor: activeColor,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
