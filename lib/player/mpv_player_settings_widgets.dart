part of 'mpv_player_page.dart';

class PlaybackSettingsHeaderAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const PlaybackSettingsHeaderAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      icon: Icon(icon, color: Colors.white, size: 19),
      label: Text(label, style: const TextStyle(fontSize: 14)),
    );
  }
}

class PlaybackSettingsMenuTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String trailingLabel;
  final VoidCallback onTap;

  const PlaybackSettingsMenuTile({
    super.key,
    required this.title,
    this.subtitle = '',
    this.trailingLabel = '',
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: _settingsCardDecoration(),
          child: Row(
            children: [
              Expanded(
                child: _SettingsTextBlock(title: title, subtitle: subtitle),
              ),
              if (trailingLabel.trim().isNotEmpty) ...[
                const SizedBox(width: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 72, maxWidth: 88),
                  child: Text(
                    trailingLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Color(0xB3FFFFFF),
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Color(0x99FFFFFF),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlaybackSettingsSwitchTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const PlaybackSettingsSwitchTile({
    super.key,
    required this.title,
    this.subtitle = '',
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _settingsCardDecoration(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: _SettingsTextBlock(title: title, subtitle: subtitle),
            ),
            const SizedBox(width: 12),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: Colors.white,
              activeTrackColor: const Color(0xFF2D87FF),
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: Colors.white24,
            ),
          ],
        ),
      ),
    );
  }
}

class PlaybackSettingsAspectRatioTile extends StatelessWidget {
  final String value;
  final String subtitle;
  final ValueChanged<String> onChanged;

  const PlaybackSettingsAspectRatioTile({
    super.key,
    required this.value,
    required this.subtitle,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const options = <(String, String)>[
      (_MpvPlayerPageState._displayAspectRatioFit, '适应'),
      (_MpvPlayerPageState._displayAspectRatioFill, '填充'),
      (_MpvPlayerPageState._displayAspectRatio4x3, '4:3'),
      (_MpvPlayerPageState._displayAspectRatio16x9, '16:9'),
      (_MpvPlayerPageState._displayAspectRatio21x9, '21:9'),
    ];
    return DecoratedBox(
      decoration: _settingsCardDecoration(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SettingsTextBlock(title: '画面比例', subtitle: subtitle),
            const SizedBox(height: 14),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: Colors.white.withValues(alpha: 0.06),
              ),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Row(
                  children: [
                    for (final option in options)
                      Expanded(
                        child: _PlaybackSettingsAspectRatioOption(
                          label: option.$2,
                          selected: value == option.$1,
                          onTap: () => onChanged(option.$1),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PlaybackSettingsChoiceTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const PlaybackSettingsChoiceTile({
    super.key,
    required this.title,
    this.subtitle = '',
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? const Color(0xFF2D87FF)
        : Colors.white.withValues(alpha: 0.08);
    final backgroundColor = selected
        ? const Color(0x142D87FF)
        : Colors.white.withValues(alpha: 0.03);
    final titleColor = selected ? const Color(0xFF2D87FF) : Colors.white;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
            color: backgroundColor,
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? const Color(0xFF2D87FF)
                      : Colors.transparent,
                  border: Border.all(
                    color: selected
                        ? const Color(0xFF2D87FF)
                        : const Color(0x66FFFFFF),
                  ),
                ),
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: Colors.white,
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0x99FFFFFF),
                          fontSize: 12,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlaybackSettingsIntroOutroView extends StatelessWidget {
  final bool enabled;
  final String mode;
  final int introDurationSeconds;
  final int outroDurationSeconds;
  final Future<List<MpvChapterItem>> Function() chapterLoader;
  final String Function(List<MpvChapterItem> chapters) summaryBuilder;
  final String Function(List<MpvChapterItem> chapters) introChapterLabelBuilder;
  final String Function(List<MpvChapterItem> chapters) outroChapterLabelBuilder;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<String> onModeChanged;
  final VoidCallback onPickIntroChapter;
  final VoidCallback onPickOutroChapter;
  final ValueChanged<int> onAdjustIntroDuration;
  final ValueChanged<int> onAdjustOutroDuration;

  const PlaybackSettingsIntroOutroView({
    super.key,
    required this.enabled,
    required this.mode,
    required this.introDurationSeconds,
    required this.outroDurationSeconds,
    required this.chapterLoader,
    required this.summaryBuilder,
    required this.introChapterLabelBuilder,
    required this.outroChapterLabelBuilder,
    required this.onEnabledChanged,
    required this.onModeChanged,
    required this.onPickIntroChapter,
    required this.onPickOutroChapter,
    required this.onAdjustIntroDuration,
    required this.onAdjustOutroDuration,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MpvChapterItem>>(
      future: chapterLoader(),
      builder: (context, snapshot) {
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            PlaybackSettingsStatusCard(
              title: 'OP/ED 跳过',
              value: enabled ? '已开启' : '已关闭',
              description: summaryBuilder(const <MpvChapterItem>[]),
            ),
            const SizedBox(height: 12),
            PlaybackSettingsSwitchTile(
              title: '启用自动跳过',
              subtitle: '开启后按官方配置跳过片头片尾',
              value: enabled,
              onChanged: onEnabledChanged,
            ),
            if (enabled) ...[
              const SizedBox(height: 18),
              const PlaybackSettingsSectionLabel(label: '高级调整'),
              const SizedBox(height: 10),
              PlaybackSettingsStepperTile(
                title: '片头时长',
                subtitle: '默认 1-2 分钟，必要时再微调',
                valueLabel: _formatSecondsLabel(introDurationSeconds),
                onDecrease: () => onAdjustIntroDuration(-5),
                onIncrease: () => onAdjustIntroDuration(5),
              ),
              const SizedBox(height: 10),
              PlaybackSettingsStepperTile(
                title: '片尾时长',
                subtitle: '默认 1-2 分钟，必要时再微调',
                valueLabel: _formatSecondsLabel(outroDurationSeconds),
                onDecrease: () => onAdjustOutroDuration(-5),
                onIncrease: () => onAdjustOutroDuration(5),
              ),
            ],
          ],
        );
        final chapters = snapshot.data ?? const <MpvChapterItem>[];
        final showChapterControls =
            enabled &&
            (mode == _MpvPlayerPageState._introOutroModeAuto ||
                mode == _MpvPlayerPageState._introOutroModeChapter);
        final showManualControls =
            enabled &&
            (mode == _MpvPlayerPageState._introOutroModeAuto ||
                mode == _MpvPlayerPageState._introOutroModeManual);
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            PlaybackSettingsStatusCard(
              title: '跳过功能',
              value: enabled ? '开启' : '关闭',
              description: summaryBuilder(chapters),
            ),
            const SizedBox(height: 12),
            PlaybackSettingsSwitchTile(
              title: '开启',
              subtitle: '总开关',
              value: enabled,
              onChanged: onEnabledChanged,
            ),
            const SizedBox(height: 18),
            const PlaybackSettingsSectionLabel(label: '模式选择'),
            const SizedBox(height: 10),
            PlaybackSettingsChoiceTile(
              title: '自动模式',
              subtitle: '优先章节，无则使用手动时长',
              selected: mode == _MpvPlayerPageState._introOutroModeAuto,
              onTap: () =>
                  onModeChanged(_MpvPlayerPageState._introOutroModeAuto),
            ),
            const SizedBox(height: 10),
            PlaybackSettingsChoiceTile(
              title: '章节模式',
              subtitle: '通过 mpv 章节自动识别',
              selected: mode == _MpvPlayerPageState._introOutroModeChapter,
              onTap: () =>
                  onModeChanged(_MpvPlayerPageState._introOutroModeChapter),
            ),
            const SizedBox(height: 10),
            PlaybackSettingsChoiceTile(
              title: '手动模式',
              subtitle: '手动指定片头片尾长度',
              selected: mode == _MpvPlayerPageState._introOutroModeManual,
              onTap: () =>
                  onModeChanged(_MpvPlayerPageState._introOutroModeManual),
            ),
            if (showChapterControls) ...[
              const SizedBox(height: 18),
              const PlaybackSettingsSectionLabel(label: '章节识别'),
              const SizedBox(height: 10),
              PlaybackSettingsMenuTile(
                title: '片头章节',
                subtitle: chapters.isEmpty ? '当前未读取到可用章节' : '使用 mpv 章节名进行定位',
                trailingLabel: introChapterLabelBuilder(chapters),
                onTap: onPickIntroChapter,
              ),
              const SizedBox(height: 10),
              PlaybackSettingsMenuTile(
                title: '片尾章节',
                subtitle: chapters.isEmpty ? '当前未读取到可用章节' : '使用 mpv 章节名进行定位',
                trailingLabel: outroChapterLabelBuilder(chapters),
                onTap: onPickOutroChapter,
              ),
            ],
            if (showManualControls) ...[
              const SizedBox(height: 18),
              const PlaybackSettingsSectionLabel(label: '手动时长'),
              const SizedBox(height: 10),
              PlaybackSettingsStepperTile(
                title: '片头时长',
                subtitle: mode == _MpvPlayerPageState._introOutroModeAuto
                    ? '章节缺失时使用'
                    : '手动指定片头跳过时长',
                valueLabel: _formatSecondsLabel(introDurationSeconds),
                onDecrease: () => onAdjustIntroDuration(-5),
                onIncrease: () => onAdjustIntroDuration(5),
              ),
              const SizedBox(height: 10),
              PlaybackSettingsStepperTile(
                title: '片尾时长',
                subtitle: mode == _MpvPlayerPageState._introOutroModeAuto
                    ? '章节缺失时使用'
                    : '手动指定片尾跳过时长',
                valueLabel: _formatSecondsLabel(outroDurationSeconds),
                onDecrease: () => onAdjustOutroDuration(-5),
                onIncrease: () => onAdjustOutroDuration(5),
              ),
            ],
          ],
        );
      },
    );
  }

  String _formatSecondsLabel(int seconds) {
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$secs' : '$minutes:$secs';
  }
}

class PlaybackSettingsChapterPicker extends StatefulWidget {
  final Future<List<MpvChapterItem>> Function() loader;
  final int? selectedIndex;
  final ValueChanged<int?> onSelected;

  const PlaybackSettingsChapterPicker({
    super.key,
    required this.loader,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  State<PlaybackSettingsChapterPicker> createState() =>
      _PlaybackSettingsChapterPickerState();
}

class _PlaybackSettingsChapterPickerState
    extends State<PlaybackSettingsChapterPicker> {
  late final Future<List<MpvChapterItem>> _future = widget.loader();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MpvChapterItem>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                '读取章节失败: ${snapshot.error}',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          );
        }
        final chapters = snapshot.data ?? const <MpvChapterItem>[];
        if (chapters.isEmpty) {
          return const Center(
            child: Text(
              '当前视频没有可用章节',
              style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 14),
            ),
          );
        }
        return ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: chapters.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            if (index == 0) {
              return PlaybackSettingsChapterTile(
                title: '不使用章节',
                trailingLabel: '',
                selected: widget.selectedIndex == null,
                onTap: () => widget.onSelected(null),
              );
            }
            final chapter = chapters[index - 1];
            final title = chapter.title.trim().isNotEmpty
                ? chapter.title.trim()
                : '第 ${chapter.index + 1} 章';
            return PlaybackSettingsChapterTile(
              title: title,
              trailingLabel: _formatChapterTime(chapter.time),
              selected: widget.selectedIndex == chapter.index,
              onTap: () => widget.onSelected(chapter.index),
            );
          },
        );
      },
    );
  }

  String _formatChapterTime(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    final milliseconds = value.inMilliseconds
        .remainder(1000)
        .toString()
        .padLeft(3, '0');
    return hours > 0
        ? '$hours:$minutes:$seconds.$milliseconds'
        : '$minutes:$seconds.$milliseconds';
  }
}

class PlaybackSettingsStatusCard extends StatelessWidget {
  final String title;
  final String value;
  final String description;

  const PlaybackSettingsStatusCard({
    super.key,
    required this.title,
    required this.value,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _settingsCardDecoration(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xB3FFFFFF),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (description.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                description,
                style: const TextStyle(
                  color: Color(0x99FFFFFF),
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class PlaybackSettingsSectionLabel extends StatelessWidget {
  final String label;

  const PlaybackSettingsSectionLabel({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xC7FFFFFF),
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class PlaybackSettingsStepperTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String valueLabel;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  const PlaybackSettingsStepperTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.valueLabel,
    required this.onDecrease,
    required this.onIncrease,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _settingsCardDecoration(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: _SettingsTextBlock(title: title, subtitle: subtitle),
            ),
            const SizedBox(width: 12),
            _PlaybackSettingsStepButton(
              icon: Icons.remove_rounded,
              onTap: onDecrease,
            ),
            const SizedBox(width: 10),
            _PlaybackSettingsValueChip(label: valueLabel),
            const SizedBox(width: 10),
            _PlaybackSettingsStepButton(
              icon: Icons.add_rounded,
              onTap: onIncrease,
            ),
          ],
        ),
      ),
    );
  }
}

class PlaybackSettingsChapterTile extends StatelessWidget {
  final String title;
  final String trailingLabel;
  final bool selected;
  final VoidCallback onTap;

  const PlaybackSettingsChapterTile({
    super.key,
    required this.title,
    required this.trailingLabel,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? const Color(0xFF2D87FF)
        : Colors.white.withValues(alpha: 0.08);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
            color: selected
                ? const Color(0x142D87FF)
                : Colors.white.withValues(alpha: 0.03),
          ),
          child: Row(
            children: [
              _SelectionIndicator(selected: selected),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: selected ? const Color(0xFFDFEAFF) : Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (trailingLabel.trim().isNotEmpty) ...[
                const SizedBox(width: 10),
                Text(
                  trailingLabel,
                  style: const TextStyle(
                    color: Color(0xB3FFFFFF),
                    fontSize: 13,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class PlaybackDetailSection {
  final String title;
  final List<PlaybackDetailItem> items;

  const PlaybackDetailSection({required this.title, required this.items});
}

class PlaybackDetailItem {
  final String label;
  final String value;

  const PlaybackDetailItem(this.label, this.value);
}

class PlaybackDetailCard extends StatelessWidget {
  final PlaybackDetailSection section;

  const PlaybackDetailCard({super.key, required this.section});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _settingsCardDecoration(alpha: 0.04),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              section.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            ...section.items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 86,
                      child: Text(
                        item.label,
                        style: const TextStyle(
                          color: Color(0x99FFFFFF),
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.value,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsTextBlock extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SettingsTextBlock({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (subtitle.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0x99FFFFFF),
              fontSize: 12,
              height: 1.25,
            ),
          ),
        ],
      ],
    );
  }
}

class _PlaybackSettingsAspectRatioOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PlaybackSettingsAspectRatioOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: selected ? const Color(0x1F2D87FF) : Colors.transparent,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? const Color(0xFF2D87FF) : Colors.white,
              fontSize: 14,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaybackSettingsStepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _PlaybackSettingsStepButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x1F2D87FF),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}

class _PlaybackSettingsValueChip extends StatelessWidget {
  final String label;

  const _PlaybackSettingsValueChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _SelectionIndicator extends StatelessWidget {
  final bool selected;

  const _SelectionIndicator({required this.selected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? const Color(0xFF2D87FF) : Colors.transparent,
        border: Border.all(
          color: selected ? const Color(0xFF2D87FF) : const Color(0x66FFFFFF),
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
          : null,
    );
  }
}

BoxDecoration _settingsCardDecoration({double alpha = 0.03}) {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
    color: Colors.white.withValues(alpha: alpha),
  );
}
