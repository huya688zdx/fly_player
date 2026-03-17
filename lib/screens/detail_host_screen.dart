import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/media_item.dart';
import '../models/media_library_item.dart';
import '../pages/tv_season_detail_page.dart';
import '../ui/app_transitions.dart';
import '../ui/detail_presentation.dart';
import 'app_settings_screen.dart';
import 'category_items_screen.dart';
import 'favorite_items_screen.dart';
import 'parallel_placeholder_screen.dart';
import 'person_detail_screen.dart';
import 'play_detail_screen.dart';
import 'search_screen.dart';

class DetailHostScreen extends StatefulWidget {
  final String initialRouteName;

  const DetailHostScreen({super.key, required this.initialRouteName});

  @override
  State<DetailHostScreen> createState() => _DetailHostScreenState();
}

class _DetailHostScreenState extends State<DetailHostScreen> {
  static const MethodChannel _channel = MethodChannel('fly_player/detail_host');

  late String _currentRouteName;

  @override
  void initState() {
    super.initState();
    _currentRouteName = widget.initialRouteName.trim().isEmpty
        ? '/'
        : widget.initialRouteName.trim();
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method != 'replaceRoute') return;
    final routeName =
        (call.arguments as Map?)?['routeName']?.toString().trim() ?? '';
    if (!mounted || routeName.isEmpty || routeName == _currentRouteName) return;
    setState(() {
      _currentRouteName = routeName;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppTransitions.crossFadeSwitch(
      switchKey: _currentRouteName,
      child: KeyedSubtree(
        key: ValueKey<String>(_currentRouteName),
        child: _buildRouteChild(_currentRouteName),
      ),
    );
  }
}

Widget _buildRouteChild(String routeName) {
  final uri = Uri.tryParse(routeName.trim());
  if (uri == null) {
    return const _DetailHostRouteError(message: '路由无效');
  }

  if (uri.path == '/detail/item') {
    final itemGuid = uri.queryParameters['itemGuid'] ?? '';
    if (itemGuid.trim().isEmpty) {
      return const _DetailHostRouteError(message: '缺少详情参数');
    }
    return PlayDetailScreen(
      key: ValueKey<String>(routeName),
      itemGuid: itemGuid,
      presentation: DetailPresentation.pane,
    );
  }

  if (uri.path == '/detail/season') {
    final rawSeasonItem = uri.queryParameters['seasonItem'] ?? '';
    final decodedSeasonItem = rawSeasonItem.isEmpty
        ? const <String, dynamic>{}
        : (jsonDecode(rawSeasonItem) as Map).cast<String, dynamic>();
    final parentGuid = uri.queryParameters['parentGuid'] ?? '';
    final seasonItem = MediaLibraryItem.fromJson(decodedSeasonItem);
    if (parentGuid.trim().isEmpty || seasonItem.guid.trim().isEmpty) {
      return const _DetailHostRouteError(message: '缺少季详情参数');
    }
    return TvSeasonDetailPage(
      key: ValueKey<String>(routeName),
      parentGuid: parentGuid,
      seriesTitle: uri.queryParameters['seriesTitle'] ?? '',
      backdropPath: uri.queryParameters['backdropPath'] ?? '',
      seasonItem: seasonItem,
      presentation: DetailPresentation.pane,
    );
  }

  if (uri.path == '/detail/person') {
    final personGuid = uri.queryParameters['personGuid'] ?? '';
    if (personGuid.trim().isEmpty) {
      return const _DetailHostRouteError(message: '缺少人物参数');
    }
    return PersonDetailScreen(
      key: ValueKey<String>(routeName),
      personGuid: personGuid,
      initialName: uri.queryParameters['initialName'] ?? '',
      presentation: DetailPresentation.pane,
    );
  }

  if (uri.path == '/screen/search') {
    return const SearchScreen(
      key: ValueKey<String>('/screen/search'),
      secondaryHost: true,
    );
  }

  if (uri.path == '/screen/favorites') {
    return const FavoriteItemsScreen.secondaryHost(
      key: ValueKey<String>('/screen/favorites'),
    );
  }

  if (uri.path == '/screen/category') {
    final rawCategory = uri.queryParameters['category'] ?? '';
    final rawTypes = uri.queryParameters['types'] ?? '';
    final decodedCategory = rawCategory.isEmpty
        ? const <String, dynamic>{}
        : (jsonDecode(rawCategory) as Map).cast<String, dynamic>();
    final decodedTypes = rawTypes.isEmpty
        ? null
        : (jsonDecode(rawTypes) as List)
              .map((value) => '$value')
              .toList(growable: false);
    return CategoryItemsScreen(
      key: ValueKey<String>(routeName),
      category: MediaItem.fromJson(decodedCategory),
      initialTypeTags: decodedTypes,
      secondaryHost: true,
    );
  }

  if (uri.path == '/screen/settings') {
    return const AppSettingsScreen(
      key: ValueKey<String>('/screen/settings'),
      secondaryHost: true,
    );
  }

  if (uri.path == '/parallel/placeholder') {
    return const ParallelPlaceholderScreen(
      key: ValueKey<String>('/parallel/placeholder'),
    );
  }

  return const _DetailHostRouteError(message: '暂不支持的副屏路由');
}

class _DetailHostRouteError extends StatelessWidget {
  final String message;

  const _DetailHostRouteError({required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      body: Center(
        child: Text(
          message,
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 16),
        ),
      ),
    );
  }
}
