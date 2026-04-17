import 'package:flutter/material.dart';

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
