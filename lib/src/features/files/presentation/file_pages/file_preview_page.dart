part of file_pages;

class FilePreviewPage extends StatefulWidget {
  const FilePreviewPage({
    super.key,
    required this.controller,
    required this.onDownload,
    required this.onCancelDownload,
  });

  final AppController controller;
  final Future<void> Function(BuildContext context, String filePath) onDownload;
  final Future<void> Function(String filePath) onCancelDownload;

  @override
  State<FilePreviewPage> createState() => _FilePreviewPageState();
}

class _FilePreviewPageState extends State<FilePreviewPage> {
  late final TextEditingController _editorController = TextEditingController();
  String? _editingPath;
  bool _isEditing = false;

  @override
  void dispose() {
    _editorController.dispose();
    super.dispose();
  }

  void _syncEditorFromController() {
    final controller = widget.controller;
    final path = controller.selectedFilePath;
    if (!_isEditing &&
        controller.selectedFileIsHumanReadable &&
        path != null &&
        path.isNotEmpty &&
        _editingPath != path) {
      _editingPath = path;
      _editorController.text = controller.selectedFileContent ?? '';
    }
    if (!_isEditing && !controller.selectedFileIsHumanReadable) {
      _editingPath = null;
      _editorController.clear();
    }
  }

  Future<void> _saveFile(BuildContext context) async {
    try {
      await widget.controller.saveOpenedFileContent(_editorController.text);
      if (!mounted) {
        return;
      }
      setState(() {
        _isEditing = false;
      });
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      final message = widget.controller.filePreviewSaveError?.trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            message == null || message.isEmpty
                ? 'Unable to save the file.'
                : message,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, Widget? child) {
        _syncEditorFromController();
        final controller = widget.controller;
        final filePath = controller.selectedFilePath;
        final canEdit =
            controller.selectedFileIsHumanReadable &&
            filePath != null &&
            filePath.isNotEmpty;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              filePath == null || filePath.isEmpty ? 'File preview' : filePath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: <Widget>[
              if (canEdit)
                TextButton(
                  onPressed: controller.isSavingFilePreview
                      ? null
                      : () {
                          if (_isEditing) {
                            _saveFile(context);
                          } else {
                            setState(() {
                              _isEditing = true;
                              _editingPath = filePath;
                              _editorController.text =
                                  controller.selectedFileContent ?? '';
                            });
                          }
                        },
                  child: Text(_isEditing ? 'Save' : 'Edit'),
                ),
              if (canEdit && _isEditing)
                TextButton(
                  onPressed: controller.isSavingFilePreview
                      ? null
                      : () {
                          setState(() {
                            _isEditing = false;
                            _editorController.text =
                                controller.selectedFileContent ?? '';
                          });
                        },
                  child: const Text('Cancel'),
                ),
              if (filePath != null && filePath.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: controller.isFileDownloading(filePath)
                      ? ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 280),
                          child: _DownloadProgressPanel(
                            status: controller.fileDownloadStatus(filePath),
                            onCancel: () => widget.onCancelDownload(filePath),
                          ),
                        )
                      : OutlinedButton.icon(
                          onPressed: controller.selectedFileBytes == null
                              ? null
                              : () => widget.onDownload(context, filePath),
                          icon: const Icon(Icons.download_outlined, size: 18),
                          label: const Text('Download'),
                        ),
                ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
              child: _FilePreviewBody(
                controller: controller,
                isEditing: _isEditing,
                editorController: _editorController,
              ),
            ),
          ),
        );
      },
    );
  }
}
