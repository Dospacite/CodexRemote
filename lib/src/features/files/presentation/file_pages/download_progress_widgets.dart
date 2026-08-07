part of file_pages;

class _DownloadProgressPanel extends StatelessWidget {
  const _DownloadProgressPanel({required this.status, required this.onCancel});

  final FileDownloadStatus? status;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Expanded(child: _DownloadProgressDetails(status: status)),
          const SizedBox(width: 10),
          IconButton(
            tooltip: 'Cancel download',
            onPressed: onCancel,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}

class _DownloadProgressDetails extends StatelessWidget {
  const _DownloadProgressDetails({required this.status});

  final FileDownloadStatus? status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = (status?.progress ?? 0).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        LinearProgressIndicator(value: progress),
        const SizedBox(height: 6),
        Text(_formatTransferSize(status), style: theme.textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(
          _formatEta(status),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
