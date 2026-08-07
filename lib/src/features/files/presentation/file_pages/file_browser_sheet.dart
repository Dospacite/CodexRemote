part of file_pages;

class FileBrowserSheet extends StatefulWidget {
  const FileBrowserSheet({super.key, required this.controller});

  final AppController controller;

  @override
  State<FileBrowserSheet> createState() => _FileBrowserSheetState();
}

class _FileBrowserSheetState extends State<FileBrowserSheet> {
  late final TextEditingController _pathController;

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController(
      text: widget.controller.fileBrowserPath,
    );
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, Widget? child) {
        final controller = widget.controller;
        if (_pathController.text != controller.fileBrowserPath) {
          _pathController.value = _pathController.value.copyWith(
            text: controller.fileBrowserPath,
            selection: TextSelection.collapsed(
              offset: controller.fileBrowserPath.length,
            ),
          );
        }
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Container(
            margin: const EdgeInsets.only(right: 24),
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(22),
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
                ),
                child: SizedBox(
                  height: MediaQuery.sizeOf(context).height,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              'Files',
                              style: theme.textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          IconButton(
                            tooltip: 'Up',
                            onPressed: controller.fileBrowserPath == '/'
                                ? null
                                : controller.navigateToParentDirectory,
                            icon: const Icon(Icons.arrow_upward),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _pathController,
                              decoration: const InputDecoration(
                                labelText: 'Absolute path',
                              ),
                              onSubmitted: controller.loadDirectory,
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: controller.isLoadingFiles
                                ? null
                                : () => controller.loadDirectory(
                                    _pathController.text,
                                  ),
                            child: const Text('Open'),
                          ),
                        ],
                      ),
                      if (controller.fileBrowserError != null) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(
                          controller.fileBrowserError!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Expanded(child: _buildFileList(theme, controller)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _downloadFile(BuildContext context, String filePath) async {
    try {
      await widget.controller.saveFileToDevice(filePath);
    } catch (error) {
      // Download errors are shown in the download center.
    }
  }

  Future<void> _cancelDownload(String filePath) async {
    await widget.controller.cancelFileDownload(filePath);
  }

  Future<void> _openPreviewForFile(String filePath, {int? line}) async {
    await widget.controller.openFile(filePath, highlightedLine: line);
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (BuildContext context) {
          return FilePreviewPage(
            controller: widget.controller,
            onDownload: _downloadFile,
            onCancelDownload: _cancelDownload,
          );
        },
      ),
    );
  }

  Widget _buildFileList(ThemeData theme, AppController controller) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: controller.isLoadingFiles && controller.fileBrowserEntries.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: controller.fileBrowserEntries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (BuildContext context, int index) {
                final entry = controller.fileBrowserEntries[index];
                final fullPath = controller.joinFileBrowserPath(entry.fileName);
                return _FileEntryTile(
                  controller: controller,
                  entry: entry,
                  isDownloading: controller.isFileDownloading(fullPath),
                  downloadStatus: controller.fileDownloadStatus(fullPath),
                  onOpenFile: entry.isFile
                      ? () => _openPreviewForFile(fullPath)
                      : null,
                  onDownload: entry.isFile
                      ? () => _downloadFile(context, fullPath)
                      : null,
                  onCancelDownload: entry.isFile
                      ? () => _cancelDownload(fullPath)
                      : null,
                );
              },
            ),
    );
  }
}
