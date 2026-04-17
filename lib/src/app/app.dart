import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_controller.dart';
import '../home_page.dart';
import 'providers.dart';
import 'theme/app_theme.dart';

class CodexRemoteApp extends StatelessWidget {
  const CodexRemoteApp({super.key, this.controller});

  final AppController? controller;

  @override
  Widget build(BuildContext context) {
    if (controller == null) {
      return const _CodexRemoteAppView();
    }
    return ProviderScope(
      overrides: <Override>[
        appControllerProvider.overrideWith((Ref ref) => controller!),
      ],
      child: const _CodexRemoteAppView(),
    );
  }
}

class _CodexRemoteAppView extends ConsumerWidget {
  const _CodexRemoteAppView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(appControllerProvider);
    return MaterialApp(
      title: 'Codex Remote',
      debugShowCheckedModeBanner: false,
      themeMode: controller.settings.materialThemeMode,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      home: HomePage(controller: controller),
    );
  }
}
