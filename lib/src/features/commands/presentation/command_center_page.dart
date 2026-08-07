library command_center_page;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../../app_controller.dart';
import '../../../models.dart';

part 'command_center_page/command_form.dart';
part 'command_center_page/shell_tab_row.dart';
part 'command_center_page/terminal_theme.dart';

class CommandCenterPage extends StatefulWidget {
  const CommandCenterPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<CommandCenterPage> createState() => _CommandCenterPageState();
}

class _CommandCenterPageState extends State<CommandCenterPage> {
  late final TextEditingController _cwdController;
  late final TextEditingController _timeoutController;
  late final TextEditingController _outputCapController;
  late final FocusNode _terminalFocusNode;
  late SandboxMode _sandboxMode;
  late bool _allowNetwork;
  bool _disableTimeout = true;
  bool _disableOutputCap = true;
  bool _isStartingShell = false;
  bool _didAttemptAutoStart = false;
  String? _lastSyncedShellSessionId;
  int _viewportRows = 20;
  int _viewportCols = 80;

  @override
  void initState() {
    super.initState();
    _cwdController = TextEditingController();
    _timeoutController = TextEditingController(text: '60000');
    _outputCapController = TextEditingController(text: '32768');
    _terminalFocusNode = FocusNode(debugLabel: 'shell-session-focus');
    _sandboxMode = widget.controller.settings.sandboxMode;
    _allowNetwork = widget.controller.settings.allowNetwork;
    _loadShellFormState(widget.controller.activeShellSession);
  }

  @override
  void dispose() {
    _cwdController.dispose();
    _timeoutController.dispose();
    _outputCapController.dispose();
    _terminalFocusNode.dispose();
    super.dispose();
  }

  Future<void> _ensureShellSession(int rows, int cols) async {
    if (_isStartingShell) {
      return;
    }
    _isStartingShell = true;
    try {
      await widget.controller.ensureInitialShellSession(rows: rows, cols: cols);
      if (mounted) {
        _terminalFocusNode.requestFocus();
      }
    } finally {
      _isStartingShell = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _loadShellFormState(ShellSession? session) {
    final controller = widget.controller;
    _cwdController.text = controller.shellSessionWorkingDirectoryText(session);
    _sandboxMode = session?.sandboxMode ?? controller.settings.sandboxMode;
    _allowNetwork = session?.allowNetwork ?? controller.settings.allowNetwork;
    _disableTimeout = session?.disableTimeout ?? true;
    _timeoutController.text = (session?.timeoutMs ?? 60000).toString();
    _disableOutputCap = session?.disableOutputCap ?? true;
    _outputCapController.text = (session?.outputBytesCap ?? 32768).toString();
    _lastSyncedShellSessionId = session?.id;
  }

  void _applyShellSettings(String? sessionId) {
    if (sessionId == null) {
      return;
    }
    final timeoutMs = int.tryParse(_timeoutController.text.trim()) ?? 0;
    final outputCap = int.tryParse(_outputCapController.text.trim()) ?? 0;
    widget.controller.updateShellSessionSettings(
      sessionId,
      cwdText: _cwdController.text,
      sandboxMode: _sandboxMode,
      allowNetwork: _allowNetwork,
      disableTimeout: _disableTimeout,
      timeoutMs: timeoutMs,
      disableOutputCap: _disableOutputCap,
      outputBytesCap: outputCap,
    );
  }

  Future<void> _handleShellAction() async {
    final shell = widget.controller.activeShellSession;
    if (shell == null) {
      return;
    }
    if (shell.isRunning) {
      await widget.controller.terminateShellSession(shell.id);
      return;
    }
    await widget.controller.restartShellSession(
      shell.id,
      rows: _viewportRows,
      cols: _viewportCols,
    );
    if (mounted) {
      _terminalFocusNode.requestFocus();
    }
  }

  Future<void> _createShellSession() async {
    final controller = widget.controller;
    final activeId = controller.activeShellSession?.id;
    final insertAfterIndex = activeId == null
        ? null
        : controller.shellSessions.indexWhere(
            (session) => session.id == activeId,
          );
    await controller.createShellSession(
      insertAfterIndex: insertAfterIndex == -1 ? null : insertAfterIndex,
      rows: _viewportRows,
      cols: _viewportCols,
    );
    if (mounted) {
      _terminalFocusNode.requestFocus();
    }
  }

  Future<void> _closeShellSession(String sessionId) async {
    await widget.controller.closeShellSession(sessionId);
    if (mounted && widget.controller.activeShellSession != null) {
      _terminalFocusNode.requestFocus();
    }
  }

  Future<void> _openSettingsModal() async {
    _loadShellFormState(widget.controller.activeShellSession);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            final sessionId = widget.controller.activeShellSession?.id;
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                MediaQuery.viewInsetsOf(context).bottom +
                    MediaQuery.paddingOf(context).bottom +
                    20,
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
                      onWorkingDirectoryChanged: (_) {
                        _applyShellSettings(sessionId);
                      },
                      onSandboxChanged: (SandboxMode value) {
                        _sandboxMode = value;
                        _applyShellSettings(sessionId);
                        setModalState(() {});
                      },
                      onAllowNetworkChanged: (bool value) {
                        _allowNetwork = value;
                        _applyShellSettings(sessionId);
                        setModalState(() {});
                      },
                      onDisableTimeoutChanged: (bool value) {
                        _disableTimeout = value;
                        _applyShellSettings(sessionId);
                        setModalState(() {});
                      },
                      onDisableOutputCapChanged: (bool value) {
                        _disableOutputCap = value;
                        _applyShellSettings(sessionId);
                        setModalState(() {});
                      },
                      onTimeoutChanged: (_) {
                        _applyShellSettings(sessionId);
                      },
                      onOutputCapChanged: (_) {
                        _applyShellSettings(sessionId);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, Widget? child) {
        final controller = widget.controller;
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final activeShell = controller.activeShellSession;
        if (_lastSyncedShellSessionId != activeShell?.id) {
          _loadShellFormState(activeShell);
        }
        final terminalTheme = _buildTerminalTheme(theme);
        final terminalTextStyle = TerminalStyle.fromTextStyle(
          theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
                color: terminalTheme.foreground,
              ) ??
              TextStyle(
                fontSize: 14,
                height: 1.4,
                fontFamily: 'monospace',
                color: terminalTheme.foreground,
              ),
        );
        final shell = activeShell;
        final isRunning = shell?.isRunning == true;
        final statusText = !controller.isConnected
            ? 'Disconnected'
            : shell == null
            ? 'Starting shell'
            : shell.statusLabel;
        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: AppBar(
            backgroundColor: theme.appBarTheme.backgroundColor,
            leading: IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            titleSpacing: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Shell',
                  key: ValueKey<String>('command-shell-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  shell?.cwdDisplay ?? statusText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            actions: <Widget>[
              IconButton(
                tooltip: 'Command settings',
                onPressed: _openSettingsModal,
                icon: const Icon(Icons.tune_rounded),
              ),
              IconButton(
                tooltip: isRunning ? 'Terminate shell' : 'Restart shell',
                onPressed: shell == null ? null : _handleShellAction,
                icon: Icon(
                  isRunning ? Icons.stop_circle_outlined : Icons.restart_alt,
                ),
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            bottom: true,
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final rows = (constraints.maxHeight / 18)
                    .floor()
                    .clamp(10, 60)
                    .toInt();
                final cols = (constraints.maxWidth / 9)
                    .floor()
                    .clamp(36, 160)
                    .toInt();
                _viewportRows = rows;
                _viewportCols = cols;
                if (!_didAttemptAutoStart) {
                  _didAttemptAutoStart = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    unawaited(_ensureShellSession(rows, cols));
                  });
                }
                final currentShell = controller.activeShellSession;
                final terminal = currentShell == null
                    ? null
                    : controller.terminalForShellSession(currentShell.id);
                return Column(
                  children: <Widget>[
                    _ShellTabRow(
                      sessions: controller.shellSessions,
                      activeSessionId: currentShell?.id,
                      labelForSession: controller.shellSessionTabLabel,
                      onSessionSelected: (String sessionId) {
                        controller.selectShellSession(sessionId);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            _terminalFocusNode.requestFocus();
                          }
                        });
                      },
                      onCloseSession: _closeShellSession,
                      onCreateShell: _createShellSession,
                    ),
                    Expanded(
                      child: Container(
                        key: const ValueKey<String>('command-shell-panel'),
                        color: terminalTheme.background,
                        child: terminal == null
                            ? Center(
                                child: Text(
                                  statusText,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              )
                            : TerminalView(
                                terminal,
                                autofocus: true,
                                focusNode: _terminalFocusNode,
                                theme: terminalTheme,
                                textStyle: terminalTextStyle,
                                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                                backgroundOpacity: 1,
                                cursorType: TerminalCursorType.block,
                                keyboardAppearance: scheme.brightness,
                                keyboardType: TextInputType.visiblePassword,
                                readOnly: !controller.isConnected || !isRunning,
                              ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}
