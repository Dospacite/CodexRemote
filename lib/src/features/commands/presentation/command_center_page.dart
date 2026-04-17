import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app_controller.dart';
import '../../../models.dart';
import '../../../core/widgets/monospace_output_view.dart';

class CommandCenterPage extends StatefulWidget {
  const CommandCenterPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<CommandCenterPage> createState() => _CommandCenterPageState();
}

class _CommandCenterPageState extends State<CommandCenterPage> {
  late final TextEditingController _commandController;
  late final TextEditingController _stdinController;
  late final TextEditingController _cwdController;
  late final TextEditingController _timeoutController;
  late final TextEditingController _outputCapController;
  late SandboxMode _sandboxMode;
  late bool _allowNetwork;
  bool _disableTimeout = true;
  bool _disableOutputCap = true;
  int _lastRows = 0;
  int _lastCols = 0;

  @override
  void initState() {
    super.initState();
    final controller = widget.controller;
    final settings = controller.settings;
    _commandController = TextEditingController();
    _commandController.addListener(_handleLocalInputChanged);
    _stdinController = TextEditingController();
    _stdinController.addListener(_handleLocalInputChanged);
    _cwdController = TextEditingController(
      text: controller.preferredCommandCwd,
    );
    _timeoutController = TextEditingController(text: '60000');
    _outputCapController = TextEditingController(text: '32768');
    _sandboxMode = settings.sandboxMode;
    _allowNetwork = settings.allowNetwork;
  }

  @override
  void dispose() {
    _commandController.removeListener(_handleLocalInputChanged);
    _commandController.dispose();
    _stdinController.removeListener(_handleLocalInputChanged);
    _stdinController.dispose();
    _cwdController.dispose();
    _timeoutController.dispose();
    _outputCapController.dispose();
    super.dispose();
  }

  void _handleLocalInputChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, Widget? child) {
        final activeSession = widget.controller.activeCommandSession;
        final preferredCwd = widget.controller.preferredCommandCwd;
        final runningSessionCount = widget.controller.commandSessions
            .where((session) => session.isRunning)
            .length;
        if (_commandController.text.isEmpty &&
            _cwdController.text.trim().isEmpty &&
            preferredCwd.isNotEmpty) {
          _cwdController.text = preferredCwd;
        }
        return Scaffold(
          resizeToAvoidBottomInset: false,
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Command settings',
              onPressed: _openSettingsModal,
              icon: const Icon(Icons.settings_outlined),
            ),
            title: const Text('Command Center'),
            actions: <Widget>[
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final wideLayout = constraints.maxWidth >= 960;
                  final historyPanel = _CommandHistoryPanel(
                    controller: widget.controller,
                    canRepeat: _commandController.text.trim().isEmpty,
                    onRepeat: _repeatCommandFromHistory,
                  );
                  final terminalPanel = _CommandSessionView(
                    session: activeSession,
                    stdinController: _stdinController,
                    onSubmitStdin: _submitTerminalInput,
                    onSendQuickInput: activeSession == null
                        ? null
                        : (String input) => widget.controller
                              .writeToCommandSession(activeSession.id, input),
                    onTerminate: activeSession == null
                        ? null
                        : () => widget.controller.terminateCommandSession(
                            activeSession.id,
                          ),
                    onResize: activeSession == null
                        ? null
                        : (int rows, int cols) {
                            if (_lastRows == rows && _lastCols == cols) {
                              return;
                            }
                            _lastRows = rows;
                            _lastCols = cols;
                            widget.controller.resizeCommandSession(
                              activeSession.id,
                              rows: rows,
                              cols: cols,
                            );
                          },
                  );

                  final launcher = _CommandLauncherCard(
                    commandController: _commandController,
                    cwdController: _cwdController,
                    sandboxMode: _sandboxMode,
                    allowNetwork: _allowNetwork,
                    disableTimeout: _disableTimeout,
                    timeoutMs:
                        int.tryParse(_timeoutController.text.trim()) ?? 0,
                    disableOutputCap: _disableOutputCap,
                    outputBytesCap:
                        int.tryParse(_outputCapController.text.trim()) ?? 0,
                    runningSessionCount: runningSessionCount,
                    onRun: _runCommand,
                    onOpenSettings: _openSettingsModal,
                  );

                  if (wideLayout) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SizedBox(
                          width: constraints.maxWidth * 0.34,
                          child: launcher,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              SizedBox(height: 156, child: historyPanel),
                              const SizedBox(height: 14),
                              Expanded(child: terminalPanel),
                            ],
                          ),
                        ),
                      ],
                    );
                  }

                  return SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        launcher,
                        const SizedBox(height: 14),
                        SizedBox(height: 108, child: historyPanel),
                        const SizedBox(height: 14),
                        SizedBox(height: 360, child: terminalPanel),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _runCommand() async {
    final commandText = _commandController.text;
    if (commandText.trim().isEmpty) {
      return;
    }
    final timeoutMs = int.tryParse(_timeoutController.text.trim()) ?? 0;
    final outputCap = int.tryParse(_outputCapController.text.trim()) ?? 0;
    final disableTimeout =
        _disableTimeout || _looksLikeFlutterBuildCommand(commandText);
    await widget.controller.startCommandExecution(
      commandText: commandText,
      cwd: _cwdController.text,
      sandboxMode: _sandboxMode,
      allowNetwork: _allowNetwork,
      mode: CommandSessionMode.interactive,
      timeoutMs: timeoutMs,
      disableTimeout: disableTimeout,
      outputBytesCap: outputCap,
      disableOutputCap: _disableOutputCap,
      rows: 24,
      cols: 96,
    );
    _commandController.clear();
  }

  bool _looksLikeFlutterBuildCommand(String commandText) {
    return RegExp(r'(^|\s)flutter\s+build(\s|$)').hasMatch(commandText.trim());
  }

  Future<void> _sendCommandInput(CommandSession session) async {
    final text = _stdinController.text;
    if (text.isEmpty) {
      return;
    }
    _stdinController.clear();
    await widget.controller.writeToCommandSession(session.id, '$text\n');
  }

  Future<void> _submitTerminalInput() async {
    final session = widget.controller.activeCommandSession;
    final canSendToInteractive =
        session != null &&
        session.isInteractive &&
        session.isRunning &&
        !session.stdinClosed;
    if (!canSendToInteractive) {
      return;
    }
    await _sendCommandInput(session);
  }

  void _applyRecentCommand(RecentCommand recent) {
    _commandController.text = recent.commandText;
    _cwdController.text = recent.cwd;
    _timeoutController.text = recent.timeoutMs.toString();
    _outputCapController.text = recent.outputBytesCap.toString();
    setState(() {
      _sandboxMode = recent.sandboxMode;
      _allowNetwork = recent.allowNetwork;
      _disableTimeout = recent.disableTimeout;
      _disableOutputCap = recent.disableOutputCap;
    });
  }

  void _repeatCommandFromHistory(CommandSession session) {
    if (_commandController.text.trim().isNotEmpty) {
      return;
    }
    final command = session.commandDisplay.trim();
    if (command.isEmpty) {
      return;
    }
    _commandController
      ..text = command
      ..selection = TextSelection.collapsed(offset: command.length);
  }

  Future<void> _openSettingsModal() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return FractionallySizedBox(
              heightFactor: 0.82,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  MediaQuery.viewInsetsOf(context).bottom + 20,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _CommandForm(
                        cwdController: _cwdController,
                        timeoutController: _timeoutController,
                        outputCapController: _outputCapController,
                        sandboxMode: _sandboxMode,
                        allowNetwork: _allowNetwork,
                        disableTimeout: _disableTimeout,
                        disableOutputCap: _disableOutputCap,
                        onSandboxChanged: (SandboxMode value) {
                          setState(() => _sandboxMode = value);
                          setModalState(() {});
                        },
                        onAllowNetworkChanged: (bool value) {
                          setState(() => _allowNetwork = value);
                          setModalState(() {});
                        },
                        onDisableTimeoutChanged: (bool value) {
                          setState(() => _disableTimeout = value);
                          setModalState(() {});
                        },
                        onDisableOutputCapChanged: (bool value) {
                          setState(() => _disableOutputCap = value);
                          setModalState(() {});
                        },
                      ),
                      const SizedBox(height: 12),
                      _SavedCommandPanel(
                        controller: widget.controller,
                        onTapCommand: (RecentCommand recent) {
                          _applyRecentCommand(recent);
                          Navigator.of(context).pop();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _CommandForm extends StatelessWidget {
  const _CommandForm({
    required this.cwdController,
    required this.timeoutController,
    required this.outputCapController,
    required this.sandboxMode,
    required this.allowNetwork,
    required this.disableTimeout,
    required this.disableOutputCap,
    required this.onSandboxChanged,
    required this.onAllowNetworkChanged,
    required this.onDisableTimeoutChanged,
    required this.onDisableOutputCapChanged,
  });

  final TextEditingController cwdController;
  final TextEditingController timeoutController;
  final TextEditingController outputCapController;
  final SandboxMode sandboxMode;
  final bool allowNetwork;
  final bool disableTimeout;
  final bool disableOutputCap;
  final ValueChanged<SandboxMode> onSandboxChanged;
  final ValueChanged<bool> onAllowNetworkChanged;
  final ValueChanged<bool> onDisableTimeoutChanged;
  final ValueChanged<bool> onDisableOutputCapChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Setup', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.terminal_outlined),
            title: const Text('Interactive shell'),
            subtitle: const Text('Commands always run in interactive mode.'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: cwdController,
            decoration: const InputDecoration(labelText: 'Working directory'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<SandboxMode>(
            initialValue: sandboxMode,
            decoration: const InputDecoration(labelText: 'Sandbox'),
            items: SandboxMode.values
                .map(
                  (SandboxMode item) => DropdownMenuItem<SandboxMode>(
                    value: item,
                    child: Text(item.name),
                  ),
                )
                .toList(),
            onChanged: (SandboxMode? value) {
              if (value != null) {
                onSandboxChanged(value);
              }
            },
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Network'),
            value: allowNetwork,
            onChanged: onAllowNetworkChanged,
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Disable timeout'),
            value: disableTimeout,
            onChanged: onDisableTimeoutChanged,
          ),
          if (!disableTimeout) ...<Widget>[
            TextField(
              controller: timeoutController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Timeout ms'),
            ),
            const SizedBox(height: 8),
          ],
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Disable output cap'),
            value: disableOutputCap,
            onChanged: onDisableOutputCapChanged,
          ),
          if (!disableOutputCap) ...<Widget>[
            TextField(
              controller: outputCapController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Output cap bytes'),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _CommandLauncherCard extends StatelessWidget {
  const _CommandLauncherCard({
    required this.commandController,
    required this.cwdController,
    required this.sandboxMode,
    required this.allowNetwork,
    required this.disableTimeout,
    required this.timeoutMs,
    required this.disableOutputCap,
    required this.outputBytesCap,
    required this.runningSessionCount,
    required this.onRun,
    required this.onOpenSettings,
  });

  final TextEditingController commandController;
  final TextEditingController cwdController;
  final SandboxMode sandboxMode;
  final bool allowNetwork;
  final bool disableTimeout;
  final int timeoutMs;
  final bool disableOutputCap;
  final int outputBytesCap;
  final int runningSessionCount;
  final Future<void> Function() onRun;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final runEnabled = commandController.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.terminal_rounded, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Launch Command', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      runningSessionCount == 0
                          ? 'Start a fresh shell session.'
                          : '$runningSessionCount live session${runningSessionCount == 1 ? '' : 's'} connected.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: onOpenSettings,
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('Options'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            key: const ValueKey<String>('command-shell-input'),
            controller: commandController,
            onSubmitted: (_) {
              unawaited(onRun());
            },
            textInputAction: TextInputAction.go,
            maxLines: 1,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
            ),
            decoration: const InputDecoration(
              labelText: 'Command',
              hintText: 'npm test  or  flutter build apk --release',
              prefixIcon: Icon(Icons.code_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: cwdController,
            maxLines: 1,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
            ),
            decoration: const InputDecoration(
              labelText: 'Working directory',
              hintText: '/workspace/project',
              prefixIcon: Icon(Icons.folder_open_rounded),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _CommandSettingChip(
                icon: Icons.shield_outlined,
                label: _sandboxLabel(sandboxMode),
              ),
              _CommandSettingChip(
                icon: allowNetwork
                    ? Icons.public_rounded
                    : Icons.public_off_rounded,
                label: allowNetwork ? 'Network on' : 'Network off',
              ),
              _CommandSettingChip(
                icon: Icons.timer_outlined,
                label: disableTimeout
                    ? 'No timeout'
                    : '${timeoutMs <= 0 ? 60000 : timeoutMs} ms',
              ),
              _CommandSettingChip(
                icon: Icons.unfold_more_rounded,
                label: disableOutputCap
                    ? 'Uncapped output'
                    : '${outputBytesCap <= 0 ? 32768 : outputBytesCap} bytes',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Commands run via `/bin/bash -lc` and keep streaming output in the selected session below.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: runEnabled
                    ? () {
                        unawaited(onRun());
                      }
                    : null,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Run'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CommandSettingChip extends StatelessWidget {
  const _CommandSettingChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _CommandSessionCard extends StatelessWidget {
  const _CommandSessionCard({
    required this.session,
    required this.selected,
    required this.onTap,
    required this.canRepeat,
    required this.onRepeat,
    required this.onTerminate,
  });

  final CommandSession session;
  final bool selected;
  final VoidCallback onTap;
  final bool canRepeat;
  final VoidCallback onRepeat;
  final VoidCallback onTerminate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusColor = session.isRunning
        ? scheme.primary
        : session.exitCode == 0
        ? scheme.secondary
        : scheme.error;

    return SizedBox(
      width: 250,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.10)
                : scheme.surfaceContainerLow,
            border: Border.all(
              color: selected ? scheme.primary : theme.dividerColor,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: selected
                ? <BoxShadow>[
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.10),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        session.commandDisplay,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                          color: selected ? scheme.onSurface : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      session.outputCapReached
                          ? '${session.statusLabel} • cap'
                          : session.statusLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Repeat',
                onPressed: canRepeat ? onRepeat : null,
                visualDensity: const VisualDensity(
                  horizontal: -4,
                  vertical: -4,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                splashRadius: 16,
                icon: const Icon(Icons.replay_rounded, size: 16),
              ),
              if (session.isRunning)
                IconButton(
                  tooltip: 'Terminate',
                  onPressed: onTerminate,
                  visualDensity: const VisualDensity(
                    horizontal: -4,
                    vertical: -4,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  splashRadius: 16,
                  icon: const Icon(Icons.stop_circle_outlined, size: 16),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentCommandCard extends StatelessWidget {
  const _RecentCommandCard({
    required this.command,
    required this.onTap,
    required this.onRemove,
  });

  final RecentCommand command;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    command.commandText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    command.sandboxMode.name,
                    style: theme.textTheme.bodySmall,
                  ),
                  if (command.cwd.isNotEmpty)
                    Text(
                      command.cwd,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remove saved command',
              onPressed: onRemove,
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              splashRadius: 16,
              icon: const Icon(Icons.close, size: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommandSessionView extends StatefulWidget {
  const _CommandSessionView({
    required this.session,
    required this.stdinController,
    required this.onSubmitStdin,
    required this.onSendQuickInput,
    required this.onTerminate,
    required this.onResize,
  });

  final CommandSession? session;
  final TextEditingController stdinController;
  final Future<void> Function() onSubmitStdin;
  final Future<void> Function(String input)? onSendQuickInput;
  final VoidCallback? onTerminate;
  final void Function(int rows, int cols)? onResize;

  @override
  State<_CommandSessionView> createState() => _CommandSessionViewState();
}

class _CommandSessionViewState extends State<_CommandSessionView> {
  final ScrollController _verticalOutputController = ScrollController();
  final ScrollController _horizontalOutputController = ScrollController();

  @override
  void didUpdateWidget(covariant _CommandSessionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previousId = oldWidget.session?.id;
    final nextId = widget.session?.id;
    final previousOutputLength =
        (oldWidget.session?.stdout.length ?? 0) +
        (oldWidget.session?.stderr.length ?? 0);
    final nextOutputLength =
        (widget.session?.stdout.length ?? 0) +
        (widget.session?.stderr.length ?? 0);
    if (previousId != nextId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_horizontalOutputController.hasClients) {
          _horizontalOutputController.jumpTo(0);
        }
        _scrollToLatest(force: true);
      });
      return;
    }
    if (nextOutputLength > previousOutputLength) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToLatest();
      });
    }
  }

  @override
  void dispose() {
    _verticalOutputController.dispose();
    _horizontalOutputController.dispose();
    super.dispose();
  }

  void _scrollToLatest({bool force = false}) {
    if (!_verticalOutputController.hasClients) {
      return;
    }
    final position = _verticalOutputController.position;
    final distanceFromBottom = position.maxScrollExtent - position.pixels;
    final shouldFollow = force || distanceFromBottom < 56;
    if (!shouldFollow) {
      return;
    }
    _verticalOutputController.animateTo(
      position.maxScrollExtent,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final outputBackground = Color.alphaBlend(
      scheme.primary.withValues(alpha: 0.05),
      scheme.surfaceContainerLow,
    );
    final interactiveInput =
        session != null &&
        session.isInteractive &&
        session.isRunning &&
        !session.stdinClosed;
    return Container(
      key: const ValueKey<String>('command-shell-panel'),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        session?.commandDisplay ?? 'Shell',
                        key: const ValueKey<String>('command-shell-title'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          _InlineTerminalPill(
                            label: session?.statusLabel ?? 'idle',
                            color: session == null
                                ? scheme.onSurfaceVariant
                                : session.isRunning
                                ? scheme.primary
                                : session.exitCode == 0
                                ? scheme.secondary
                                : scheme.error,
                          ),
                          _InlineTerminalPill(
                            label: session?.usesTty == true ? 'PTY' : 'stream',
                          ),
                          if (session?.stdinClosed == true)
                            const _InlineTerminalPill(label: 'stdin closed'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        session?.cwd.isNotEmpty == true
                            ? session!.cwd
                            : 'Select a session or run a command to stream output here.',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.onTerminate != null)
                  IconButton(
                    tooltip: 'Terminate',
                    onPressed: session?.isRunning == true
                        ? widget.onTerminate
                        : null,
                    icon: const Icon(Icons.stop_circle_outlined),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.dividerColor),
          Expanded(
            child: Container(
              color: outputBackground,
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final rows = (constraints.maxHeight / 18).floor().clamp(
                    10,
                    60,
                  );
                  final cols = (constraints.maxWidth / 8).floor().clamp(
                    40,
                    160,
                  );
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (session != null &&
                        session.isInteractive &&
                        session.usesTty &&
                        session.isRunning &&
                        widget.onResize != null) {
                      widget.onResize!(rows, cols);
                    }
                  });
                  return Scrollbar(
                    controller: _verticalOutputController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _verticalOutputController,
                      primary: false,
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                      child: Scrollbar(
                        controller: _horizontalOutputController,
                        thumbVisibility: true,
                        notificationPredicate: (notification) =>
                            notification.metrics.axis == Axis.horizontal,
                        child: SingleChildScrollView(
                          controller: _horizontalOutputController,
                          primary: false,
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: constraints.maxWidth - 28,
                              minHeight: constraints.maxHeight > 28
                                  ? constraints.maxHeight - 28
                                  : 0,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                if (session != null &&
                                    session.stdout.isNotEmpty)
                                  MonospaceOutputView(
                                    text: session.stdout,
                                    scrollable: false,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontFamily: 'monospace',
                                      height: 1.24,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                if (session == null)
                                  Text(
                                    '\$ Run a command to open a live shell session.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontFamily: 'monospace',
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                if (session != null &&
                                    session.stdout.isEmpty &&
                                    session.stderr.isEmpty)
                                  Text(
                                    session.isRunning
                                        ? 'Waiting for output...'
                                        : 'Command produced no output.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontFamily: 'monospace',
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                if (session != null &&
                                    session.outputCapReached) ...<Widget>[
                                  const SizedBox(height: 10),
                                  Text(
                                    'Output cap reached',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontFamily: 'monospace',
                                      color: scheme.secondary,
                                    ),
                                  ),
                                ],
                                if (session != null &&
                                    session.stderr.isNotEmpty) ...<Widget>[
                                  const SizedBox(height: 12),
                                  Text(
                                    'stderr',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.error,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  MonospaceOutputView(
                                    text: session.stderr,
                                    scrollable: false,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontFamily: 'monospace',
                                      color: scheme.error,
                                      height: 1.24,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Divider(height: 1, color: theme.dividerColor),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: <Widget>[
                      _TerminalQuickButton(
                        label: 'Ctrl+C',
                        onPressed:
                            interactiveInput && widget.onSendQuickInput != null
                            ? () {
                                unawaited(widget.onSendQuickInput!('\u0003'));
                              }
                            : null,
                      ),
                      _TerminalQuickButton(
                        label: 'Ctrl+D',
                        onPressed:
                            interactiveInput && widget.onSendQuickInput != null
                            ? () {
                                unawaited(widget.onSendQuickInput!('\u0004'));
                              }
                            : null,
                      ),
                      _TerminalQuickButton(
                        label: 'Esc',
                        onPressed:
                            interactiveInput && widget.onSendQuickInput != null
                            ? () {
                                unawaited(widget.onSendQuickInput!('\u001B'));
                              }
                            : null,
                      ),
                      _TerminalQuickButton(
                        label: 'Tab',
                        onPressed:
                            interactiveInput && widget.onSendQuickInput != null
                            ? () {
                                unawaited(widget.onSendQuickInput!('\t'));
                              }
                            : null,
                      ),
                      _TerminalQuickButton(
                        label: '↑',
                        onPressed:
                            interactiveInput && widget.onSendQuickInput != null
                            ? () {
                                unawaited(widget.onSendQuickInput!('\u001B[A'));
                              }
                            : null,
                      ),
                      _TerminalQuickButton(
                        label: '↓',
                        onPressed:
                            interactiveInput && widget.onSendQuickInput != null
                            ? () {
                                unawaited(widget.onSendQuickInput!('\u001B[B'));
                              }
                            : null,
                      ),
                      _TerminalQuickButton(
                        label: '←',
                        onPressed:
                            interactiveInput && widget.onSendQuickInput != null
                            ? () {
                                unawaited(widget.onSendQuickInput!('\u001B[D'));
                              }
                            : null,
                      ),
                      _TerminalQuickButton(
                        label: '→',
                        onPressed:
                            interactiveInput && widget.onSendQuickInput != null
                            ? () {
                                unawaited(widget.onSendQuickInput!('\u001B[C'));
                              }
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '\$',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFamily: 'monospace',
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        key: const ValueKey<String>('command-stdin-input'),
                        controller: widget.stdinController,
                        onSubmitted: (_) {
                          unawaited(widget.onSubmitStdin());
                        },
                        enabled: interactiveInput,
                        textInputAction: TextInputAction.send,
                        maxLines: 1,
                        cursorColor: scheme.primary,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: interactiveInput
                              ? 'stdin to active process'
                              : 'interactive input is unavailable for this session',
                        ),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                          color: scheme.onSurface,
                          height: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed:
                          interactiveInput &&
                              widget.stdinController.text.isNotEmpty
                          ? () {
                              unawaited(widget.onSubmitStdin());
                            }
                          : null,
                      child: const Text('Send'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommandHistoryPanel extends StatelessWidget {
  const _CommandHistoryPanel({
    required this.controller,
    required this.canRepeat,
    required this.onRepeat,
  });

  final AppController controller;
  final bool canRepeat;
  final ValueChanged<CommandSession> onRepeat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFinishedSessions = controller.commandSessions.any(
      (session) => !session.isRunning,
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('Shell history', style: theme.textTheme.titleMedium),
              const Spacer(),
              IconButton(
                tooltip: 'Clear finished runs',
                onPressed: hasFinishedSessions
                    ? controller.clearFinishedCommandSessions
                    : null,
                visualDensity: const VisualDensity(
                  horizontal: -4,
                  vertical: -4,
                ),
                icon: const Icon(Icons.delete_outline),
              ),
              if (controller.commandSessions.isNotEmpty)
                Text(
                  '${controller.commandSessions.length}',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: controller.commandSessions.isEmpty
                ? Center(
                    child: Text(
                      'No shell commands yet.',
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: controller.commandSessions.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (BuildContext context, int index) {
                      final session = controller.commandSessions[index];
                      final selected =
                          controller.activeCommandSession?.id == session.id;
                      return _CommandSessionCard(
                        session: session,
                        selected: selected,
                        canRepeat: canRepeat,
                        onRepeat: () => onRepeat(session),
                        onTap: () =>
                            controller.selectCommandSession(session.id),
                        onTerminate: () =>
                            controller.terminateCommandSession(session.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _InlineTerminalPill extends StatelessWidget {
  const _InlineTerminalPill({required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor = color ?? theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: effectiveColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: effectiveColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TerminalQuickButton extends StatelessWidget {
  const _TerminalQuickButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: const Size(0, 36),
        ),
        child: Text(label),
      ),
    );
  }
}

String _sandboxLabel(SandboxMode mode) {
  return switch (mode) {
    SandboxMode.workspaceWrite => 'Workspace write',
    SandboxMode.readOnly => 'Read only',
    SandboxMode.dangerFullAccess => 'Danger full access',
  };
}

class _SavedCommandPanel extends StatelessWidget {
  const _SavedCommandPanel({
    required this.controller,
    required this.onTapCommand,
  });

  final AppController controller;
  final ValueChanged<RecentCommand> onTapCommand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('Saved', style: theme.textTheme.titleMedium),
              const Spacer(),
              if (controller.recentCommands.isNotEmpty)
                Text(
                  '${controller.recentCommands.length}',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (controller.recentCommands.isEmpty)
            Text(
              'Saved commands appear here after you run them.',
              style: theme.textTheme.bodySmall,
            )
          else
            ...controller.recentCommands.map((recent) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _RecentCommandCard(
                  command: recent,
                  onTap: () => onTapCommand(recent),
                  onRemove: () => controller.removeRecentCommand(recent),
                ),
              );
            }),
        ],
      ),
    );
  }
}
