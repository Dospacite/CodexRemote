import '../../settings/domain/app_settings.dart';

enum CommandSessionMode { buffered, interactive }

class RecentCommand {
  const RecentCommand({
    required this.commandText,
    required this.cwd,
    required this.mode,
    required this.sandboxMode,
    required this.allowNetwork,
    required this.disableTimeout,
    required this.timeoutMs,
    required this.disableOutputCap,
    required this.outputBytesCap,
  });

  final String commandText;
  final String cwd;
  final CommandSessionMode mode;
  final SandboxMode sandboxMode;
  final bool allowNetwork;
  final bool disableTimeout;
  final int timeoutMs;
  final bool disableOutputCap;
  final int outputBytesCap;
}

class CommandSession {
  CommandSession({
    required this.id,
    required this.processId,
    required this.commandDisplay,
    required this.cwd,
    required this.mode,
    required this.usesTty,
    required this.startedAt,
    this.exitCode,
    this.stdout = '',
    this.stderr = '',
    this.status = 'running',
    this.stdinClosed = false,
    this.outputCapReached = false,
  });

  final String id;
  final String processId;
  final String commandDisplay;
  final String cwd;
  final CommandSessionMode mode;
  final bool usesTty;
  final DateTime startedAt;
  int? exitCode;
  String stdout;
  String stderr;
  String status;
  bool stdinClosed;
  bool outputCapReached;

  bool get isRunning => status == 'running';
  bool get isInteractive => mode == CommandSessionMode.interactive;

  String get statusLabel {
    if (isRunning) {
      return 'running';
    }
    if (exitCode != null) {
      return 'exit $exitCode';
    }
    return status;
  }
}
