import 'package:flutter/material.dart';

import '../core/model.dart';
import '../core/store.dart';
import 'home.dart';
import 'listenable_bridge.dart';

/// 应用根：主题偏好驱动 MaterialApp，全局监听 store 变更。
class NotebaseApp extends StatefulWidget {
  const NotebaseApp({super.key, required this.store});

  final AppStore store;

  @override
  State<NotebaseApp> createState() => _NotebaseAppState();
}

class _NotebaseAppState extends State<NotebaseApp> {
  late final CoreListenableBridge _bridge;

  @override
  void initState() {
    super.initState();
    _bridge = CoreListenableBridge(widget.store);
  }

  @override
  void dispose() {
    _bridge.dispose();
    super.dispose();
  }

  ThemeData _theme(Brightness brightness) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: brightness,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _bridge,
      builder: (context, _) => MaterialApp(
        title: 'Notebase',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: switch (widget.store.theme) {
          ThemeSetting.system => ThemeMode.system,
          ThemeSetting.light => ThemeMode.light,
          ThemeSetting.dark => ThemeMode.dark,
        },
        home: HomePage(store: widget.store),
      ),
    );
  }
}
