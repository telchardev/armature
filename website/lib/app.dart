import 'package:flutter/material.dart';

import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

class ArmatureWebsiteApp extends StatefulWidget {
  const ArmatureWebsiteApp({super.key});

  @override
  State<ArmatureWebsiteApp> createState() => _ArmatureWebsiteAppState();
}

class _ArmatureWebsiteAppState extends State<ArmatureWebsiteApp> {
  final ThemeController _themeController = ThemeController();
  late final _router = AppRouter.create();

  @override
  void dispose() {
    _themeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ThemeScope(
      notifier: _themeController,
      child: ListenableBuilder(
        listenable: _themeController,
        builder: (context, _) => MaterialApp.router(
          title: 'Armature',
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: _themeController.mode,
          routerConfig: _router,
          debugShowCheckedModeBanner: false,
        ),
      ),
    );
  }
}
