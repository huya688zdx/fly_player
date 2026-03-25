import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../services/play_stats/play_stats.dart';
import '../../theme/app_theme.dart';
import '../../ui/app_info_popover.dart';
import 'play_stats_report_formatters.dart';

class PlayStatsReportPalette {
  final Color cyan;
  final Color amber;
  final Color coral;
  final Color mint;
  final Color violet;
  final Color blue;
  final Color rose;
  final Color heatmapBase;
  final Color heatmapActive;
  final Color divider;

  const PlayStatsReportPalette({
    required this.cyan,
    required this.amber,
    required this.coral,
    required this.mint,
    required this.violet,
    required this.blue,
    required this.rose,
    required this.heatmapBase,
    required this.heatmapActive,
    required this.divider,
  });

  static PlayStatsReportPalette of(BuildContext context) {
    final colors = context.appColors;
    final isLight = colors.backgroundBase.computeLuminance() >= 0.58;
    return isLight
        ? const PlayStatsReportPalette(
            cyan: Color(0xFF007EA7),
            amber: Color(0xFFF59E0B),
            coral: Color(0xFFE85D75),
            mint: Color(0xFF10B981),
            violet: Color(0xFF7C5CFC),
            blue: Color(0xFF3B82F6),
            rose: Color(0xFFEF476F),
            heatmapBase: Color(0xFFE5EFEA),
            heatmapActive: Color(0xFF12B981),
            divider: Color(0xFFF7FAFC),
          )
        : const PlayStatsReportPalette(
            cyan: Color(0xFF48CAE4),
            amber: Color(0xFFFFB703),
            coral: Color(0xFFFF6B6B),
            mint: Color(0xFF80ED99),
            violet: Color(0xFFB388FF),
            blue: Color(0xFF5AA9FF),
            rose: Color(0xFFFF7AA2),
            heatmapBase: Color(0xFF17362D),
            heatmapActive: Color(0xFF88F7B0),
            divider: Color(0xFFEFF7F6),
          );
  }

  List<Color> get mediaPieColors => <Color>[cyan, amber, coral, mint, violet];

  List<Color> get behaviorPieColors => <Color>[blue, amber, mint, rose, violet];
}

class PlayStatsReportSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  const PlayStatsReportSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: colors.borderSubtle),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: colors.overlayScrim.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle != null &&
                        subtitle!.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12.8,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class PlayStatsHeroCard extends StatelessWidget {
  final PlayStatsOverview overview;
  final PlayStatsRange selectedRange;
  final PlayStatsReportFormatters formatters;

  const PlayStatsHeroCard({
    super.key,
    required this.overview,
    required this.selectedRange,
    required this.formatters,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colors.accent.withValues(alpha: 0.28),
            colors.surfaceStrong.withValues(alpha: 0.96),
            colors.backgroundElevated.withValues(alpha: 0.92),
          ],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: colors.borderStrong.withValues(alpha: 0.7)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: colors.accent.withValues(alpha: 0.14),
            blurRadius: 28,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colors.accentSoft.withValues(alpha: 0.58),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${selectedRange.label}观影战报',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              _HeroStatBadge(
                label: '活跃天数',
                value: '${overview.activeDays}',
                valueChild: PlayStatsAnimatedMetricText(
                  value: overview.activeDays.toDouble(),
                  builder: (value) => value.round().toString(),
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          PlayStatsAnimatedMetricText(
            value: overview.totalPlayedMs.toDouble(),
            builder: (value) =>
                '累计 ${formatters.duration(value.round(), compact: true)}',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
            duration: const Duration(milliseconds: 560),
            pulseScale: 1.08,
          ),
          const SizedBox(height: 8),
          Text(
            overview.insight,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 13.6,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _MetricPill(
                label: '播放次数',
                value: '${overview.totalClickCount}',
                tone: colors.selectionStrong,
                infoTitle: '播放次数',
                infoDescription: '统计这段时间里，你主动点开播放或手动切换内容的次数。',
                infoDetail: '更接近你发起了多少次播放，不包含自动连播或系统恢复。',
                valueChild: PlayStatsAnimatedMetricText(
                  value: overview.totalClickCount.toDouble(),
                  builder: (value) => value.round().toString(),
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14.4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _MetricPill(
                label: '观看次数',
                value: '${overview.totalViewCount}',
                tone: colors.accent,
                infoTitle: '观看次数',
                infoDescription: '只统计达到有效观看门槛的播放记录，用来看你真正进入观看状态了多少次。',
                infoDetail: '剧集需看满 20%，电影需看满 10%。',
                valueChild: PlayStatsAnimatedMetricText(
                  value: overview.totalViewCount.toDouble(),
                  builder: (value) => value.round().toString(),
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14.4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _MetricPill(
                label: '完播视频',
                value: '${overview.totalCompletedVideoCount}',
                tone: colors.success,
                infoTitle: '完播视频',
                infoDescription: '统计被判定为完整看完的具体视频条目数，更接近你真正看完了多少集或多少部片。',
                infoDetail: '通常需要看满约 80%，并且结尾不是一拖而过，才会记入完播。',
                valueChild: PlayStatsAnimatedMetricText(
                  value: overview.totalCompletedVideoCount.toDouble(),
                  builder: (value) => value.round().toString(),
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14.4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _MetricPill(
                label: '完播季度',
                value: '${overview.totalCompletedSeasonCount}',
                tone: colors.warning,
                infoTitle: '完播季度',
                infoDescription: '统计在当前时间范围内，被判定为整季看完的季度数量。',
                infoDetail: '只有计入季完播的正片都完成后，这一季才会记作 1 个完播季度。',
                valueChild: PlayStatsAnimatedMetricText(
                  value: overview.totalCompletedSeasonCount.toDouble(),
                  builder: (value) => value.round().toString(),
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14.4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _MetricPill(
                label: '元数据覆盖',
                value: formatters.percent(
                  overview.metadataCoverage,
                  fractionDigits: 0,
                ),
                tone: colors.selectionStrong,
                infoTitle: '元数据覆盖',
                infoDescription: '反映这批内容里，类型、国家地区、年份和演职人员等信息补全得有多完整。',
                infoDetail: '覆盖越高，下面的偏好分析和亲和榜越完整、越可靠。',
                valueChild: PlayStatsAnimatedMetricText(
                  value: overview.metadataCoverage * 100,
                  builder: (value) => '${value.round()}%',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14.4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class PlayStatsRangeSelector extends StatelessWidget {
  final PlayStatsRange selectedRange;
  final ValueChanged<PlayStatsRange> onChanged;
  final bool compact;

  const PlayStatsRangeSelector({
    super.key,
    required this.selectedRange,
    required this.onChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final itemSpacing = compact ? 6.0 : 8.0;
    final verticalPadding = compact ? 9.0 : 11.0;
    final fontSize = compact ? 11.8 : 12.8;
    return Row(
      children: PlayStatsRange.values
          .map((range) {
            final active = range == selectedRange;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: range == PlayStatsRange.values.last ? 0 : itemSpacing,
                ),
                child: InkWell(
                  onTap: () => onChanged(range),
                  borderRadius: BorderRadius.circular(999),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    padding: EdgeInsets.symmetric(vertical: verticalPadding),
                    decoration: BoxDecoration(
                      color: active ? colors.accent : colors.surfaceSubtle,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: active
                            ? colors.accentStrong.withValues(alpha: 0.84)
                            : colors.borderSubtle,
                      ),
                    ),
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      style: TextStyle(
                        color: active ? Colors.white : colors.textPrimary,
                        fontSize: fontSize,
                        fontWeight: FontWeight.w700,
                      ),
                      child: Text(range.label, textAlign: TextAlign.center),
                    ),
                  ),
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }
}

class PlayStatsChargedBar extends StatelessWidget {
  final double value;
  final double minHeight;
  final Color color;
  final Color backgroundColor;

  const PlayStatsChargedBar({
    super.key,
    required this.value,
    required this.minHeight,
    required this.color,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final clampedValue = value.clamp(0.0, 1.0).toDouble();
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: clampedValue),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: minHeight,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                DecoratedBox(decoration: BoxDecoration(color: backgroundColor)),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: animatedValue,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: <Color>[color.withValues(alpha: 0.86), color],
                        ),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class PlayStatsLineChartCard extends StatelessWidget {
  final List<PlayStatsTrendPoint> points;
  final PlayStatsReportFormatters formatters;

  const PlayStatsLineChartCard({
    super.key,
    required this.points,
    required this.formatters,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final palette = PlayStatsReportPalette.of(context);
    if (points.isEmpty) {
      return const _InlineEmpty(label: '暂无播放趋势数据');
    }
    final xAxisLabelIndexes = _buildXAxisLabelIndexes(points.length);
    final maxY = points.fold<int>(
      0,
      (maxValue, item) => math.max(maxValue, item.playedMs),
    );
    final yAxisStepMs = _pickDurationAxisStepMs(maxY);
    final yAxisTopValue = math.max(
      yAxisStepMs.toDouble(),
      (maxY <= 0 ? yAxisStepMs : ((maxY / yAxisStepMs).ceil() * yAxisStepMs))
          .toDouble(),
    );
    final yAxisValues = <int>{
      for (var value = 0; value <= yAxisTopValue.round(); value += yAxisStepMs)
        value,
    };
    return SizedBox(
      height: 188,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (points.length - 1).toDouble(),
          minY: 0,
          maxY: yAxisTopValue,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: colors.borderSubtle.withValues(alpha: 0.55),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 52,
                interval: yAxisStepMs.toDouble(),
                getTitlesWidget: (value, _) {
                  final roundedValue = value.round();
                  if (!yAxisValues.contains(roundedValue)) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    formatters.duration(roundedValue, compact: true),
                    style: TextStyle(color: colors.textMuted, fontSize: 10.5),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: 1,
                getTitlesWidget: (value, _) {
                  final index = value.round();
                  if (index < 0 ||
                      index >= points.length ||
                      !xAxisLabelIndexes.contains(index)) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      formatters.date(points[index].date, compact: true),
                      style: TextStyle(color: colors.textMuted, fontSize: 10.5),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => colors.surfaceStrong,
              tooltipRoundedRadius: 14,
              getTooltipItems: (spots) {
                return spots
                    .map((spot) {
                      final item = points[spot.x.round()];
                      return LineTooltipItem(
                        '${formatters.date(item.date)}\n${formatters.duration(item.playedMs, compact: true)}',
                        TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      );
                    })
                    .toList(growable: false);
              },
            ),
          ),
          lineBarsData: <LineChartBarData>[
            LineChartBarData(
              spots: List<FlSpot>.generate(
                points.length,
                (index) =>
                    FlSpot(index.toDouble(), points[index].playedMs.toDouble()),
              ),
              isCurved: true,
              color: palette.cyan,
              barWidth: 3.6,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    palette.cyan.withValues(alpha: 0.24),
                    palette.cyan.withValues(alpha: 0.02),
                  ],
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  Set<int> _buildXAxisLabelIndexes(int pointCount) {
    if (pointCount <= 0) {
      return const <int>{};
    }
    if (pointCount <= 6) {
      return Set<int>.from(List<int>.generate(pointCount, (index) => index));
    }
    return <int>{
      0,
      (pointCount * 0.25).round().clamp(0, pointCount - 1),
      (pointCount * 0.5).round().clamp(0, pointCount - 1),
      (pointCount * 0.75).round().clamp(0, pointCount - 1),
      pointCount - 1,
    };
  }
}

class PlayStatsBarChartCard extends StatelessWidget {
  final List<PlayStatsTrendPoint> points;

  const PlayStatsBarChartCard({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (points.isEmpty) {
      return const _InlineEmpty(label: '暂无观看次数数据');
    }
    final maxY = points.fold<int>(
      0,
      (maxValue, item) => math.max(maxValue, item.viewCount),
    );
    return SizedBox(
      height: 154,
      child: BarChart(
        BarChartData(
          minY: 0,
          maxY: maxY <= 0 ? 1 : maxY.toDouble() * 1.2,
          alignment: BarChartAlignment.spaceAround,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: colors.borderSubtle.withValues(alpha: 0.45),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: maxY <= 0
                    ? 1
                    : math.max(1, (maxY / 3).round()).toDouble(),
                getTitlesWidget: (value, _) {
                  return Text(
                    value.toInt().toString(),
                    style: TextStyle(color: colors.textMuted, fontSize: 10.5),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: math.max(1, (points.length / 4).floor()).toDouble(),
                getTitlesWidget: (value, _) {
                  final index = value.round();
                  if (index < 0 || index >= points.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${points[index].date.month.toString().padLeft(2, '0')}/${points[index].date.day.toString().padLeft(2, '0')}',
                      style: TextStyle(color: colors.textMuted, fontSize: 10.5),
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => colors.surfaceStrong,
              getTooltipItem: (group, _, rod, __) {
                return BarTooltipItem(
                  '${points[group.x.toInt()].date.month}/${points[group.x.toInt()].date.day}\n${rod.toY.toInt()} 次',
                  TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                );
              },
            ),
          ),
          barGroups: List<BarChartGroupData>.generate(points.length, (index) {
            final item = points[index];
            return BarChartGroupData(
              x: index,
              barRods: <BarChartRodData>[
                BarChartRodData(
                  toY: item.viewCount.toDouble(),
                  width: points.length > 40 ? 4.5 : 8,
                  borderRadius: BorderRadius.circular(999),
                  gradient: const LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: <Color>[Color(0xFFFFB703), Color(0xFFFF6B6B)],
                  ),
                ),
              ],
            );
          }),
        ),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      ),
    );
  }
}

class PlayStatsHeatmap extends StatelessWidget {
  final List<PlayStatsHeatmapCell> cells;
  final PlayStatsReportFormatters formatters;

  const PlayStatsHeatmap({
    super.key,
    required this.cells,
    required this.formatters,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (cells.isEmpty) {
      return const _InlineEmpty(label: '暂无活跃时段数据');
    }
    final palette = PlayStatsReportPalette.of(context);
    final cellMap = <String, PlayStatsHeatmapCell>{
      for (final item in cells) '${item.weekday}-${item.hour}': item,
    };
    final maxValue = cells.fold<int>(
      0,
      (maxSoFar, item) => math.max(maxSoFar, item.playedMs),
    );
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            const SizedBox(width: 24),
            for (var hour = 0; hour < 24; hour += 4)
              Expanded(
                child: Text(
                  formatters.hourLabel(hour),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textMuted, fontSize: 10.5),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Column(
          children: List<Widget>.generate(7, (rowIndex) {
            final weekday = rowIndex + 1;
            return Padding(
              padding: EdgeInsets.only(bottom: rowIndex == 6 ? 0 : 6),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 24,
                    child: Text(
                      formatters.weekday(weekday),
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: List<Widget>.generate(24, (hour) {
                        final cell =
                            cellMap['$weekday-$hour'] ??
                            PlayStatsHeatmapCell(
                              weekday: weekday,
                              hour: hour,
                              playedMs: 0,
                              sessionCount: 0,
                            );
                        final intensity = maxValue <= 0
                            ? 0.0
                            : cell.playedMs / maxValue;
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(right: hour == 23 ? 0 : 3),
                            child: Tooltip(
                              message:
                                  '周${formatters.weekday(weekday)} ${formatters.hourLabel(hour)}:00\n${cell.sessionCount} 次 / ${formatters.duration(cell.playedMs, compact: true)}',
                              child: Container(
                                height: 14,
                                decoration: BoxDecoration(
                                  color: Color.lerp(
                                    palette.heatmapBase,
                                    palette.heatmapActive,
                                    intensity.clamp(0.0, 1.0),
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            Text('少', style: TextStyle(color: colors.textMuted, fontSize: 11)),
            const SizedBox(width: 6),
            Container(
              width: 14,
              height: 8,
              decoration: BoxDecoration(
                color: palette.heatmapBase,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: 4),
            Container(
              width: 14,
              height: 8,
              decoration: BoxDecoration(
                color: palette.heatmapActive,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: 6),
            Text('多', style: TextStyle(color: colors.textMuted, fontSize: 11)),
          ],
        ),
      ],
    );
  }
}

class PlayStatsPieSummary extends StatefulWidget {
  static const double _chartSize = 156;
  static const double _centerSpaceRadius = 42;
  static const double _centerBoxSize = 84;

  final List<PlayStatsDistributionBucket> buckets;
  final List<Color> palette;
  final String centerLabel;
  final String centerValue;
  final Widget? centerValueChild;
  final String Function(PlayStatsDistributionBucket bucket) labelBuilder;
  final String Function(PlayStatsDistributionBucket bucket)? valueBuilder;
  final String Function(PlayStatsDistributionBucket bucket)?
  selectedCenterValueBuilder;
  final String Function(PlayStatsDistributionBucket bucket)?
  selectedCenterDetailBuilder;

  const PlayStatsPieSummary({
    super.key,
    required this.buckets,
    required this.palette,
    required this.centerLabel,
    required this.centerValue,
    this.centerValueChild,
    required this.labelBuilder,
    this.valueBuilder,
    this.selectedCenterValueBuilder,
    this.selectedCenterDetailBuilder,
  });

  @override
  State<PlayStatsPieSummary> createState() => _PlayStatsPieSummaryState();
}

class _PlayStatsPieSummaryState extends State<PlayStatsPieSummary> {
  int? _selectedIndex;

  @override
  void didUpdateWidget(covariant PlayStatsPieSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    final visibleLength = math.min(5, widget.buckets.length);
    if (_selectedIndex != null && _selectedIndex! >= visibleLength) {
      _selectedIndex = null;
    }
  }

  void _toggleSelection(int index) {
    if (index < 0 || index >= math.min(5, widget.buckets.length)) {
      if (_selectedIndex != null) {
        setState(() {
          _selectedIndex = null;
        });
      }
      return;
    }
    setState(() {
      _selectedIndex = _selectedIndex == index ? null : index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (widget.buckets.isEmpty) {
      return const _InlineEmpty(label: '暂无分布数据');
    }
    final reportPalette = PlayStatsReportPalette.of(context);
    final visible = widget.buckets
        .take(math.min(5, widget.buckets.length))
        .toList(growable: false);
    final selectedBucket = _selectedIndex == null
        ? null
        : visible[_selectedIndex!];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        SizedBox(
          width: PlayStatsPieSummary._chartSize,
          height: PlayStatsPieSummary._chartSize,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              PieChart(
                PieChartData(
                  centerSpaceRadius: PlayStatsPieSummary._centerSpaceRadius,
                  sectionsSpace: 3,
                  startDegreeOffset: -90,
                  pieTouchData: PieTouchData(
                    enabled: true,
                    touchCallback: (event, response) {
                      if (event is! FlTapUpEvent) {
                        return;
                      }
                      final touched = response?.touchedSection;
                      if (touched == null) {
                        return;
                      }
                      final sectionIndex = touched.touchedSectionIndex;
                      if (sectionIndex < 0 || sectionIndex >= visible.length) {
                        return;
                      }
                      _toggleSelection(sectionIndex);
                    },
                  ),
                  sections: List<PieChartSectionData>.generate(visible.length, (
                    index,
                  ) {
                    final bucket = visible[index];
                    final isSelected = _selectedIndex == index;
                    return PieChartSectionData(
                      value: bucket.value.toDouble(),
                      color: widget.palette[index % widget.palette.length],
                      radius: isSelected ? 31 : 25,
                      borderSide: BorderSide(
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.95)
                            : reportPalette.divider.withValues(alpha: 0.9),
                        width: isSelected ? 2.3 : 1.4,
                      ),
                      badgeWidget: isSelected
                          ? Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: widget
                                    .palette[index % widget.palette.length],
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  width: 1.4,
                                ),
                                boxShadow: <BoxShadow>[
                                  BoxShadow(
                                    color: widget
                                        .palette[index % widget.palette.length]
                                        .withValues(alpha: 0.42),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                            )
                          : null,
                      badgePositionPercentageOffset: 1.18,
                      showTitle: false,
                    );
                  }),
                ),
                duration: const Duration(milliseconds: 360),
                curve: Curves.easeOutCubic,
              ),
              SizedBox(
                width: PlayStatsPieSummary._centerBoxSize,
                height: PlayStatsPieSummary._centerBoxSize,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeOutCubic,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.08),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: selectedBucket == null
                        ? _PieCenterContent(
                            key: const ValueKey<String>('pie-center-default'),
                            topText: widget.centerLabel,
                            topStyle: TextStyle(
                              color: colors.textMuted,
                              fontSize: 11,
                            ),
                            middle: widget.centerValueChild,
                            middleText: widget.centerValue,
                            middleStyle: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          )
                        : _PieCenterContent(
                            key: ValueKey<String>(
                              'pie-center-${selectedBucket.id}',
                            ),
                            topText: widget.labelBuilder(selectedBucket),
                            topStyle: TextStyle(
                              color: colors.accentStrong,
                              fontSize: 11.4,
                              fontWeight: FontWeight.w800,
                            ),
                            middleText:
                                widget.selectedCenterValueBuilder?.call(
                                  selectedBucket,
                                ) ??
                                widget.centerValue,
                            middleStyle: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w900,
                            ),
                            bottomText: widget.selectedCenterDetailBuilder
                                ?.call(selectedBucket),
                            bottomStyle: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 10.8,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            children: visible
                .map((bucket) {
                  final index = visible.indexOf(bucket);
                  final isSelected = _selectedIndex == index;
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: bucket == visible.last ? 0 : 10,
                    ),
                    child: InkWell(
                      onTap: () => _toggleSelection(index),
                      borderRadius: BorderRadius.circular(20),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? widget.palette[index % widget.palette.length]
                                    .withValues(alpha: 0.14)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? widget.palette[index % widget.palette.length]
                                      .withValues(alpha: 0.36)
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          children: <Widget>[
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              width: isSelected ? 14 : 10,
                              height: isSelected ? 14 : 10,
                              decoration: BoxDecoration(
                                color: widget
                                    .palette[index % widget.palette.length],
                                borderRadius: BorderRadius.circular(999),
                                boxShadow: isSelected
                                    ? <BoxShadow>[
                                        BoxShadow(
                                          color: widget
                                              .palette[index %
                                                  widget.palette.length]
                                              .withValues(alpha: 0.36),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ]
                                    : const <BoxShadow>[],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                widget.labelBuilder(bucket),
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 12.8,
                                  fontWeight: isSelected
                                      ? FontWeight.w800
                                      : FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 10),
                            AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              style: TextStyle(
                                color: isSelected
                                    ? colors.textPrimary
                                    : colors.textSecondary,
                                fontSize: isSelected ? 12.6 : 12,
                                fontWeight: isSelected
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                              ),
                              child: Text(
                                widget.valueBuilder?.call(bucket) ??
                                    '${(bucket.share * 100).toStringAsFixed(0)}%',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                })
                .toList(growable: false),
          ),
        ),
      ],
    );
  }
}

class _PieCenterContent extends StatelessWidget {
  final String topText;
  final TextStyle topStyle;
  final Widget? middle;
  final String? middleText;
  final TextStyle? middleStyle;
  final String? bottomText;
  final TextStyle? bottomStyle;

  const _PieCenterContent({
    super.key,
    required this.topText,
    required this.topStyle,
    this.middle,
    this.middleText,
    this.middleStyle,
    this.bottomText,
    this.bottomStyle,
  });

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 72, maxHeight: 72),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 68,
              child: Text(
                topText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: topStyle,
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 68,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child:
                    middle ??
                    Text(
                      middleText ?? '',
                      softWrap: false,
                      textAlign: TextAlign.center,
                      style: middleStyle,
                    ),
              ),
            ),
            if (bottomText != null &&
                bottomText!.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              SizedBox(
                width: 68,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    bottomText!,
                    softWrap: false,
                    textAlign: TextAlign.center,
                    style: bottomStyle,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class PlayStatsDistributionBars extends StatelessWidget {
  final List<PlayStatsDistributionBucket> buckets;
  final String Function(PlayStatsDistributionBucket bucket) labelBuilder;
  final String Function(PlayStatsDistributionBucket bucket)? trailingBuilder;

  const PlayStatsDistributionBars({
    super.key,
    required this.buckets,
    required this.labelBuilder,
    this.trailingBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final palette = PlayStatsReportPalette.of(context);
    final barColors = <Color>[
      palette.cyan,
      palette.amber,
      palette.coral,
      palette.mint,
      palette.violet,
      palette.blue,
      palette.rose,
    ];
    if (buckets.isEmpty) {
      return const _InlineEmpty(label: '相关元数据还在补全中');
    }
    final maxValue = buckets.fold<int>(
      0,
      (maxSoFar, item) => math.max(maxSoFar, item.value),
    );
    return Column(
      children: buckets
          .asMap()
          .entries
          .map((entry) {
            final index = entry.key;
            final bucket = entry.value;
            final ratio = maxValue <= 0 ? 0.0 : bucket.value / maxValue;
            return Padding(
              padding: EdgeInsets.only(bottom: bucket == buckets.last ? 0 : 12),
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          labelBuilder(bucket),
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        trailingBuilder?.call(bucket) ??
                            '${(bucket.share * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  PlayStatsChargedBar(
                    minHeight: 10,
                    value: ratio,
                    backgroundColor: colors.surfaceSubtle,
                    color: barColors[index % barColors.length],
                  ),
                ],
              ),
            );
          })
          .toList(growable: false),
    );
  }
}

class PlayStatsSeekComparison extends StatelessWidget {
  final int forwardSeekCount;
  final int backwardSeekCount;

  const PlayStatsSeekComparison({
    super.key,
    required this.forwardSeekCount,
    required this.backwardSeekCount,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final maxValue = math.max(forwardSeekCount, backwardSeekCount);
    if (maxValue <= 0) {
      return const _InlineEmpty(label: '本时间段几乎没有快进或回退操作');
    }
    return Column(
      children: <Widget>[
        _CompareBar(
          label: '快进',
          value: forwardSeekCount,
          maxValue: maxValue,
          color: colors.warning,
        ),
        const SizedBox(height: 12),
        _CompareBar(
          label: '回退',
          value: backwardSeekCount,
          maxValue: maxValue,
          color: colors.selectionStrong,
        ),
      ],
    );
  }
}

class PlayStatsOpEdRow extends StatelessWidget {
  final String label;
  final PlayStatsOpEdSummary summary;

  const PlayStatsOpEdRow({
    super.key,
    required this.label,
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (summary.detectedCount <= 0) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surfaceSubtle,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          '$label 暂无检测记录',
          style: TextStyle(color: colors.textSecondary, fontSize: 12.6),
        ),
      );
    }
    final skippedRatio = summary.detectedCount <= 0
        ? 0.0
        : summary.skippedCount / summary.detectedCount;
    final watchedRatio = summary.detectedCount <= 0
        ? 0.0
        : summary.watchedCount / summary.detectedCount;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceSubtle,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '检测 ${summary.detectedCount} 次 · 跳过 ${summary.skippedCount} 次',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12.2),
                ),
                const SizedBox(height: 12),
                _MiniRatioLine(
                  label: '跳过',
                  value: skippedRatio,
                  color: colors.warning,
                ),
                const SizedBox(height: 8),
                _MiniRatioLine(
                  label: '完整观看',
                  value: watchedRatio,
                  color: colors.success,
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 84,
            height: 84,
            child: PieChart(
              PieChartData(
                centerSpaceRadius: 22,
                sectionsSpace: 2,
                startDegreeOffset: -90,
                sections: <PieChartSectionData>[
                  PieChartSectionData(
                    value: summary.skippedCount.toDouble(),
                    color: colors.warning,
                    showTitle: false,
                    radius: 14,
                  ),
                  PieChartSectionData(
                    value: summary.watchedCount.toDouble(),
                    color: colors.success,
                    showTitle: false,
                    radius: 14,
                  ),
                  PieChartSectionData(
                    value: math
                        .max(
                          0,
                          summary.detectedCount -
                              summary.skippedCount -
                              summary.watchedCount,
                        )
                        .toDouble(),
                    color: colors.surfaceStrong,
                    showTitle: false,
                    radius: 14,
                  ),
                ],
              ),
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
            ),
          ),
        ],
      ),
    );
  }
}

class PlayStatsRankList extends StatelessWidget {
  final List<PlayStatsRankDisplayItem> items;

  const PlayStatsRankList({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _InlineEmpty(label: '当前没有足够的排行数据');
    }
    return Column(
      children: List<Widget>.generate(items.length, (index) {
        final item = items[index];
        return _RankTile(
          rank: index + 1,
          title: item.title,
          subtitle: item.subtitle,
          trailing: item.trailing,
          onTap: item.onTap,
          isLast: index == items.length - 1,
        );
      }),
    );
  }
}

class PlayStatsTimelineList extends StatelessWidget {
  final List<PlayHistoryRecord> items;
  final PlayStatsReportFormatters formatters;

  const PlayStatsTimelineList({
    super.key,
    required this.items,
    required this.formatters,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (items.isEmpty) {
      return const _InlineEmpty(label: '最近还没有新的观看记录');
    }
    return Column(
      children: List<Widget>.generate(items.length, (index) {
        final item = items[index];
        final isLast = index == items.length - 1;
        return Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Column(
                children: <Widget>[
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colors.accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  if (!isLast)
                    Container(width: 2, height: 48, color: colors.borderSubtle),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.surfaceSubtle,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        item.title.trim().isEmpty ? '未命名视频' : item.title,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        formatters.historySubtitle(item),
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

int _pickDurationAxisStepMs(int maxY) {
  const candidates = <int>[
    5 * 1000,
    10 * 1000,
    15 * 1000,
    30 * 1000,
    60 * 1000,
    2 * 60 * 1000,
    3 * 60 * 1000,
    5 * 60 * 1000,
    10 * 60 * 1000,
    15 * 60 * 1000,
    20 * 60 * 1000,
    30 * 60 * 1000,
    45 * 60 * 1000,
    60 * 60 * 1000,
  ];

  final target = maxY <= 0 ? 1 : (maxY / 3).ceil();
  for (final candidate in candidates) {
    if (candidate >= target) {
      return candidate;
    }
  }
  return candidates.last;
}

class PlayStatsPagedTimelineList extends StatefulWidget {
  final List<PlayHistoryRecord> items;
  final PlayStatsReportFormatters formatters;
  final int pageSize;

  const PlayStatsPagedTimelineList({
    super.key,
    required this.items,
    required this.formatters,
    this.pageSize = 6,
  });

  @override
  State<PlayStatsPagedTimelineList> createState() =>
      _PlayStatsPagedTimelineListState();
}

class _PlayStatsPagedTimelineListState
    extends State<PlayStatsPagedTimelineList> {
  int _pageIndex = 0;

  int get _pageCount {
    if (widget.items.isEmpty) {
      return 0;
    }
    return (widget.items.length / widget.pageSize).ceil();
  }

  @override
  void didUpdateWidget(covariant PlayStatsPagedTimelineList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pageCount = _pageCount;
    if (_pageIndex >= pageCount) {
      _pageIndex = pageCount <= 0 ? 0 : pageCount - 1;
    }
  }

  Future<void> _pickPage() async {
    if (_pageCount <= 1) {
      return;
    }
    final controller = TextEditingController(text: '${_pageIndex + 1}');
    final selectedIndex = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final colors = sheetContext.appColors;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '跳转页码',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '输入 1 到 $_pageCount 之间的页码',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12.6),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: '页码',
                    hintText: '例如 ${_pageIndex + 1}',
                    isDense: true,
                    filled: true,
                    fillColor: colors.surfaceSubtle,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onSubmitted: (value) {
                    final page = int.tryParse(value);
                    if (page == null) {
                      return;
                    }
                    final targetIndex = (page - 1).clamp(0, _pageCount - 1);
                    Navigator.of(sheetContext).pop(targetIndex);
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      child: const Text('取消'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () {
                        final page = int.tryParse(controller.text);
                        if (page == null) {
                          Navigator.of(sheetContext).pop();
                          return;
                        }
                        final targetIndex = (page - 1).clamp(0, _pageCount - 1);
                        Navigator.of(sheetContext).pop(targetIndex);
                      },
                      child: const Text('跳转'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    controller.dispose();
    if (selectedIndex == null || !mounted) {
      return;
    }
    setState(() {
      _pageIndex = selectedIndex;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (widget.items.isEmpty) {
      return const _InlineEmpty(label: '最近还没有新的观看记录');
    }
    final pageItems = widget.items
        .skip(_pageIndex * widget.pageSize)
        .take(widget.pageSize)
        .toList(growable: false);
    return Column(
      children: <Widget>[
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Column(
            key: ValueKey<int>(_pageIndex),
            children: List<Widget>.generate(pageItems.length, (index) {
              final item = pageItems[index];
              final isLast = index == pageItems.length - 1;
              return Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
                child: _TimelineEventTile(
                  item: item,
                  formatters: widget.formatters,
                ),
              );
            }),
          ),
        ),
        if (_pageCount > 1) ...<Widget>[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            decoration: BoxDecoration(
              color: colors.surfaceSubtle,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: colors.borderSubtle),
                      ),
                      child: Text(
                        '第 ${_pageIndex + 1} / $_pageCount 页',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 12.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_pageIndex * widget.pageSize + 1}-${math.min(widget.items.length, (_pageIndex + 1) * widget.pageSize)} / ${widget.items.length}',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 11.8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      key: const Key('play-stats-history-page-picker'),
                      onTap: _pickPage,
                      borderRadius: BorderRadius.circular(999),
                      child: Ink(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: colors.accentSoft.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: colors.accent.withValues(alpha: 0.24),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              Icons.edit_rounded,
                              size: 14,
                              color: colors.textPrimary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '跳页',
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 11.8,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _TimelinePagerWideButton(
                        key: const Key('play-stats-history-first-page'),
                        label: '第一页',
                        icon: Icons.first_page_rounded,
                        enabled: _pageIndex > 0,
                        onTap: () => setState(() => _pageIndex = 0),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _TimelinePagerWideButton(
                        key: const Key('play-stats-history-prev-page'),
                        label: '上一页',
                        icon: Icons.chevron_left_rounded,
                        enabled: _pageIndex > 0,
                        onTap: () => setState(() => _pageIndex -= 1),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _TimelinePagerWideButton(
                        key: const Key('play-stats-history-next-page'),
                        label: '下一页',
                        icon: Icons.chevron_right_rounded,
                        enabled: _pageIndex < _pageCount - 1,
                        onTap: () => setState(() => _pageIndex += 1),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _TimelinePagerWideButton(
                        key: const Key('play-stats-history-last-page'),
                        label: '最后页',
                        icon: Icons.last_page_rounded,
                        enabled: _pageIndex < _pageCount - 1,
                        onTap: () =>
                            setState(() => _pageIndex = _pageCount - 1),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _TimelineEventTile extends StatelessWidget {
  final PlayHistoryRecord item;
  final PlayStatsReportFormatters formatters;

  const _TimelineEventTile({required this.item, required this.formatters});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Column(
          children: <Widget>[
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: colors.accent,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Container(width: 2, height: 74, color: colors.borderSubtle),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.surfaceSubtle,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.title.trim().isEmpty ? '未命名视频' : item.title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  formatters.historyContext(item),
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12.2,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formatters.historyMeta(item),
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 11.6,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TimelinePagerWideButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _TimelinePagerWideButton({
    super.key,
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 70;
        final foregroundColor = enabled ? colors.textPrimary : colors.textMuted;
        return InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            height: 36,
            padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 10),
            decoration: BoxDecoration(
              color: enabled ? colors.surface : colors.surfaceStrong,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: enabled ? colors.accentSoft : colors.borderSubtle,
              ),
            ),
            child: Center(
              child: compact
                  ? Icon(icon, size: 17, color: foregroundColor)
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(icon, size: 16, color: foregroundColor),
                          const SizedBox(width: 4),
                          Text(
                            label,
                            style: TextStyle(
                              color: foregroundColor,
                              fontSize: 11.6,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}

class PlayStatsContinueWatchingStrip extends StatefulWidget {
  final List<PlayStatsContinueWatchingItem> items;
  final PlayStatsReportFormatters formatters;

  const PlayStatsContinueWatchingStrip({
    super.key,
    required this.items,
    required this.formatters,
  });

  @override
  State<PlayStatsContinueWatchingStrip> createState() =>
      _PlayStatsContinueWatchingStripState();
}

class _PlayStatsContinueWatchingStripState
    extends State<PlayStatsContinueWatchingStrip> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(keepScrollOffset: false);
  }

  @override
  void didUpdateWidget(covariant PlayStatsContinueWatchingStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_signature(oldWidget.items) != _signature(widget.items)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) {
          return;
        }
        _scrollController.jumpTo(0);
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _signature(List<PlayStatsContinueWatchingItem> items) {
    return items
        .map(
          (item) => '${item.videoId}:${item.lastPlayedAtMs}:${item.progress}',
        )
        .join('|');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (widget.items.isEmpty) {
      return const _InlineEmpty(label: '目前没有适合继续观看的内容');
    }
    return SizedBox(
      height: 156,
      child: ScrollConfiguration(
        behavior: const _NoOverscrollScrollBehavior(),
        child: ListView.separated(
          controller: _scrollController,
          dragStartBehavior: DragStartBehavior.down,
          physics: const ClampingScrollPhysics(),
          scrollDirection: Axis.horizontal,
          itemBuilder: (context, index) {
            final item = widget.items[index];
            return Container(
              width: 212,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surfaceSubtle,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: colors.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.title.trim().isEmpty ? '未命名视频' : item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.formatters.continueWatchingSubtitle(item),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12.2,
                      height: 1.4,
                    ),
                  ),
                  const Spacer(),
                  PlayStatsChargedBar(
                    minHeight: 8,
                    value: item.progress,
                    backgroundColor: colors.surfaceStrong,
                    color: colors.accent,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '上次观看 ${widget.formatters.dateTime(item.lastPlayedAtMs)}',
                    style: TextStyle(color: colors.textMuted, fontSize: 11.5),
                  ),
                ],
              ),
            );
          },
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemCount: widget.items.length,
        ),
      ),
    );
  }
}

class _NoOverscrollScrollBehavior extends ScrollBehavior {
  const _NoOverscrollScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

class PlayStatsEmptyState extends StatelessWidget {
  const PlayStatsEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        children: <Widget>[
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: colors.accentSoft.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(Icons.insights_rounded, color: colors.accent, size: 30),
          ),
          const SizedBox(height: 16),
          Text(
            '还没有可展示的观影战报',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '开始播放内容后，这里会自动生成趋势、偏好、行为和回看报表。',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 13,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroStatBadge extends StatelessWidget {
  final String label;
  final String value;
  final Widget? valueChild;

  const _HeroStatBadge({
    required this.label,
    required this.value,
    this.valueChild,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.64),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        children: <Widget>[
          Text(
            label,
            style: TextStyle(color: colors.textMuted, fontSize: 10.5),
          ),
          const SizedBox(height: 2),
          valueChild ??
              Text(
                value,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final String label;
  final String value;
  final Color tone;
  final String? infoTitle;
  final String? infoDescription;
  final String? infoDetail;
  final Widget? valueChild;

  const _MetricPill({
    required this.label,
    required this.value,
    required this.tone,
    this.infoTitle,
    this.infoDescription,
    this.infoDetail,
    this.valueChild,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tone.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Wrap(
            spacing: 3,
            runSpacing: 3,
            children: <Widget>[
              Text(
                label,
                style: TextStyle(color: colors.textMuted, fontSize: 11.3),
              ),
              if (infoTitle != null && infoDescription != null) ...<Widget>[
                AppInfoPopoverAnchor(
                  title: infoTitle!,
                  description: infoDescription!,
                  detail: infoDetail,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: colors.surfaceStrong.withValues(alpha: 0.44),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: tone.withValues(alpha: 0.2)),
                    ),
                    child: Icon(
                      Icons.info_outline_rounded,
                      size: 11,
                      color: colors.textMuted,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          valueChild ??
              Text(
                value,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14.4,
                  fontWeight: FontWeight.w800,
                ),
              ),
        ],
      ),
    );
  }
}

class PlayStatsAnimatedMetricText extends StatefulWidget {
  final double value;
  final String Function(double value) builder;
  final TextStyle style;
  final Duration duration;
  final double pulseScale;

  const PlayStatsAnimatedMetricText({
    super.key,
    required this.value,
    required this.builder,
    required this.style,
    this.duration = const Duration(milliseconds: 420),
    this.pulseScale = 1.0,
  });

  @override
  State<PlayStatsAnimatedMetricText> createState() =>
      _PlayStatsAnimatedMetricTextState();
}

class _PlayStatsAnimatedMetricTextState
    extends State<PlayStatsAnimatedMetricText> {
  late double _beginValue;

  @override
  void initState() {
    super.initState();
    _beginValue = widget.value;
  }

  @override
  void didUpdateWidget(covariant PlayStatsAnimatedMetricText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _beginValue = oldWidget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: _beginValue, end: widget.value),
      duration: widget.duration,
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, _) {
        return Text(widget.builder(animatedValue), style: widget.style);
      },
    );
  }
}

class _CompareBar extends StatelessWidget {
  final String label;
  final int value;
  final int maxValue;
  final Color color;

  const _CompareBar({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final ratio = maxValue <= 0 ? 0.0 : value / maxValue;
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              '$value 次',
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 8),
        PlayStatsChargedBar(
          minHeight: 10,
          value: ratio,
          backgroundColor: colors.surfaceSubtle,
          color: color,
        ),
      ],
    );
  }
}

class _MiniRatioLine extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _MiniRatioLine({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      children: <Widget>[
        SizedBox(
          width: 56,
          child: Text(
            label,
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
        ),
        Expanded(
          child: PlayStatsChargedBar(
            minHeight: 8,
            value: value,
            backgroundColor: colors.surfaceStrong,
            color: color,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '${(value * 100).toStringAsFixed(0)}%',
          style: TextStyle(color: colors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }
}

class _RankTile extends StatelessWidget {
  final int rank;
  final String title;
  final String subtitle;
  final String trailing;
  final VoidCallback? onTap;
  final bool isLast;

  const _RankTile({
    required this.rank,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final topBadgeColor = switch (rank) {
      1 => const Color(0xFFFFC94D),
      2 => const Color(0xFFD7DEE8),
      3 => const Color(0xFFD78A4A),
      _ => null,
    };
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.surfaceSubtle,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 36,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: rank <= 3
                              ? colors.accent.withValues(alpha: 0.18)
                              : colors.surfaceStrong,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$rank',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (topBadgeColor != null)
                        Positioned(
                          left: -3,
                          top: -6,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: colors.backgroundBase.withValues(
                                alpha: 0.92,
                              ),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: topBadgeColor.withValues(alpha: 0.42),
                              ),
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: topBadgeColor.withValues(alpha: 0.26),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.workspace_premium_outlined,
                              size: 10,
                              color: topBadgeColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 13.4,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  trailing,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (onTap != null) ...<Widget>[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: colors.textMuted,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  final String label;

  const _InlineEmpty({required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceSubtle,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        label,
        style: TextStyle(color: colors.textSecondary, fontSize: 12.8),
      ),
    );
  }
}

class PlayStatsRankDisplayItem {
  final String title;
  final String subtitle;
  final String trailing;
  final VoidCallback? onTap;

  const PlayStatsRankDisplayItem({
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
  });
}

List<PlayStatsRankDisplayItem> animeRankItems(
  List<PlayStatsTopAnime> items,
  PlayStatsReportFormatters formatters, {
  VoidCallback? Function(PlayStatsTopAnime item)? onTapBuilder,
}) {
  return items
      .map(
        (item) => PlayStatsRankDisplayItem(
          title: item.title.trim().isEmpty ? '未命名剧集' : item.title,
          subtitle: '观看 ${item.sessionCount} 次 · 完整观看 ${item.viewCount} 次',
          trailing: formatters.duration(item.playedMs, compact: true),
          onTap: onTapBuilder?.call(item),
        ),
      )
      .toList(growable: false);
}

List<PlayStatsRankDisplayItem> videoRankItems(
  List<PlayStatsTopVideo> items,
  PlayStatsReportFormatters formatters, {
  VoidCallback? Function(PlayStatsTopVideo item)? onTapBuilder,
}) {
  return items
      .map(
        (item) => PlayStatsRankDisplayItem(
          title: item.title.trim().isEmpty ? '未命名视频' : item.title,
          subtitle: formatters.topVideoSubtitle(item),
          trailing: formatters.duration(item.playedMs, compact: true),
          onTap: onTapBuilder?.call(item),
        ),
      )
      .toList(growable: false);
}

List<PlayStatsRankDisplayItem> affinityRankItems(
  List<PlayStatsAffinityPerson> items,
  PlayStatsReportFormatters formatters, {
  VoidCallback? Function(PlayStatsAffinityPerson item)? onTapBuilder,
}) {
  return items
      .map(
        (item) => PlayStatsRankDisplayItem(
          title: item.name.trim().isEmpty ? '未知人物' : item.name,
          subtitle: formatters.affinitySubtitle(item),
          trailing: '${item.appearanceCount} 次',
          onTap: onTapBuilder?.call(item),
        ),
      )
      .toList(growable: false);
}
