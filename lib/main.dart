import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/store.dart';
import 'look.dart';
import 'screens/onboarding.dart';
import 'screens/shell.dart';
import 'screens/splash.dart';
import 'screens/tour.dart';
import 'services/notify.dart';
import 'services/sfx.dart';
import 'services/updater.dart';
import 'theme.dart';
import 'widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await store.load();
  Look.apply();
  runApp(const ShelfwiseApp());
  unawaited(Notifier.init());
  if (store.settings.autoUpdate) Future.delayed(const Duration(seconds: 4), () => Updater.check());
  Future.delayed(const Duration(seconds: 2), Sfx.warmUp);
}

class ShelfwiseApp extends StatelessWidget {
  const ShelfwiseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: Look.sig,
      builder: (context, _, _) => MaterialApp(
        title: 'Shelfwise',
        debugShowCheckedModeBanner: false,
        navigatorKey: navKey,
        theme: buildTheme(),
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(textScaler: TextScaler.linear(mq.textScaler.scale(1) * store.settings.textScale)),
            child: FxHost(child: SplashGate(child: child!)),
          );
        },
        home: const _Root(),
      ),
    );
  }
}

/// Swaps between the intro and the app, and saves when the app is backgrounded.
class _Root extends StatefulWidget {
  const _Root();
  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> with WidgetsBindingObserver {
  late bool _on = store.onboarded;
  late bool _toured = store.toured;
  late final AppLifecycleListener _life = AppLifecycleListener(
    onPause: store.flush,
    onDetach: store.flush,
    onHide: store.flush,
  );

  @override
  void initState() {
    super.initState();
    _life;
    store.addListener(_check);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangePlatformBrightness() => Look.apply(animate: true);

  void _check() {
    if (store.onboarded != _on || store.toured != _toured) {
      setState(() {
        _on = store.onboarded;
        _toured = store.toured;
      });
    }
    Look.apply(animate: true);
  }

  @override
  void dispose() {
    store.removeListener(_check);
    WidgetsBinding.instance.removeObserver(this);
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      switchInCurve: ease,
      transitionBuilder: (c, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween(begin: 1.03, end: 1.0).animate(a), child: c),
      ),
      child: !_on
          ? const Onboarding(key: ValueKey('intro'))
          : _toured
              ? const Shell(key: ValueKey('app'))
              : const Tour(key: ValueKey('tour')),
    );
  }
}
