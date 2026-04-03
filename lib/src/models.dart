import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

enum ThemePreference { system, light, dark }

enum SandboxMode { workspaceWrite, readOnly, dangerFullAccess }

enum ConnectionStatus { disconnected, connecting, initializing, ready, error }

enum ConnectionMode { direct, relay }

enum EntryKind { user, agent, reasoning, command, fileChange, tool, system }

const Set<String> validApprovalPolicies = <String>{
  'untrusted',
  'on-request',
  'on-failure',
  'never',
};

String normalizeApprovalPolicy(String? value) {
  final raw = (value ?? '').trim();
  if (raw == 'unlessTrusted') {
    return 'untrusted';
  }
  if (validApprovalPolicies.contains(raw)) {
    return raw;
  }
  return 'untrusted';
}

class AppSettings {
  const AppSettings({
    required this.connectionMode,
    required this.serverUrl,
    required this.websocketBearerToken,
    required this.relayUrl,
    required this.relayDeviceId,
    required this.relayBridgeLabel,
    required this.relayBridgeSigningPublicKey,
    required this.relayClientPrivateKey,
    required this.relayClientPublicKey,
    required this.model,
    required this.reasoningEffort,
    required this.planMode,
    required this.approvalPolicy,
    required this.sandboxMode,
    required this.allowNetwork,
    required this.themePreference,
    required this.resumeThreadId,
    required this.favoriteThreadIds,
    required this.threadDownloadDirectories,
    required this.automationSnapshots,
    required this.automations,
  });

  factory AppSettings.defaults() {
    return const AppSettings(
      connectionMode: ConnectionMode.direct,
      serverUrl: 'ws://127.0.0.1:8080',
      websocketBearerToken: '',
      relayUrl: '',
      relayDeviceId: '',
      relayBridgeLabel: '',
      relayBridgeSigningPublicKey: '',
      relayClientPrivateKey: '',
      relayClientPublicKey: '',
      model: '',
      reasoningEffort: 'medium',
      planMode: false,
      approvalPolicy: 'untrusted',
      sandboxMode: SandboxMode.workspaceWrite,
      allowNetwork: false,
      themePreference: ThemePreference.system,
      resumeThreadId: '',
      favoriteThreadIds: <String>[],
      threadDownloadDirectories: <String, String>{},
      automationSnapshots: <String, Map<String, String>>{},
      automations: <AutomationDefinition>[],
    );
  }

  final ConnectionMode connectionMode;
  final String serverUrl;
  final String websocketBearerToken;
  final String relayUrl;
  final String relayDeviceId;
  final String relayBridgeLabel;
  final String relayBridgeSigningPublicKey;
  final String relayClientPrivateKey;
  final String relayClientPublicKey;
  final String model;
  final String reasoningEffort;
  final bool planMode;
  final String approvalPolicy;
  final SandboxMode sandboxMode;
  final bool allowNetwork;
  final ThemePreference themePreference;
  final String resumeThreadId;
  final List<String> favoriteThreadIds;
  final Map<String, String> threadDownloadDirectories;
  final Map<String, Map<String, String>> automationSnapshots;
  final List<AutomationDefinition> automations;

  ThemeMode get materialThemeMode {
    return switch (themePreference) {
      ThemePreference.system => ThemeMode.system,
      ThemePreference.light => ThemeMode.light,
      ThemePreference.dark => ThemeMode.dark,
    };
  }

  String get activeConnectionLabel {
    if (connectionMode == ConnectionMode.relay) {
      final relay = relayUrl.trim();
      if (relay.isNotEmpty) {
        return relay;
      }
    }
    return serverUrl.trim();
  }

  AppSettings copyWith({
    ConnectionMode? connectionMode,
    String? serverUrl,
    String? websocketBearerToken,
    String? relayUrl,
    String? relayDeviceId,
    String? relayBridgeLabel,
    String? relayBridgeSigningPublicKey,
    String? relayClientPrivateKey,
    String? relayClientPublicKey,
    String? model,
    String? reasoningEffort,
    bool? planMode,
    String? approvalPolicy,
    SandboxMode? sandboxMode,
    bool? allowNetwork,
    ThemePreference? themePreference,
    String? resumeThreadId,
    List<String>? favoriteThreadIds,
    Map<String, String>? threadDownloadDirectories,
    Map<String, Map<String, String>>? automationSnapshots,
    List<AutomationDefinition>? automations,
  }) {
    return AppSettings(
      connectionMode: connectionMode ?? this.connectionMode,
      serverUrl: serverUrl ?? this.serverUrl,
      websocketBearerToken: websocketBearerToken ?? this.websocketBearerToken,
      relayUrl: relayUrl ?? this.relayUrl,
      relayDeviceId: relayDeviceId ?? this.relayDeviceId,
      relayBridgeLabel: relayBridgeLabel ?? this.relayBridgeLabel,
      relayBridgeSigningPublicKey:
          relayBridgeSigningPublicKey ?? this.relayBridgeSigningPublicKey,
      relayClientPrivateKey:
          relayClientPrivateKey ?? this.relayClientPrivateKey,
      relayClientPublicKey: relayClientPublicKey ?? this.relayClientPublicKey,
      model: model ?? this.model,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      planMode: planMode ?? this.planMode,
      approvalPolicy: normalizeApprovalPolicy(
        approvalPolicy ?? this.approvalPolicy,
      ),
      sandboxMode: sandboxMode ?? this.sandboxMode,
      allowNetwork: allowNetwork ?? this.allowNetwork,
      themePreference: themePreference ?? this.themePreference,
      resumeThreadId: resumeThreadId ?? this.resumeThreadId,
      favoriteThreadIds: favoriteThreadIds ?? this.favoriteThreadIds,
      threadDownloadDirectories:
          threadDownloadDirectories ?? this.threadDownloadDirectories,
      automationSnapshots: automationSnapshots ?? this.automationSnapshots,
      automations: automations ?? this.automations,
    );
  }
}

class ActivityEntry {
  ActivityEntry({
    required this.key,
    required this.kind,
    required this.title,
    this.body = '',
    this.secondary = '',
    this.status = '',
    this.isStreaming = false,
    this.isLocalPending = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final String key;
  final EntryKind kind;
  final DateTime timestamp;
  String title;
  String body;
  String secondary;
  String status;
  bool isStreaming;
  bool isLocalPending;
}

class PendingApproval {
  PendingApproval({
    required this.requestId,
    required this.method,
    required this.itemId,
    required this.title,
    required this.detail,
    required this.availableDecisions,
  });

  final int requestId;
  final String method;
  final String itemId;
  final String title;
  final String detail;
  final List<String> availableDecisions;
}

class EventLogEntry {
  EventLogEntry(this.method, this.summary) : timestamp = DateTime.now();

  final String method;
  final String summary;
  final DateTime timestamp;
}

class ThreadSummary {
  const ThreadSummary({
    required this.id,
    required this.preview,
    required this.cwd,
    required this.source,
    required this.modelProvider,
    required this.createdAt,
    required this.updatedAt,
    required this.status,
    this.name,
    this.agentNickname,
    this.agentRole,
  });

  final String id;
  final String preview;
  final String cwd;
  final String source;
  final String modelProvider;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String status;
  final String? name;
  final String? agentNickname;
  final String? agentRole;

  String get title {
    final named = name?.trim() ?? '';
    if (named.isNotEmpty) {
      return named;
    }
    final trimmed = preview.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
    return 'Untitled thread';
  }
}

class FileSystemEntry {
  const FileSystemEntry({
    required this.fileName,
    required this.isDirectory,
    required this.isFile,
  });

  final String fileName;
  final bool isDirectory;
  final bool isFile;
}

class ModelOption {
  const ModelOption({
    required this.id,
    required this.model,
    required this.displayName,
    required this.description,
    required this.isDefault,
    required this.hidden,
  });

  final String id;
  final String model;
  final String displayName;
  final String description;
  final bool isDefault;
  final bool hidden;
}

enum PendingPromptMode { queued, steer }

class PendingPrompt {
  const PendingPrompt({
    required this.id,
    required this.text,
    required this.mode,
    this.attachments = const <ComposerAttachment>[],
  });

  final String id;
  final String text;
  final PendingPromptMode mode;
  final List<ComposerAttachment> attachments;

  PendingPrompt copyWith({
    String? id,
    String? text,
    PendingPromptMode? mode,
    List<ComposerAttachment>? attachments,
  }) {
    return PendingPrompt(
      id: id ?? this.id,
      text: text ?? this.text,
      mode: mode ?? this.mode,
      attachments: attachments ?? this.attachments,
    );
  }
}

enum ComposerAttachmentKind { textFile, image }

class ComposerAttachment {
  const ComposerAttachment({
    required this.id,
    required this.fileName,
    required this.kind,
    required this.bytes,
    this.mimeType,
    this.textContent,
  });

  final String id;
  final String fileName;
  final ComposerAttachmentKind kind;
  final Uint8List bytes;
  final String? mimeType;
  final String? textContent;

  bool get isImage => kind == ComposerAttachmentKind.image;
  bool get isTextFile => kind == ComposerAttachmentKind.textFile;

  String? get dataUrl {
    final type = mimeType;
    if (type == null || type.isEmpty) {
      return null;
    }
    return 'data:$type;base64,${base64Encode(bytes)}';
  }
}

bool isLikelyHumanReadableFile(String path, Uint8List bytes) {
  const textExtensions = <String>{
    'txt',
    'md',
    'markdown',
    'json',
    'yaml',
    'yml',
    'toml',
    'xml',
    'html',
    'css',
    'js',
    'ts',
    'tsx',
    'jsx',
    'dart',
    'kt',
    'java',
    'swift',
    'm',
    'mm',
    'c',
    'cc',
    'cpp',
    'h',
    'hpp',
    'rs',
    'go',
    'py',
    'rb',
    'php',
    'sh',
    'zsh',
    'bash',
    'fish',
    'sql',
    'csv',
    'log',
    'ini',
    'cfg',
    'conf',
    'env',
    'gitignore',
    'pubspec',
    'lock',
  };

  final segments = path.split('/');
  final fileName = segments.isEmpty ? path : segments.last;
  final extension = fileName.contains('.')
      ? fileName.split('.').last.toLowerCase()
      : fileName.toLowerCase();
  if (textExtensions.contains(extension)) {
    return true;
  }

  if (bytes.isEmpty) {
    return true;
  }

  var suspicious = 0;
  for (final byte in bytes.take(512)) {
    if (byte == 0) {
      return false;
    }
    if (byte < 9 || (byte > 13 && byte < 32)) {
      suspicious += 1;
    }
  }
  return suspicious < 12;
}

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

enum AutomationNodeKind {
  watchFileChanged,
  watchDirectoryChanged,
  turnCompleted,
  didPathChangeSinceLastRun,
  ifElse,
  quit,
  downloadChangedFile,
  installDownloadedApk,
  sendMessageToCurrentThread,
  runCommand,
}

enum AutomationBranchOutcome { continueFlow, quitFlow }

extension AutomationNodeKindUi on AutomationNodeKind {
  bool get isTrigger {
    return this == AutomationNodeKind.watchFileChanged ||
        this == AutomationNodeKind.watchDirectoryChanged ||
        this == AutomationNodeKind.turnCompleted;
  }

  String get title {
    return switch (this) {
      AutomationNodeKind.watchFileChanged => 'Watch file changes',
      AutomationNodeKind.watchDirectoryChanged => 'Watch folder changes',
      AutomationNodeKind.turnCompleted => 'Turn completed',
      AutomationNodeKind.didPathChangeSinceLastRun =>
        'Did file or folder change',
      AutomationNodeKind.ifElse => 'If / else',
      AutomationNodeKind.quit => 'Quit',
      AutomationNodeKind.downloadChangedFile => 'Download changed file',
      AutomationNodeKind.installDownloadedApk => 'Install downloaded APK',
      AutomationNodeKind.sendMessageToCurrentThread =>
        'Send message to current thread',
      AutomationNodeKind.runCommand => 'Run command',
    };
  }

  IconData get icon {
    return switch (this) {
      AutomationNodeKind.watchFileChanged => Icons.description_outlined,
      AutomationNodeKind.watchDirectoryChanged => Icons.folder_outlined,
      AutomationNodeKind.turnCompleted => Icons.task_alt_outlined,
      AutomationNodeKind.didPathChangeSinceLastRun =>
        Icons.rule_folder_outlined,
      AutomationNodeKind.ifElse => Icons.call_split_outlined,
      AutomationNodeKind.quit => Icons.stop_circle_outlined,
      AutomationNodeKind.downloadChangedFile => Icons.download_outlined,
      AutomationNodeKind.installDownloadedApk => Icons.android_outlined,
      AutomationNodeKind.sendMessageToCurrentThread =>
        Icons.mark_chat_unread_outlined,
      AutomationNodeKind.runCommand => Icons.terminal_outlined,
    };
  }
}

class AutomationNode {
  const AutomationNode({
    required this.id,
    required this.kind,
    this.path = '',
    this.commandText = '',
    this.cwd = '',
    this.directory = '',
    this.conditionToken = '',
    this.whenTrue = AutomationBranchOutcome.continueFlow,
    this.whenFalse = AutomationBranchOutcome.quitFlow,
  });

  final String id;
  final AutomationNodeKind kind;
  final String path;
  final String commandText;
  final String cwd;
  final String directory;
  final String conditionToken;
  final AutomationBranchOutcome whenTrue;
  final AutomationBranchOutcome whenFalse;

  AutomationNode copyWith({
    String? id,
    AutomationNodeKind? kind,
    String? path,
    String? commandText,
    String? cwd,
    String? directory,
    String? conditionToken,
    AutomationBranchOutcome? whenTrue,
    AutomationBranchOutcome? whenFalse,
  }) {
    return AutomationNode(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      path: path ?? this.path,
      commandText: commandText ?? this.commandText,
      cwd: cwd ?? this.cwd,
      directory: directory ?? this.directory,
      conditionToken: conditionToken ?? this.conditionToken,
      whenTrue: whenTrue ?? this.whenTrue,
      whenFalse: whenFalse ?? this.whenFalse,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'kind': kind.name,
      'path': path,
      'commandText': commandText,
      'cwd': cwd,
      'directory': directory,
      'conditionToken': conditionToken,
      'whenTrue': whenTrue.name,
      'whenFalse': whenFalse.name,
    };
  }

  factory AutomationNode.fromJson(Map<String, dynamic> json) {
    final kindName = json['kind']?.toString() ?? '';
    final kind = AutomationNodeKind.values.firstWhere(
      (value) => value.name == kindName,
      orElse: () => AutomationNodeKind.runCommand,
    );
    return AutomationNode(
      id: json['id']?.toString() ?? '',
      kind: kind,
      path: json['path']?.toString() ?? '',
      commandText: json['commandText']?.toString() ?? '',
      cwd: json['cwd']?.toString() ?? '',
      directory: json['directory']?.toString() ?? '',
      conditionToken: json['conditionToken']?.toString() ?? '',
      whenTrue: AutomationBranchOutcome.values.firstWhere(
        (value) => value.name == json['whenTrue']?.toString(),
        orElse: () => AutomationBranchOutcome.continueFlow,
      ),
      whenFalse: AutomationBranchOutcome.values.firstWhere(
        (value) => value.name == json['whenFalse']?.toString(),
        orElse: () => AutomationBranchOutcome.quitFlow,
      ),
    );
  }
}

class AutomationDefinition {
  const AutomationDefinition({
    required this.id,
    required this.name,
    required this.enabled,
    required this.nodes,
    this.ownerThreadId = '',
  });

  final String id;
  final String name;
  final bool enabled;
  final List<AutomationNode> nodes;
  final String ownerThreadId;

  AutomationNode? get triggerNode {
    for (final node in nodes) {
      if (node.kind.isTrigger) {
        return node;
      }
    }
    return null;
  }

  List<AutomationNode> get actionNodes {
    return nodes.where((node) => !node.kind.isTrigger).toList(growable: false);
  }

  AutomationDefinition copyWith({
    String? id,
    String? name,
    bool? enabled,
    List<AutomationNode>? nodes,
    String? ownerThreadId,
  }) {
    return AutomationDefinition(
      id: id ?? this.id,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      nodes: nodes ?? this.nodes,
      ownerThreadId: ownerThreadId ?? this.ownerThreadId,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'enabled': enabled,
      'nodes': nodes.map((node) => node.toJson()).toList(),
      'ownerThreadId': ownerThreadId,
    };
  }

  factory AutomationDefinition.fromJson(Map<String, dynamic> json) {
    final rawNodes = json['nodes'];
    final nodes = <AutomationNode>[];
    if (rawNodes is List<dynamic>) {
      for (final item in rawNodes) {
        if (item is Map<String, dynamic>) {
          nodes.add(AutomationNode.fromJson(item));
        }
      }
    }
    return AutomationDefinition(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      enabled: json['enabled'] != false,
      nodes: nodes,
      ownerThreadId: json['ownerThreadId']?.toString() ?? '',
    );
  }
}
