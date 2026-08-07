import '../../settings/domain/app_settings.dart';

enum CommandSessionMode { buffered, interactive }

enum ShellSpawnCwdMode { threadPath, home }

class ShellSession {
  ShellSession({
    required this.id,
    required this.processId,
    required this.cwdDisplay,
    required this.spawnCwdMode,
    required this.spawnCwdPath,
    required this.sandboxMode,
    required this.allowNetwork,
    required this.disableTimeout,
    required this.timeoutMs,
    required this.disableOutputCap,
    required this.outputBytesCap,
    required this.usesTty,
    required this.startedAt,
    this.status = 'running',
    this.stdinClosed = false,
    this.exitCode,
  });

  final String id;
  final String processId;
  final String cwdDisplay;
  final ShellSpawnCwdMode spawnCwdMode;
  final String spawnCwdPath;
  final SandboxMode sandboxMode;
  final bool allowNetwork;
  final bool disableTimeout;
  final int timeoutMs;
  final bool disableOutputCap;
  final int outputBytesCap;
  final bool usesTty;
  final DateTime startedAt;
  String status;
  bool stdinClosed;
  int? exitCode;

  bool get isRunning => status == 'running';

  ShellSession copyWith({
    String? id,
    String? processId,
    String? cwdDisplay,
    ShellSpawnCwdMode? spawnCwdMode,
    String? spawnCwdPath,
    SandboxMode? sandboxMode,
    bool? allowNetwork,
    bool? disableTimeout,
    int? timeoutMs,
    bool? disableOutputCap,
    int? outputBytesCap,
    bool? usesTty,
    DateTime? startedAt,
    String? status,
    bool? stdinClosed,
    int? exitCode,
    bool clearExitCode = false,
  }) {
    return ShellSession(
      id: id ?? this.id,
      processId: processId ?? this.processId,
      cwdDisplay: cwdDisplay ?? this.cwdDisplay,
      spawnCwdMode: spawnCwdMode ?? this.spawnCwdMode,
      spawnCwdPath: spawnCwdPath ?? this.spawnCwdPath,
      sandboxMode: sandboxMode ?? this.sandboxMode,
      allowNetwork: allowNetwork ?? this.allowNetwork,
      disableTimeout: disableTimeout ?? this.disableTimeout,
      timeoutMs: timeoutMs ?? this.timeoutMs,
      disableOutputCap: disableOutputCap ?? this.disableOutputCap,
      outputBytesCap: outputBytesCap ?? this.outputBytesCap,
      usesTty: usesTty ?? this.usesTty,
      startedAt: startedAt ?? this.startedAt,
      status: status ?? this.status,
      stdinClosed: stdinClosed ?? this.stdinClosed,
      exitCode: clearExitCode ? null : (exitCode ?? this.exitCode),
    );
  }

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
