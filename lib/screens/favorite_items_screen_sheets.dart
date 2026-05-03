part of 'favorite_items_screen.dart';

extension _FavoriteItemsScreenSheets on _FavoriteItemsScreenState {
  Future<void> _openSortSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF141C29),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  _t('layout.list.sort.title', 'Sort'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                for (final column in _FavoriteItemsScreenState._sortColumns)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    minVerticalPadding: 0,
                    visualDensity: const VisualDensity(vertical: -1),
                    title: Text(
                      _sortLabelFor(column),
                      style: TextStyle(
                        color: column == _sortColumn
                            ? Colors.white
                            : Colors.white70,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                    trailing: column == _sortColumn
                        ? Text(
                            _sortType == 'ASC'
                                ? '${_t('layout.list.sort.sortType.asc', 'Ascending')} ↕'
                                : '${_t('layout.list.sort.sortType.desc', 'Descending')} ↕',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          )
                        : null,
                    onTap: () async {
                      if (column == _sortColumn) {
                        _sortType = _sortType == 'ASC' ? 'DESC' : 'ASC';
                      } else {
                        _sortColumn = column;
                        _sortType = 'DESC';
                      }
                      Navigator.of(context).pop();
                      await FeiniuApi(
                        context.read<NasProvider>(),
                      ).setUserListSetting(
                        '',
                        sortField: _sortColumn,
                        sortType: _sortType,
                        viewType: _viewType.storageValue,
                        key: _favoriteListSettingKey,
                      );
                      _reloadAfterQueryChanged();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openFilterSheet() async {
    final tempMediaTypes = Set<dynamic>.from(_selectedMediaTypes);
    final tempGenres = Set<dynamic>.from(_selectedGenres);
    final tempLocate = Set<dynamic>.from(_selectedLocate);
    final tempDecades = Set<dynamic>.from(_selectedDecades);
    final tempResolutions = Set<dynamic>.from(_selectedResolutions);
    final tempColorRange = Set<dynamic>.from(_selectedColorRange);
    final tempAudioType = Set<dynamic>.from(_selectedAudioType);
    final tempRecognition = Set<dynamic>.from(_selectedRecognitionStatus);
    final tempWatched = Set<dynamic>.from(_selectedWatched);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141C29),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModal) {
            Widget chip(String label, bool selected, VoidCallback onTap) {
              return GestureDetector(
                onTap: onTap,
                child: Container(
                  margin: const EdgeInsets.only(right: 8, bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF0D4CA3)
                        : const Color(0xFF1D2735),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white70,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            }

            Widget section(
              String title,
              List<dynamic> values,
              Set<dynamic> selected,
              String Function(dynamic) labeler,
            ) {
              if (values.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    children: <Widget>[
                      chip(
                        _t('layout.list.filter.all', 'All'),
                        selected.isEmpty,
                        () => setModal(() => selected.clear()),
                      ),
                      for (final value in values)
                        chip(
                          labeler(value),
                          selected.contains(value),
                          () => setModal(() {
                            if (selected.contains(value)) {
                              selected.clear();
                            } else {
                              selected
                                ..clear()
                                ..add(value);
                            }
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              );
            }

            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.78,
                  child: Column(
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const Spacer(),
                          Text(
                            _t('layout.list.filter.filterButton', 'Filter'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                      Expanded(
                        child: ListView(
                          children: <Widget>[
                            section(
                              _t(
                                'layout.list.filter.tagMap.type',
                                'Media type',
                              ),
                              _selectedTab == _FavoriteTab.all
                                  ? const <String>['Movie', 'TV']
                                  : const <String>[],
                              tempMediaTypes,
                              _mediaTypeLabel,
                            ),
                            section(
                              _t('layout.list.filter.tagMap.genres', 'Genre'),
                              _tagOptions['genres'] ?? const <dynamic>[],
                              tempGenres,
                              _genreLabel,
                            ),
                            section(
                              _t(
                                'layout.list.filter.tagMap.locate',
                                'Country and region',
                              ),
                              _tagOptions['locate'] ?? const <dynamic>[],
                              tempLocate,
                              _locateLabel,
                            ),
                            section(
                              _t(
                                'layout.list.filter.tagMap.decade',
                                'Release year',
                              ),
                              _tagOptions['decades'] ?? const <dynamic>[],
                              tempDecades,
                              _decadeLabel,
                            ),
                            section(
                              _t(
                                'layout.list.filter.tagMap.resolution',
                                'Resolution',
                              ),
                              _tagOptions['resolutions'] ?? const <dynamic>[],
                              tempResolutions,
                              (value) => _resolutionLabel('$value'),
                            ),
                            section(
                              _t(
                                'layout.list.filter.tagMap.color_range',
                                'Video range',
                              ),
                              _tagOptions['color_range'] ?? const <dynamic>[],
                              tempColorRange,
                              (value) => '$value',
                            ),
                            section(
                              _t(
                                'layout.list.filter.tagMap.audio_type',
                                'Audio spec',
                              ),
                              _tagOptions['audio_type'] ?? const <dynamic>[],
                              tempAudioType,
                              _audioLabel,
                            ),
                            section(
                              _t(
                                'layout.list.filter.tagMap.recognition_status',
                                'Match status',
                              ),
                              _tagOptions['recognition_status'] ??
                                  const <dynamic>[],
                              tempRecognition,
                              _recognitionStatusLabel,
                            ),
                            section(
                              _t(
                                'layout.list.filter.tagMap.watched',
                                'Watched status',
                              ),
                              const <int>[1, 0],
                              tempWatched,
                              _watchedLabel,
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setModal(() {
                                  tempMediaTypes.clear();
                                  tempGenres.clear();
                                  tempLocate.clear();
                                  tempDecades.clear();
                                  tempResolutions.clear();
                                  tempColorRange.clear();
                                  tempAudioType.clear();
                                  tempRecognition.clear();
                                  tempWatched.clear();
                                });
                              },
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                  color: Color(0x334F6B8F),
                                ),
                                foregroundColor: Colors.white70,
                                minimumSize: const Size.fromHeight(44),
                              ),
                              child: Text(
                                _t('layout.list.filter.resetButton', 'Reset'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                _setStateIfMounted(() {
                                  _selectedMediaTypes = tempMediaTypes;
                                  _selectedGenres = tempGenres;
                                  _selectedLocate = tempLocate;
                                  _selectedDecades = tempDecades;
                                  _selectedResolutions = tempResolutions;
                                  _selectedColorRange = tempColorRange;
                                  _selectedAudioType = tempAudioType;
                                  _selectedRecognitionStatus = tempRecognition;
                                  _selectedWatched = tempWatched;
                                });
                                _reloadAfterQueryChanged();
                              },
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(44),
                              ),
                              child: Text(
                                _t('common.actions.default.default', 'Confirm'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
