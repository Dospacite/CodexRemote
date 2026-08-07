// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app_controller.dart';
import '../../../models.dart';

class AutomationPage extends StatefulWidget {
  const AutomationPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<AutomationPage> createState() => _AutomationPageState();
}

class _AutomationPageState extends State<AutomationPage> {
  bool _showAllAutomations = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, Widget? child) {
        final theme = Theme.of(context);
        final visibleAutomations = _showAllAutomations
            ? widget.controller.automations
            : widget.controller.automations
                  .where(widget.controller.isAutomationVisibleInCurrentThread)
                  .toList(growable: false);
        final emptyMessage = _showAllAutomations
            ? 'Create automations from nodes: a filesystem watch trigger followed by sequential actions like download, install APK, or run a command.'
            : 'No automations are scoped to the current thread yet.';
        return Theme(
          data: theme.copyWith(
            splashFactory: InkRipple.splashFactory,
            useMaterial3: false,
          ),
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Automations'),
              actions: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _showAllAutomations = !_showAllAutomations;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: theme.dividerColor),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            _showAllAutomations ? Icons.list : Icons.filter_alt,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(_showAllAutomations ? 'All' : 'Current'),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'New automation',
                  onPressed: () => _openEditor(context),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            body: visibleAutomations.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Text(
                        emptyMessage,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    itemBuilder: (BuildContext context, int index) {
                      final automation = visibleAutomations[index];
                      final ownerThreadId = automation.ownerThreadId.trim();
                      final currentThreadId = widget
                          .controller
                          .currentAutomationScopeThreadId
                          .trim();
                      final canCopyToCurrentThread =
                          ownerThreadId.isNotEmpty &&
                          currentThreadId.isNotEmpty &&
                          ownerThreadId != currentThreadId;
                      return _AutomationCard(
                        automation: automation,
                        isRunning: widget.controller.isAutomationRunning(
                          automation.id,
                        ),
                        onToggleEnabled: (value) {
                          widget.controller.setAutomationEnabled(
                            automation.id,
                            value,
                          );
                        },
                        onEdit: () =>
                            _openEditor(context, automation: automation),
                        onCopyToCurrentThread: canCopyToCurrentThread
                            ? () => widget.controller
                                  .copyAutomationToCurrentThread(automation.id)
                            : null,
                        onDelete: () =>
                            widget.controller.deleteAutomation(automation.id),
                      );
                    },
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemCount: visibleAutomations.length,
                  ),
          ),
        );
      },
    );
  }

  Future<void> _openEditor(
    BuildContext context, {
    AutomationDefinition? automation,
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (BuildContext context) {
          return AutomationEditorPage(
            controller: widget.controller,
            initialAutomation:
                automation ??
                AutomationDefinition(
                  id: 'automation-${DateTime.now().microsecondsSinceEpoch}',
                  name: '',
                  enabled: true,
                  nodes: const <AutomationNode>[],
                ),
          );
        },
      ),
    );
  }
}

class _AutomationCard extends StatelessWidget {
  const _AutomationCard({
    required this.automation,
    required this.isRunning,
    required this.onToggleEnabled,
    required this.onEdit,
    required this.onCopyToCurrentThread,
    required this.onDelete,
  });

  final AutomationDefinition automation;
  final bool isRunning;
  final ValueChanged<bool> onToggleEnabled;
  final VoidCallback onEdit;
  final VoidCallback? onCopyToCurrentThread;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trigger = automation.triggerNode;
    final actions = automation.actionNodes;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    automation.name.trim().isEmpty
                        ? 'Untitled automation'
                        : automation.name,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Switch(value: automation.enabled, onChanged: onToggleEnabled),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              trigger == null
                  ? 'No trigger configured'
                  : trigger.path.trim().isEmpty
                  ? trigger.kind.title
                  : '${trigger.kind.title} • ${trigger.path}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Text(
              actions.isEmpty
                  ? 'No actions configured'
                  : actions.map((node) => node.kind.title).join(' → '),
              style: theme.textTheme.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isRunning
                        ? theme.colorScheme.primary.withValues(alpha: 0.12)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    isRunning
                        ? 'Running'
                        : automation.enabled
                        ? 'Enabled'
                        : 'Disabled',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isRunning
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const Spacer(),
                _AutomationActionButton(label: 'Edit', onTap: onEdit),
                if (onCopyToCurrentThread != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _AutomationActionButton(
                      label: 'Copy',
                      onTap: onCopyToCurrentThread!,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _AutomationActionButton(
                    label: 'Delete',
                    onTap: onDelete,
                    destructive: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AutomationActionButton extends StatelessWidget {
  const _AutomationActionButton({
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final bool destructive;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = destructive ? scheme.error : scheme.primary;
    final background = destructive
        ? scheme.error.withValues(alpha: 0.10)
        : scheme.primary.withValues(alpha: 0.10);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 16, color: foreground),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AutomationIconAction extends StatelessWidget {
  const _AutomationIconAction({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Icon(icon, size: 20, color: theme.colorScheme.primary),
        ),
      ),
    );
  }
}

class AutomationEditorPage extends StatefulWidget {
  const AutomationEditorPage({
    super.key,
    required this.controller,
    required this.initialAutomation,
  });

  final AppController controller;
  final AutomationDefinition initialAutomation;

  @override
  State<AutomationEditorPage> createState() => _AutomationEditorPageState();
}

class _AutomationEditorPageState extends State<AutomationEditorPage> {
  late final TextEditingController _nameController;
  late bool _enabled;
  late List<AutomationNode> _nodes;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialAutomation.name,
    );
    _enabled = widget.initialAutomation.enabled;
    _nodes = List<AutomationNode>.from(widget.initialAutomation.nodes);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trigger = _nodes.where((node) => node.kind.isTrigger).toList();
    final actions = _nodes.where((node) => !node.kind.isTrigger).toList();
    return Theme(
      data: theme.copyWith(
        splashFactory: InkRipple.splashFactory,
        useMaterial3: false,
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Automation'),
          actions: <Widget>[
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _AutomationActionButton(
                label: 'Save',
                onTap: _saveAutomation,
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: <Widget>[
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Automation name'),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enabled'),
                value: _enabled,
                onChanged: (value) {
                  setState(() {
                    _enabled = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Text('Nodes', style: theme.textTheme.titleLarge),
                  const Spacer(),
                  if (trigger.isEmpty)
                    _AutomationActionButton(
                      label: 'Add trigger',
                      icon: Icons.flash_on_outlined,
                      onTap: () => _addNode(isTrigger: true),
                    )
                  else
                    _AutomationActionButton(
                      label: 'Add action',
                      icon: Icons.add,
                      onTap: () => _addNode(isTrigger: false),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (_nodes.isEmpty)
                Text(
                  'Start with a trigger, then add sequential action and control nodes.',
                  style: theme.textTheme.bodyMedium,
                )
              else
                ..._nodes.asMap().entries.map((entry) {
                  final index = entry.key;
                  final node = entry.value;
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: index == _nodes.length - 1 ? 0 : 10,
                    ),
                    child: _AutomationNodeCard(
                      index: index,
                      node: node,
                      onEdit: () => _editNode(index),
                      onDelete: () {
                        setState(() {
                          _nodes.removeAt(index);
                        });
                      },
                    ),
                  );
                }),
              if (actions.isNotEmpty) ...<Widget>[
                const SizedBox(height: 18),
                Text(
                  'Sequential actions run in the order shown above.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addNode({required bool isTrigger}) async {
    final kind = await showModalBottomSheet<AutomationNodeKind>(
      context: context,
      builder: (BuildContext context) {
        final options = isTrigger
            ? const <AutomationNodeKind>[
                AutomationNodeKind.watchFileChanged,
                AutomationNodeKind.watchDirectoryChanged,
                AutomationNodeKind.turnCompleted,
              ]
            : const <AutomationNodeKind>[
                AutomationNodeKind.didPathChangeSinceLastRun,
                AutomationNodeKind.ifElse,
                AutomationNodeKind.quit,
                AutomationNodeKind.downloadChangedFile,
                AutomationNodeKind.installDownloadedApk,
                AutomationNodeKind.sendMessageToCurrentThread,
                AutomationNodeKind.runCommand,
              ];
        return SafeArea(
          child: Wrap(
            children: options
                .map(
                  (kind) => ListTile(
                    leading: Icon(kind.icon),
                    title: Text(kind.title),
                    onTap: () => Navigator.of(context).pop(kind),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
    if (kind == null || !mounted) {
      return;
    }
    final draft = AutomationNode(
      id: 'node-${DateTime.now().microsecondsSinceEpoch}',
      kind: kind,
    );
    final edited = await Navigator.of(context).push<AutomationNode>(
      MaterialPageRoute<AutomationNode>(
        fullscreenDialog: true,
        builder: (BuildContext context) {
          return AutomationNodeEditorPage(
            controller: widget.controller,
            node: draft,
          );
        },
      ),
    );
    if (edited == null) {
      return;
    }
    setState(() {
      if (kind.isTrigger) {
        _nodes.removeWhere((node) => node.kind.isTrigger);
        _nodes.insert(0, edited);
      } else {
        _nodes.add(edited);
      }
    });
  }

  Future<void> _editNode(int index) async {
    final edited = await Navigator.of(context).push<AutomationNode>(
      MaterialPageRoute<AutomationNode>(
        fullscreenDialog: true,
        builder: (BuildContext context) {
          return AutomationNodeEditorPage(
            controller: widget.controller,
            node: _nodes[index],
          );
        },
      ),
    );
    if (edited == null) {
      return;
    }
    setState(() {
      _nodes[index] = edited;
      if (edited.kind.isTrigger) {
        final triggerIndex = _nodes.indexWhere((node) => node.id == edited.id);
        if (triggerIndex > 0) {
          final trigger = _nodes.removeAt(triggerIndex);
          _nodes.insert(0, trigger);
        }
      }
    });
  }

  Future<void> _saveAutomation() async {
    final name = _nameController.text.trim();
    final hasTrigger = _nodes.any((node) => node.kind.isTrigger);
    final hasAction = _nodes.any((node) => !node.kind.isTrigger);
    if (name.isEmpty || !hasTrigger || !hasAction) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Automation needs a name, one trigger, and at least one action.',
          ),
        ),
      );
      return;
    }
    await widget.controller.saveAutomation(
      widget.initialAutomation.copyWith(
        name: name,
        enabled: _enabled,
        nodes: List<AutomationNode>.from(_nodes),
      ),
    );
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }
}

class _AutomationNodeCard extends StatelessWidget {
  const _AutomationNodeCard({
    required this.index,
    required this.node,
    required this.onEdit,
    required this.onDelete,
  });

  final int index;
  final AutomationNode node;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          radius: 14,
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          child: Text('${index + 1}', style: theme.textTheme.labelSmall),
        ),
        title: Text(node.kind.title),
        subtitle: Text(
          _automationNodeSummary(node),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: onEdit,
        trailing: IconButton(
          tooltip: 'Delete node',
          onPressed: onDelete,
          icon: const Icon(Icons.close),
        ),
      ),
    );
  }
}

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

String _automationNodeSummary(AutomationNode node) {
  switch (node.kind) {
    case AutomationNodeKind.watchFileChanged:
    case AutomationNodeKind.watchDirectoryChanged:
      return node.path.trim().isEmpty ? 'No path configured' : node.path.trim();
    case AutomationNodeKind.turnCompleted:
      return 'Runs after an LLM turn completes.';
    case AutomationNodeKind.didPathChangeSinceLastRun:
      return node.path.trim().isEmpty
          ? 'Compare a file or folder against the previous automation run'
          : 'Compare ${node.path.trim()} against the previous automation run';
    case AutomationNodeKind.ifElse:
      final condition = node.conditionToken.trim().isEmpty
          ? '{{previous.changed}}'
          : node.conditionToken.trim();
      return 'If $condition → ${_branchOutcomeLabel(node.whenTrue)} / ${_branchOutcomeLabel(node.whenFalse)}';
    case AutomationNodeKind.quit:
      return 'Stop the automation immediately.';
    case AutomationNodeKind.downloadChangedFile:
      return node.directory.trim().isEmpty
          ? 'Download to remembered thread directory'
          : 'Download to ${node.directory.trim()}';
    case AutomationNodeKind.installDownloadedApk:
      return 'Install the APK that was downloaded by an earlier node.';
    case AutomationNodeKind.sendMessageToCurrentThread:
      final message = node.commandText.trim();
      return message.isEmpty ? 'No message configured' : message;
    case AutomationNodeKind.runCommand:
      final command = node.commandText.trim();
      final cwd = node.cwd.trim();
      if (command.isEmpty) {
        return 'No command configured';
      }
      if (cwd.isEmpty) {
        return command;
      }
      return '$command • $cwd';
  }
}

String _branchOutcomeLabel(AutomationBranchOutcome value) {
  return switch (value) {
    AutomationBranchOutcome.continueFlow => 'Continue',
    AutomationBranchOutcome.quitFlow => 'Quit',
  };
}
