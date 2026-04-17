import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_controller.dart';

final appControllerProvider = ChangeNotifierProvider<AppController>((ref) {
  throw UnimplementedError(
    'appControllerProvider must be overridden during bootstrap.',
  );
});
