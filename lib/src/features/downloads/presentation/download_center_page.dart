import 'package:flutter/material.dart';

import '../../../app_controller.dart';
import '../../../core/platform/download_location_opener.dart';

class DownloadCenterPage extends StatelessWidget {
  const DownloadCenterPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Downloads'),
            actions: <Widget>[
              TextButton(
                onPressed:
                    controller.downloadRecords.any(
                      (item) => item.state != DownloadState.running,
                    )
                    ? controller.clearFinishedDownloads
                    : null,
                child: const Text('Clear finished'),
              ),
            ],
          ),
          body: SafeArea(
            child: controller.downloadRecords.isEmpty
                ? Center(
                    child: Text(
                      'No downloads yet.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: controller.downloadRecords.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (BuildContext context, int index) {
                      final record = controller.downloadRecords[index];
                      return _DownloadRecordTile(
                        record: record,
                        onOpen: record.targetPath == null
                            ? null
                            : () => openDownloadedLocation(
                                context,
                                record.targetPath!,
                              ),
                        onCancel: record.state == DownloadState.running
                            ? () => controller.cancelFileDownload(
                                record.sourcePath,
                              )
                            : null,
                      );
                    },
                  ),
          ),
        );
      },
    );
  }
}

class _DownloadRecordTile extends StatelessWidget {
  const _DownloadRecordTile({required this.record, this.onOpen, this.onCancel});

  final DownloadRecord record;
  final VoidCallback? onOpen;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = record.status;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(_downloadStateIcon(record.state), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  record.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Text(
                _downloadStateLabel(record.state),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            record.sourcePath,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (status != null) ...<Widget>[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: record.state == DownloadState.running
                  ? status.progress
                  : 1,
            ),
            const SizedBox(height: 6),
            Text(_formatTransferSize(status), style: theme.textTheme.bodySmall),
            const SizedBox(height: 2),
            Text(
              record.state == DownloadState.running
                  ? _formatEta(status)
                  : _downloadCompletionText(record),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ] else if (record.error != null &&
              record.error!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              record.error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              if (record.targetPath != null && onOpen != null)
                OutlinedButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: const Text('Open'),
                ),
              if (record.state == DownloadState.running &&
                  onCancel != null) ...<Widget>[
                if (record.targetPath != null) const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Cancel'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

IconData _downloadStateIcon(DownloadState state) {
  return switch (state) {
    DownloadState.running => Icons.downloading_rounded,
    DownloadState.completed => Icons.download_done_outlined,
    DownloadState.failed => Icons.error_outline,
    DownloadState.cancelled => Icons.remove_circle_outline,
  };
}

String _downloadStateLabel(DownloadState state) {
  return switch (state) {
    DownloadState.running => 'Downloading',
    DownloadState.completed => 'Completed',
    DownloadState.failed => 'Failed',
    DownloadState.cancelled => 'Cancelled',
  };
}

String _downloadCompletionText(DownloadRecord record) {
  final finishedAt = record.finishedAt;
  if (finishedAt == null) {
    return '';
  }
  final local = finishedAt;
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return 'Finished at $hour:$minute';
}

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
