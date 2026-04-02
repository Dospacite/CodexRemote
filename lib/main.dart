import 'package:flutter/widgets.dart';

import 'src/app.dart';
import 'src/app_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = await AppController.bootstrap();
  runApp(CodexRemoteApp(controller: controller));
}
