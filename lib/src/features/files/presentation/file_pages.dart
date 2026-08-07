library file_pages;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app_controller.dart';
import '../../../models.dart';

part 'file_pages/download_progress_widgets.dart';
part 'file_pages/file_browser_sheet.dart';
part 'file_pages/file_entry_tile.dart';
part 'file_pages/file_preview_body.dart';
part 'file_pages/file_preview_page.dart';

String _formatTransferSize(FileDownloadStatus? status) {
  final received = _formatMegabytes(status?.receivedBytes ?? 0);
  final totalBytes = status?.totalBytes;
  final total = totalBytes == null ? '--' : _formatMegabytes(totalBytes);
  return '$received MB / $total MB';
}

String _formatEta(FileDownloadStatus? status) {
  final eta = status?.eta;
  if (eta == null) {
    return 'Estimating time remaining...';
  }
  if (eta == Duration.zero) {
    return 'Almost done';
  }
  final seconds = eta.inSeconds;
  if (seconds < 60) {
    return '${seconds}s remaining';
  }
  final minutes = eta.inMinutes;
  final remainingSeconds = seconds % 60;
  if (minutes < 60) {
    return '${minutes}m ${remainingSeconds}s remaining';
  }
  final hours = eta.inHours;
  final remainingMinutes = minutes % 60;
  return '${hours}h ${remainingMinutes}m remaining';
}

String _formatMegabytes(int bytes) {
  final megabytes = bytes / (1024 * 1024);
  return megabytes.toStringAsFixed(megabytes >= 10 ? 0 : 1);
}
