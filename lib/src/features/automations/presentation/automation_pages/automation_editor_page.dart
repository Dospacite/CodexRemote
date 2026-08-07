part of automation_pages;

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
