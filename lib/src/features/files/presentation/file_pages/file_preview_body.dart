part of file_pages;

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
