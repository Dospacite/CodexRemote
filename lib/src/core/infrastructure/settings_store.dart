import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models.dart';

class SettingsStore {
  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final defaults = AppSettings.defaults();
    return defaults.copyWith(
      connectionMode: ConnectionMode.values.byName(
        prefs.getString(_connectionModeKey) ?? defaults.connectionMode.name,
      ),
      serverUrl: prefs.getString(_serverUrlKey) ?? defaults.serverUrl,
      websocketBearerToken:
          prefs.getString(_websocketBearerTokenKey) ??
          defaults.websocketBearerToken,
      relayUrl: prefs.getString(_relayUrlKey) ?? defaults.relayUrl,
      relayDeviceId:
          prefs.getString(_relayDeviceIdKey) ?? defaults.relayDeviceId,
      relayBridgeLabel:
          prefs.getString(_relayBridgeLabelKey) ?? defaults.relayBridgeLabel,
      relayBridgeSigningPublicKey:
          prefs.getString(_relayBridgeSigningPublicKeyKey) ??
          defaults.relayBridgeSigningPublicKey,
      relayClientPrivateKey:
          prefs.getString(_relayClientPrivateKeyKey) ??
          defaults.relayClientPrivateKey,
      relayClientPublicKey:
          prefs.getString(_relayClientPublicKeyKey) ??
          defaults.relayClientPublicKey,
      model: prefs.getString(_modelKey) ?? defaults.model,
      reasoningEffort:
          prefs.getString(_reasoningEffortKey) ?? defaults.reasoningEffort,
      planMode: prefs.getBool(_planModeKey) ?? defaults.planMode,
      approvalPolicy: normalizeApprovalPolicy(
        prefs.getString(_approvalPolicyKey) ?? defaults.approvalPolicy,
      ),
      sandboxMode: SandboxMode.values.byName(
        prefs.getString(_sandboxModeKey) ?? defaults.sandboxMode.name,
      ),
      allowNetwork: prefs.getBool(_allowNetworkKey) ?? defaults.allowNetwork,
      themePreference: ThemePreference.values.byName(
        prefs.getString(_themePreferenceKey) ?? defaults.themePreference.name,
      ),
      threadLoadTimeoutMs:
          prefs.getInt(_threadLoadTimeoutMsKey) ?? defaults.threadLoadTimeoutMs,
      resumeThreadId:
          prefs.getString(_resumeThreadIdKey) ?? defaults.resumeThreadId,
      favoriteThreadIds: _readFavoriteThreadIds(prefs),
      threadDownloadDirectories: _readThreadDownloadDirectories(prefs),
      automationSnapshots: _readAutomationSnapshots(prefs),
      automations: _readAutomations(prefs),
    );
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_connectionModeKey, settings.connectionMode.name);
    await prefs.setString(_serverUrlKey, settings.serverUrl);
    await prefs.setString(
      _websocketBearerTokenKey,
      settings.websocketBearerToken,
    );
    await prefs.setString(_relayUrlKey, settings.relayUrl);
    await prefs.setString(_relayDeviceIdKey, settings.relayDeviceId);
    await prefs.setString(_relayBridgeLabelKey, settings.relayBridgeLabel);
    await prefs.setString(
      _relayBridgeSigningPublicKeyKey,
      settings.relayBridgeSigningPublicKey,
    );
    await prefs.setString(
      _relayClientPrivateKeyKey,
      settings.relayClientPrivateKey,
    );
    await prefs.setString(
      _relayClientPublicKeyKey,
      settings.relayClientPublicKey,
    );
    await prefs.remove(_cwdKey);
    await prefs.setString(_modelKey, settings.model);
    await prefs.setString(_reasoningEffortKey, settings.reasoningEffort);
    await prefs.setBool(_planModeKey, settings.planMode);
    await prefs.setString(
      _approvalPolicyKey,
      normalizeApprovalPolicy(settings.approvalPolicy),
    );
    await prefs.setString(_sandboxModeKey, settings.sandboxMode.name);
    await prefs.setBool(_allowNetworkKey, settings.allowNetwork);
    await prefs.setString(_themePreferenceKey, settings.themePreference.name);
    await prefs.setInt(_threadLoadTimeoutMsKey, settings.threadLoadTimeoutMs);
    await prefs.setString(_resumeThreadIdKey, settings.resumeThreadId);
    await prefs.setString(
      _favoriteThreadIdsKey,
      jsonEncode(settings.favoriteThreadIds),
    );
    await prefs.setString(
      _threadDownloadDirectoriesKey,
      jsonEncode(settings.threadDownloadDirectories),
    );
    await prefs.setString(
      _automationSnapshotsKey,
      jsonEncode(settings.automationSnapshots),
    );
    await prefs.setString(
      _automationsKey,
      jsonEncode(
        settings.automations
            .map((automation) => automation.toJson())
            .toList(growable: false),
      ),
    );
  }

  Map<String, String> _readThreadDownloadDirectories(SharedPreferences prefs) {
    final raw = prefs.getString(_threadDownloadDirectoriesKey);
    if (raw == null || raw.trim().isEmpty) {
      return <String, String>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return <String, String>{};
      }
      return decoded.map<String, String>((key, value) {
        return MapEntry(key, value?.toString() ?? '');
      })..removeWhere(
        (key, value) => key.trim().isEmpty || value.trim().isEmpty,
      );
    } catch (_) {
      return <String, String>{};
    }
  }

  List<String> _readFavoriteThreadIds(SharedPreferences prefs) {
    final raw = prefs.getString(_favoriteThreadIdsKey);
    if (raw == null || raw.trim().isEmpty) {
      return const <String>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) {
        return const <String>[];
      }
      return decoded
          .map((item) => item?.toString() ?? '')
          .where((item) => item.trim().isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <String>[];
    }
  }

  Map<String, Map<String, String>> _readAutomationSnapshots(
    SharedPreferences prefs,
  ) {
    final raw = prefs.getString(_automationSnapshotsKey);
    if (raw == null || raw.trim().isEmpty) {
      return <String, Map<String, String>>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return <String, Map<String, String>>{};
      }
      final result = <String, Map<String, String>>{};
      for (final entry in decoded.entries) {
        if (entry.key.trim().isEmpty || entry.value is! Map<String, dynamic>) {
          continue;
        }
        final snapshotMap = <String, String>{};
        for (final snapshotEntry
            in (entry.value as Map<String, dynamic>).entries) {
          final key = snapshotEntry.key.trim();
          final value = snapshotEntry.value?.toString() ?? '';
          if (key.isEmpty || value.trim().isEmpty) {
            continue;
          }
          snapshotMap[key] = value;
        }
        result[entry.key] = snapshotMap;
      }
      return result;
    } catch (_) {
      return <String, Map<String, String>>{};
    }
  }

  Future<List<RecentCommand>> loadRecentCommands() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_recentCommandsKey) ?? const <String>[];
    final items = <RecentCommand>[];
    for (final encoded in raw) {
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is! Map<String, dynamic>) {
          continue;
        }
        items.add(
          RecentCommand(
            commandText: decoded['commandText']?.toString() ?? '',
            cwd: decoded['cwd']?.toString() ?? '',
            mode: CommandSessionMode.values.byName(
              decoded['mode']?.toString() ?? CommandSessionMode.buffered.name,
            ),
            sandboxMode: SandboxMode.values.byName(
              decoded['sandboxMode']?.toString() ??
                  SandboxMode.workspaceWrite.name,
            ),
            allowNetwork: decoded['allowNetwork'] == true,
            disableTimeout: decoded['disableTimeout'] != false,
            timeoutMs: decoded['timeoutMs'] as int? ?? 60000,
            disableOutputCap: decoded['disableOutputCap'] != false,
            outputBytesCap: decoded['outputBytesCap'] as int? ?? 32768,
          ),
        );
      } catch (_) {
        continue;
      }
    }
    return items;
  }

  Future<void> saveRecentCommands(List<RecentCommand> commands) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = commands
        .map(
          (command) => jsonEncode(<String, dynamic>{
            'commandText': command.commandText,
            'cwd': command.cwd,
            'mode': command.mode.name,
            'sandboxMode': command.sandboxMode.name,
            'allowNetwork': command.allowNetwork,
            'disableTimeout': command.disableTimeout,
            'timeoutMs': command.timeoutMs,
            'disableOutputCap': command.disableOutputCap,
            'outputBytesCap': command.outputBytesCap,
          }),
        )
        .toList();
    await prefs.setStringList(_recentCommandsKey, encoded);
  }

  List<AutomationDefinition> _readAutomations(SharedPreferences prefs) {
    final raw = prefs.getString(_automationsKey);
    if (raw == null || raw.trim().isEmpty) {
      return const <AutomationDefinition>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) {
        return const <AutomationDefinition>[];
      }
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(AutomationDefinition.fromJson)
          .where((automation) => automation.id.trim().isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <AutomationDefinition>[];
    }
  }
}

const _connectionModeKey = 'connection_mode';
const _serverUrlKey = 'server_url';
const _websocketBearerTokenKey = 'websocket_bearer_token';
const _relayUrlKey = 'relay_url';
const _relayDeviceIdKey = 'relay_device_id';
const _relayBridgeLabelKey = 'relay_bridge_label';
const _relayBridgeSigningPublicKeyKey = 'relay_bridge_signing_public_key';
const _relayClientPrivateKeyKey = 'relay_client_private_key';
const _relayClientPublicKeyKey = 'relay_client_public_key';
const _cwdKey = 'cwd';
const _modelKey = 'model';
const _reasoningEffortKey = 'reasoning_effort';
const _planModeKey = 'plan_mode';
const _approvalPolicyKey = 'approval_policy';
const _sandboxModeKey = 'sandbox_mode';
const _allowNetworkKey = 'allow_network';
const _themePreferenceKey = 'theme_preference';
const _threadLoadTimeoutMsKey = 'thread_load_timeout_ms';
const _resumeThreadIdKey = 'resume_thread_id';
const _favoriteThreadIdsKey = 'favorite_thread_ids';
const _threadDownloadDirectoriesKey = 'thread_download_directories';
const _automationSnapshotsKey = 'automation_snapshots';
const _automationsKey = 'automations';
const _recentCommandsKey = 'recent_commands';
