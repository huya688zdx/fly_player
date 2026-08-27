import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/models/tv_episode_browser_models.dart';
import 'package:fly_player/models/tv_episode_picker_mode.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/widgets/detail/tv_episode_browser_section.dart';

void main() {
  testWidgets('选集预览初次显示时滚动到选中的集数', (tester) async {
    final episodes = List<TvEpisodeCardData>.generate(
      9,
      (index) => TvEpisodeCardData(
        guid: 'episode-${index + 1}',
        shortLabel: '${index + 1}',
        title: '${index + 1}.测试',
        summary: '',
        durationText: '24 分钟',
        statusLabel: '',
        imageUrls: const <String>[],
        resolutions: const <String>[],
        selected: index == 8,
        playing: false,
        completed: false,
        progress: 0,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.build(AppThemePreset.midnight),
        home: Scaffold(
          body: SizedBox(
            width: 390,
            child: TvEpisodeBrowserSection(
              title: '选集',
              totalLabel: '共 9 集',
              seasons: const <TvEpisodeSeasonOptionData>[],
              episodes: episodes,
              selectedRangeIndex: 0,
              rangeSize: 30,
              previewCount: 4,
              emptyText: '暂无',
              detailText: '详情',
              token: '',
              accessCode: '',
              baseUrl: '',
              mode: TvEpisodePickerMode.list,
              onSeasonSelected: (_) {},
              onRangeSelected: (_) {},
              onEpisodeSelected: (_) {},
              onEpisodeLongPress: (_) {},
              onEpisodeDetailTap: (_) {},
              onOpenPicker: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    expect(position.pixels, greaterThan(0));
  });
}
