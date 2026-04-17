import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';

Future<void> openDownloadedLocation(
  BuildContext context,
  String savedPath,
) async {
  if (Platform.isAndroid) {
    final currentStatus = await Permission.manageExternalStorage.status;
    if (!currentStatus.isGranted) {
      final requested = await Permission.manageExternalStorage.request();
      if (!requested.isGranted) {
        await openAppSettings();
        if (!context.mounted) {
          return;
        }
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              'Allow All files access for Codex Remote to open downloaded locations.',
            ),
          ),
        );
        return;
      }
    }
  }
  final parentPath = File(savedPath).parent.path;
  var result = await OpenFilex.open(parentPath);
  if (result.type != ResultType.done) {
    result = await OpenFilex.open(savedPath);
  }
  if (result.type == ResultType.done || !context.mounted) {
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(
        result.message.isNotEmpty
            ? result.message
            : 'Unable to open the downloaded file location.',
      ),
    ),
  );
}
