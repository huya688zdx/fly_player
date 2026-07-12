part of 'favorite_items_screen.dart';

extension _FavoriteItemsScreenSheets on _FavoriteItemsScreenState {
  Future<void> _openSortSheet() async {
    final nasProvider = context.read<NasProvider>();
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
                  AppLocalizations.of(context).listSortTitle,
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
                                ? '${AppLocalizations.of(context).listSortAsc} ↕'
                                : '${AppLocalizations.of(context).listSortDesc} ↕',
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
                      if (_isFeiniuBackend) {
                        await FeiniuApi(nasProvider).setUserListSetting(
                          '',
                          sortField: _sortColumn,
                          sortType: _sortType,
                          viewType: _viewType.storageValue,
                          key: _favoriteListSettingKey,
                        );
                      }
                      if (!mounted) return;
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
                        AppLocalizations.of(context).listFilterAll,
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
                            AppLocalizations.of(context).listFilterButton,
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
                              AppLocalizations.of(context).listFilterType,
                              _selectedTab == _FavoriteTab.all
                                  ? const <String>['Movie', 'TV']
                                  : const <String>[],
                              tempMediaTypes,
                              _mediaTypeLabel,
                            ),
                            section(
                              AppLocalizations.of(context).listFilterGenres,
                              _tagOptions['genres'] ?? const <dynamic>[],
                              tempGenres,
                              _genreLabel,
                            ),
                            section(
                              AppLocalizations.of(context).listFilterLocate,
                              _tagOptions['locate'] ?? const <dynamic>[],
                              tempLocate,
                              _locateLabel,
                            ),
                            section(
                              AppLocalizations.of(context).listFilterDecade,
                              _tagOptions['decades'] ?? const <dynamic>[],
                              tempDecades,
                              _decadeLabel,
                            ),
                            section(
                              AppLocalizations.of(context).listFilterResolution,
                              _tagOptions['resolutions'] ?? const <dynamic>[],
                              tempResolutions,
                              (value) => _resolutionLabel('$value'),
                            ),
                            section(
                              AppLocalizations.of(context).listFilterColorRange,
                              _tagOptions['color_range'] ?? const <dynamic>[],
                              tempColorRange,
                              (value) => '$value',
                            ),
                            section(
                              AppLocalizations.of(context).listFilterAudioType,
                              _tagOptions['audio_type'] ?? const <dynamic>[],
                              tempAudioType,
                              _audioLabel,
                            ),
                            section(
                              AppLocalizations.of(
                                context,
                              ).listFilterRecognitionStatus,
                              _tagOptions['recognition_status'] ??
                                  const <dynamic>[],
                              tempRecognition,
                              _recognitionStatusLabel,
                            ),
                            section(
                              AppLocalizations.of(context).listFilterWatched,
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
                                AppLocalizations.of(
                                  context,
                                ).listFilterResetButton,
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
                                AppLocalizations.of(context).commonConfirm,
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
