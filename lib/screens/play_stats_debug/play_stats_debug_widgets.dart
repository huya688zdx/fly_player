import 'package:flutter/material.dart';

import '../../services/play_stats/play_stats.dart';
import '../../theme/app_theme.dart';
import 'play_stats_debug_formatters.dart';

class PlayStatsDebugSectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const PlayStatsDebugSectionCard({
    super.key,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class PlayStatsDebugEntryTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const PlayStatsDebugEntryTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.surfaceSubtle,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: colors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class PlayStatsDebugFieldLine extends StatelessWidget {
  final String label;
  final String value;
  final bool isLast;

  const PlayStatsDebugFieldLine({
    super.key,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: colors.borderSubtle.withValues(alpha: 0.8),
                ),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: TextStyle(color: colors.textSecondary, fontSize: 12.5),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value.trim().isEmpty ? '-' : value,
              style: TextStyle(color: colors.textPrimary, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

Widget buildDebugRows(List<PlayStatsDebugRowData> rows) {
  return Column(
    children: List<Widget>.generate(rows.length, (index) {
      final row = rows[index];
      return PlayStatsDebugFieldLine(
        label: row.label,
        value: row.value,
        isLast: index == rows.length - 1,
      );
    }),
  );
}

class PlayStatsDebugCreditList extends StatelessWidget {
  final List<PlayStatsCredit> credits;

  const PlayStatsDebugCreditList({super.key, required this.credits});

  @override
  Widget build(BuildContext context) {
    if (credits.isEmpty) {
      return const Text('当前没有记录到演职人员快照。');
    }
    return Column(
      children: credits
          .map(
            (credit) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.appColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(12),
              ),
              child: buildDebugRows(<PlayStatsDebugRowData>[
                PlayStatsDebugRowData('人员 ID', credit.personId),
                PlayStatsDebugRowData('姓名', credit.name),
                PlayStatsDebugRowData('角色', credit.role),
                PlayStatsDebugRowData('工种', credit.job),
                PlayStatsDebugRowData('排序', '${credit.order}'),
              ]),
            ),
          )
          .toList(growable: false),
    );
  }
}

class PlayStatsDebugCreditCarousel extends StatefulWidget {
  final List<PlayStatsCredit> credits;

  const PlayStatsDebugCreditCarousel({super.key, required this.credits});

  @override
  State<PlayStatsDebugCreditCarousel> createState() =>
      _PlayStatsDebugCreditCarouselState();
}

class _PlayStatsDebugCreditCarouselState
    extends State<PlayStatsDebugCreditCarousel> {
  late final PageController _controller;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 0.92);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.credits.isEmpty) {
      return const Text('当前没有记录到演职人员快照。');
    }
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 6,
          children: List<Widget>.generate(widget.credits.length, (index) {
            final active = index == _currentIndex;
            return GestureDetector(
              onTap: () {
                _controller.animateToPage(
                  index,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: active ? 18 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: active
                      ? colors.accent
                      : colors.textMuted.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 248,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.credits.length,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemBuilder: (context, index) {
              final credit = widget.credits[index];
              return Padding(
                padding: EdgeInsets.only(
                  right: index == widget.credits.length - 1 ? 0 : 10,
                ),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.surfaceSubtle,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: SingleChildScrollView(
                    child: buildDebugRows(<PlayStatsDebugRowData>[
                      PlayStatsDebugRowData('人员 ID', credit.personId),
                      PlayStatsDebugRowData('姓名', credit.name),
                      PlayStatsDebugRowData('角色', credit.role),
                      PlayStatsDebugRowData('工种', credit.job),
                      PlayStatsDebugRowData('排序', '${credit.order}'),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class PlayStatsDebugHistoryPager extends StatefulWidget {
  final List<PlayHistoryRecord> items;
  final PlayStatsDebugFormatters formatters;
  final Widget Function(BuildContext context, PlayHistoryRecord item)
  itemBuilder;
  final int pageSize;

  const PlayStatsDebugHistoryPager({
    super.key,
    required this.items,
    required this.formatters,
    required this.itemBuilder,
    this.pageSize = 6,
  });

  @override
  State<PlayStatsDebugHistoryPager> createState() =>
      _PlayStatsDebugHistoryPagerState();
}

class _PlayStatsDebugHistoryPagerState
    extends State<PlayStatsDebugHistoryPager> {
  int _currentPage = 0;

  int get _pageCount => (widget.items.length / widget.pageSize).ceil();

  List<PlayHistoryRecord> get _currentItems {
    final start = _currentPage * widget.pageSize;
    final end = (start + widget.pageSize > widget.items.length)
        ? widget.items.length
        : start + widget.pageSize;
    return widget.items.sublist(start, end);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const SizedBox.shrink();
    }
    final children = _currentItems
        .map((item) => widget.itemBuilder(context, item))
        .toList(growable: false);
    if (_pageCount <= 1) {
      return Column(children: children);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _PlayStatsDebugPaginator(
          currentPage: _currentPage,
          pageCount: _pageCount,
          onPrevious: _currentPage == 0
              ? null
              : () => setState(() => _currentPage -= 1),
          onNext: _currentPage >= _pageCount - 1
              ? null
              : () => setState(() => _currentPage += 1),
          onSelectPage: (page) => setState(() => _currentPage = page),
        ),
        const SizedBox(height: 12),
        Column(children: children),
      ],
    );
  }
}

class _PlayStatsDebugPaginator extends StatelessWidget {
  final int currentPage;
  final int pageCount;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final ValueChanged<int> onSelectPage;

  const _PlayStatsDebugPaginator({
    required this.currentPage,
    required this.pageCount,
    required this.onPrevious,
    required this.onNext,
    required this.onSelectPage,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '第 ${currentPage + 1} 页 / 共 $pageCount 页',
          style: TextStyle(color: colors.textSecondary, fontSize: 12.5),
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            OutlinedButton(onPressed: onPrevious, child: const Text('上一页')),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: onNext, child: const Text('下一页')),
            const SizedBox(width: 12),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Wrap(
                  spacing: 8,
                  children: List<Widget>.generate(pageCount, (index) {
                    final selected = index == currentPage;
                    return ChoiceChip(
                      label: Text('${index + 1}'),
                      selected: selected,
                      onSelected: (_) => onSelectPage(index),
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
