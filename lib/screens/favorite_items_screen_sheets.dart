part of 'favorite_items_screen.dart';

extension _FavoriteItemsScreenSheets on _FavoriteItemsScreenState {
  Future<void> _openSortSheet() async {
    final nasProvider = context.read<NasProvider>();
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

    _sortColumn = result.field;
    _sortType = result.sortType;
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
  }

  Future<void> _openFilterSheet() async {
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

    final result = await AppCatalogFilterSheet.show(
      context,
      sections: candidates.whereType<AppCatalogFilterSection>().toList(),
    );
    if (!mounted || result == null) return;

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
}
