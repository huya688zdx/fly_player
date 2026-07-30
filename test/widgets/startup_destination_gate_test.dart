import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:fly_player/providers/startup_preferences_provider.dart';
import 'package:fly_player/widgets/startup_destination_gate.dart';

void main() {
  testWidgets('偏好未就绪时显示轻量加载态且不构建普通首页', (tester) async {
    final provider = StartupPreferencesProvider(autoLoad: false);

    await tester.pumpWidget(_testApp(provider));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('普通首页'), findsNothing);
  });

  testWidgets('启动直达关闭时直接显示普通首页', (tester) async {
    final provider = StartupPreferencesProvider(
      autoLoad: false,
      loadPreference: () async => false,
    );
    await provider.load();

    await tester.pumpWidget(_testApp(provider));
    await tester.pumpAndSettle();

    expect(find.text('普通首页'), findsOneWidget);
    expect(find.text('海报首页'), findsNothing);
  });

  testWidgets('启动直达开启时只自动打开一次且返回后显示普通首页', (tester) async {
    var storedValue = true;
    final provider = StartupPreferencesProvider(
      autoLoad: false,
      loadPreference: () async => storedValue,
      savePreference: (value) async {
        storedValue = value;
        return true;
      },
    );
    await provider.load();

    await tester.pumpWidget(_testApp(provider));
    await tester.pumpAndSettle();

    expect(find.text('海报首页'), findsOneWidget);
    expect(find.text('普通首页'), findsNothing);

    Navigator.of(tester.element(find.text('海报首页'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('普通首页'), findsOneWidget);

    await provider.setOpenPosterHomeOnStartup(false);
    await provider.setOpenPosterHomeOnStartup(true);
    await tester.pumpAndSettle();

    expect(find.text('普通首页'), findsOneWidget);
    expect(find.text('海报首页'), findsNothing);
  });

  testWidgets('冷启动无有效会话时消费决策且登录后不再自动跳转', (tester) async {
    final provider = StartupPreferencesProvider(
      autoLoad: false,
      loadPreference: () async => true,
    );
    await provider.load();

    await tester.pumpWidget(
      _EligibilityHarness(provider: provider, canOpenDestination: false),
    );
    await tester.pumpAndSettle();
    expect(find.text('登录页'), findsOneWidget);
    expect(find.text('海报首页'), findsNothing);

    await tester.tap(find.text('模拟登录'));
    await tester.pumpAndSettle();

    expect(find.text('普通首页'), findsOneWidget);
    expect(find.text('海报首页'), findsNothing);
  });

  testWidgets('偏好先就绪而会话后就绪时仍会自动打开海报首页', (tester) async {
    final provider = StartupPreferencesProvider(
      autoLoad: false,
      loadPreference: () async => true,
    );
    await provider.load();

    await tester.pumpWidget(_DecisionReadyHarness(provider: provider));
    await tester.pumpAndSettle();
    expect(find.text('会话加载中'), findsOneWidget);
    expect(find.text('海报首页'), findsNothing);

    await tester.tap(find.text('会话就绪'));
    await tester.pumpAndSettle();

    expect(find.text('海报首页'), findsOneWidget);
  });
}

Widget _testApp(StartupPreferencesProvider provider) {
  return ChangeNotifierProvider<StartupPreferencesProvider>.value(
    value: provider,
    child: MaterialApp(
      home: const StartupDestinationGate(child: Scaffold(body: Text('普通首页'))),
      routes: <String, WidgetBuilder>{
        '/screen/poster-browse': (_) => const Scaffold(body: Text('海报首页')),
      },
    ),
  );
}

class _EligibilityHarness extends StatefulWidget {
  const _EligibilityHarness({
    required this.provider,
    required this.canOpenDestination,
  });

  final StartupPreferencesProvider provider;
  final bool canOpenDestination;

  @override
  State<_EligibilityHarness> createState() => _EligibilityHarnessState();
}

class _EligibilityHarnessState extends State<_EligibilityHarness> {
  late bool _canOpenDestination = widget.canOpenDestination;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<StartupPreferencesProvider>.value(
      value: widget.provider,
      child: MaterialApp(
        home: StartupDestinationGate(
          decisionReady: true,
          canOpenDestination: _canOpenDestination,
          child: Scaffold(
            body: _canOpenDestination
                ? const Text('普通首页')
                : Column(
                    children: <Widget>[
                      const Text('登录页'),
                      TextButton(
                        onPressed: () {
                          setState(() => _canOpenDestination = true);
                        },
                        child: const Text('模拟登录'),
                      ),
                    ],
                  ),
          ),
        ),
        routes: <String, WidgetBuilder>{
          '/screen/poster-browse': (_) => const Scaffold(body: Text('海报首页')),
        },
      ),
    );
  }
}

class _DecisionReadyHarness extends StatefulWidget {
  const _DecisionReadyHarness({required this.provider});

  final StartupPreferencesProvider provider;

  @override
  State<_DecisionReadyHarness> createState() => _DecisionReadyHarnessState();
}

class _DecisionReadyHarnessState extends State<_DecisionReadyHarness> {
  bool _decisionReady = false;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<StartupPreferencesProvider>.value(
      value: widget.provider,
      child: MaterialApp(
        home: StartupDestinationGate(
          decisionReady: _decisionReady,
          canOpenDestination: true,
          child: Scaffold(
            body: _decisionReady
                ? const Text('普通首页')
                : Column(
                    children: <Widget>[
                      const Text('会话加载中'),
                      TextButton(
                        onPressed: () {
                          setState(() => _decisionReady = true);
                        },
                        child: const Text('会话就绪'),
                      ),
                    ],
                  ),
          ),
        ),
        routes: <String, WidgetBuilder>{
          '/screen/poster-browse': (_) => const Scaffold(body: Text('海报首页')),
        },
      ),
    );
  }
}
