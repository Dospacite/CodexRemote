import '../../app_controller.dart';

class AppBootstrap {
  const AppBootstrap._();

  static Future<AppController> load() {
    return AppController.bootstrap();
  }
}
