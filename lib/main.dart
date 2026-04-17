import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';
import 'src/app/bootstrap/app_bootstrap.dart';
import 'src/app/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = await AppBootstrap.load();
  runApp(
    ProviderScope(
      overrides: <Override>[
        appControllerProvider.overrideWith((Ref ref) => controller),
      ],
      child: const CodexRemoteApp(),
    ),
  );
}
