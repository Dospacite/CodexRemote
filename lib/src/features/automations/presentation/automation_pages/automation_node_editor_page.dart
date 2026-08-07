part of automation_pages;

class AutomationNodeEditorPage extends StatefulWidget {
  const AutomationNodeEditorPage({
    super.key,
    required this.controller,
    required this.node,
  });

  final AppController controller;
  final AutomationNode node;

  @override
  State<AutomationNodeEditorPage> createState() =>
      _AutomationNodeEditorPageState();
}

class _AutomationNodeEditorPageState extends State<AutomationNodeEditorPage> {
  late final TextEditingController _pathController;
  late final TextEditingController _commandController;
  late final TextEditingController _cwdController;
  late final TextEditingController _directoryController;
  late final TextEditingController _conditionTokenController;
  late AutomationBranchOutcome _whenTrue;
  late AutomationBranchOutcome _whenFalse;

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController(text: widget.node.path);
    _commandController = TextEditingController(text: widget.node.commandText);
    _cwdController = TextEditingController(text: widget.node.cwd);
    _directoryController = TextEditingController(text: widget.node.directory);
    _conditionTokenController = TextEditingController(
      text: widget.node.conditionToken,
    );
    _whenTrue = widget.node.whenTrue;
    _whenFalse = widget.node.whenFalse;
  }

  @override
  void dispose() {
    _pathController.dispose();
    _commandController.dispose();
    _cwdController.dispose();
    _directoryController.dispose();
    _conditionTokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        splashFactory: InkRipple.splashFactory,
        useMaterial3: false,
      ),
      child: Scaffold(
        appBar: AppBar(
          title: Text(node.kind.title),
          actions: <Widget>[
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _AutomationActionButton(label: 'Save', onTap: _saveNode),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: <Widget>[
              if (node.kind == AutomationNodeKind.watchFileChanged ||
                  node.kind ==
                      AutomationNodeKind.watchDirectoryChanged) ...<Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _pathController,
                        decoration: InputDecoration(
                          labelText:
                              node.kind ==
                                  AutomationNodeKind.watchDirectoryChanged
                              ? 'Folder path'
                              : 'File path',
                          hintText:
                              node.kind ==
                                  AutomationNodeKind.watchDirectoryChanged
                              ? '/workspace/app'
                              : '/workspace/app/build/app-release.apk',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _AutomationIconAction(
                      tooltip: 'Browse remote files',
                      icon: Icons.folder_open_outlined,
                      onTap: () => _browseForPath(
                        node.kind,
                        allowDirectorySelection:
                            node.kind ==
                            AutomationNodeKind.watchDirectoryChanged,
                        allowFileSelection:
                            node.kind !=
                            AutomationNodeKind.watchDirectoryChanged,
                      ),
                    ),
                  ],
                ),
              ],
              if (node.kind == AutomationNodeKind.turnCompleted) ...<Widget>[
                const Text(
                  'Triggers after the app-server reports an LLM turn completed. No filesystem path is required.',
                ),
                const SizedBox(height: 8),
                Text(
                  'Use this with actions like Run command to start follow-up automation after a response finishes.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (node.kind == AutomationNodeKind.watchFileChanged ||
                  node.kind ==
                      AutomationNodeKind.watchDirectoryChanged) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  'Pick the trigger target from the remote file explorer.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (node.kind ==
                  AutomationNodeKind.didPathChangeSinceLastRun) ...<Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _pathController,
                        decoration: const InputDecoration(
                          labelText: 'File or folder path',
                          hintText: '/workspace/app/build/app-release.apk',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _AutomationIconAction(
                      tooltip: 'Browse remote files',
                      icon: Icons.folder_open_outlined,
                      onTap: () => _browseForPath(
                        node.kind,
                        allowDirectorySelection: true,
                        allowFileSelection: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Compares the selected file or folder against the previous execution of this automation and stores {{previous.changed}} for the next node.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (node.kind == AutomationNodeKind.ifElse) ...<Widget>[
                TextField(
                  controller: _conditionTokenController,
                  decoration: const InputDecoration(
                    labelText: 'Condition value or template',
                    hintText: '{{previous.changed}}',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AutomationBranchOutcome>(
                  initialValue: _whenTrue,
                  decoration: const InputDecoration(labelText: 'When true'),
                  items: AutomationBranchOutcome.values
                      .map(
                        (value) => DropdownMenuItem<AutomationBranchOutcome>(
                          value: value,
                          child: Text(_branchOutcomeLabel(value)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _whenTrue = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AutomationBranchOutcome>(
                  initialValue: _whenFalse,
                  decoration: const InputDecoration(labelText: 'When false'),
                  items: AutomationBranchOutcome.values
                      .map(
                        (value) => DropdownMenuItem<AutomationBranchOutcome>(
                          value: value,
                          child: Text(_branchOutcomeLabel(value)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _whenFalse = value;
                    });
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'Defaults to {{previous.changed}} so it can branch after a Did file or folder change node.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (node.kind == AutomationNodeKind.quit) ...<Widget>[
                const Text(
                  'Stops the automation immediately when this node is reached.',
                ),
              ],
              if (node.kind ==
                  AutomationNodeKind.downloadChangedFile) ...<Widget>[
                Text(
                  'Downloads the file path reported by the trigger. If no explicit directory is set here, the automation uses the remembered download directory for the active thread.',
                ),
                const SizedBox(height: 8),
                Text(
                  'Optional templates: {{trigger.changedPath}}, {{previous.downloadedPath}}, {{node.someId.downloadedPath}}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _directoryController,
                  decoration: const InputDecoration(
                    labelText: 'Download directory (optional)',
                    hintText: '/storage/emulated/0/Download',
                  ),
                ),
              ],
              if (node.kind ==
                  AutomationNodeKind.installDownloadedApk) ...<Widget>[
                const Text(
                  'Opens the downloaded APK with the system installer. By default it uses the previous download node output.',
                ),
                const SizedBox(height: 8),
                Text(
                  'Optional path override or template: {{previous.downloadedPath}}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pathController,
                  decoration: const InputDecoration(
                    labelText: 'APK path override (optional)',
                    hintText: '{{previous.downloadedPath}}',
                  ),
                ),
              ],
              if (node.kind ==
                  AutomationNodeKind.sendMessageToCurrentThread) ...<Widget>[
                TextField(
                  controller: _commandController,
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    hintText: 'A new APK build is ready.',
                  ),
                  maxLines: 4,
                  minLines: 2,
                ),
                const SizedBox(height: 8),
                Text(
                  'Templates: {{trigger.changedPath}}, {{previous.downloadedPath}}, {{previous.stdout}}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (node.kind == AutomationNodeKind.runCommand) ...<Widget>[
                TextField(
                  controller: _commandController,
                  decoration: const InputDecoration(
                    labelText: 'Command',
                    hintText: 'flutter build apk --release',
                  ),
                  maxLines: 3,
                  minLines: 1,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _cwdController,
                  decoration: const InputDecoration(
                    labelText: 'Working directory (optional)',
                    hintText: '/workspace/app',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Templates: {{trigger.changedPath}}, {{trigger.path}}, {{previous.stdout}}, {{previous.downloadedPath}}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _saveNode() {
    final next = widget.node.copyWith(
      path: _pathController.text.trim(),
      commandText: _commandController.text.trim(),
      cwd: _cwdController.text.trim(),
      directory: _directoryController.text.trim(),
      conditionToken: _conditionTokenController.text.trim(),
      whenTrue: _whenTrue,
      whenFalse: _whenFalse,
    );
    final needsPath =
        next.kind == AutomationNodeKind.watchFileChanged ||
        next.kind == AutomationNodeKind.watchDirectoryChanged ||
        next.kind == AutomationNodeKind.didPathChangeSinceLastRun;
    final needsCommand =
        next.kind == AutomationNodeKind.runCommand ||
        next.kind == AutomationNodeKind.sendMessageToCurrentThread;
    if (needsPath && next.path.isEmpty) {
      _showValidation('An absolute path is required.');
      return;
    }
    if (needsCommand && next.commandText.isEmpty) {
      _showValidation(
        next.kind == AutomationNodeKind.sendMessageToCurrentThread
            ? 'A message is required.'
            : 'A command is required.',
      );
      return;
    }
    Navigator.of(context).pop(next);
  }

  Future<void> _browseForPath(
    AutomationNodeKind kind, {
    bool allowDirectorySelection = false,
    bool allowFileSelection = true,
  }) async {
    final selectedPath = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        fullscreenDialog: true,
        builder: (BuildContext context) {
          return AutomationPathPickerPage(
            controller: widget.controller,
            allowDirectorySelection: allowDirectorySelection,
            allowFileSelection: allowFileSelection,
            title: allowDirectorySelection && allowFileSelection
                ? 'Select file or folder'
                : kind == AutomationNodeKind.watchDirectoryChanged
                ? 'Select watched folder'
                : 'Select watched file',
            initialPath: _pathController.text.trim(),
          );
        },
      ),
    );
    if (selectedPath == null) {
      return;
    }
    _pathController
      ..text = selectedPath
      ..selection = TextSelection.collapsed(offset: selectedPath.length);
  }

  void _showValidation(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
