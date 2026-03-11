import 'dart:io';
import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/nas_provider.dart';
import 'screens/connection_screen.dart';
import 'screens/media_library_screen.dart';
import 'screens/media_list_screen.dart';
import 'ui/adaptive_text.dart';
import 'ui/app_transitions.dart';
import 'utils/private_network_http_overrides.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('[APP][FLUTTER_ERROR] ${details.exceptionAsString()}');
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('[APP][PLATFORM_ERROR] $error');
      return true;
    };
    HttpOverrides.global = PrivateNetworkHttpOverrides();
    ErrorWidget.builder = (details) {
      return Material(
        color: const Color(0xFF09111C),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(
                  Icons.error_outline_rounded,
                  color: Color(0xFFD67171),
                  size: 52,
                ),
                SizedBox(height: 16),
                Text(
                  '加载失败',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    };
    runApp(const FlyPlayerApp());
  }, (error, stack) {
    debugPrint('[APP][ZONE_ERROR] $error');
  });
}

class FlyPlayerApp extends StatelessWidget {
  const FlyPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => NasProvider(),
      child: MaterialApp(
        title: 'Fly Player',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
        ),
        builder: (context, child) {
          if (child == null) return const SizedBox.shrink();
          final media = MediaQuery.of(context);
          final scale = AdaptiveText.globalScale(media);
          return MediaQuery(
            data: media.copyWith(textScaler: TextScaler.linear(scale)),
            child: child,
          );
        },
        home: const AppEntry(),
      ),
    );
  }
}

class AppEntry extends StatelessWidget {
  const AppEntry({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NasProvider>();
    if (!provider.isReady) {
      return const Scaffold(
        backgroundColor: Color(0xFF09111C),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!provider.isConfigured) {
      return const ConnectionScreen();
    }
    return const MainNavigation();
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    const pages = [MediaListScreen(), MediaLibraryScreen()];

    return Scaffold(
      body: AnimatedSwitcher(
        duration: AppTransitions.switchDuration,
        switchInCurve: AppTransitions.easeOut,
        switchOutCurve: AppTransitions.easeIn,
        transitionBuilder: (child, animation) {
          return AppTransitions.fadeSlideTransition(
            child,
            animation,
            begin: const Offset(0.04, 0),
          );
        },
        child: KeyedSubtree(
          key: ValueKey(_selectedIndex),
          child: pages[_selectedIndex],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.movie), label: '影视'),
          BottomNavigationBarItem(icon: Icon(Icons.folder_open), label: '媒体库'),
        ],
      ),
    );
  }
}
