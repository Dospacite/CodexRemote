part of automation_pages;

class AutomationPathPickerPage extends StatefulWidget {
  const AutomationPathPickerPage({
    super.key,
    required this.controller,
    required this.allowDirectorySelection,
    required this.allowFileSelection,
    required this.title,
    this.initialPath,
  });

  final AppController controller;
  final bool allowDirectorySelection;
  final bool allowFileSelection;
  final String title;
  final String? initialPath;

  @override
  State<AutomationPathPickerPage> createState() =>
      _AutomationPathPickerPageState();
}

class _AutomationPathPickerPageState extends State<AutomationPathPickerPage> {
  late final TextEditingController _pathController;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialPath?.trim();
    final initialDirectory = _initialDirectory(initial);
    _pathController = TextEditingController(text: initialDirectory);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(widget.controller.loadDirectory(initialDirectory));
    });
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, Widget? child) {
        final controller = widget.controller;
        final theme = Theme.of(context);
        if (_pathController.text != controller.fileBrowserPath &&
            controller.fileBrowserPath.isNotEmpty) {
          _pathController.value = _pathController.value.copyWith(
            text: controller.fileBrowserPath,
            selection: TextSelection.collapsed(
              offset: controller.fileBrowserPath.length,
            ),
          );
        }
        return Theme(
          data: theme.copyWith(
            splashFactory: InkRipple.splashFactory,
            useMaterial3: false,
          ),
          child: Scaffold(
            appBar: AppBar(
              title: Text(widget.title),
              actions: <Widget>[
                if (widget.allowDirectorySelection)
                  TextButton(
                    onPressed: controller.fileBrowserPath.trim().isEmpty
                        ? null
                        : () => Navigator.of(
                            context,
                          ).pop(controller.fileBrowserPath),
                    child: const Text('Select'),
                  ),
              ],
            ),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  children: <Widget>[
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
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          border: Border.all(color: theme.dividerColor),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child:
                            controller.isLoadingFiles &&
                                controller.fileBrowserEntries.isEmpty
                            ? const Center(child: CircularProgressIndicator())
                            : ListView.separated(
                                padding: const EdgeInsets.all(12),
                                itemCount: controller.fileBrowserEntries.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (BuildContext context, int index) {
                                  final entry =
                                      controller.fileBrowserEntries[index];
                                  final fullPath = controller
                                      .joinFileBrowserPath(entry.fileName);
                                  return ListTile(
                                    dense: true,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    tileColor:
                                        theme.colorScheme.surfaceContainerLow,
                                    leading: Icon(
                                      entry.isDirectory
                                          ? Icons.folder_outlined
                                          : Icons.insert_drive_file_outlined,
                                    ),
                                    title: Text(
                                      entry.fileName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onTap: () async {
                                      if (entry.isDirectory) {
                                        await controller.loadDirectory(
                                          fullPath,
                                        );
                                        return;
                                      }
                                      if (widget.allowFileSelection &&
                                          entry.isFile) {
                                        if (!mounted) {
                                          return;
                                        }
                                        Navigator.of(context).pop(fullPath);
                                      }
                                    },
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _initialDirectory(String? initialPath) {
    if (initialPath == null || initialPath.isEmpty) {
      return widget.controller.preferredFileBrowserRoot;
    }
    if (widget.allowDirectorySelection) {
      return initialPath;
    }
    final slashIndex = initialPath.lastIndexOf('/');
    if (slashIndex <= 0) {
      return '/';
    }
    return initialPath.substring(0, slashIndex);
  }
}
