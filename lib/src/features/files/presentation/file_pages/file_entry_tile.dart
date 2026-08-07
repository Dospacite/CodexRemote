part of file_pages;

class _FileEntryTile extends StatelessWidget {
  const _FileEntryTile({
    required this.controller,
    required this.entry,
    required this.isDownloading,
    required this.downloadStatus,
    this.onOpenFile,
    this.onDownload,
    this.onCancelDownload,
  });

  final AppController controller;
  final FileSystemEntry entry;
  final bool isDownloading;
  final FileDownloadStatus? downloadStatus;
  final VoidCallback? onOpenFile;
  final VoidCallback? onDownload;
  final VoidCallback? onCancelDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fullPath = controller.joinFileBrowserPath(entry.fileName);
    final selected = controller.selectedFilePath == fullPath;
    return InkWell(
      onTap: () {
        if (entry.isDirectory) {
          controller.loadDirectory(fullPath);
        } else if (entry.isFile) {
          onOpenFile?.call();
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  entry.isDirectory
                      ? Icons.folder_outlined
                      : Icons.description_outlined,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    entry.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                if (entry.isFile && onDownload != null) ...<Widget>[
                  const SizedBox(width: 8),
                  isDownloading
                      ? IconButton(
                          tooltip: 'Cancel download',
                          onPressed: onCancelDownload,
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close, size: 18),
                        )
                      : IconButton(
                          tooltip: 'Download',
                          onPressed: onDownload,
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.download_outlined, size: 18),
                        ),
                ],
              ],
            ),
            if (isDownloading && downloadStatus != null) ...<Widget>[
              const SizedBox(height: 8),
              _DownloadProgressDetails(status: downloadStatus!),
            ],
          ],
        ),
      ),
    );
  }
}
