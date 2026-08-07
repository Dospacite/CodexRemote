import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app_controller.dart';
import '../../../models.dart';

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

class _FilePreviewBody extends StatefulWidget {
  const _FilePreviewBody({
    required this.controller,
    required this.isEditing,
    required this.editorController,
  });

  final AppController controller;
  final bool isEditing;
  final TextEditingController editorController;

  @override
  State<_FilePreviewBody> createState() => _FilePreviewBodyState();
}

class _FilePreviewBodyState extends State<_FilePreviewBody> {
  static const double _lineHeight = 22;
  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();
  int? _lastScrolledLine;

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final theme = Theme.of(context);
    if (controller.isLoadingFilePreview) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.selectedFilePath == null) {
      return Center(
        child: Text(
          'Select a file to preview it.',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    if (controller.selectedFileIsHumanReadable) {
      if (widget.isEditing) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (controller.filePreviewSaveError != null) ...<Widget>[
              Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 8),
                child: Text(
                  controller.filePreviewSaveError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
            Expanded(
              child: TextField(
                controller: widget.editorController,
                expands: true,
                maxLines: null,
                minLines: null,
                keyboardType: TextInputType.multiline,
                textAlignVertical: TextAlignVertical.top,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  height: 1.35,
                  color: theme.colorScheme.onSurface,
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.fromLTRB(16, 0, 0, 0),
                  hintText: 'Edit file contents',
                  hintStyle: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ],
        );
      }
      final lines = (controller.selectedFileContent ?? '').split('\n');
      final highlightedLine = controller.selectedFileHighlightedLine;
      if (highlightedLine != null &&
          highlightedLine > 0 &&
          highlightedLine <= lines.length &&
          _lastScrolledLine != highlightedLine) {
        _lastScrolledLine = highlightedLine;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_verticalController.hasClients) {
            return;
          }
          final targetOffset = ((highlightedLine - 1) * _lineHeight) - 80;
          _verticalController.animateTo(
            targetOffset.clamp(0, _verticalController.position.maxScrollExtent),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          );
        });
      }
      return Scrollbar(
        controller: _horizontalController,
        thumbVisibility: true,
        notificationPredicate: (notification) =>
            notification.metrics.axis == Axis.horizontal,
        child: SingleChildScrollView(
          controller: _horizontalController,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: 720,
            child: Scrollbar(
              controller: _verticalController,
              thumbVisibility: true,
              child: ListView.builder(
                controller: _verticalController,
                itemCount: lines.length,
                itemBuilder: (BuildContext context, int index) {
                  final lineNumber = index + 1;
                  final isHighlighted = highlightedLine == lineNumber;
                  return Container(
                    key: isHighlighted
                        ? const ValueKey<String>('highlighted-file-line')
                        : null,
                    height: _lineHeight,
                    color: isHighlighted
                        ? theme.colorScheme.primary.withValues(alpha: 0.12)
                        : null,
                    padding: const EdgeInsets.only(right: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SizedBox(
                          width: 56,
                          child: Text(
                            '$lineNumber',
                            textAlign: TextAlign.right,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: isHighlighted
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SelectableText(
                            lines[index],
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              height: 1.3,
                              color: isHighlighted
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.insert_drive_file_outlined,
              size: 36,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'This file is not previewed as text.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Use Download to save it locally and open it with an appropriate app.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            if (controller.selectedFileBytes != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                '${controller.selectedFileBytes!.length} bytes',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

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
