part of 'favorite_items_screen.dart';

extension _FavoriteItemsScreenSheets on _FavoriteItemsScreenState {
  Future<void> _openSortSheet() async {
    final result = await AppCatalogSortSheet.show(
      context,
      options: <AppCatalogSortOption>[
        for (final column in _FavoriteItemsScreenState._sortColumns)
          AppCatalogSortOption(field: column, label: _sortLabelFor(column)),
      ],
      selectedField: _sortColumn,
      sortType: _sortType,
    );
    if (!mounted || result == null) return;
    await _applySortSelection(field: result.field, type: result.sortType);
  }

  List<AppCatalogFilterSection> _buildFilterSections() {
    final l10n = AppLocalizations.of(context);

    AppCatalogFilterSection? section(
      String key,
      String title,
      List<dynamic> values,
      Set<dynamic> selected,
      String Function(dynamic) labeler,
    ) {
      if (values.isEmpty) return null;
      return AppCatalogFilterSection(
        key: key,
        title: title,
        options: <AppCatalogFilterOption>[
          for (final value in values)
            AppCatalogFilterOption(value: value, label: labeler(value)),
        ],
        selectedValues: Set<Object>.from(selected),
      );
    }

    final candidates = <AppCatalogFilterSection?>[
      section(
        'type',
        l10n.listFilterType,
        _selectedTab == _FavoriteTab.all
            ? const <String>['Movie', 'TV']
            : const <String>[],
        _selectedMediaTypes,
        _mediaTypeLabel,
      ),
      section(
        'genres',
        l10n.listFilterGenres,
        _tagOptions['genres'] ?? const <dynamic>[],
        _selectedGenres,
        _genreLabel,
      ),
      section(
        'locate',
        l10n.listFilterLocate,
        _tagOptions['locate'] ?? const <dynamic>[],
        _selectedLocate,
        _locateLabel,
      ),
      section(
        'decades',
        l10n.listFilterDecade,
        _tagOptions['decades'] ?? const <dynamic>[],
        _selectedDecades,
        _decadeLabel,
      ),
      section(
        'resolutions',
        l10n.listFilterResolution,
        _tagOptions['resolutions'] ?? const <dynamic>[],
        _selectedResolutions,
        (value) => _resolutionLabel('$value'),
      ),
      section(
        'color_range',
        l10n.listFilterColorRange,
        _tagOptions['color_range'] ?? const <dynamic>[],
        _selectedColorRange,
        (value) => '$value',
      ),
      section(
        'audio_type',
        l10n.listFilterAudioType,
        _tagOptions['audio_type'] ?? const <dynamic>[],
        _selectedAudioType,
        _audioLabel,
      ),
      section(
        'recognition_status',
        l10n.listFilterRecognitionStatus,
        _tagOptions['recognition_status'] ?? const <dynamic>[],
        _selectedRecognitionStatus,
        _recognitionStatusLabel,
      ),
      section(
        'watched',
        l10n.listFilterWatched,
        const <int>[1, 0],
        _selectedWatched,
        _watchedLabel,
      ),
    ];

    return candidates.whereType<AppCatalogFilterSection>().toList();
  }

  Future<void> _openFilterSheet() async {
    await _loadFilterMetadata();
    if (!mounted) return;
    if (DesktopEnvironment.isDesktopPlatform) {
      _setStateIfMounted(() {
        _filterDraft = _filterDraft == null
            ? {
                for (final section in _buildFilterSections())
                  section.key: Set<Object>.from(section.selectedValues),
              }
            : null;
      });
      return;
    }
    final result = await AppCatalogFilterSheet.show(
      context,
      sections: _buildFilterSections(),
    );
    if (!mounted || result == null) return;
    _applyFilterSelection(result);
  }

  void _applyFilterSelection(Map<String, Set<Object>> result) {
    Set<dynamic> valuesFor(String key) =>
        Set<dynamic>.from(result[key] ?? const <Object>{});
    _setStateIfMounted(() {
      _selectedMediaTypes = valuesFor('type');
      _selectedGenres = valuesFor('genres');
      _selectedLocate = valuesFor('locate');
      _selectedDecades = valuesFor('decades');
      _selectedResolutions = valuesFor('resolutions');
      _selectedColorRange = valuesFor('color_range');
      _selectedAudioType = valuesFor('audio_type');
      _selectedRecognitionStatus = valuesFor('recognition_status');
      _selectedWatched = valuesFor('watched');
    });
    _reloadAfterQueryChanged();
  }

  void _closeDesktopFilter() => _setStateIfMounted(() => _filterDraft = null);

  Widget _buildDesktopFilterPanel(bool floating) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppCatalogFilterInlinePanel(
          framed: !floating,
          sections: [
            for (final section in _buildFilterSections())
              AppCatalogFilterSection(
                key: section.key,
                title: section.title,
                options: section.options,
                selectedValues: _filterDraft![section.key] ?? const {},
              ),
          ],
          onOptionSelected: (section, value) => _setStateIfMounted(() {
            final values = _filterDraft![section.key]!;
            final wasSelected = values.contains(value);
            values.clear();
            if (value != null && !wasSelected) values.add(value);
          }),
          onCollapse: _closeDesktopFilter,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => _setStateIfMounted(() {
                  for (final values in _filterDraft!.values) {
                    values.clear();
                  }
                }),
                child: Text(l10n.listFilterResetButton),
              ),
              const SizedBox(width: 12),
              FilledButton.tonal(
                onPressed: () {
                  final result = _filterDraft!;
                  _closeDesktopFilter();
                  _applyFilterSelection(result);
                },
                child: Text(l10n.commonConfirm),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 桌面端排序/布局走点击式下拉（触屏保留原 sheet）。
  Future<void> _onSortTriggerTap() async {
    if (DesktopEnvironment.isDesktopPlatform) {
      _sortDropdownKey.currentState?.toggle();
      return;
    }
    await _openSortSheet();
  }

  Future<void> _onLayoutTriggerTap() async {
    if (DesktopEnvironment.isDesktopPlatform) {
      _layoutDropdownKey.currentState?.toggle();
      return;
    }
    await _openLayoutSheet();
  }

  DesktopHoverDropdownSpec get _sortDropdownSpec {
    final l10n = AppLocalizations.of(context);
    return DesktopHoverDropdownSpec(
      groups: <DesktopDropdownOptionGroup>[
        DesktopDropdownOptionGroup(
          items: <TrackOptionSheetItem>[
            for (final column in _FavoriteItemsScreenState._sortColumns)
              TrackOptionSheetItem(id: column, title: _sortLabelFor(column)),
          ],
          selectedId: _sortColumn,
          onSelected: (field) =>
              _applySortSelection(field: field, type: _sortType),
        ),
        DesktopDropdownOptionGroup(
          items: <TrackOptionSheetItem>[
            TrackOptionSheetItem(id: 'ASC', title: l10n.listSortAsc),
            TrackOptionSheetItem(id: 'DESC', title: l10n.listSortDesc),
          ],
          selectedId: _sortType,
          onSelected: (type) =>
              _applySortSelection(field: _sortColumn, type: type),
        ),
      ],
    );
  }

  DesktopHoverDropdownSpec get _layoutDropdownSpec {
    final l10n = AppLocalizations.of(context);
    String label(MediaCollectionViewType type) {
      switch (type) {
        case MediaCollectionViewType.list:
          return l10n.collectionLayoutList;
        case MediaCollectionViewType.horizontalPoster:
          return l10n.collectionLayoutHorizontalPoster;
        case MediaCollectionViewType.verticalPoster:
          return l10n.collectionLayoutVerticalPoster;
      }
    }

    return DesktopHoverDropdownSpec(
      groups: <DesktopDropdownOptionGroup>[
        DesktopDropdownOptionGroup(
          items: <TrackOptionSheetItem>[
            for (final type in MediaCollectionViewType.values)
              TrackOptionSheetItem(id: type.storageValue, title: label(type)),
          ],
          selectedId: _viewType.storageValue,
          onSelected: (id) =>
              _applyLayoutSelection(MediaCollectionViewTypeX.fromStorage(id)),
        ),
      ],
    );
  }

  /// 桌面点击下拉直接落地排序（字段/方向各组独立选择）。
  Future<void> _applySortSelection({
    required String field,
    required String type,
  }) async {
    if (field == _sortColumn && type == _sortType) return;
    _setStateIfMounted(() {
      _sortColumn = field;
      _sortType = type;
    });
    if (_isFeiniuBackend) {
      await FeiniuApi(context.read<NasProvider>()).setUserListSetting(
        '',
        sortField: _sortColumn,
        sortType: _sortType,
        viewType: _viewType.storageValue,
        key: _favoriteListSettingKey,
      );
    }
    if (!mounted) return;
    _reloadAfterQueryChanged();
  }

  /// 桌面点击下拉直接落地视图切换。
  Future<void> _applyLayoutSelection(MediaCollectionViewType next) async {
    if (!mounted || next == _viewType) return;
    _setStateIfMounted(() {
      _viewType = next;
    });
    if (_isFeiniuBackend) {
      await FeiniuApi(context.read<NasProvider>()).setUserListSetting(
        '',
        viewType: next.storageValue,
        key: _favoriteListSettingKey,
      );
    }
  }
}
