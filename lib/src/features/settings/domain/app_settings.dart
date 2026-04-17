import 'package:flutter/material.dart';

import '../../automations/domain/automation_models.dart';

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
    required this.threadLoadTimeoutMs,
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
      threadLoadTimeoutMs: 20000,
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
  final int threadLoadTimeoutMs;
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
    int? threadLoadTimeoutMs,
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
      threadLoadTimeoutMs: threadLoadTimeoutMs ?? this.threadLoadTimeoutMs,
      resumeThreadId: resumeThreadId ?? this.resumeThreadId,
      favoriteThreadIds: favoriteThreadIds ?? this.favoriteThreadIds,
      threadDownloadDirectories:
          threadDownloadDirectories ?? this.threadDownloadDirectories,
      automationSnapshots: automationSnapshots ?? this.automationSnapshots,
      automations: automations ?? this.automations,
    );
  }
}
