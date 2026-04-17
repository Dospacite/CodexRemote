import 'dart:convert';
import 'dart:typed_data';

import '../../settings/domain/app_settings.dart';

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
