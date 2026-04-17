import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models.dart';
import '../../settings_store.dart';
import '../../transport.dart';

class AppController extends ChangeNotifier with WidgetsBindingObserver {
  static const Duration _directoryReadTimeout = Duration(minutes: 2);

  AppController._(
    this._settingsStore,
    this._settings,
    this._transport,
    this._httpClientFactory,
    this._openPath,
    this._automationFsQuietPeriod,
  ) {
    automations.addAll(_settings.automations);
  }

  static Future<AppController> bootstrap() async {
    final store = SettingsStore();
    final settings = await store.load();
    final recentCommands = await store.loadRecentCommands();
    final controller = AppController._(
      store,
      settings,
      createDefaultTransport(),
      () => HttpClient(),
      _defaultOpenPath,
      const Duration(milliseconds: 1500),
    );
    controller.recentCommands.addAll(recentCommands);
    WidgetsBinding.instance.addObserver(controller);
    return controller;
  }

  @visibleForTesting
  factory AppController.testing({
    AppTransport? transport,
    HttpClient Function()? httpClientFactory,
    Future<bool> Function(String path)? openPath,
    Duration automationFsQuietPeriod = const Duration(milliseconds: 20),
  }) {
    return AppController._(
      SettingsStore(),
      AppSettings.defaults(),
      transport ?? DirectWebSocketTransport(),
      httpClientFactory ?? (() => HttpClient()),
      openPath ?? _defaultOpenPath,
      automationFsQuietPeriod,
    );
  }

  final SettingsStore _settingsStore;
  final AppTransport _transport;
  final HttpClient Function() _httpClientFactory;
  final Future<bool> Function(String path) _openPath;
  final Duration _automationFsQuietPeriod;
  AppSettings _settings;

  AppSettings get settings => _settings;

  ConnectionStatus status = ConnectionStatus.disconnected;
  String statusMessage = 'Disconnected';
  String? activeThreadId;
  String? activeThreadName;
  String activeThreadCwd = '';
  String? _subscribedThreadId;
  String? activeTurnId;
  final Map<String, String> _activeTurnIdsByThread = <String, String>{};
  bool isLoadingHistory = false;
  String? openingThreadId;
  bool isLoadingFiles = false;
  bool isLoadingFilePreview = false;
  bool isSavingFilePreview = false;
  bool isLoadingModels = false;
  String? threadHistoryError;
  String? fileBrowserError;
  String? filePreviewSaveError;
  String? modelListError;
  String? rateLimitSummary;
  List<String> rateLimitResetDetails = const <String>[];
  String? contextWindowSummary;
  int? contextUsagePercent;
  String? _threadHistoryCursor;
  String? activeCommandSessionId;
  bool isSteering = false;
  String fileBrowserPath = '';
  String? selectedFilePath;
  String? selectedFileContent;
  Uint8List? selectedFileBytes;
  bool selectedFileIsHumanReadable = false;
  int? selectedFileHighlightedLine;
  final Map<String, FileDownloadStatus> _fileDownloadStatusByPath =
      <String, FileDownloadStatus>{};
  final Map<String, String> _fileDownloadProcessIdByPath = <String, String>{};
  final Map<String, _DirectoryCacheEntry> _directoryCache =
      <String, _DirectoryCacheEntry>{};
  final Map<String, _FilePreviewCacheEntry> _filePreviewCache =
      <String, _FilePreviewCacheEntry>{};
  DateTime? _threadHistoryLoadedAt;
  DateTime? _modelOptionsLoadedAt;

  final List<ActivityEntry> entries = <ActivityEntry>[];
  final List<PendingApproval> approvals = <PendingApproval>[];
  final List<EventLogEntry> eventLog = <EventLogEntry>[];
  final List<ThreadSummary> threadHistory = <ThreadSummary>[];
  final List<FileSystemEntry> fileBrowserEntries = <FileSystemEntry>[];
  final List<ModelOption> modelOptions = <ModelOption>[];
  final List<AutomationDefinition> automations = <AutomationDefinition>[];
  final List<CommandSession> commandSessions = <CommandSession>[];
  final List<RecentCommand> recentCommands = <RecentCommand>[];
  final List<PendingPrompt> pendingPrompts = <PendingPrompt>[];
  final List<DownloadRecord> downloadRecords = <DownloadRecord>[];

  final Map<String, ActivityEntry> _entryByItemId = <String, ActivityEntry>{};
  final List<String> _pendingOptimisticUserEntryKeys = <String>[];
  final Map<String, CommandSession> _commandSessionsById =
      <String, CommandSession>{};
  final Map<String, CommandSession> _commandSessionsByProcessId =
      <String, CommandSession>{};
  final Map<String, _PendingDownload> _pendingDownloadsByProcessId =
      <String, _PendingDownload>{};
  final Map<String, _PendingTransferServer> _pendingTransferServersByProcessId =
      <String, _PendingTransferServer>{};
  final Map<String, List<String>> _uploadedImagePathsByTurnId =
      <String, List<String>>{};
  final Map<String, _ActiveAutomationWatch> _activeAutomationWatches =
      <String, _ActiveAutomationWatch>{};
  final Map<String, _RegisteredAutomationWatch> _registeredAutomationWatches =
      <String, _RegisteredAutomationWatch>{};
  final Map<int, CommandSession> _pendingCommandRequestsById =
      <int, CommandSession>{};
  final Map<int, Completer<Map<String, dynamic>?>> _pendingRequests =
      <int, Completer<Map<String, dynamic>?>>{};

  StreamSubscription<String>? _subscription;
  int _requestId = 1;
  bool _manualDisconnect = false;
  bool _shouldReconnectOnResume = false;
  bool _isInBackground = false;
  String? _pendingNewThreadCwd;
  final Set<String> _runningAutomationIds = <String>{};
  final Map<String, List<String>> _queuedAutomationChangedPaths =
      <String, List<String>>{};
  final Map<String, Timer> _automationDebounceTimers = <String, Timer>{};
  final Map<String, List<String>> _debouncedAutomationChangedPaths =
      <String, List<String>>{};
  Completer<void>? _automationWatchSyncCompleter;
  bool _automationWatchSyncQueued = false;

  bool get isConnected => status == ConnectionStatus.ready;
  bool get hasActiveTurn => activeTurnId != null;
  bool get hasMoreThreadHistory => _threadHistoryCursor != null;
  bool get isOpeningThread => openingThreadId != null;
  int get queuedPromptCount => pendingPrompts.length;
  List<String> get queuedPrompts =>
      pendingPrompts.map((item) => item.text).toList();
  String? get composerMetaLeftText {
    final value = rateLimitSummary?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  bool get hasRateLimitResetDetails => rateLimitResetDetails.isNotEmpty;

  String? get composerMetaRightText {
    final value = contextWindowSummary?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  String get preferredCommandCwd {
    final threadCwd = activeThreadCwd.trim();
    if (threadCwd.isNotEmpty) {
      return threadCwd;
    }
    return _pendingNewThreadCwd?.trim() ?? '';
  }

  String get preferredFileBrowserRoot {
    final commandCwd = preferredCommandCwd;
    if (commandCwd.isNotEmpty) {
      return commandCwd;
    }
    return '/';
  }

  Duration get _threadLoadTimeout {
    final timeoutMs = _settings.threadLoadTimeoutMs;
    if (timeoutMs <= 0) {
      return const Duration(seconds: 20);
    }
    return Duration(milliseconds: timeoutMs);
  }

  bool get needsThreadDirectorySelection {
    return activeThreadId == null &&
        _settings.resumeThreadId.trim().isEmpty &&
        (_pendingNewThreadCwd?.trim().isEmpty ?? true);
  }

  String? _preferredDownloadDirectoryForThread(String threadId) {
    if (threadId.trim().isEmpty) {
      return null;
    }
    final value =
        _settings.threadDownloadDirectories[threadId.trim()]?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  Future<void> _rememberDownloadDirectoryForThread(
    String threadId,
    String directory,
  ) async {
    final normalizedThreadId = threadId.trim();
    final normalizedDirectory = directory.trim();
    if (normalizedThreadId.isEmpty || normalizedDirectory.isEmpty) {
      return;
    }
    final nextDirectories = Map<String, String>.from(
      _settings.threadDownloadDirectories,
    );
    nextDirectories[normalizedThreadId] = normalizedDirectory;
    await saveSettings(
      _settings.copyWith(threadDownloadDirectories: nextDirectories),
    );
  }

  bool isFileDownloading(String path) {
    final normalizedPath = _normalizeAbsolutePath(path);
    return _fileDownloadStatusByPath.containsKey(normalizedPath);
  }

  double? fileDownloadProgress(String path) {
    final normalizedPath = _normalizeAbsolutePath(path);
    return _fileDownloadStatusByPath[normalizedPath]?.progress;
  }

  FileDownloadStatus? fileDownloadStatus(String path) {
    final normalizedPath = _normalizeAbsolutePath(path);
    return _fileDownloadStatusByPath[normalizedPath];
  }

  int get activeDownloadCount => downloadRecords
      .where((item) => item.state == DownloadState.running)
      .length;

  bool get hasDownloads => downloadRecords.isNotEmpty;
  bool threadHasActiveTurn(String threadId) {
    final normalized = threadId.trim();
    if (normalized.isEmpty) {
      return false;
    }
    return _activeTurnIdsByThread.containsKey(normalized);
  }

  bool isAutomationRunning(String automationId) {
    return _runningAutomationIds.contains(automationId);
  }

  bool isThreadFavorite(String threadId) {
    return _settings.favoriteThreadIds.contains(threadId.trim());
  }

  String get currentAutomationScopeThreadId {
    final active = activeThreadId?.trim() ?? '';
    if (active.isNotEmpty) {
      return active;
    }
    return _settings.resumeThreadId.trim();
  }

  bool isAutomationVisibleInCurrentThread(AutomationDefinition automation) {
    final ownerThreadId = automation.ownerThreadId.trim();
    if (ownerThreadId.isEmpty) {
      return true;
    }
    final scopeThreadId = currentAutomationScopeThreadId;
    if (scopeThreadId.isEmpty) {
      return false;
    }
    return ownerThreadId == scopeThreadId;
  }

  void _resyncAutomationWatchesForCurrentThread() {
    if (isConnected) {
      unawaited(_syncAutomationWatches());
    }
  }

  Future<void> toggleFavoriteThread(String threadId) async {
    final normalizedThreadId = threadId.trim();
    if (normalizedThreadId.isEmpty) {
      return;
    }
    final nextFavorites = List<String>.from(_settings.favoriteThreadIds);
    if (nextFavorites.contains(normalizedThreadId)) {
      nextFavorites.removeWhere((item) => item == normalizedThreadId);
    } else {
      nextFavorites.insert(0, normalizedThreadId);
    }
    await saveSettings(_settings.copyWith(favoriteThreadIds: nextFavorites));
    _sortThreadHistory();
    notifyListeners();
  }

  Future<void> saveSettings(AppSettings nextSettings) async {
    final previousModel = _settings.model.trim();
    final previousAutomations = jsonEncode(
      _settings.automations
          .map((item) => item.toJson())
          .toList(growable: false),
    );
    _settings = nextSettings;
    automations
      ..clear()
      ..addAll(_settings.automations);
    await _settingsStore.save(_settings);
    notifyListeners();
    final nextModel = nextSettings.model.trim();
    final nextAutomations = jsonEncode(
      _settings.automations
          .map((item) => item.toJson())
          .toList(growable: false),
    );
    if (isConnected && previousModel != nextModel) {
      unawaited(_refreshUsageMetadata());
    }
    if (isConnected && previousAutomations != nextAutomations) {
      await _syncAutomationWatches();
    }
  }

  Future<void> clearThreadState() async {
    final previousThreadId = activeThreadId?.trim() ?? '';
    if (previousThreadId.isNotEmpty) {
      await _unsubscribeFromThread(previousThreadId);
    }
    activeThreadId = null;
    activeThreadName = null;
    activeThreadCwd = '';
    activeTurnId = null;
    _activeTurnIdsByThread.clear();
    contextUsagePercent = null;
    isSteering = false;
    entries.clear();
    approvals.clear();
    _entryByItemId.clear();
    _pendingOptimisticUserEntryKeys.clear();
    pendingPrompts.clear();
    _pendingNewThreadCwd = null;
    await saveSettings(_settings.copyWith(resumeThreadId: ''));
    _addSystemEntry(
      'Started a new local session. The next prompt will open a new thread.',
    );
  }

  Future<void> connect({bool preserveAutomationWatches = true}) async {
    await disconnect(
      clearUiState: false,
      manual: false,
      preserveAutomationWatches: preserveAutomationWatches,
    );
    _manualDisconnect = false;
    status = ConnectionStatus.connecting;
    statusMessage = 'Connecting';
    notifyListeners();

    try {
      _subscription = _transport.messages.listen(
        _handleSocketMessage,
        onError: (Object error, StackTrace stackTrace) {
          status = ConnectionStatus.error;
          statusMessage = 'Connection error';
          _shouldReconnectOnResume = !_manualDisconnect;
          _addSystemEntry('Websocket error: $error');
          notifyListeners();
        },
        onDone: () {
          if (status != ConnectionStatus.disconnected) {
            status = ConnectionStatus.disconnected;
            statusMessage = 'Disconnected';
            activeTurnId = null;
            _shouldReconnectOnResume = !_manualDisconnect;
            notifyListeners();
          }
        },
      );
      await _transport.connect(_settings);

      status = ConnectionStatus.initializing;
      statusMessage = 'Initializing';
      notifyListeners();

      await _request('initialize', <String, dynamic>{
        'clientInfo': <String, dynamic>{
          'name': 'codex_remote_flutter',
          'title': 'Codex Remote',
          'version': '1.0.0',
        },
      });

      _notify('initialized');
      status = ConnectionStatus.ready;
      statusMessage = 'Ready';
      _shouldReconnectOnResume = true;
      _addSystemEntry('Connected to ${_settings.activeConnectionLabel}.');
      await _refreshUsageMetadata(notify: false);
      await loadModelOptions(force: true);
      await _syncAutomationWatches();
      notifyListeners();
    } catch (error) {
      status = ConnectionStatus.error;
      statusMessage = 'Failed to connect';
      _shouldReconnectOnResume = !_manualDisconnect;
      _addSystemEntry('Connection failed: $error');
      notifyListeners();
    }
  }

  Future<void> disconnect({
    bool clearUiState = false,
    bool manual = true,
    bool preserveAutomationWatches = false,
  }) async {
    _manualDisconnect = manual;
    if (manual) {
      _shouldReconnectOnResume = false;
    }
    await _subscription?.cancel();
    _subscription = null;
    await _transport.disconnect();
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Connection closed'));
      }
    }
    _pendingRequests.clear();
    status = ConnectionStatus.disconnected;
    statusMessage = 'Disconnected';
    activeTurnId = null;
    _activeTurnIdsByThread.clear();
    openingThreadId = null;
    _subscribedThreadId = null;
    rateLimitSummary = null;
    contextWindowSummary = null;
    contextUsagePercent = null;
    if (!preserveAutomationWatches) {
      _activeAutomationWatches.clear();
      _registeredAutomationWatches.clear();
    }
    _runningAutomationIds.clear();
    _queuedAutomationChangedPaths.clear();
    if (clearUiState) {
      activeThreadName = null;
      activeThreadCwd = '';
      entries.clear();
      approvals.clear();
      _entryByItemId.clear();
      _pendingOptimisticUserEntryKeys.clear();
    }
    notifyListeners();
  }

  Future<void> reconnectWithSettings(AppSettings nextSettings) async {
    final modeChanged = nextSettings.connectionMode != _settings.connectionMode;
    final urlChanged = nextSettings.serverUrl != _settings.serverUrl;
    final authChanged =
        nextSettings.websocketBearerToken.trim() !=
        _settings.websocketBearerToken.trim();
    final relayChanged =
        nextSettings.relayUrl.trim() != _settings.relayUrl.trim() ||
        nextSettings.relayDeviceId.trim() != _settings.relayDeviceId.trim() ||
        nextSettings.relayClientPrivateKey.trim() !=
            _settings.relayClientPrivateKey.trim() ||
        nextSettings.relayClientPublicKey.trim() !=
            _settings.relayClientPublicKey.trim() ||
        nextSettings.relayBridgeSigningPublicKey.trim() !=
            _settings.relayBridgeSigningPublicKey.trim();
    await saveSettings(nextSettings);
    if ((modeChanged || urlChanged || authChanged || relayChanged) &&
        status != ConnectionStatus.disconnected) {
      await connect(preserveAutomationWatches: false);
    }
  }

  Future<void> pairRelayDevice({
    required String pairingCode,
    String clientLabel = 'Codex Remote',
  }) async {
    final decoded = _decodeRelayPairingCode(pairingCode);
    final signing = Ed25519();
    final keyPair = await signing.newKeyPair();
    final keyPairData = await keyPair.extract();
    final publicKey = await keyPair.extractPublicKey();
    final request = await _httpClientFactory().postUrl(
      Uri.parse('${decoded.relayUrl}/api/v1/device/claim'),
    );
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode(<String, dynamic>{
        'pairingCode': pairingCode.trim(),
        'clientLabel': clientLabel.trim().isEmpty
            ? 'Codex Remote'
            : clientLabel.trim(),
        'clientSigningPublicKey': _b64urlEncode(publicKey.bytes),
      }),
    );
    final response = await request.close();
    final responseBody = await utf8.decodeStream(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Relay pairing failed: ${response.statusCode} $responseBody',
      );
    }
    final payload = jsonDecode(responseBody) as Map<String, dynamic>;
    await saveSettings(
      _settings.copyWith(
        connectionMode: ConnectionMode.relay,
        relayUrl: decoded.relayUrl,
        relayDeviceId: decoded.deviceId,
        relayBridgeLabel:
            payload['bridgeLabel']?.toString() ?? decoded.bridgeLabel,
        relayBridgeSigningPublicKey:
            payload['bridgeSigningPublicKey']?.toString() ??
            decoded.bridgeSigningPublicKey,
        relayClientPrivateKey: _b64urlEncode(keyPairData.bytes),
        relayClientPublicKey: _b64urlEncode(publicKey.bytes),
      ),
    );
  }

  Future<void> clearRelayPairing() async {
    await saveSettings(
      _settings.copyWith(
        connectionMode: ConnectionMode.direct,
        relayUrl: '',
        relayDeviceId: '',
        relayBridgeLabel: '',
        relayBridgeSigningPublicKey: '',
        relayClientPrivateKey: '',
        relayClientPublicKey: '',
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        final shouldReconnect =
            _isInBackground &&
            _shouldReconnectOnResume &&
            !_manualDisconnect &&
            !_transport.isConnected &&
            (status == ConnectionStatus.disconnected ||
                status == ConnectionStatus.error);
        _isInBackground = false;
        if (shouldReconnect) {
          unawaited(_reconnectAfterResume());
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _isInBackground = true;
      case AppLifecycleState.detached:
        _isInBackground = false;
    }
  }

  Future<void> _reconnectAfterResume() async {
    if (_transport.isConnected) {
      if (status != ConnectionStatus.ready) {
        status = ConnectionStatus.ready;
        statusMessage = 'Ready';
        notifyListeners();
      }
      return;
    }
    await connect();
    if (!isConnected) {
      return;
    }

    final threadId = activeThreadId ?? _settings.resumeThreadId.trim();
    if (threadId.isEmpty) {
      return;
    }

    try {
      final response = await _request('thread/resume', <String, dynamic>{
        'threadId': threadId,
      }, _threadLoadTimeout);
      final thread = response?['thread'];
      if (thread is Map<String, dynamic>) {
        activeThreadId = thread['id']?.toString() ?? threadId;
        _subscribedThreadId = activeThreadId;
        activeThreadCwd = thread['cwd']?.toString() ?? activeThreadCwd;
        activeThreadName = thread['name']?.toString() ?? activeThreadName;
        await saveSettings(
          _settings.copyWith(resumeThreadId: activeThreadId ?? threadId),
        );
        _resyncAutomationWatchesForCurrentThread();
      }
      _addSystemEntry('Reconnected after returning to the app.');
    } catch (error) {
      _addSystemEntry('Reconnect after resume failed: $error');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> startFreshThreadInDirectory(String cwd) async {
    await clearThreadState();
    _pendingNewThreadCwd = cwd.trim();
    if (isConnected) {
      await _ensureThread(forceNew: true);
    }
  }

  Future<void> saveAutomation(AutomationDefinition automation) async {
    final next = List<AutomationDefinition>.from(automations);
    final scopeThreadId = currentAutomationScopeThreadId;
    final normalizedAutomation = automation.copyWith(
      ownerThreadId: automation.ownerThreadId.trim().isEmpty
          ? scopeThreadId
          : automation.ownerThreadId.trim(),
    );
    final index = next.indexWhere((item) => item.id == automation.id);
    if (index >= 0) {
      next[index] = normalizedAutomation;
    } else {
      next.insert(0, normalizedAutomation);
    }
    await saveSettings(_settings.copyWith(automations: next));
  }

  Future<void> copyAutomationToCurrentThread(String automationId) async {
    AutomationDefinition? source;
    for (final automation in automations) {
      if (automation.id == automationId) {
        source = automation;
        break;
      }
    }
    if (source == null) {
      return;
    }
    final copiedAutomation = source.copyWith(
      id: 'automation-${DateTime.now().microsecondsSinceEpoch}',
      ownerThreadId: currentAutomationScopeThreadId,
      nodes: source.nodes
          .map(
            (node) => node.copyWith(
              id: 'node-${DateTime.now().microsecondsSinceEpoch}-${node.id}',
            ),
          )
          .toList(growable: false),
    );
    await saveAutomation(copiedAutomation);
  }

  Future<void> deleteAutomation(String automationId) async {
    final next = automations
        .where((item) => item.id != automationId)
        .toList(growable: false);
    await saveSettings(_settings.copyWith(automations: next));
  }

  Future<void> setAutomationEnabled(String automationId, bool enabled) async {
    final next = automations
        .map((item) {
          if (item.id != automationId) {
            return item;
          }
          return item.copyWith(enabled: enabled);
        })
        .toList(growable: false);
    await saveSettings(_settings.copyWith(automations: next));
  }

  Future<void> startCommandExecution({
    required String commandText,
    required String cwd,
    required SandboxMode sandboxMode,
    required bool allowNetwork,
    required CommandSessionMode mode,
    required int timeoutMs,
    required bool disableTimeout,
    required int outputBytesCap,
    required bool disableOutputCap,
    int rows = 20,
    int cols = 80,
  }) async {
    await _startCommandExecutionInternal(
      commandText: commandText,
      cwd: cwd,
      sandboxMode: sandboxMode,
      allowNetwork: allowNetwork,
      mode: mode,
      timeoutMs: timeoutMs,
      disableTimeout: disableTimeout,
      outputBytesCap: outputBytesCap,
      disableOutputCap: disableOutputCap,
      rows: rows,
      cols: cols,
      rememberRecent: true,
      awaitCompletion: false,
    );
  }

  Future<CommandSession?> _startCommandExecutionInternal({
    required String commandText,
    required String cwd,
    required SandboxMode sandboxMode,
    required bool allowNetwork,
    required CommandSessionMode mode,
    required int timeoutMs,
    required bool disableTimeout,
    required int outputBytesCap,
    required bool disableOutputCap,
    required bool rememberRecent,
    required bool awaitCompletion,
    int rows = 20,
    int cols = 80,
  }) async {
    final trimmed = commandText.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    if (!isConnected) {
      await connect();
      if (!isConnected) {
        return null;
      }
    }

    final processId = 'cmd-${DateTime.now().microsecondsSinceEpoch}';
    final normalizedCwd = cwd.trim().isEmpty ? preferredCommandCwd : cwd.trim();
    final usesTty = _shouldUseTtyForCommand(trimmed, mode);
    final session = CommandSession(
      id: processId,
      processId: processId,
      commandDisplay: trimmed,
      cwd: normalizedCwd,
      mode: mode,
      usesTty: usesTty,
      startedAt: DateTime.now(),
    );

    if (rememberRecent) {
      await _rememberRecentCommand(
        RecentCommand(
          commandText: trimmed,
          cwd: normalizedCwd,
          mode: mode,
          sandboxMode: sandboxMode,
          allowNetwork: allowNetwork,
          disableTimeout: disableTimeout,
          timeoutMs: timeoutMs,
          disableOutputCap: disableOutputCap,
          outputBytesCap: outputBytesCap,
        ),
      );
    }

    commandSessions.insert(0, session);
    _commandSessionsById[session.id] = session;
    _commandSessionsByProcessId[session.processId] = session;
    activeCommandSessionId = session.id;
    notifyListeners();

    final id = _requestId++;
    final completer = Completer<Map<String, dynamic>?>();
    _pendingRequests[id] = completer;
    _pendingCommandRequestsById[id] = session;

    final params = <String, dynamic>{
      'command': <String>['/bin/bash', '-lc', trimmed],
      if (session.cwd.isNotEmpty) 'cwd': session.cwd,
      'processId': processId,
      'streamStdoutStderr': true,
      'sandboxPolicy': _buildCommandSandboxPolicy(
        sandboxMode,
        allowNetwork,
        session.cwd,
      ),
      if (disableOutputCap) 'disableOutputCap': true,
      if (!disableOutputCap && outputBytesCap > 0)
        'outputBytesCap': outputBytesCap,
      if (disableTimeout) 'disableTimeout': true,
      if (!disableTimeout && timeoutMs > 0) 'timeoutMs': timeoutMs,
      if (mode == CommandSessionMode.interactive) ...<String, dynamic>{
        'streamStdin': true,
        if (usesTty) 'tty': true,
        if (usesTty) 'size': <String, dynamic>{'rows': rows, 'cols': cols},
      },
    };

    try {
      await _send(<String, dynamic>{
        'id': id,
        'method': 'command/exec',
        'params': params,
      });
    } catch (error) {
      _pendingRequests.remove(id);
      _pendingCommandRequestsById.remove(id);
      session.status = 'failed';
      session.stderr = [
        session.stderr.trimRight(),
        error.toString(),
      ].where((item) => item.isNotEmpty).join('\n');
      notifyListeners();
      if (awaitCompletion) {
        rethrow;
      }
      return session;
    }

    if (mode == CommandSessionMode.interactive && usesTty) {
      unawaited(_primeInteractiveSessionSize(session, rows: rows, cols: cols));
    }

    final completion = completer.future
        .then((Map<String, dynamic>? result) {
          _pendingCommandRequestsById.remove(id);
          _completeCommandSession(session, result);
        })
        .catchError((Object error) {
          _pendingCommandRequestsById.remove(id);
          session.status = 'failed';
          session.stderr = [
            session.stderr.trimRight(),
            error.toString(),
          ].where((item) => item.isNotEmpty).join('\n');
          notifyListeners();
        });
    if (awaitCompletion) {
      await completion;
    } else {
      unawaited(completion);
    }
    return session;
  }

  Future<void> writeToCommandSession(
    String sessionId,
    String input, {
    bool closeStdin = false,
  }) async {
    final session = _commandSessionsById[sessionId];
    if (session == null || !session.isRunning) {
      return;
    }

    final payload = input.isEmpty ? null : base64Encode(utf8.encode(input));
    final payloadField = payload == null
        ? null
        : <String, dynamic>{'deltaBase64': payload};
    await _request('command/exec/write', <String, dynamic>{
      'processId': session.processId,
      ...?payloadField,
      if (closeStdin) 'closeStdin': true,
    });
    if (closeStdin) {
      session.stdinClosed = true;
      notifyListeners();
    }
  }

  Future<void> closeCommandSessionStdin(String sessionId) async {
    await writeToCommandSession(sessionId, '', closeStdin: true);
  }

  Future<void> terminateCommandSession(String sessionId) async {
    final session = _commandSessionsById[sessionId];
    if (session == null || !session.isRunning) {
      return;
    }

    await _request('command/exec/terminate', <String, dynamic>{
      'processId': session.processId,
    });
  }

  Future<void> resizeCommandSession(
    String sessionId, {
    required int rows,
    required int cols,
  }) async {
    final session = _commandSessionsById[sessionId];
    if (session == null ||
        !session.isInteractive ||
        !session.usesTty ||
        !session.isRunning) {
      return;
    }

    await _request('command/exec/resize', <String, dynamic>{
      'processId': session.processId,
      'size': <String, dynamic>{'rows': rows, 'cols': cols},
    });
  }

  Future<void> _primeInteractiveSessionSize(
    CommandSession session, {
    required int rows,
    required int cols,
  }) async {
    const delays = <Duration>[
      Duration.zero,
      Duration(milliseconds: 250),
      Duration(milliseconds: 1000),
    ];

    for (final delay in delays) {
      if (!session.isInteractive || !session.usesTty || !session.isRunning) {
        return;
      }
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      try {
        await _request('command/exec/resize', <String, dynamic>{
          'processId': session.processId,
          'size': <String, dynamic>{'rows': rows, 'cols': cols},
        });
      } catch (_) {
        // Ignore resize failures; later attempts or layout-driven resize may still succeed.
      }
    }
  }

  bool _shouldUseTtyForCommand(String commandText, CommandSessionMode mode) {
    if (mode != CommandSessionMode.interactive) {
      return false;
    }
    final trimmed = commandText.trim();
    if (trimmed.isEmpty) {
      return true;
    }
    final prefersPlainStreaming = RegExp(
      r'(^|\s)flutter(\s|$)',
    ).hasMatch(trimmed);
    return !prefersPlainStreaming;
  }

  void selectCommandSession(String sessionId) {
    if (_commandSessionsById.containsKey(sessionId)) {
      activeCommandSessionId = sessionId;
      notifyListeners();
    }
  }

  Future<void> clearFinishedCommandSessions() async {
    commandSessions.removeWhere((session) => !session.isRunning);
    _commandSessionsById.removeWhere(
      (_, CommandSession session) => !session.isRunning,
    );
    _commandSessionsByProcessId.removeWhere(
      (_, CommandSession session) => !session.isRunning,
    );
    if (activeCommandSessionId != null &&
        !_commandSessionsById.containsKey(activeCommandSessionId)) {
      activeCommandSessionId = commandSessions.isEmpty
          ? null
          : commandSessions.first.id;
    }
    notifyListeners();
  }

  Future<void> clearAllCommandSessions() async {
    commandSessions.clear();
    _commandSessionsById.clear();
    _commandSessionsByProcessId.clear();
    activeCommandSessionId = null;
    notifyListeners();
  }

  Future<void> removeRecentCommand(RecentCommand target) async {
    recentCommands.removeWhere(
      (command) => _sameRecentCommand(command, target),
    );
    await _settingsStore.saveRecentCommands(recentCommands);
    notifyListeners();
  }

  Future<void> loadThreadHistory({bool reset = false}) async {
    if (isLoadingHistory) {
      return;
    }
    final now = DateTime.now();
    final isFreshCache =
        reset &&
        _threadHistoryLoadedAt != null &&
        now.difference(_threadHistoryLoadedAt!) < const Duration(seconds: 20) &&
        threadHistory.isNotEmpty;
    if (isFreshCache) {
      return;
    }

    if (!isConnected) {
      await connect();
      if (!isConnected) {
        return;
      }
    }

    if (reset) {
      threadHistory.clear();
      _threadHistoryCursor = null;
      threadHistoryError = null;
      notifyListeners();
    }

    isLoadingHistory = true;
    threadHistoryError = null;
    notifyListeners();

    try {
      final response = await _request('thread/list', <String, dynamic>{
        'limit': 25,
        'sortKey': 'updated_at',
        if (!reset && _threadHistoryCursor != null)
          'cursor': _threadHistoryCursor,
      }, _threadLoadTimeout);
      final data = response?['data'];
      final nextCursor = response?['nextCursor'];
      final nextItems = <ThreadSummary>[];
      if (data is List<dynamic>) {
        for (final item in data) {
          final parsed = _parseThreadSummary(item);
          if (parsed != null && parsed.id.isNotEmpty) {
            nextItems.add(parsed);
          }
        }
      }

      if (reset) {
        threadHistory
          ..clear()
          ..addAll(nextItems);
      } else {
        final existingIds = threadHistory.map((item) => item.id).toSet();
        for (final item in nextItems) {
          if (!existingIds.contains(item.id)) {
            threadHistory.add(item);
          }
        }
      }
      _sortThreadHistory();

      _threadHistoryCursor = nextCursor?.toString();
      _threadHistoryLoadedAt = DateTime.now();
    } catch (error) {
      threadHistoryError = error.toString();
    } finally {
      isLoadingHistory = false;
      notifyListeners();
    }
  }

  Future<void> openFileBrowser({String? path}) async {
    await loadDirectory(path ?? preferredFileBrowserRoot);
  }

  Future<void> loadModelOptions({bool force = false}) async {
    if (isLoadingModels) {
      return;
    }
    if (!force &&
        modelOptions.isNotEmpty &&
        _modelOptionsLoadedAt != null &&
        DateTime.now().difference(_modelOptionsLoadedAt!) <
            const Duration(minutes: 5)) {
      return;
    }

    if (!isConnected) {
      await connect();
      if (!isConnected) {
        return;
      }
    }

    isLoadingModels = true;
    modelListError = null;
    notifyListeners();

    try {
      final response = await _request('model/list', <String, dynamic>{
        'limit': 100,
      });
      final data = response?['data'];
      final nextOptions = <ModelOption>[];
      if (data is List<dynamic>) {
        for (final item in data) {
          if (item is! Map<String, dynamic>) {
            continue;
          }
          nextOptions.add(
            ModelOption(
              id: item['id']?.toString() ?? '',
              model: item['model']?.toString() ?? '',
              displayName: item['displayName']?.toString() ?? '',
              description: item['description']?.toString() ?? '',
              isDefault: item['isDefault'] == true,
              hidden: item['hidden'] == true,
            ),
          );
        }
      }
      nextOptions.sort((a, b) {
        if (a.isDefault != b.isDefault) {
          return a.isDefault ? -1 : 1;
        }
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });
      modelOptions
        ..clear()
        ..addAll(nextOptions.where((option) => !option.hidden));
      _modelOptionsLoadedAt = DateTime.now();
    } catch (error) {
      modelListError = error.toString();
    } finally {
      isLoadingModels = false;
      notifyListeners();
    }
  }

  Future<void> loadDirectory(String path) async {
    final normalizedPath = _normalizeAbsolutePath(path);
    if (normalizedPath.isEmpty) {
      fileBrowserError = 'File browser requires an absolute path.';
      notifyListeners();
      return;
    }

    final cached = _directoryCache[normalizedPath];
    if (cached != null &&
        DateTime.now().difference(cached.loadedAt) <
            const Duration(seconds: 20)) {
      isLoadingFiles = false;
      fileBrowserError = null;
      fileBrowserPath = normalizedPath;
      selectedFilePath = null;
      selectedFileBytes = null;
      selectedFileContent = null;
      selectedFileIsHumanReadable = false;
      selectedFileHighlightedLine = null;
      fileBrowserEntries
        ..clear()
        ..addAll(cached.entries);
      notifyListeners();
      return;
    }

    if (!isConnected) {
      await connect();
      if (!isConnected) {
        return;
      }
    }

    isLoadingFiles = true;
    fileBrowserError = null;
    fileBrowserPath = normalizedPath;
    selectedFilePath = null;
    selectedFileContent = null;
    selectedFileBytes = null;
    selectedFileIsHumanReadable = false;
    selectedFileHighlightedLine = null;
    notifyListeners();

    try {
      final nextEntries = await _readDirectoryEntries(normalizedPath);
      nextEntries.sort((a, b) {
        if (a.isDirectory != b.isDirectory) {
          return a.isDirectory ? -1 : 1;
        }
        return a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase());
      });
      fileBrowserEntries
        ..clear()
        ..addAll(nextEntries);
      _directoryCache[normalizedPath] = _DirectoryCacheEntry(
        entries: List<FileSystemEntry>.from(nextEntries),
        loadedAt: DateTime.now(),
      );
    } catch (error) {
      fileBrowserError = error.toString();
      fileBrowserEntries.clear();
    } finally {
      isLoadingFiles = false;
      notifyListeners();
    }
  }

  Future<List<FileSystemEntry>> _readDirectoryEntries(String path) async {
    try {
      final response = await _request('fs/readDirectory', <String, dynamic>{
        'path': path,
      }, _directoryReadTimeout);
      return _parseDirectoryEntries(response?['entries']);
    } catch (_) {
      return _readDirectoryEntriesViaCommand(path);
    }
  }

  List<FileSystemEntry> _parseDirectoryEntries(dynamic entriesRaw) {
    final nextEntries = <FileSystemEntry>[];
    if (entriesRaw is! List<dynamic>) {
      return nextEntries;
    }
    for (final item in entriesRaw) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      nextEntries.add(
        FileSystemEntry(
          fileName: item['fileName']?.toString() ?? '',
          isDirectory: item['isDirectory'] == true,
          isFile: item['isFile'] == true,
        ),
      );
    }
    return nextEntries;
  }

  Future<List<FileSystemEntry>> _readDirectoryEntriesViaCommand(
    String path,
  ) async {
    const script = '''
import json
import os
import sys

entries = []
with os.scandir(sys.argv[1]) as it:
    for entry in it:
        try:
            is_dir = entry.is_dir(follow_symlinks=False)
        except OSError:
            is_dir = False
        try:
            is_file = entry.is_file(follow_symlinks=False)
        except OSError:
            is_file = False
        entries.append({
            "fileName": entry.name,
            "isDirectory": is_dir,
            "isFile": is_file,
        })

print(json.dumps({"entries": entries}))
''';
    final response = await _request('command/exec', <String, dynamic>{
      'command': <String>['/usr/bin/env', 'python3', '-c', script, path],
      'sandboxPolicy': const <String, dynamic>{'type': 'readOnly'},
    }, _directoryReadTimeout);
    final stdout = response?['stdout']?.toString() ?? '';
    if (stdout.trim().isEmpty) {
      return <FileSystemEntry>[];
    }
    final decoded = jsonDecode(stdout) as Map<String, dynamic>;
    return _parseDirectoryEntries(decoded['entries']);
  }

  Future<void> openFile(String path, {int? highlightedLine}) async {
    final normalizedPath = _normalizeAbsolutePath(path);
    if (normalizedPath.isEmpty) {
      return;
    }

    final cached = _filePreviewCache[normalizedPath];
    if (cached != null &&
        DateTime.now().difference(cached.loadedAt) <
            const Duration(minutes: 2)) {
      selectedFilePath = normalizedPath;
      selectedFileBytes = cached.bytes;
      selectedFileContent = cached.content;
      selectedFileIsHumanReadable = cached.isHumanReadable;
      selectedFileHighlightedLine = highlightedLine;
      fileBrowserError = null;
      notifyListeners();
      return;
    }

    if (!isConnected) {
      await connect();
      if (!isConnected) {
        return;
      }
    }

    isLoadingFilePreview = true;
    filePreviewSaveError = null;
    fileBrowserError = null;
    selectedFilePath = normalizedPath;
    selectedFileContent = null;
    selectedFileBytes = null;
    selectedFileIsHumanReadable = false;
    selectedFileHighlightedLine = highlightedLine;
    notifyListeners();

    try {
      final bytes = await readFileBytes(normalizedPath);
      selectedFileBytes = bytes;
      selectedFileIsHumanReadable = _isLikelyHumanReadableFile(
        normalizedPath,
        bytes,
      );
      if (selectedFileIsHumanReadable) {
        selectedFileContent = utf8.decode(bytes, allowMalformed: true);
      } else {
        selectedFileContent = null;
      }
      _filePreviewCache[normalizedPath] = _FilePreviewCacheEntry(
        bytes: bytes,
        content: selectedFileContent,
        isHumanReadable: selectedFileIsHumanReadable,
        loadedAt: DateTime.now(),
      );
    } catch (error) {
      fileBrowserError = error.toString();
      selectedFileBytes = null;
      selectedFileContent = null;
      selectedFileIsHumanReadable = false;
      selectedFileHighlightedLine = null;
    } finally {
      isLoadingFilePreview = false;
      notifyListeners();
    }
  }

  Future<void> saveOpenedFileContent(String content) async {
    final selectedPath = selectedFilePath?.trim() ?? '';
    if (selectedPath.isEmpty) {
      throw StateError('No file is open.');
    }
    if (!selectedFileIsHumanReadable) {
      throw StateError('This file cannot be edited as text.');
    }
    if (!isConnected) {
      await connect();
      if (!isConnected) {
        throw StateError('Not connected.');
      }
    }

    isSavingFilePreview = true;
    filePreviewSaveError = null;
    notifyListeners();
    try {
      final bytes = Uint8List.fromList(utf8.encode(content));
      await _request('fs/writeFile', <String, dynamic>{
        'path': selectedPath,
        'dataBase64': base64Encode(bytes),
      }, const Duration(minutes: 2));
      selectedFileContent = content;
      selectedFileBytes = bytes;
      _filePreviewCache[selectedPath] = _FilePreviewCacheEntry(
        bytes: bytes,
        content: content,
        isHumanReadable: true,
        loadedAt: DateTime.now(),
      );
    } catch (error) {
      filePreviewSaveError = error.toString();
      rethrow;
    } finally {
      isSavingFilePreview = false;
      notifyListeners();
    }
  }

  Future<Uint8List> readFileBytes(String path) async {
    final normalizedPath = _normalizeAbsolutePath(path);
    if (normalizedPath.isEmpty) {
      throw StateError('File browser requires an absolute path.');
    }

    if (!isConnected) {
      await connect();
      if (!isConnected) {
        throw StateError('Not connected.');
      }
    }

    final response = await _request('fs/readFile', <String, dynamic>{
      'path': normalizedPath,
    }, const Duration(minutes: 2));
    final dataBase64 = response?['dataBase64']?.toString() ?? '';
    return Uint8List.fromList(base64Decode(dataBase64));
  }

  Future<void> _downloadViaDirectHttpServer(
    String path, {
    required File targetFile,
    ValueChanged<FileDownloadStatus>? onProgress,
    String? processId,
  }) async {
    final normalizedPath = _normalizeAbsolutePath(path);
    if (normalizedPath.isEmpty) {
      throw StateError('File browser requires an absolute path.');
    }

    if (!isConnected) {
      await connect();
      if (!isConnected) {
        throw StateError('Not connected.');
      }
    }

    onProgress?.call(
      const FileDownloadStatus(
        progress: 0,
        receivedBytes: 0,
        totalBytes: null,
        eta: null,
      ),
    );
    final expectedBytes = await _readFileSizeViaCommand(normalizedPath);
    final resolvedProcessId =
        processId ?? 'download-${DateTime.now().microsecondsSinceEpoch}';
    final pending = _PendingDownload(
      expectedBytes: expectedBytes,
      onProgress: onProgress,
    );
    _pendingDownloadsByProcessId[resolvedProcessId] = pending;
    final pendingServer = _PendingTransferServer();
    _pendingTransferServersByProcessId[resolvedProcessId] = pendingServer;
    final token = _randomTransferToken();

    try {
      final responseFuture = _request('command/exec', <String, dynamic>{
        'command': <String>[
          '/usr/bin/env',
          'python3',
          '-u',
          '-c',
          _directDownloadServerScript,
          normalizedPath,
          token,
        ],
        'processId': resolvedProcessId,
        'streamStdoutStderr': true,
        'disableTimeout': true,
        'disableOutputCap': true,
        'sandboxPolicy': _buildCommandSandboxPolicy(
          _settings.sandboxMode,
          true,
          preferredCommandCwd,
        ),
      }, const Duration(minutes: 30));

      final endpoint = await pendingServer.waitForReady();
      final downloadUri = _buildDirectDownloadUri(
        port: endpoint.port,
        token: endpoint.token,
      );
      await _downloadHttpFile(
        uri: downloadUri,
        targetFile: targetFile,
        pending: pending,
      );

      final response = await responseFuture;
      final exitCode = response?['exitCode'] as int?;
      if (pending.isCancelled) {
        throw const _DownloadCancelled();
      }
      if (exitCode != null && exitCode != 0) {
        if (pending.isCancelled) {
          throw const _DownloadCancelled();
        }
        final detail = pendingServer.stderr.trim();
        throw StateError(
          detail.isEmpty
              ? 'Download command failed with exit code $exitCode.'
              : detail,
        );
      }
      pending.markProcessExited();
      await pending.waitForCompletion();
      onProgress?.call(
        FileDownloadStatus(
          progress: 1,
          receivedBytes: pending.writtenBytes,
          totalBytes: pending.expectedBytes ?? pending.writtenBytes,
          eta: Duration.zero,
        ),
      );
    } finally {
      _pendingDownloadsByProcessId.remove(resolvedProcessId);
      _pendingTransferServersByProcessId.remove(resolvedProcessId);
    }
  }

  Future<void> _downloadViaRelayHttp(
    String path, {
    required File targetFile,
    required String processId,
    ValueChanged<FileDownloadStatus>? onProgress,
  }) async {
    final normalizedPath = _normalizeAbsolutePath(path);
    if (normalizedPath.isEmpty) {
      throw StateError('File browser requires an absolute path.');
    }

    if (!isConnected) {
      await connect();
      if (!isConnected) {
        throw StateError('Not connected.');
      }
    }

    final response = await _request('bridge/download/start', <String, dynamic>{
      'path': normalizedPath,
    }, const Duration(minutes: 2));
    final url = response?['url']?.toString().trim() ?? '';
    if (url.isEmpty) {
      throw StateError('Relay bridge did not provide a download URL.');
    }
    final expectedBytes = response?['sizeBytes'] as int?;
    onProgress?.call(
      FileDownloadStatus(
        progress: 0,
        receivedBytes: 0,
        totalBytes: expectedBytes,
        eta: null,
      ),
    );
    final pending = _PendingDownload(
      expectedBytes: expectedBytes,
      onProgress: onProgress,
    );
    _pendingDownloadsByProcessId[processId] = pending;
    try {
      await _downloadHttpFile(
        uri: Uri.parse(url),
        targetFile: targetFile,
        pending: pending,
      );
      onProgress?.call(
        FileDownloadStatus(
          progress: 1,
          receivedBytes: pending.writtenBytes,
          totalBytes: pending.expectedBytes ?? pending.writtenBytes,
          eta: Duration.zero,
        ),
      );
    } finally {
      _pendingDownloadsByProcessId.remove(processId);
    }
  }

  Future<String?> saveFileToDevice(
    String path, {
    String? preferredDirectory,
    bool promptIfNeeded = true,
  }) async {
    final normalizedPath = _normalizeAbsolutePath(path);
    if (normalizedPath.isEmpty) {
      throw StateError('File browser requires an absolute path.');
    }
    if (isFileDownloading(normalizedPath)) {
      return null;
    }

    final processId = 'download-${DateTime.now().microsecondsSinceEpoch}';
    _fileDownloadProcessIdByPath[normalizedPath] = processId;
    _upsertDownloadRecord(
      normalizedPath,
      state: DownloadState.running,
      status: const FileDownloadStatus(
        progress: 0.04,
        receivedBytes: 0,
        totalBytes: null,
        eta: null,
      ),
    );
    _setFileDownloadStatus(
      normalizedPath,
      const FileDownloadStatus(
        progress: 0.04,
        receivedBytes: 0,
        totalBytes: null,
        eta: null,
      ),
    );

    File? targetFile;
    try {
      final fileName = normalizedPath
          .split('/')
          .where((part) => part.isNotEmpty)
          .last;
      final threadId = activeThreadId?.trim() ?? '';
      String? targetDirectory = preferredDirectory?.trim();
      if (targetDirectory == null || targetDirectory.isEmpty) {
        targetDirectory = _preferredDownloadDirectoryForThread(threadId);
      }
      if (targetDirectory == null || targetDirectory.trim().isEmpty) {
        if (!promptIfNeeded) {
          throw StateError(
            'No download directory is configured for this thread.',
          );
        }
        targetDirectory = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'Choose download location',
        );
        if (targetDirectory != null && targetDirectory.trim().isNotEmpty) {
          await _rememberDownloadDirectoryForThread(threadId, targetDirectory);
        }
      }
      if (targetDirectory == null || targetDirectory.trim().isEmpty) {
        return null;
      }
      final directory = Directory(targetDirectory);
      await directory.create(recursive: true);
      targetFile = await _nextAvailableFile(directory.path, fileName);
      if (_settings.connectionMode == ConnectionMode.relay) {
        await _downloadViaRelayHttp(
          normalizedPath,
          processId: processId,
          targetFile: targetFile,
          onProgress: (FileDownloadStatus status) {
            _setFileDownloadStatus(normalizedPath, status);
          },
        );
      } else {
        await _downloadViaDirectHttpServer(
          normalizedPath,
          processId: processId,
          targetFile: targetFile,
          onProgress: (FileDownloadStatus status) {
            _setFileDownloadStatus(normalizedPath, status);
          },
        );
      }
      final currentStatus = fileDownloadStatus(normalizedPath);
      _setFileDownloadStatus(
        normalizedPath,
        FileDownloadStatus(
          progress: 1,
          receivedBytes:
              currentStatus?.totalBytes ?? currentStatus?.receivedBytes ?? 0,
          totalBytes: currentStatus?.totalBytes ?? currentStatus?.receivedBytes,
          eta: Duration.zero,
        ),
      );
      _upsertDownloadRecord(
        normalizedPath,
        state: DownloadState.completed,
        targetPath: targetFile.path,
        status: fileDownloadStatus(normalizedPath),
      );
      return targetFile.path;
    } on _DownloadCancelled {
      if (targetFile != null && await targetFile.exists()) {
        await targetFile.delete();
      }
      _upsertDownloadRecord(
        normalizedPath,
        state: DownloadState.cancelled,
        targetPath: targetFile?.path,
        status: fileDownloadStatus(normalizedPath),
      );
      notifyListeners();
      return null;
    } catch (error) {
      if (targetFile != null && await targetFile.exists()) {
        await targetFile.delete();
      }
      _upsertDownloadRecord(
        normalizedPath,
        state: DownloadState.failed,
        targetPath: targetFile?.path,
        status: fileDownloadStatus(normalizedPath),
        error: error.toString(),
      );
      notifyListeners();
      rethrow;
    } finally {
      _fileDownloadProcessIdByPath.remove(normalizedPath);
      await Future<void>.delayed(const Duration(milliseconds: 220));
      _clearFileDownloadProgress(normalizedPath);
    }
  }

  Future<void> cancelFileDownload(String path) async {
    final normalizedPath = _normalizeAbsolutePath(path);
    final processId = _fileDownloadProcessIdByPath[normalizedPath];
    if (processId == null) {
      return;
    }
    final pending = _pendingDownloadsByProcessId[processId];
    pending?.cancel();
    try {
      await _request('command/exec/terminate', <String, dynamic>{
        'processId': processId,
      });
    } catch (_) {
      // Ignore termination failures; local cancellation state is still enough.
    }
  }

  void clearFinishedDownloads() {
    downloadRecords.removeWhere((item) => item.state != DownloadState.running);
    notifyListeners();
  }

  Future<void> _syncAutomationWatches() async {
    final inFlight = _automationWatchSyncCompleter;
    if (inFlight != null) {
      _automationWatchSyncQueued = true;
      return inFlight.future;
    }
    final completer = Completer<void>();
    _automationWatchSyncCompleter = completer;
    try {
      do {
        _automationWatchSyncQueued = false;
        await _performAutomationWatchSync();
      } while (_automationWatchSyncQueued);
      completer.complete();
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
      rethrow;
    } finally {
      _automationWatchSyncCompleter = null;
    }
  }

  Future<void> _performAutomationWatchSync() async {
    if (!isConnected) {
      return;
    }

    final desired = <String, AutomationNode>{};
    for (final automation in automations) {
      if (!automation.enabled) {
        continue;
      }
      if (!isAutomationVisibleInCurrentThread(automation)) {
        continue;
      }
      final trigger = automation.triggerNode;
      if (trigger == null) {
        continue;
      }
      if (trigger.kind == AutomationNodeKind.turnCompleted) {
        continue;
      }
      final normalizedPath = _normalizeAbsolutePath(trigger.path);
      if (normalizedPath.isEmpty) {
        continue;
      }
      desired[automation.id] = trigger.copyWith(path: normalizedPath);
    }

    final staleIds = _activeAutomationWatches.keys
        .where((automationId) {
          final active = _activeAutomationWatches[automationId];
          final desiredNode = desired[automationId];
          return active == null ||
              desiredNode == null ||
              active.path != desiredNode.path ||
              active.kind != desiredNode.kind;
        })
        .toList(growable: false);
    for (final automationId in staleIds) {
      final active = _activeAutomationWatches.remove(automationId);
      if (active == null) {
        continue;
      }
      _automationDebounceTimers.remove(automationId)?.cancel();
      _debouncedAutomationChangedPaths.remove(automationId);
    }

    final desiredPaths = desired.values.map((item) => item.path).toSet();
    final stalePaths = _registeredAutomationWatches.keys
        .where((path) => !desiredPaths.contains(path))
        .toList(growable: false);
    for (final path in stalePaths) {
      final registered = _registeredAutomationWatches.remove(path);
      if (registered == null) {
        continue;
      }
      try {
        await _request('fs/unwatch', <String, dynamic>{
          'watchId': registered.watchId,
        });
      } catch (_) {
        // Ignore best-effort cleanup failures during resync.
      }
    }

    for (final entry in desired.entries) {
      final active = _activeAutomationWatches[entry.key];
      if (active != null &&
          active.path == entry.value.path &&
          active.kind == entry.value.kind) {
        continue;
      }
      try {
        final registered = await _ensureRegisteredAutomationWatch(
          entry.value.path,
        );
        if (registered == null) {
          continue;
        }
        _activeAutomationWatches[entry.key] = _ActiveAutomationWatch(
          automationId: entry.key,
          watchId: registered.watchId,
          path: registered.path,
          kind: entry.value.kind,
        );
      } catch (error) {
        _addSystemEntry(
          'Automation watch failed for ${_automationName(entry.key)}: $error',
        );
      }
    }
    notifyListeners();
  }

  Future<_RegisteredAutomationWatch?> _ensureRegisteredAutomationWatch(
    String path,
  ) async {
    final existing = _registeredAutomationWatches[path];
    if (existing != null) {
      return existing;
    }
    final response = await _request('fs/watch', <String, dynamic>{
      'path': path,
    });
    final watchId = response?['watchId']?.toString() ?? '';
    if (watchId.isEmpty) {
      return null;
    }
    final registered = _RegisteredAutomationWatch(
      watchId: watchId,
      path: response?['path']?.toString() ?? path,
    );
    _registeredAutomationWatches[path] = registered;
    return registered;
  }

  Future<void> _handleAutomationFsChanged(
    String watchId,
    List<String> changedPaths,
  ) async {
    final activeWatches = _activeAutomationWatches.values
        .where((watch) => watch.watchId == watchId)
        .toList(growable: false);
    if (activeWatches.isEmpty) {
      return;
    }
    for (final activeWatch in activeWatches) {
      AutomationDefinition? automation;
      for (final item in automations) {
        if (item.id == activeWatch.automationId) {
          automation = item;
          break;
        }
      }
      if (automation == null || !automation.enabled) {
        continue;
      }
      final relevantPaths = _matchingAutomationChangedPaths(
        activeWatch,
        changedPaths,
      );
      if (relevantPaths.isEmpty) {
        continue;
      }
      final automationId = automation.id;
      final pendingPaths = <String>{
        ...?_debouncedAutomationChangedPaths[automationId],
        ...relevantPaths,
      }.toList(growable: false);
      _debouncedAutomationChangedPaths[automationId] = pendingPaths;
      _automationDebounceTimers.remove(automationId)?.cancel();
      _automationDebounceTimers[automationId] = Timer(
        _automationFsQuietPeriod,
        () {
          _automationDebounceTimers.remove(automationId);
          final stabilizedPaths =
              _debouncedAutomationChangedPaths.remove(automationId) ??
              const <String>[];
          if (stabilizedPaths.isEmpty) {
            return;
          }
          unawaited(
            _triggerAutomationAfterQuietPeriod(
              automation!,
              activeWatch,
              stabilizedPaths,
            ),
          );
        },
      );
    }
  }

  Future<void> _triggerAutomationAfterQuietPeriod(
    AutomationDefinition automation,
    _ActiveAutomationWatch activeWatch,
    List<String> relevantPaths,
  ) async {
    if (_runningAutomationIds.contains(automation.id)) {
      _queuedAutomationChangedPaths[automation.id] = relevantPaths;
      notifyListeners();
      return;
    }
    _runningAutomationIds.add(automation.id);
    notifyListeners();
    unawaited(
      _runAutomation(automation, activeWatch, relevantPaths).whenComplete(
        () async {
          _runningAutomationIds.remove(automation.id);
          notifyListeners();
          final queued = _queuedAutomationChangedPaths.remove(automation.id);
          if (queued != null && queued.isNotEmpty) {
            await _handleAutomationFsChanged(activeWatch.watchId, queued);
          }
        },
      ),
    );
  }

  List<String> _matchingAutomationChangedPaths(
    _ActiveAutomationWatch activeWatch,
    List<String> changedPaths,
  ) {
    final normalized = changedPaths
        .map(_normalizeAbsolutePath)
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (activeWatch.kind == AutomationNodeKind.watchFileChanged) {
      return normalized.where((item) => item == activeWatch.path).toList();
    }
    return normalized.where((item) {
      return item == activeWatch.path ||
          item.startsWith('${activeWatch.path}/');
    }).toList();
  }

  Future<void> _runAutomation(
    AutomationDefinition automation,
    _ActiveAutomationWatch activeWatch,
    List<String> changedPaths,
  ) async {
    final context = _AutomationExecutionContext(
      changedPaths: changedPaths,
      watchedPath: activeWatch.path,
      triggerKind: activeWatch.kind,
    );
    _addSystemEntry('Automation "${automation.name}" triggered.');
    try {
      for (final node in automation.actionNodes) {
        switch (node.kind) {
          case AutomationNodeKind.turnCompleted:
            break;
          case AutomationNodeKind.didPathChangeSinceLastRun:
            final comparisonPath = _resolveAutomationComparisonPath(
              node,
              context,
              activeWatch,
            );
            if (comparisonPath.isEmpty) {
              throw StateError(
                'No file or folder path was configured to compare.',
              );
            }
            final currentSnapshot = await _captureAutomationSnapshot(
              comparisonPath,
            );
            final previousSnapshot = _automationSnapshotFor(
              automation.id,
              comparisonPath,
            );
            final changed =
                previousSnapshot == null || previousSnapshot != currentSnapshot;
            await _storeAutomationSnapshot(
              automation.id,
              comparisonPath,
              currentSnapshot,
            );
            context.recordNodeOutput(node.id, <String, String>{
              'changed': changed ? 'true' : 'false',
              'path': comparisonPath,
              'snapshot': currentSnapshot,
            });
          case AutomationNodeKind.ifElse:
            final outcome = _evaluateAutomationBranch(node, context);
            context.recordNodeOutput(node.id, <String, String>{
              'condition': _resolveAutomationConditionValue(node, context),
              'outcome': outcome.name,
            });
            if (outcome == AutomationBranchOutcome.quitFlow) {
              _addSystemEntry(
                'Automation "${automation.name}" stopped by ${node.kind.title}.',
              );
              return;
            }
          case AutomationNodeKind.quit:
            context.recordNodeOutput(node.id, <String, String>{
              'outcome': AutomationBranchOutcome.quitFlow.name,
            });
            _addSystemEntry(
              'Automation "${automation.name}" stopped by ${node.kind.title}.',
            );
            return;
          case AutomationNodeKind.downloadChangedFile:
            final sourcePath = _resolveAutomationDownloadSourcePath(
              node,
              context,
              activeWatch,
            );
            if (sourcePath == null) {
              throw StateError('No changed file was available to download.');
            }
            final target = await saveFileToDevice(
              sourcePath,
              preferredDirectory:
                  _resolveAutomationTemplate(
                    node.directory,
                    context,
                  ).trim().isEmpty
                  ? null
                  : _resolveAutomationTemplate(node.directory, context).trim(),
              promptIfNeeded: false,
            );
            if (target == null || target.trim().isEmpty) {
              throw StateError('Download was cancelled.');
            }
            context.lastDownloadedPath = target;
            context.recordNodeOutput(node.id, <String, String>{
              'sourcePath': sourcePath,
              'downloadedPath': target,
            });
          case AutomationNodeKind.installDownloadedApk:
            final installPath = _resolveAutomationInstallPath(node, context);
            if (installPath.isEmpty) {
              throw StateError('No downloaded file was available to install.');
            }
            if (!installPath.toLowerCase().endsWith('.apk')) {
              throw StateError('The downloaded file is not an APK.');
            }
            final opened = await _openPath(installPath);
            if (!opened) {
              throw StateError('Unable to open the downloaded APK.');
            }
            context.recordNodeOutput(node.id, <String, String>{
              'installedPath': installPath,
            });
          case AutomationNodeKind.sendMessageToCurrentThread:
            final messageText = _resolveAutomationTemplate(
              node.commandText,
              context,
            ).trim();
            if (messageText.isEmpty) {
              throw StateError('Automation message is empty.');
            }
            await _sendAutomationMessage(messageText);
            context.recordNodeOutput(node.id, <String, String>{
              'messageText': messageText,
            });
          case AutomationNodeKind.runCommand:
            final commandText = _resolveAutomationTemplate(
              node.commandText,
              context,
            ).trim();
            if (commandText.isEmpty) {
              throw StateError('Automation command is empty.');
            }
            final resolvedCwd = _resolveAutomationTemplate(
              node.cwd,
              context,
            ).trim();
            final cwd = resolvedCwd.isNotEmpty
                ? resolvedCwd
                : _defaultAutomationCommandCwd(context);
            final session = await _runAutomationCommand(commandText, cwd: cwd);
            context.recordNodeOutput(node.id, <String, String>{
              'commandText': commandText,
              'cwd': cwd,
              'stdout': session?.stdout ?? '',
              'stderr': session?.stderr ?? '',
              'processId': session?.processId ?? '',
            });
          case AutomationNodeKind.watchFileChanged:
          case AutomationNodeKind.watchDirectoryChanged:
            // Trigger nodes are handled by fs/watch registration.
            break;
        }
      }
      _addSystemEntry('Automation "${automation.name}" completed.');
    } catch (error) {
      _addSystemEntry('Automation "${automation.name}" failed: $error');
    }
  }

  String? _resolveAutomationChangedFile(
    _AutomationExecutionContext context,
    _ActiveAutomationWatch activeWatch,
  ) {
    if (activeWatch.kind == AutomationNodeKind.watchFileChanged) {
      return context.changedPaths.isEmpty
          ? activeWatch.path
          : context.changedPaths.first;
    }
    for (final path in context.changedPaths) {
      if (!_looksLikeDirectoryPath(path)) {
        return path;
      }
    }
    return null;
  }

  String? _resolveAutomationDownloadSourcePath(
    AutomationNode node,
    _AutomationExecutionContext context,
    _ActiveAutomationWatch activeWatch,
  ) {
    final configuredPath = _resolveAutomationTemplate(
      node.path,
      context,
    ).trim();
    if (configuredPath.isNotEmpty) {
      return configuredPath;
    }
    return _resolveAutomationChangedFile(context, activeWatch);
  }

  String _resolveAutomationComparisonPath(
    AutomationNode node,
    _AutomationExecutionContext context,
    _ActiveAutomationWatch activeWatch,
  ) {
    final configuredPath = _resolveAutomationTemplate(
      node.path,
      context,
    ).trim();
    if (configuredPath.isNotEmpty) {
      return configuredPath;
    }
    if (context.triggerKind == AutomationNodeKind.watchDirectoryChanged ||
        context.triggerKind == AutomationNodeKind.watchFileChanged) {
      return activeWatch.path;
    }
    return context.watchedPath;
  }

  String _resolveAutomationInstallPath(
    AutomationNode node,
    _AutomationExecutionContext context,
  ) {
    final configuredPath = _resolveAutomationTemplate(
      node.path,
      context,
    ).trim();
    if (configuredPath.isNotEmpty) {
      return configuredPath;
    }
    final previousDownloadedPath =
        context.valueForToken('previous.downloadedPath')?.trim() ?? '';
    if (previousDownloadedPath.isNotEmpty) {
      return previousDownloadedPath;
    }
    return context.lastDownloadedPath?.trim() ?? '';
  }

  String _resolveAutomationConditionValue(
    AutomationNode node,
    _AutomationExecutionContext context,
  ) {
    final template = node.conditionToken.trim().isEmpty
        ? '{{previous.changed}}'
        : node.conditionToken.trim();
    return _resolveAutomationTemplate(template, context).trim();
  }

  AutomationBranchOutcome _evaluateAutomationBranch(
    AutomationNode node,
    _AutomationExecutionContext context,
  ) {
    final value = _resolveAutomationConditionValue(node, context).toLowerCase();
    final isTruthy =
        value == 'true' ||
        value == '1' ||
        value == 'yes' ||
        value == 'y' ||
        value == 'continue';
    return isTruthy ? node.whenTrue : node.whenFalse;
  }

  bool _looksLikeDirectoryPath(String path) {
    final parts = path.split('/').where((part) => part.isNotEmpty).toList();
    final name = parts.isEmpty ? '' : parts.last;
    return name.isEmpty || !name.contains('.');
  }

  String _defaultAutomationCommandCwd(_AutomationExecutionContext context) {
    if (context.triggerKind == AutomationNodeKind.turnCompleted) {
      return preferredCommandCwd;
    }
    if (context.triggerKind == AutomationNodeKind.watchDirectoryChanged) {
      return context.watchedPath;
    }
    final segments = context.watchedPath
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList();
    if (segments.isEmpty) {
      return preferredCommandCwd;
    }
    final parent = '/${segments.take(segments.length - 1).join('/')}';
    return parent == '/' ? parent : _normalizeAbsolutePath(parent);
  }

  Future<CommandSession?> _runAutomationCommand(
    String commandText, {
    required String cwd,
  }) async {
    return _startCommandExecutionInternal(
      commandText: commandText,
      cwd: cwd,
      sandboxMode: _settings.sandboxMode,
      allowNetwork: _settings.allowNetwork,
      mode: CommandSessionMode.buffered,
      timeoutMs: 30 * 60 * 1000,
      disableTimeout: true,
      outputBytesCap: 32768,
      disableOutputCap: true,
      rememberRecent: false,
      awaitCompletion: true,
    );
  }

  Future<void> _sendAutomationMessage(String messageText) async {
    if (!isConnected) {
      await connect();
      if (!isConnected) {
        throw StateError('Unable to connect to the app-server.');
      }
    }
    if (activeThreadId == null || activeThreadId!.trim().isEmpty) {
      throw StateError('No active thread is available.');
    }
    if (hasActiveTurn) {
      _enqueuePendingPrompt(messageText, PendingPromptMode.queued);
      return;
    }
    await _startTurn(messageText, const <ComposerAttachment>[]);
  }

  String _resolveAutomationTemplate(
    String value,
    _AutomationExecutionContext context,
  ) {
    if (value.isEmpty) {
      return value;
    }
    return value.replaceAllMapped(
      RegExp(r'\{\{\s*([^}]+?)\s*\}\}'),
      (match) => context.valueForToken(match.group(1)?.trim() ?? '') ?? '',
    );
  }

  String _automationName(String automationId) {
    for (final automation in automations) {
      if (automation.id == automationId) {
        return automation.name;
      }
    }
    return automationId;
  }

  String? _automationSnapshotFor(String automationId, String path) {
    return _settings.automationSnapshots[automationId]?[path];
  }

  Future<void> _storeAutomationSnapshot(
    String automationId,
    String path,
    String snapshot,
  ) async {
    final normalizedAutomationId = automationId.trim();
    final normalizedPath = path.trim();
    if (normalizedAutomationId.isEmpty ||
        normalizedPath.isEmpty ||
        snapshot.trim().isEmpty) {
      return;
    }
    final nextSnapshots = <String, Map<String, String>>{};
    for (final entry in _settings.automationSnapshots.entries) {
      nextSnapshots[entry.key] = Map<String, String>.from(entry.value);
    }
    final automationSnapshots =
        nextSnapshots[normalizedAutomationId] ?? <String, String>{};
    automationSnapshots[normalizedPath] = snapshot;
    nextSnapshots[normalizedAutomationId] = automationSnapshots;
    _settings = _settings.copyWith(automationSnapshots: nextSnapshots);
    await _settingsStore.save(_settings);
  }

  Future<String> _captureAutomationSnapshot(String path) async {
    final normalizedPath = _normalizeAbsolutePath(path);
    if (normalizedPath.isEmpty) {
      throw StateError('Automation comparison path must be absolute.');
    }
    final metadata = await _request('fs/getMetadata', <String, dynamic>{
      'path': normalizedPath,
    });
    if (metadata == null) {
      throw StateError('Unable to read metadata for $normalizedPath.');
    }
    final isDirectory = metadata['isDirectory'] == true;
    final isFile = metadata['isFile'] == true;
    final modifiedAtMs = metadata['modifiedAtMs']?.toString() ?? '0';
    final createdAtMs = metadata['createdAtMs']?.toString() ?? '0';
    if (isFile) {
      return 'file|$normalizedPath|$createdAtMs|$modifiedAtMs';
    }
    if (!isDirectory) {
      return 'missing|$normalizedPath';
    }
    final entries = await _readDirectoryEntries(normalizedPath);
    final signatures = <String>[];
    for (final entry in entries) {
      final fileName = entry.fileName;
      if (fileName.trim().isEmpty) {
        continue;
      }
      final childPath = normalizedPath == '/'
          ? '/$fileName'
          : '$normalizedPath/$fileName';
      final childMetadata = await _request('fs/getMetadata', <String, dynamic>{
        'path': childPath,
      });
      final childModifiedAtMs =
          childMetadata?['modifiedAtMs']?.toString() ?? '0';
      final childType = childMetadata?['isDirectory'] == true ? 'dir' : 'file';
      signatures.add('$fileName|$childType|$childModifiedAtMs');
    }
    signatures.sort();
    return 'dir|$normalizedPath|$modifiedAtMs|${signatures.join(';')}';
  }

  Future<void> _handleAutomationTurnCompleted(String turnId) async {
    for (final automation in automations) {
      if (!automation.enabled) {
        continue;
      }
      if (!isAutomationVisibleInCurrentThread(automation)) {
        continue;
      }
      final trigger = automation.triggerNode;
      if (trigger?.kind != AutomationNodeKind.turnCompleted) {
        continue;
      }
      if (_runningAutomationIds.contains(automation.id)) {
        continue;
      }
      _runningAutomationIds.add(automation.id);
      notifyListeners();
      final syntheticTrigger = _ActiveAutomationWatch(
        automationId: automation.id,
        watchId: 'turn-completed:$turnId',
        path: preferredCommandCwd,
        kind: AutomationNodeKind.turnCompleted,
      );
      unawaited(
        _runAutomation(automation, syntheticTrigger, <String>[
          turnId,
        ]).whenComplete(() {
          _runningAutomationIds.remove(automation.id);
          notifyListeners();
        }),
      );
    }
  }

  Uri _buildDirectDownloadUri({required int port, required String token}) {
    final serverUri = Uri.parse(_settings.serverUrl);
    final scheme = serverUri.scheme == 'wss' ? 'https' : 'http';
    final host = serverUri.host;
    if (host.isEmpty) {
      throw StateError('Cannot determine a download host from the server URL.');
    }
    return Uri(scheme: scheme, host: host, port: port, path: '/$token');
  }

  Future<void> _downloadHttpFile({
    required Uri uri,
    required File targetFile,
    required _PendingDownload pending,
  }) async {
    final client = _httpClientFactory();
    IOSink? sink;
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw StateError('Download server returned ${response.statusCode}.');
      }
      sink = targetFile.openWrite(mode: FileMode.writeOnly);
      await for (final chunk in response) {
        if (pending.isCancelled) {
          throw const _DownloadCancelled();
        }
        sink.add(chunk);
        pending.addBytes(chunk.length);
      }
      await sink.flush();
      await sink.close();
    } finally {
      client.close(force: true);
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
    }
  }

  String _randomTransferToken() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var index = 0; index < 24; index += 1) {
      buffer.write(chars[random.nextInt(chars.length)]);
    }
    return buffer.toString();
  }

  static const String _directDownloadServerScript = r'''
import http.server
import json
import os
import socketserver
import sys
import time

file_path = sys.argv[1]
token = sys.argv[2]

class OneShotHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != f"/{token}":
            self.send_response(404)
            self.end_headers()
            return
        stat = os.stat(file_path)
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(stat.st_size))
        self.send_header(
            "Content-Disposition",
            f'attachment; filename="{os.path.basename(file_path)}"',
        )
        self.end_headers()
        with open(file_path, "rb") as handle:
            while True:
                chunk = handle.read(1024 * 1024)
                if not chunk:
                    break
                self.wfile.write(chunk)
        self.wfile.flush()
        self.server.served = True

    def log_message(self, format, *args):
        return

class OneShotServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

server = OneShotServer(("0.0.0.0", 0), OneShotHandler)
server.served = False
server.timeout = 1
print(json.dumps({
    "event": "ready",
    "port": server.server_address[1],
    "token": token,
}), flush=True)

deadline = time.time() + 300
while not server.served and time.time() < deadline:
    server.handle_request()
''';

  Future<int?> _readFileSizeViaCommand(String path) async {
    try {
      final response = await _request('command/exec', <String, dynamic>{
        'command': <String>['/bin/bash', '-lc', r'wc -c < "$1"', 'bash', path],
        'sandboxPolicy': _buildCommandSandboxPolicy(
          _settings.sandboxMode,
          false,
          preferredCommandCwd,
        ),
      }, const Duration(seconds: 30));
      final stdout = response?['stdout']?.toString().trim() ?? '';
      return int.tryParse(stdout);
    } catch (_) {
      return null;
    }
  }

  String _joinFilePath(String directory, String fileName) {
    final normalizedDirectory = directory.endsWith(Platform.pathSeparator)
        ? directory.substring(0, directory.length - 1)
        : directory;
    return '$normalizedDirectory${Platform.pathSeparator}$fileName';
  }

  Future<File> _nextAvailableFile(String directory, String fileName) async {
    final dotIndex = fileName.lastIndexOf('.');
    final hasExtension = dotIndex > 0;
    final baseName = hasExtension ? fileName.substring(0, dotIndex) : fileName;
    final extension = hasExtension ? fileName.substring(dotIndex) : '';
    var candidate = File(_joinFilePath(directory, fileName));
    var suffix = 1;
    while (await candidate.exists()) {
      candidate = File(
        _joinFilePath(directory, '$baseName ($suffix)$extension'),
      );
      suffix += 1;
    }
    return candidate;
  }

  String? resolveFileReferencePath(String rawPath) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final absolute = _normalizeAbsolutePath(trimmed);
    if (absolute.isNotEmpty) {
      return absolute;
    }
    final base = preferredCommandCwd.trim();
    if (base.isEmpty) {
      return null;
    }
    return _normalizeAbsolutePath(_joinFilePath(base, trimmed));
  }

  void _setFileDownloadStatus(String path, FileDownloadStatus value) {
    _fileDownloadStatusByPath[path] = value;
    _upsertDownloadRecord(path, status: value, state: DownloadState.running);
    notifyListeners();
  }

  void _clearFileDownloadProgress(String path) {
    if (_fileDownloadStatusByPath.remove(path) != null) {
      notifyListeners();
    }
  }

  void _upsertDownloadRecord(
    String path, {
    required DownloadState state,
    FileDownloadStatus? status,
    String? targetPath,
    String? error,
  }) {
    final normalizedPath = _normalizeAbsolutePath(path);
    final parts = normalizedPath
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList();
    final fileName = parts.isEmpty ? normalizedPath : parts.last;
    final index = downloadRecords.indexWhere(
      (item) => item.sourcePath == normalizedPath,
    );
    final previous = index >= 0 ? downloadRecords[index] : null;
    final next = DownloadRecord(
      sourcePath: normalizedPath,
      fileName: fileName,
      targetPath: targetPath ?? previous?.targetPath,
      state: state,
      status: status ?? previous?.status,
      error: error ?? previous?.error,
      startedAt: previous?.startedAt ?? DateTime.now(),
      finishedAt: state == DownloadState.running ? null : DateTime.now(),
    );
    if (index >= 0) {
      downloadRecords[index] = next;
    } else {
      downloadRecords.insert(0, next);
    }
  }

  Future<void> navigateToParentDirectory() async {
    final current = fileBrowserPath.trim();
    if (current.isEmpty || current == '/') {
      return;
    }
    final slashIndex = current.lastIndexOf('/');
    final parent = slashIndex <= 0 ? '/' : current.substring(0, slashIndex);
    await loadDirectory(parent);
  }

  String joinFileBrowserPath(String childName) {
    final base = fileBrowserPath.trim();
    if (base.isEmpty || base == '/') {
      return '/$childName';
    }
    return '$base/$childName';
  }

  Future<void> resumeThreadFromHistory(String threadId) async {
    if (threadId.isEmpty) {
      return;
    }
    if (activeThreadId == threadId) {
      return;
    }
    if (isOpeningThread) {
      return;
    }

    if (!isConnected) {
      await connect();
      if (!isConnected) {
        return;
      }
    }

    openingThreadId = threadId;
    notifyListeners();

    try {
      final readResponse = await _request('thread/read', <String, dynamic>{
        'threadId': threadId,
        'includeTurns': true,
      }, _threadLoadTimeout);
      final thread = readResponse?['thread'];
      if (thread is Map<String, dynamic>) {
        _hydrateEntriesFromThread(thread);
        activeThreadCwd = thread['cwd']?.toString() ?? activeThreadCwd;
        activeThreadName = thread['name']?.toString() ?? activeThreadName;
      }

      final resumeResponse = await _request('thread/resume', <String, dynamic>{
        'threadId': threadId,
      }, _threadLoadTimeout);
      final resumed = resumeResponse?['thread'];
      final resumedTurn = resumeResponse?['turn'];
      if (resumed is Map<String, dynamic>) {
        activeThreadId = resumed['id']?.toString() ?? threadId;
        _subscribedThreadId = activeThreadId;
        activeThreadCwd = resumed['cwd']?.toString() ?? activeThreadCwd;
        activeThreadName = resumed['name']?.toString() ?? activeThreadName;
      } else {
        activeThreadId = threadId;
        _subscribedThreadId = threadId;
      }
      if (resumedTurn is Map<String, dynamic>) {
        _hydrateResumeTurn(resumedTurn);
      } else {
        activeTurnId = _activeTurnIdsByThread[threadId];
        statusMessage = activeTurnId == null ? 'Ready' : 'Turn running';
      }

      await saveSettings(
        _settings.copyWith(resumeThreadId: activeThreadId ?? threadId),
      );
      _resyncAutomationWatchesForCurrentThread();
      _addSystemEntry(
        'Resumed thread ${activeThreadName?.trim().isNotEmpty == true ? activeThreadName : activeThreadId ?? threadId}.',
      );
    } catch (error) {
      _addSystemEntry('Thread resume failed: $error');
    } finally {
      openingThreadId = null;
      notifyListeners();
    }
  }

  Future<void> renameThread(String threadId, String name) async {
    final trimmed = name.trim();
    if (threadId.trim().isEmpty || trimmed.isEmpty) {
      return;
    }
    if (!isConnected) {
      await connect();
      if (!isConnected) {
        return;
      }
    }
    await _request('thread/name/set', <String, dynamic>{
      'threadId': threadId,
      'name': trimmed,
    });
    _updateThreadSummaryName(threadId, trimmed);
    if (activeThreadId == threadId) {
      activeThreadName = trimmed;
    }
    notifyListeners();
  }

  Future<void> sendPrompt(
    String prompt, {
    List<ComposerAttachment> attachments = const <ComposerAttachment>[],
  }) async {
    final trimmed = prompt.trim();
    final normalizedAttachments = List<ComposerAttachment>.from(attachments);
    if (trimmed.isEmpty && normalizedAttachments.isEmpty) {
      return;
    }

    if (!isConnected) {
      await connect();
      if (!isConnected) {
        return;
      }
    }

    await _ensureThread();
    if (activeThreadId == null) {
      _addSystemEntry('Unable to start a thread.');
      return;
    }

    if (hasActiveTurn) {
      _enqueuePendingPrompt(
        trimmed,
        PendingPromptMode.queued,
        attachments: normalizedAttachments,
      );
      return;
    }

    await _startTurn(trimmed, normalizedAttachments);
  }

  Future<bool> steerPrompt(
    String prompt, {
    List<ComposerAttachment> attachments = const <ComposerAttachment>[],
  }) async {
    final trimmed = prompt.trim();
    final normalizedAttachments = List<ComposerAttachment>.from(attachments);
    if (trimmed.isEmpty && normalizedAttachments.isEmpty) {
      return false;
    }

    if (!isConnected) {
      await connect();
      if (!isConnected) {
        return false;
      }
    }

    await _ensureThread();
    if (activeThreadId == null || !hasActiveTurn || isSteering) {
      return false;
    }
    _enqueuePendingPrompt(
      trimmed,
      PendingPromptMode.steer,
      attachments: normalizedAttachments,
    );
    return true;
  }

  Future<void> interruptTurn() async {
    if (activeThreadId == null || activeTurnId == null) {
      return;
    }

    try {
      await _request('turn/interrupt', <String, dynamic>{
        'threadId': activeThreadId,
        'turnId': activeTurnId,
      });
      _addSystemEntry('Interrupt requested for $activeTurnId.');
    } catch (error) {
      _addSystemEntry('Interrupt failed: $error');
    }
    notifyListeners();
  }

  Future<void> _startTurn(
    String prompt,
    List<ComposerAttachment> attachments,
  ) async {
    var optimisticEntryKey = '';
    var uploadedImagePaths = <String>[];
    try {
      final preparedInput = await _buildUserInput(prompt, attachments);
      final input = preparedInput.input;
      uploadedImagePaths = preparedInput.uploadedImagePaths;
      optimisticEntryKey = _addOptimisticUserEntry(prompt, attachments);
      final containsImageAttachment = attachments.any((item) => item.isImage);
      final response = await _request(
        'turn/start',
        <String, dynamic>{
          'threadId': activeThreadId,
          'input': input,
          if (activeThreadCwd.trim().isNotEmpty) 'cwd': activeThreadCwd.trim(),
          if (_settings.model.trim().isNotEmpty)
            'model': _settings.model.trim(),
          if (_settings.reasoningEffort.trim().isNotEmpty)
            'effort': _settings.reasoningEffort.trim(),
          'approvalPolicy': normalizeApprovalPolicy(_settings.approvalPolicy),
          'sandboxPolicy': _buildSandboxPolicy(),
          'personality': 'pragmatic',
        },
        containsImageAttachment
            ? const Duration(minutes: 5)
            : const Duration(seconds: 20),
      );

      final turn = response?['turn'];
      if (turn is Map<String, dynamic>) {
        activeTurnId = turn['id'] as String?;
        final threadId = activeThreadId?.trim() ?? '';
        if (threadId.isNotEmpty && activeTurnId != null) {
          _activeTurnIdsByThread[threadId] = activeTurnId!;
        }
        _trackUploadedImagePaths(activeTurnId, uploadedImagePaths);
        uploadedImagePaths = <String>[];
        statusMessage = 'Turn running';
        notifyListeners();
      }
    } catch (error) {
      await _cleanupUploadedImagePaths(uploadedImagePaths);
      if (optimisticEntryKey.isNotEmpty) {
        _discardOptimisticUserEntry(optimisticEntryKey);
      }
      _addSystemEntry('Prompt failed: $error');
      notifyListeners();
    }
  }

  Future<bool> _steerPrompt(
    String prompt,
    List<ComposerAttachment> attachments,
  ) async {
    if (activeThreadId == null || activeTurnId == null) {
      return false;
    }
    final containsImageAttachment = attachments.any((item) => item.isImage);
    var uploadedImagePaths = <String>[];

    try {
      isSteering = true;
      notifyListeners();
      final preparedInput = await _buildUserInput(prompt, attachments);
      uploadedImagePaths = preparedInput.uploadedImagePaths;
      final response = await _request(
        'turn/steer',
        <String, dynamic>{
          'threadId': activeThreadId,
          'expectedTurnId': activeTurnId,
          'input': preparedInput.input,
        },
        containsImageAttachment
            ? const Duration(minutes: 5)
            : const Duration(seconds: 20),
      );
      final turnId = response?['turnId']?.toString();
      if (turnId != null && turnId.isNotEmpty) {
        activeTurnId = turnId;
        final threadId = activeThreadId?.trim() ?? '';
        if (threadId.isNotEmpty) {
          _activeTurnIdsByThread[threadId] = turnId;
        }
        _trackUploadedImagePaths(turnId, uploadedImagePaths);
        uploadedImagePaths = <String>[];
      }
      _addSystemEntry('Sent as steer input.');
      return true;
    } catch (_) {
      await _cleanupUploadedImagePaths(uploadedImagePaths);
      return false;
    } finally {
      isSteering = false;
      notifyListeners();
    }
  }

  void _enqueuePendingPrompt(
    String prompt,
    PendingPromptMode mode, {
    List<ComposerAttachment> attachments = const <ComposerAttachment>[],
  }) {
    pendingPrompts.add(
      PendingPrompt(
        id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
        text: prompt,
        mode: mode,
        attachments: List<ComposerAttachment>.from(attachments),
      ),
    );
    notifyListeners();
    unawaited(_processPendingPrompts());
  }

  void cancelPendingPrompt(String id) {
    pendingPrompts.removeWhere((item) => item.id == id);
    notifyListeners();
  }

  PendingPrompt? takePendingPromptForEditing(String id) {
    final index = pendingPrompts.indexWhere((item) => item.id == id);
    if (index < 0) {
      return null;
    }
    final value = pendingPrompts.removeAt(index);
    notifyListeners();
    return value;
  }

  bool promotePendingPromptToSteer(String id) {
    final index = pendingPrompts.indexWhere((item) => item.id == id);
    if (index < 0) {
      return false;
    }
    final current = pendingPrompts[index];
    if (current.mode == PendingPromptMode.steer) {
      return false;
    }
    pendingPrompts[index] = current.copyWith(mode: PendingPromptMode.steer);
    notifyListeners();
    unawaited(_processPendingPrompts());
    return true;
  }

  Future<void> _processPendingPrompts() async {
    if (pendingPrompts.isEmpty) {
      return;
    }
    final nextPrompt = pendingPrompts.first;
    if (nextPrompt.mode == PendingPromptMode.steer) {
      if (!hasActiveTurn || isSteering) {
        return;
      }
      final accepted = await _steerPrompt(
        nextPrompt.text,
        nextPrompt.attachments,
      );
      if (accepted) {
        pendingPrompts.removeWhere((item) => item.id == nextPrompt.id);
        notifyListeners();
      }
      return;
    }
    if (hasActiveTurn) {
      return;
    }
    await _startTurn(nextPrompt.text, nextPrompt.attachments);
    pendingPrompts.removeWhere((item) => item.id == nextPrompt.id);
    notifyListeners();
  }

  Future<_PreparedUserInput> _buildUserInput(
    String prompt,
    List<ComposerAttachment> attachments,
  ) async {
    final input = <Map<String, dynamic>>[];
    final uploadedImagePaths = <String>[];
    final fileAttachments = attachments
        .where((item) => item.isTextFile)
        .toList(growable: false);
    final imageAttachments = attachments
        .where((item) => item.isImage)
        .toList(growable: false);
    final text = _composeTextInput(prompt, fileAttachments);
    if (text.isNotEmpty) {
      input.add(<String, dynamic>{'type': 'text', 'text': text});
    }
    for (final attachment in imageAttachments) {
      final uploadedPath = await _uploadImageAttachment(attachment);
      uploadedImagePaths.add(uploadedPath);
      input.add(<String, dynamic>{'type': 'localImage', 'path': uploadedPath});
    }
    return _PreparedUserInput(
      input: input,
      uploadedImagePaths: uploadedImagePaths,
    );
  }

  String _addOptimisticUserEntry(
    String prompt,
    List<ComposerAttachment> attachments,
  ) {
    final text = _composeTextInput(
      prompt,
      attachments.where((item) => item.isTextFile).toList(),
    );
    final imageCount = attachments.where((item) => item.isImage).length;
    final body = [
      text.trim(),
      if (imageCount > 0)
        imageCount == 1 ? '[1 image]' : '[$imageCount images]',
    ].where((item) => item.isNotEmpty).join('\n');
    final key = 'local-user-${DateTime.now().microsecondsSinceEpoch}';
    entries.add(
      ActivityEntry(
        key: key,
        kind: EntryKind.user,
        title: 'You',
        body: body,
        isLocalPending: true,
      ),
    );
    _pendingOptimisticUserEntryKeys.add(key);
    notifyListeners();
    return key;
  }

  void _discardOptimisticUserEntry(String key) {
    _pendingOptimisticUserEntryKeys.remove(key);
    entries.removeWhere((entry) => entry.key == key);
  }

  Future<String> _uploadImageAttachment(ComposerAttachment attachment) async {
    final path = _buildRemoteImageAttachmentPath(attachment.fileName);
    await _request('fs/writeFile', <String, dynamic>{
      'path': path,
      'dataBase64': base64Encode(attachment.bytes),
    }, const Duration(minutes: 2));
    return path;
  }

  String _buildRemoteImageAttachmentPath(String fileName) {
    final baseDirectory = activeThreadCwd.trim().isNotEmpty
        ? activeThreadCwd.trim()
        : '/tmp';
    final extension = _remoteAttachmentExtension(fileName);
    final fileSuffix =
        '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';
    return _joinRemotePath(
      baseDirectory,
      '.codex_remote_image_$fileSuffix$extension',
    );
  }

  String _remoteAttachmentExtension(String fileName) {
    final trimmed = fileName.trim();
    final dotIndex = trimmed.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex == trimmed.length - 1) {
      return '';
    }
    final extension = trimmed.substring(dotIndex);
    return RegExp(r'^\.[A-Za-z0-9]+$').hasMatch(extension) ? extension : '';
  }

  String _joinRemotePath(String directory, String name) {
    final separator = directory.contains(r'\') && !directory.contains('/')
        ? r'\'
        : '/';
    final trimmedDirectory = directory.endsWith(separator)
        ? directory.substring(0, directory.length - 1)
        : directory;
    if (trimmedDirectory.isEmpty) {
      return name;
    }
    return '$trimmedDirectory$separator$name';
  }

  void _trackUploadedImagePaths(String? turnId, List<String> paths) {
    if (turnId == null || turnId.isEmpty || paths.isEmpty) {
      return;
    }
    final tracked = _uploadedImagePathsByTurnId.putIfAbsent(
      turnId,
      () => <String>[],
    );
    tracked.addAll(paths);
  }

  Future<void> _cleanupUploadedImagePaths(List<String> paths) async {
    for (final path in paths) {
      try {
        await _request('fs/remove', <String, dynamic>{
          'path': path,
        }, const Duration(seconds: 20));
      } catch (_) {
        // Ignore cleanup failures for best-effort temp-file removal.
      }
    }
  }

  void _cleanupUploadedImagesForTurn(String? turnId) {
    if (turnId == null || turnId.isEmpty) {
      return;
    }
    final paths = _uploadedImagePathsByTurnId.remove(turnId);
    if (paths == null || paths.isEmpty) {
      return;
    }
    unawaited(_cleanupUploadedImagePaths(paths));
  }

  ActivityEntry _resolveOptimisticUserEntry(String actualItemId) {
    while (_pendingOptimisticUserEntryKeys.isNotEmpty) {
      final pendingKey = _pendingOptimisticUserEntryKeys.removeAt(0);
      final index = entries.indexWhere((entry) => entry.key == pendingKey);
      if (index < 0) {
        continue;
      }
      final pending = entries[index];
      final resolved = ActivityEntry(
        key: actualItemId,
        kind: EntryKind.user,
        title: pending.title,
        body: pending.body,
        secondary: pending.secondary,
        status: pending.status,
        timestamp: pending.timestamp,
      );
      entries[index] = resolved;
      return resolved;
    }
    return _createEntry(actualItemId, 'userMessage', const <String, dynamic>{
      'type': 'userMessage',
    });
  }

  String _composeTextInput(
    String prompt,
    List<ComposerAttachment> fileAttachments,
  ) {
    final sections = <String>[];
    final trimmed = prompt.trim();
    if (trimmed.isNotEmpty) {
      sections.add(trimmed);
    }
    for (final attachment in fileAttachments) {
      final content = attachment.textContent?.trim() ?? '';
      if (content.isEmpty) {
        continue;
      }
      sections.add(
        'Attached file: ${attachment.fileName}\n```text\n$content\n```',
      );
    }
    return sections.join('\n\n');
  }

  Future<void> resolveApproval(
    PendingApproval approval,
    String decision,
  ) async {
    await _send(<String, dynamic>{
      'id': approval.requestId,
      'result': <String, dynamic>{'decision': decision},
    });
    approvals.removeWhere((item) => item.requestId == approval.requestId);
    notifyListeners();
  }

  Future<void> _refreshUsageMetadata({bool notify = true}) async {
    if (!isConnected) {
      if (notify) {
        notifyListeners();
      }
      return;
    }

    try {
      final rateResponse = await _request(
        'account/rateLimits/read',
        null,
        const Duration(seconds: 20),
      );
      final snapshot = _selectRateLimitSnapshot(rateResponse);
      rateLimitSummary = _formatRateLimitSummary(snapshot);
      rateLimitResetDetails = _formatRateLimitResetDetails(snapshot);
    } catch (_) {
      rateLimitSummary = null;
      rateLimitResetDetails = const <String>[];
    }

    try {
      final configResponse = await _request(
        'config/read',
        <String, dynamic>{},
        const Duration(seconds: 20),
      );
      final config = configResponse?['config'];
      if (config is Map<String, dynamic>) {
        final contextState = _contextStateFromConfig(config);
        contextWindowSummary = contextState.$1;
        contextUsagePercent = contextState.$2;
      } else {
        contextWindowSummary = null;
        contextUsagePercent = null;
      }
    } catch (_) {
      contextWindowSummary = null;
      contextUsagePercent = null;
    }

    if (notify) {
      notifyListeners();
    }
  }

  Future<void> _ensureThread({bool forceNew = false}) async {
    if (!forceNew && activeThreadId != null) {
      return;
    }

    if (!forceNew && _settings.resumeThreadId.trim().isNotEmpty) {
      try {
        final response = await _request('thread/resume', <String, dynamic>{
          'threadId': _settings.resumeThreadId.trim(),
        }, _threadLoadTimeout);
        final thread = response?['thread'];
        if (thread is Map<String, dynamic>) {
          final threadId = thread['id'] as String?;
          if (threadId != null) {
            activeThreadId = threadId;
            _subscribedThreadId = threadId;
            activeThreadCwd = thread['cwd']?.toString() ?? activeThreadCwd;
            activeThreadName = thread['name']?.toString() ?? activeThreadName;
            _addSystemEntry(
              'Resumed thread ${activeThreadName?.trim().isNotEmpty == true ? activeThreadName : threadId}.',
            );
            notifyListeners();
            _resyncAutomationWatchesForCurrentThread();
            return;
          }
        }
      } catch (_) {
        _addSystemEntry(
          'Stored thread ${_settings.resumeThreadId} could not be resumed. Starting a new thread.',
        );
      }
    }

    final initialCwd = _pendingNewThreadCwd?.trim() ?? '';
    final response = await _request('thread/start', <String, dynamic>{
      if (initialCwd.isNotEmpty) 'cwd': initialCwd,
    });
    final thread = response?['thread'];
    if (thread is! Map<String, dynamic>) {
      return;
    }
    final threadId = thread['id'] as String?;
    if (threadId == null) {
      return;
    }
    activeThreadId = threadId;
    _subscribedThreadId = threadId;
    activeThreadCwd = thread['cwd']?.toString() ?? activeThreadCwd;
    activeThreadName = thread['name']?.toString() ?? activeThreadName;
    _pendingNewThreadCwd = null;
    await saveSettings(_settings.copyWith(resumeThreadId: threadId));
    _resyncAutomationWatchesForCurrentThread();
    _addSystemEntry(
      'Opened thread ${activeThreadName?.trim().isNotEmpty == true ? activeThreadName : threadId}.',
    );
  }

  Map<String, dynamic> _buildSandboxPolicy() {
    switch (_settings.sandboxMode) {
      case SandboxMode.workspaceWrite:
        final writableRoots = activeThreadCwd.trim().isEmpty
            ? const <String>[]
            : <String>[activeThreadCwd.trim()];
        return <String, dynamic>{
          'type': 'workspaceWrite',
          if (writableRoots.isNotEmpty) 'writableRoots': writableRoots,
          'networkAccess': _settings.allowNetwork,
        };
      case SandboxMode.readOnly:
        return <String, dynamic>{'type': 'readOnly'};
      case SandboxMode.dangerFullAccess:
        return <String, dynamic>{'type': 'dangerFullAccess'};
    }
  }

  Map<String, dynamic> _buildCommandSandboxPolicy(
    SandboxMode sandboxMode,
    bool allowNetwork,
    String cwd,
  ) {
    switch (sandboxMode) {
      case SandboxMode.workspaceWrite:
        final writableRoots = cwd.trim().isEmpty
            ? const <String>[]
            : <String>[cwd];
        return <String, dynamic>{
          'type': 'workspaceWrite',
          if (writableRoots.isNotEmpty) 'writableRoots': writableRoots,
          'networkAccess': allowNetwork,
        };
      case SandboxMode.readOnly:
        return <String, dynamic>{'type': 'readOnly'};
      case SandboxMode.dangerFullAccess:
        return <String, dynamic>{'type': 'dangerFullAccess'};
    }
  }

  Future<Map<String, dynamic>?> _request(
    String method, [
    Object? params = const <String, dynamic>{},
    Duration timeout = const Duration(seconds: 20),
  ]) async {
    final id = _requestId++;
    final completer = Completer<Map<String, dynamic>?>();
    _pendingRequests[id] = completer;
    final paramsField = <String, dynamic>{'params': params};
    try {
      await _send(<String, dynamic>{
        'id': id,
        'method': method,
        ...paramsField,
      });
    } catch (_) {
      _pendingRequests.remove(id);
      rethrow;
    }
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pendingRequests.remove(id);
        throw TimeoutException('Request timed out: $method', timeout);
      },
    );
  }

  void _notify(String method, [Map<String, dynamic>? params]) {
    final paramsField = params == null
        ? null
        : <String, dynamic>{'params': params};
    unawaited(_send(<String, dynamic>{'method': method, ...?paramsField}));
  }

  Future<void> _send(Map<String, dynamic> payload) {
    return _transport.send(jsonEncode(payload));
  }

  void _handleSocketMessage(String rawMessage) {
    final dynamic decoded = jsonDecode(rawMessage);
    if (decoded is! Map<String, dynamic>) {
      return;
    }

    final method = decoded['method'] as String?;
    final id = decoded['id'];

    if (method == null && id is int) {
      _handleResponse(id, decoded);
      return;
    }

    if (method != null && id is int) {
      _handleServerRequest(id, method, decoded['params']);
      return;
    }

    if (method != null) {
      _handleNotification(method, decoded['params']);
    }
  }

  void _handleResponse(int id, Map<String, dynamic> message) {
    final completer = _pendingRequests.remove(id);
    if (completer == null || completer.isCompleted) {
      return;
    }

    final error = message['error'];
    if (error != null) {
      completer.completeError(error.toString());
      return;
    }

    final result = message['result'];
    if (result is Map<String, dynamic>) {
      completer.complete(result);
    } else {
      completer.complete(null);
    }
  }

  void _handleServerRequest(int id, String method, dynamic params) {
    final typedParams = params is Map<String, dynamic>
        ? params
        : <String, dynamic>{};
    _pushEvent(method, typedParams);

    if (method == 'item/commandExecution/requestApproval' ||
        method == 'item/fileChange/requestApproval') {
      final detail = switch (method) {
        'item/commandExecution/requestApproval' =>
          typedParams['command']?.toString() ??
              typedParams['reason']?.toString() ??
              '',
        _ =>
          typedParams['reason']?.toString() ??
              typedParams['itemId']?.toString() ??
              '',
      };
      final approval = PendingApproval(
        requestId: id,
        method: method,
        itemId: typedParams['itemId']?.toString() ?? '$id',
        title: method == 'item/commandExecution/requestApproval'
            ? 'Command approval'
            : 'File change approval',
        detail: detail,
        availableDecisions:
            (typedParams['availableDecisions'] as List<dynamic>?)
                ?.map((item) => item.toString())
                .toList() ??
            const <String>['accept', 'acceptForSession', 'decline', 'cancel'],
      );
      approvals.removeWhere((item) => item.requestId == approval.requestId);
      approvals.add(approval);
      notifyListeners();
      return;
    }

    unawaited(
      _send(<String, dynamic>{
        'id': id,
        'error': <String, dynamic>{
          'code': -32601,
          'message': 'Unsupported request: $method',
        },
      }),
    );
  }

  void _handleNotification(String method, dynamic params) {
    final typedParams = params is Map<String, dynamic>
        ? params
        : <String, dynamic>{};
    _pushEvent(method, typedParams);

    switch (method) {
      case 'android/transportStatus':
        final transportStatus = typedParams['status']?.toString() ?? '';
        switch (transportStatus) {
          case 'connected':
            status = ConnectionStatus.ready;
            statusMessage = 'Ready';
          case 'disconnected':
            status = ConnectionStatus.disconnected;
            statusMessage = 'Disconnected';
          case 'error':
            status = ConnectionStatus.error;
            statusMessage = 'Connection error';
        }
        notifyListeners();
      case 'thread/started':
        final thread = typedParams['thread'];
        if (thread is Map<String, dynamic>) {
          final threadId = thread['id']?.toString();
          if (threadId != null && activeThreadId == null) {
            activeThreadId = threadId;
            _subscribedThreadId = threadId;
            activeThreadCwd = thread['cwd']?.toString() ?? activeThreadCwd;
            activeThreadName = thread['name']?.toString() ?? activeThreadName;
            unawaited(
              saveSettings(_settings.copyWith(resumeThreadId: threadId)),
            );
            _resyncAutomationWatchesForCurrentThread();
          }
        }
      case 'thread/status/changed':
        final threadId = typedParams['threadId']?.toString();
        final status = _statusText(typedParams['status']);
        if (threadId != null && status.isNotEmpty) {
          final index = threadHistory.indexWhere((item) => item.id == threadId);
          if (index >= 0) {
            final current = threadHistory[index];
            threadHistory[index] = ThreadSummary(
              id: current.id,
              preview: current.preview,
              cwd: current.cwd,
              source: current.source,
              modelProvider: current.modelProvider,
              createdAt: current.createdAt,
              updatedAt: current.updatedAt,
              status: status,
              name: current.name,
              agentNickname: current.agentNickname,
              agentRole: current.agentRole,
            );
            notifyListeners();
          }
        }
      case 'turn/started':
        final turn = typedParams['turn'];
        if (turn is Map<String, dynamic>) {
          final threadId =
              typedParams['threadId']?.toString() ??
              activeThreadId?.trim() ??
              '';
          final turnId = turn['id']?.toString();
          if (threadId.isNotEmpty && turnId != null && turnId.isNotEmpty) {
            _activeTurnIdsByThread[threadId] = turnId;
          }
          if (threadId == (activeThreadId?.trim() ?? '')) {
            activeTurnId = turnId;
            statusMessage = 'Turn running';
            notifyListeners();
          }
        }
      case 'turn/completed':
        final turn = typedParams['turn'];
        if (turn is Map<String, dynamic>) {
          final threadId =
              typedParams['threadId']?.toString() ??
              activeThreadId?.trim() ??
              '';
          if (threadId.isNotEmpty) {
            _activeTurnIdsByThread.remove(threadId);
          }
          final turnStatus = turn['status']?.toString() ?? 'completed';
          if (threadId == (activeThreadId?.trim() ?? '')) {
            activeTurnId = null;
            isSteering = false;
            statusMessage = 'Ready';
            if (turnStatus != 'completed') {
              _addSystemEntry('Turn finished with status $turnStatus.');
            }
            final error = turn['error'];
            if (error is Map<String, dynamic>) {
              _addSystemEntry(error['message']?.toString() ?? 'Turn failed.');
            }
            notifyListeners();
          }
          final turnId =
              turn['id']?.toString() ?? typedParams['turnId']?.toString() ?? '';
          _cleanupUploadedImagesForTurn(turnId);
          if (turnStatus == 'completed' && turnId.isNotEmpty) {
            unawaited(_handleAutomationTurnCompleted(turnId));
          }
          if (threadId == (activeThreadId?.trim() ?? '')) {
            unawaited(_processPendingPrompts());
          }
        }
      case 'item/started':
        final itemThreadId = typedParams['threadId']?.toString() ?? '';
        if (itemThreadId.isEmpty ||
            itemThreadId == (activeThreadId?.trim() ?? '')) {
          _handleItem(
            typedParams['item'],
            isCompleted: false,
            turnId: typedParams['turnId']?.toString(),
          );
        }
      case 'item/completed':
        final itemThreadId = typedParams['threadId']?.toString() ?? '';
        if (itemThreadId.isEmpty ||
            itemThreadId == (activeThreadId?.trim() ?? '')) {
          _handleItem(
            typedParams['item'],
            isCompleted: true,
            turnId: typedParams['turnId']?.toString(),
          );
        }
      case 'item/agentMessage/delta':
        final itemId = typedParams['itemId']?.toString();
        final delta = typedParams['delta']?.toString() ?? '';
        if (itemId != null) {
          final entry = _entryByItemId[itemId];
          if (entry != null) {
            entry.body += delta;
            entry.isStreaming = true;
            notifyListeners();
          }
        }
      case 'item/reasoning/summaryTextDelta':
        final itemId = typedParams['itemId']?.toString();
        final delta = typedParams['delta']?.toString() ?? '';
        if (itemId != null) {
          final entry = _entryByItemId[itemId];
          if (entry != null) {
            entry.body += delta;
            notifyListeners();
          }
        }
      case 'item/commandExecution/outputDelta':
        final itemId = typedParams['itemId']?.toString();
        final delta = typedParams['delta']?.toString() ?? '';
        if (itemId != null) {
          final entry = _entryByItemId[itemId];
          if (entry != null) {
            entry.body += delta;
            notifyListeners();
          }
        }
      case 'command/exec/outputDelta':
        final processId = typedParams['processId']?.toString();
        final deltaBase64 = typedParams['deltaBase64']?.toString();
        if (processId != null && deltaBase64 != null) {
          final rawBytes = base64Decode(deltaBase64);
          final pendingServer = _pendingTransferServersByProcessId[processId];
          if (pendingServer != null) {
            final stream = typedParams['stream']?.toString() ?? 'stdout';
            final decoded = utf8.decode(rawBytes, allowMalformed: true);
            if (stream == 'stderr') {
              pendingServer.stderr += decoded;
            } else {
              pendingServer.handleStdout(decoded);
            }
          }
          final pendingDownload = _pendingDownloadsByProcessId[processId];
          if (pendingDownload != null) {
            final stream = typedParams['stream']?.toString() ?? 'stdout';
            if (stream == 'stderr') {
              pendingDownload.stderr += utf8.decode(
                rawBytes,
                allowMalformed: true,
              );
            }
          }
          final session = _commandSessionsByProcessId[processId];
          if (session != null) {
            final decoded = utf8.decode(rawBytes, allowMalformed: true);
            final stream = typedParams['stream']?.toString() ?? 'stdout';
            if (stream == 'stderr') {
              session.stderr = _appendCommandOutput(session.stderr, decoded);
            } else {
              session.stdout = _appendCommandOutput(session.stdout, decoded);
            }
            if (typedParams['capReached'] == true) {
              session.outputCapReached = true;
            }
            notifyListeners();
          }
        }
      case 'serverRequest/resolved':
        final requestId = typedParams['requestId'];
        approvals.removeWhere((item) => item.requestId == requestId);
        notifyListeners();
      case 'account/rateLimits/updated':
        final snapshot = _selectRateLimitSnapshot(typedParams);
        rateLimitSummary = _formatRateLimitSummary(snapshot);
        rateLimitResetDetails = _formatRateLimitResetDetails(snapshot);
        notifyListeners();
      case 'thread/tokenUsage/updated':
        final threadId = typedParams['threadId']?.toString() ?? '';
        if (threadId == activeThreadId) {
          final tokenUsage = typedParams['tokenUsage'];
          if (tokenUsage is Map<String, dynamic>) {
            final contextState = _contextStateFromTokenUsage(tokenUsage);
            contextWindowSummary = contextState.$1;
            contextUsagePercent = contextState.$2;
          }
          notifyListeners();
        }
      case 'fs/changed':
        final watchId = typedParams['watchId']?.toString() ?? '';
        final changedPaths =
            (typedParams['changedPaths'] as List<dynamic>? ?? const <dynamic>[])
                .map((item) => item.toString())
                .toList(growable: false);
        if (watchId.isNotEmpty && changedPaths.isNotEmpty) {
          unawaited(_handleAutomationFsChanged(watchId, changedPaths));
        }
      case 'error':
        final error = typedParams['error'];
        if (error is Map<String, dynamic>) {
          _addSystemEntry(error['message']?.toString() ?? 'Server error');
          notifyListeners();
        }
    }
  }

  void _handleItem(dynamic item, {required bool isCompleted, String? turnId}) {
    if (item is! Map<String, dynamic>) {
      return;
    }

    final itemId = item['id']?.toString();
    final type = item['type']?.toString() ?? 'unknown';
    if (itemId == null) {
      return;
    }

    final entry =
        _entryByItemId[itemId] ??
        (type == 'userMessage'
            ? _resolveOptimisticUserEntry(itemId)
            : _createEntry(itemId, type, item));
    _entryByItemId[itemId] = entry;

    switch (type) {
      case 'userMessage':
        entry.isLocalPending = false;
        entry.body = _extractUserText(item['content']);
      case 'agentMessage':
        entry.body = item['text']?.toString() ?? entry.body;
        entry.isStreaming = !isCompleted;
      case 'reasoning':
        entry.body = _extractReasoningText(item);
      case 'commandExecution':
        entry.title = item['command']?.toString() ?? entry.title;
        entry.secondary = item['cwd']?.toString() ?? entry.secondary;
        entry.body = item['aggregatedOutput']?.toString() ?? entry.body;
        entry.status = item['status']?.toString() ?? entry.status;
      case 'fileChange':
        entry.body = _extractFileChanges(item['changes']);
        entry.status = item['status']?.toString() ?? entry.status;
      case 'mcpToolCall':
      case 'collabAgentToolCall':
      case 'dynamicToolCall':
      case 'webSearch':
      case 'plan':
        entry.body = _summarizeMap(item);
        entry.status = item['status']?.toString() ?? entry.status;
      case 'enteredReviewMode':
      case 'exitedReviewMode':
        entry.body = _summarizeMap(item);
      case 'contextCompaction':
        entry.body = _extractContextCompactionText(item);
      default:
        entry.body = _summarizeMap(item);
    }

    if (isCompleted) {
      entry.isStreaming = false;
      final itemStatus = item['status']?.toString();
      if (itemStatus != null && itemStatus.isNotEmpty) {
        entry.status = itemStatus;
      }
      if (type == 'agentMessage' &&
          item['phase']?.toString() == 'final_answer' &&
          turnId != null &&
          turnId.isNotEmpty) {
        if (pendingPrompts.isNotEmpty) {
          unawaited(_processPendingPrompts());
        }
      }
    }

    notifyListeners();
  }

  ActivityEntry _createEntry(
    String itemId,
    String type,
    Map<String, dynamic> item,
  ) {
    final entry = ActivityEntry(
      key: itemId,
      kind: switch (type) {
        'userMessage' => EntryKind.user,
        'agentMessage' => EntryKind.agent,
        'reasoning' => EntryKind.reasoning,
        'commandExecution' => EntryKind.command,
        'fileChange' => EntryKind.fileChange,
        'mcpToolCall' ||
        'collabAgentToolCall' ||
        'dynamicToolCall' ||
        'webSearch' ||
        'plan' => EntryKind.tool,
        _ => EntryKind.system,
      },
      title: switch (type) {
        'userMessage' => 'You',
        'agentMessage' => 'Codex',
        'reasoning' => 'Reasoning',
        'commandExecution' => 'Command',
        'fileChange' => 'File change',
        'mcpToolCall' => 'MCP tool',
        'collabAgentToolCall' => 'Collaboration',
        'dynamicToolCall' => 'Dynamic tool',
        'webSearch' => 'Web search',
        'plan' => 'Plan',
        'enteredReviewMode' => 'Review started',
        'exitedReviewMode' => 'Review finished',
        'contextCompaction' => 'Compaction',
        _ => type,
      },
      body: '',
      status: item['status']?.toString() ?? '',
    );
    entries.add(entry);
    return entry;
  }

  String _extractUserText(dynamic content) {
    if (content is! List<dynamic>) {
      return '';
    }

    return content
        .map((item) {
          if (item is! Map<String, dynamic>) {
            return '';
          }
          if (item['type'] == 'text') {
            return item['text']?.toString() ?? '';
          }
          if (item['type'] == 'image') {
            return '[image] ${item['url'] ?? ''}';
          }
          if (item['type'] == 'localImage') {
            return '[local image] ${item['path'] ?? ''}';
          }
          return '';
        })
        .where((item) => item.isNotEmpty)
        .join('\n');
  }

  String _extractReasoningText(Map<String, dynamic> item) {
    final summary = item['summary'];
    if (summary is List<dynamic>) {
      final text = summary
          .map((part) => part?.toString() ?? '')
          .where((part) => part.isNotEmpty)
          .join('\n');
      if (text.isNotEmpty) {
        return text;
      }
    }
    final content = item['content'];
    if (content is List<dynamic>) {
      return content
          .map((part) => part?.toString() ?? '')
          .where((part) => part.isNotEmpty)
          .join('\n');
    }
    return '';
  }

  String _extractFileChanges(dynamic changes) {
    if (changes is! List<dynamic>) {
      return '';
    }

    return changes
        .map((change) {
          if (change is! Map<String, dynamic>) {
            return '';
          }
          final path = change['path']?.toString() ?? '';
          final kind = change['kind']?.toString() ?? '';
          final diff = change['diff']?.toString() ?? '';
          final header = [
            path,
            kind,
          ].where((item) => item.isNotEmpty).join(' • ');
          return [header, diff].where((item) => item.isNotEmpty).join('\n');
        })
        .where((item) => item.isNotEmpty)
        .join('\n\n');
  }

  String _extractContextCompactionText(Map<String, dynamic> item) {
    const candidates = <String>[
      'label',
      'message',
      'text',
      'summary',
      'description',
    ];
    for (final key in candidates) {
      final value = item[key];
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) {
        return text;
      }
    }
    return 'Context Compacting';
  }

  String _summarizeMap(Map<String, dynamic> item) {
    final copy = Map<String, dynamic>.from(item)..remove('id');
    return const JsonEncoder.withIndent('  ').convert(copy);
  }

  void _addSystemEntry(String message) {
    entries.add(
      ActivityEntry(
        key: 'system-${DateTime.now().microsecondsSinceEpoch}',
        kind: EntryKind.system,
        title: 'System',
        body: message,
      ),
    );
    notifyListeners();
  }

  void _pushEvent(String method, Map<String, dynamic> params) {
    final summary = switch (method) {
      'item/agentMessage/delta' => params['delta']?.toString() ?? '',
      'item/commandExecution/outputDelta' => params['delta']?.toString() ?? '',
      _ => _singleLineSummary(params),
    };
    eventLog.insert(0, EventLogEntry(method, summary));
    if (eventLog.length > 60) {
      eventLog.removeRange(60, eventLog.length);
    }
  }

  String _singleLineSummary(Map<String, dynamic> params) {
    if (params.isEmpty) {
      return '';
    }
    final text = const JsonEncoder.withIndent('  ').convert(params);
    return text.replaceAll('\n', ' ').trim();
  }

  CommandSession? get activeCommandSession {
    if (activeCommandSessionId == null) {
      return commandSessions.isEmpty ? null : commandSessions.first;
    }
    return _commandSessionsById[activeCommandSessionId!] ??
        (commandSessions.isEmpty ? null : commandSessions.first);
  }

  void _completeCommandSession(
    CommandSession session,
    Map<String, dynamic>? result,
  ) {
    session.exitCode = result?['exitCode'] as int?;
    final stdout = result?['stdout']?.toString() ?? '';
    final stderr = result?['stderr']?.toString() ?? '';
    if (stdout.isNotEmpty) {
      session.stdout = _appendCommandOutput(session.stdout, stdout);
    }
    if (stderr.isNotEmpty) {
      session.stderr = _appendCommandOutput(session.stderr, stderr);
    }
    session.status = session.exitCode == 0 ? 'completed' : 'failed';
    notifyListeners();
  }

  Future<void> _rememberRecentCommand(RecentCommand next) async {
    recentCommands.removeWhere(
      (RecentCommand current) => _sameRecentCommand(current, next),
    );
    recentCommands.insert(0, next);
    if (recentCommands.length > 8) {
      recentCommands.removeRange(8, recentCommands.length);
    }
    await _settingsStore.saveRecentCommands(recentCommands);
    notifyListeners();
  }

  bool _sameRecentCommand(RecentCommand left, RecentCommand right) {
    return left.commandText == right.commandText &&
        left.cwd == right.cwd &&
        left.mode == right.mode &&
        left.sandboxMode == right.sandboxMode &&
        left.allowNetwork == right.allowNetwork &&
        left.disableTimeout == right.disableTimeout &&
        left.timeoutMs == right.timeoutMs &&
        left.disableOutputCap == right.disableOutputCap &&
        left.outputBytesCap == right.outputBytesCap;
  }

  Map<String, dynamic>? _selectRateLimitSnapshot(
    Map<String, dynamic>? response,
  ) {
    if (response == null) {
      return null;
    }
    final byLimitId = response['rateLimitsByLimitId'];
    if (byLimitId is Map<String, dynamic> && byLimitId.isNotEmpty) {
      final preferred = byLimitId['codex'];
      if (preferred is Map<String, dynamic>) {
        return preferred;
      }
      for (final value in byLimitId.values) {
        if (value is Map<String, dynamic>) {
          return value;
        }
      }
    }
    final snapshot = response['rateLimits'];
    return snapshot is Map<String, dynamic> ? snapshot : null;
  }

  String? _formatRateLimitSummary(Map<String, dynamic>? snapshot) {
    if (snapshot == null) {
      return null;
    }
    final segments = <String>[];
    final primary = snapshot['primary'];
    if (primary is Map<String, dynamic>) {
      final label = _formatRateLimitWindow(primary);
      if (label != null) {
        segments.add(label);
      }
    }
    final secondary = snapshot['secondary'];
    if (secondary is Map<String, dynamic>) {
      final label = _formatRateLimitWindow(secondary);
      if (label != null) {
        segments.add(label);
      }
    }
    final credits = snapshot['credits'];
    if (segments.isEmpty && credits is Map<String, dynamic>) {
      if (credits['unlimited'] == true) {
        return 'unlimited';
      }
      final balance = credits['balance']?.toString();
      if (balance != null && balance.isNotEmpty) {
        return 'Credits $balance';
      }
    }
    if (segments.isEmpty) {
      return null;
    }
    return segments.join(' • ');
  }

  List<String> _formatRateLimitResetDetails(Map<String, dynamic>? snapshot) {
    if (snapshot == null) {
      return const <String>[];
    }
    final details = <String>[];
    final primary = snapshot['primary'];
    if (primary is Map<String, dynamic>) {
      final detail = _formatRateLimitResetDetail(primary);
      if (detail != null) {
        details.add(detail);
      }
    }
    final secondary = snapshot['secondary'];
    if (secondary is Map<String, dynamic>) {
      final detail = _formatRateLimitResetDetail(secondary);
      if (detail != null) {
        details.add(detail);
      }
    }
    return details;
  }

  String? _formatRateLimitWindow(Map<String, dynamic> window) {
    final usedPercent = _parsePositiveInt(window['usedPercent']);
    if (usedPercent == null) {
      return null;
    }
    final remaining = (100 - usedPercent).clamp(0, 100);
    final duration = window['windowDurationMins'];
    final durationLabel = _formatWindowDuration(duration);
    return durationLabel == null
        ? '$remaining% left'
        : '$durationLabel $remaining% left';
  }

  String? _formatRateLimitResetDetail(Map<String, dynamic> window) {
    final durationLabel = _formatWindowDuration(window['windowDurationMins']);
    final resetAt = _parseRateLimitResetAt(window);
    if (durationLabel == null || resetAt == null) {
      return null;
    }
    return '$durationLabel resets ${_formatRateLimitResetAt(resetAt)}';
  }

  (String?, int?) _contextStateFromConfig(Map<String, dynamic> config) {
    final contextWindow = _parsePositiveInt(config['model_context_window']);
    final compactLimit = _parsePositiveInt(
      config['model_auto_compact_token_limit'],
    );
    if (contextWindow == null && compactLimit == null) {
      return (null, null);
    }
    if (contextWindow != null) {
      return ('${_formatTokenCount(contextWindow)} window', null);
    }
    if (compactLimit != null) {
      return ('${_formatTokenCount(compactLimit)} compact', null);
    }
    return (null, null);
  }

  (String?, int?) _contextStateFromTokenUsage(Map<String, dynamic> tokenUsage) {
    final last = tokenUsage['last'];
    final lastMap = last is Map<String, dynamic> ? last : null;
    final lastTurnTokens = _parsePositiveInt(lastMap?['totalTokens']);
    final contextWindow = _parsePositiveInt(tokenUsage['modelContextWindow']);
    if (lastTurnTokens == null && contextWindow == null) {
      return (null, null);
    }
    if (lastTurnTokens != null && contextWindow != null && contextWindow > 0) {
      final usedPercent = ((lastTurnTokens / contextWindow) * 100)
          .round()
          .clamp(0, 100);
      return ('$usedPercent% last/window', usedPercent);
    }
    if (lastTurnTokens != null) {
      return ('${_formatTokenCount(lastTurnTokens)} last', null);
    }
    return ('${_formatTokenCount(contextWindow!)} window', null);
  }

  int? _parsePositiveInt(dynamic value) {
    if (value is int) {
      return value > 0 ? value : null;
    }
    if (value is num) {
      final asInt = value.round();
      return asInt > 0 ? asInt : null;
    }
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }
    return null;
  }

  DateTime? _parseRateLimitResetAt(Map<String, dynamic> window) {
    const candidates = <String>[
      'resetsAt',
      'resetAt',
      'resetsAtIso',
      'resetAtIso',
      'resetsAtUnixMs',
      'resetAtUnixMs',
      'resetsAtMs',
      'resetAtMs',
      'resetsAtUnix',
      'resetAtUnix',
    ];
    for (final key in candidates) {
      final value = window[key];
      if (value == null) {
        continue;
      }
      if (value is String) {
        final parsed = DateTime.tryParse(value.trim());
        if (parsed != null) {
          return parsed.toLocal();
        }
        final asInt = int.tryParse(value.trim());
        if (asInt != null) {
          return _dateTimeFromEpochGuess(asInt);
        }
      }
      if (value is int) {
        return _dateTimeFromEpochGuess(value);
      }
      if (value is num) {
        return _dateTimeFromEpochGuess(value.round());
      }
    }
    return null;
  }

  DateTime _dateTimeFromEpochGuess(int value) {
    final isMilliseconds = value.abs() >= 100000000000;
    return isMilliseconds
        ? DateTime.fromMillisecondsSinceEpoch(value).toLocal()
        : DateTime.fromMillisecondsSinceEpoch(value * 1000).toLocal();
  }

  String? _formatWindowDuration(dynamic minutesValue) {
    if (minutesValue is! int || minutesValue <= 0) {
      return null;
    }
    if (minutesValue % 1440 == 0) {
      return '${minutesValue ~/ 1440}d';
    }
    if (minutesValue % 60 == 0) {
      return '${minutesValue ~/ 60}h';
    }
    return '${minutesValue}m';
  }

  String _formatRateLimitResetAt(DateTime value) {
    const monthNames = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = monthNames[value.month - 1];
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$month $day, $hour:$minute';
  }

  String _formatTokenCount(int value) {
    if (value >= 1000000) {
      final millions = value / 1000000;
      final text = millions.toStringAsFixed(
        millions.truncateToDouble() == millions ? 0 : 1,
      );
      return '${text}M';
    }
    if (value >= 1000) {
      final thousands = value / 1000;
      final text = thousands.toStringAsFixed(
        thousands.truncateToDouble() == thousands ? 0 : 1,
      );
      return '${text}k';
    }
    return value.toString();
  }

  String _normalizeCommandOutput(String value) {
    final csiPattern = RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]');
    final oscPattern = RegExp(r'\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)');
    final withoutOsc = value.replaceAll(oscPattern, '');
    final withoutAnsi = withoutOsc.replaceAll(csiPattern, '');
    final terminalText = _applyTerminalControls(withoutAnsi);
    return _collapseSingleCharacterLines(terminalText);
  }

  String _appendCommandOutput(String existing, String nextChunk) {
    return _normalizeCommandOutput(existing + nextChunk);
  }

  String _collapseSingleCharacterLines(String value) {
    final lines = value.split('\n');
    if (lines.length < 8) {
      return value;
    }

    final collapsed = <String>[];
    final singleCharRun = <String>[];

    void flushRun() {
      if (singleCharRun.isEmpty) {
        return;
      }
      final nonEmpty = singleCharRun.where((line) => line.isNotEmpty).toList();
      final mostlySingleChar =
          nonEmpty.length >= 6 &&
          nonEmpty.every((line) {
            final trimmed = line.trim();
            return line.runes.length == 1 || trimmed.runes.length == 1;
          });
      if (mostlySingleChar) {
        final joined = singleCharRun.join();
        if (collapsed.isNotEmpty && joined.startsWith(RegExp(r'\s'))) {
          collapsed[collapsed.length - 1] = '${collapsed.last}$joined';
        } else {
          collapsed.add(joined);
        }
      } else {
        collapsed.addAll(singleCharRun);
      }
      singleCharRun.clear();
    }

    for (final line in lines) {
      final trimmed = line.trim();
      final isRepairableSingleChar =
          line.isEmpty || line.runes.length == 1 || trimmed.runes.length == 1;
      if (isRepairableSingleChar) {
        singleCharRun.add(line);
      } else {
        flushRun();
        collapsed.add(line);
      }
    }
    flushRun();

    return collapsed.join('\n');
  }

  String _applyTerminalControls(String value) {
    final lines = <String>[];
    var currentLine = <String>[];
    var cursor = 0;

    void writeChar(String char) {
      if (cursor > currentLine.length) {
        currentLine.addAll(
          List<String>.filled(cursor - currentLine.length, ' '),
        );
      }
      if (cursor == currentLine.length) {
        currentLine.add(char);
      } else {
        currentLine[cursor] = char;
      }
      cursor += 1;
    }

    void commitLine() {
      lines.add(currentLine.join());
      currentLine = <String>[];
      cursor = 0;
    }

    for (final rune in value.runes) {
      if (rune == 10) {
        commitLine();
        continue;
      }
      if (rune == 13) {
        cursor = 0;
        continue;
      }
      if (rune == 8) {
        if (cursor > 0) {
          cursor -= 1;
        }
        continue;
      }
      if (rune == 9) {
        final spaces = 4 - (cursor % 4);
        for (var index = 0; index < spaces; index += 1) {
          writeChar(' ');
        }
        continue;
      }
      final isControl = rune < 32 || (rune >= 127 && rune <= 159);
      if (!isControl) {
        writeChar(String.fromCharCode(rune));
      }
    }

    lines.add(currentLine.join());
    return lines.join('\n');
  }

  ThreadSummary? _parseThreadSummary(dynamic item) {
    if (item is! Map<String, dynamic>) {
      return null;
    }

    return ThreadSummary(
      id: item['id']?.toString() ?? '',
      preview: item['preview']?.toString() ?? '',
      cwd: item['cwd']?.toString() ?? '',
      source: _sourceText(item['source']),
      modelProvider: item['modelProvider']?.toString() ?? '',
      createdAt: _parseUnixTimestamp(item['createdAt']),
      updatedAt: _parseUnixTimestamp(item['updatedAt']),
      status: _statusText(item['status']),
      name: item['name']?.toString(),
      agentNickname: item['agentNickname']?.toString(),
      agentRole: item['agentRole']?.toString(),
    );
  }

  DateTime? _parseUnixTimestamp(dynamic value) {
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(
        value * 1000,
        isUtc: true,
      ).toLocal();
    }
    return null;
  }

  String _statusText(dynamic status) {
    if (status is Map<String, dynamic>) {
      return status['type']?.toString() ?? '';
    }
    return status?.toString() ?? '';
  }

  String _sourceText(dynamic source) {
    if (source is Map<String, dynamic>) {
      return source['type']?.toString() ?? source.toString();
    }
    return source?.toString() ?? '';
  }

  void _updateThreadSummaryName(String threadId, String name) {
    final index = threadHistory.indexWhere((item) => item.id == threadId);
    if (index < 0) {
      return;
    }
    final current = threadHistory[index];
    threadHistory[index] = ThreadSummary(
      id: current.id,
      preview: current.preview,
      cwd: current.cwd,
      source: current.source,
      modelProvider: current.modelProvider,
      createdAt: current.createdAt,
      updatedAt: current.updatedAt,
      status: current.status,
      name: name,
      agentNickname: current.agentNickname,
      agentRole: current.agentRole,
    );
    _sortThreadHistory();
  }

  void _sortThreadHistory() {
    threadHistory.sort((a, b) {
      final aFavorite = isThreadFavorite(a.id);
      final bFavorite = isThreadFavorite(b.id);
      if (aFavorite != bFavorite) {
        return aFavorite ? -1 : 1;
      }
      final aUpdated = a.updatedAt ?? a.createdAt;
      final bUpdated = b.updatedAt ?? b.createdAt;
      if (aUpdated != null && bUpdated != null) {
        return bUpdated.compareTo(aUpdated);
      }
      if (aUpdated != null) {
        return -1;
      }
      if (bUpdated != null) {
        return 1;
      }
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
  }

  String _normalizeAbsolutePath(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (!trimmed.startsWith('/')) {
      return '';
    }
    if (trimmed.length > 1 && trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  Future<void> _unsubscribeFromThread(String threadId) async {
    final normalizedThreadId = threadId.trim();
    if (normalizedThreadId.isEmpty || !isConnected) {
      return;
    }
    if (_subscribedThreadId != normalizedThreadId &&
        activeThreadId != normalizedThreadId) {
      return;
    }
    try {
      await _request('thread/unsubscribe', <String, dynamic>{
        'threadId': normalizedThreadId,
      });
    } catch (_) {
      // Best-effort cleanup. A failed unsubscribe should not block switching threads.
    } finally {
      if (_subscribedThreadId == normalizedThreadId) {
        _subscribedThreadId = null;
      }
    }
  }

  bool _isLikelyHumanReadableFile(String path, Uint8List bytes) {
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
    final sampleSize = bytes.length > 1024 ? 1024 : bytes.length;
    for (var i = 0; i < sampleSize; i += 1) {
      final unit = bytes[i];
      if (unit == 0) {
        return false;
      }
      final isControl = unit < 32 && unit != 9 && unit != 10 && unit != 13;
      if (isControl) {
        suspicious += 1;
      }
    }
    return suspicious <= sampleSize * 0.02;
  }

  void _hydrateEntriesFromThread(Map<String, dynamic> thread) {
    final hydratedEntries = <ActivityEntry>[];
    final turns = thread['turns'];
    if (turns is List<dynamic>) {
      for (final turn in turns) {
        if (turn is! Map<String, dynamic>) {
          continue;
        }
        final items = turn['items'];
        if (items is! List<dynamic>) {
          continue;
        }
        for (final item in items) {
          final entry = _entryFromHistoryItem(item);
          if (entry != null) {
            hydratedEntries.add(entry);
          }
        }
      }
    }

    entries
      ..clear()
      ..addAll(hydratedEntries);
    approvals.clear();
    _entryByItemId
      ..clear()
      ..addEntries(
        hydratedEntries.map(
          (item) => MapEntry<String, ActivityEntry>(item.key, item),
        ),
      );
    activeTurnId = null;
    activeThreadCwd = thread['cwd']?.toString() ?? activeThreadCwd;
  }

  void _hydrateResumeTurn(Map<String, dynamic> turn) {
    final turnId = turn['id']?.toString();
    if (turnId == null || turnId.isEmpty) {
      return;
    }

    final items = turn['items'];
    if (items is List<dynamic>) {
      for (final item in items) {
        final itemMap = item is Map<String, dynamic> ? item : null;
        if (itemMap == null) {
          continue;
        }
        _handleItem(
          itemMap,
          isCompleted: turn['status']?.toString() != 'inProgress',
          turnId: turnId,
        );
      }
    }

    if (turn['status']?.toString() == 'inProgress') {
      activeTurnId = turnId;
      final threadId = activeThreadId?.trim() ?? '';
      if (threadId.isNotEmpty) {
        _activeTurnIdsByThread[threadId] = turnId;
      }
      statusMessage = 'Turn running';
    } else if (activeTurnId == turnId) {
      activeTurnId = null;
      final threadId = activeThreadId?.trim() ?? '';
      if (threadId.isNotEmpty) {
        _activeTurnIdsByThread.remove(threadId);
      }
      statusMessage = 'Ready';
    }
  }

  ActivityEntry? _entryFromHistoryItem(dynamic item) {
    if (item is! Map<String, dynamic>) {
      return null;
    }
    final itemId = item['id']?.toString();
    final type = item['type']?.toString() ?? 'unknown';
    if (itemId == null || itemId.isEmpty) {
      return null;
    }

    final entry = ActivityEntry(
      key: itemId,
      kind: switch (type) {
        'userMessage' => EntryKind.user,
        'agentMessage' => EntryKind.agent,
        'reasoning' => EntryKind.reasoning,
        'commandExecution' => EntryKind.command,
        'fileChange' => EntryKind.fileChange,
        'mcpToolCall' ||
        'collabAgentToolCall' ||
        'dynamicToolCall' ||
        'webSearch' ||
        'plan' => EntryKind.tool,
        _ => EntryKind.system,
      },
      title: switch (type) {
        'userMessage' => 'You',
        'agentMessage' => 'Codex',
        'reasoning' => 'Reasoning',
        'commandExecution' => item['command']?.toString() ?? 'Command',
        'fileChange' => 'File change',
        'mcpToolCall' => 'MCP tool',
        'collabAgentToolCall' => 'Collaboration',
        'dynamicToolCall' => 'Dynamic tool',
        'webSearch' => 'Web search',
        'plan' => 'Plan',
        _ => type,
      },
      secondary: item['cwd']?.toString() ?? '',
      status: item['status']?.toString() ?? '',
    );

    switch (type) {
      case 'userMessage':
        entry.body = _extractUserText(item['content']);
      case 'agentMessage':
        entry.body = item['text']?.toString() ?? '';
      case 'reasoning':
        entry.body = _extractReasoningText(item);
      case 'commandExecution':
        entry.body = item['aggregatedOutput']?.toString() ?? '';
      case 'fileChange':
        entry.body = _extractFileChanges(item['changes']);
      default:
        entry.body = _summarizeMap(item);
    }

    return entry;
  }

  static Future<bool> _defaultOpenPath(String path) async {
    if (Platform.isAndroid) {
      final normalizedPath = path.trim().toLowerCase();
      if (normalizedPath.isNotEmpty &&
          (normalizedPath.startsWith('/storage/') ||
              normalizedPath.startsWith('/sdcard/'))) {
        final storageStatus = await Permission.manageExternalStorage.status;
        if (!storageStatus.isGranted) {
          final requested = await Permission.manageExternalStorage.request();
          if (!requested.isGranted) {
            await openAppSettings();
            return false;
          }
        }
      }
      if (normalizedPath.endsWith('.apk')) {
        final installStatus = await Permission.requestInstallPackages.status;
        if (!installStatus.isGranted) {
          final requested = await Permission.requestInstallPackages.request();
          if (!requested.isGranted) {
            await openAppSettings();
            return false;
          }
        }
      }
    }
    final result = await OpenFilex.open(path);
    return result.type == ResultType.done;
  }

  _RelayPairingCodePayload _decodeRelayPairingCode(String value) {
    const prefix = 'crp1.';
    final trimmed = value.trim();
    if (!trimmed.startsWith(prefix)) {
      throw StateError('Unsupported pairing code format.');
    }
    final payload =
        jsonDecode(utf8.decode(_b64urlDecode(trimmed.substring(prefix.length))))
            as Map<String, dynamic>;
    if (payload['type']?.toString() != 'codex-remote-pairing-v1') {
      throw StateError('Unsupported pairing code payload.');
    }
    final relayUrl = payload['relayUrl']?.toString() ?? '';
    final deviceId = payload['deviceId']?.toString() ?? '';
    final claimToken = payload['claimToken']?.toString() ?? '';
    final bridgeSigningPublicKey =
        payload['bridgeSigningPublicKey']?.toString() ?? '';
    final bridgeLabel = payload['bridgeLabel']?.toString() ?? '';
    final expiresAt = payload['expiresAt'] as int? ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final relayUri = Uri.tryParse(relayUrl);
    if (relayUrl.isEmpty ||
        deviceId.isEmpty ||
        claimToken.isEmpty ||
        bridgeSigningPublicKey.isEmpty) {
      throw StateError('Pairing code is incomplete.');
    }
    if (relayUri == null || !relayUri.hasScheme || relayUri.host.isEmpty) {
      throw StateError('Pairing code contains an invalid relay URL.');
    }
    if (!_isAllowedRelayUri(relayUri)) {
      throw StateError(
        'Relay pairing requires HTTPS for non-local relay servers.',
      );
    }
    if (expiresAt != 0 && expiresAt < now) {
      throw StateError('Pairing code has expired.');
    }
    return _RelayPairingCodePayload(
      bridgeLabel: bridgeLabel,
      bridgeSigningPublicKey: bridgeSigningPublicKey,
      claimToken: claimToken,
      deviceId: deviceId,
      relayUrl: relayUrl,
    );
  }
}

class _RelayPairingCodePayload {
  const _RelayPairingCodePayload({
    required this.bridgeLabel,
    required this.bridgeSigningPublicKey,
    required this.claimToken,
    required this.deviceId,
    required this.relayUrl,
  });

  final String bridgeLabel;
  final String bridgeSigningPublicKey;
  final String claimToken;
  final String deviceId;
  final String relayUrl;
}

String _b64urlEncode(List<int> bytes) {
  return base64Url.encode(bytes).replaceAll('=', '');
}

Uint8List _b64urlDecode(String value) {
  final normalized = value.padRight((value.length + 3) ~/ 4 * 4, '=');
  return Uint8List.fromList(base64Url.decode(normalized));
}

bool _isAllowedRelayUri(Uri relayUri) {
  if (relayUri.scheme == 'https') {
    return true;
  }
  if (relayUri.scheme != 'http') {
    return false;
  }
  final host = relayUri.host.toLowerCase();
  return host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '::1' ||
      host.endsWith('.local');
}

class _ActiveAutomationWatch {
  const _ActiveAutomationWatch({
    required this.automationId,
    required this.watchId,
    required this.path,
    required this.kind,
  });

  final String automationId;
  final String watchId;
  final String path;
  final AutomationNodeKind kind;
}

class _RegisteredAutomationWatch {
  const _RegisteredAutomationWatch({required this.watchId, required this.path});

  final String watchId;
  final String path;
}

class _AutomationExecutionContext {
  _AutomationExecutionContext({
    required this.changedPaths,
    required this.watchedPath,
    required this.triggerKind,
  });

  final List<String> changedPaths;
  final String watchedPath;
  final AutomationNodeKind triggerKind;
  String? lastDownloadedPath;
  final Map<String, Map<String, String>> nodeOutputs =
      <String, Map<String, String>>{};
  String? _previousNodeId;

  void recordNodeOutput(String nodeId, Map<String, String> values) {
    nodeOutputs[nodeId] = values;
    _previousNodeId = nodeId;
    final downloadedPath = values['downloadedPath']?.trim() ?? '';
    if (downloadedPath.isNotEmpty) {
      lastDownloadedPath = downloadedPath;
    }
  }

  String? valueForToken(String token) {
    if (token.isEmpty) {
      return null;
    }
    final firstChangedPath = changedPaths.isEmpty ? '' : changedPaths.first;
    switch (token) {
      case 'trigger.path':
      case 'trigger.watchedPath':
        return watchedPath;
      case 'trigger.changedPath':
        return firstChangedPath;
      case 'automation.lastDownloadedPath':
      case 'lastDownloadedPath':
        return lastDownloadedPath;
    }

    if (token.startsWith('previous.')) {
      final previousNodeId = _previousNodeId;
      if (previousNodeId == null) {
        return null;
      }
      return nodeOutputs[previousNodeId]?[token.substring('previous.'.length)];
    }

    if (token.startsWith('node.')) {
      final parts = token.split('.');
      if (parts.length >= 3) {
        final nodeId = parts[1];
        final key = parts.sublist(2).join('.');
        return nodeOutputs[nodeId]?[key];
      }
    }

    return null;
  }
}

class _PendingDownload {
  _PendingDownload({required this.expectedBytes, required this.onProgress})
    : _startedAt = DateTime.now();

  final int? expectedBytes;
  final ValueChanged<FileDownloadStatus>? onProgress;
  final DateTime _startedAt;
  String stderr = '';
  bool isCancelled = false;
  int writtenBytes = 0;
  bool _processExited = false;
  final Completer<void> _completion = Completer<void>();

  void cancel() {
    isCancelled = true;
    _completeIfReady();
  }

  void markProcessExited() {
    _processExited = true;
    _completeIfReady();
  }

  void reportProgress() {
    final callback = onProgress;
    if (callback == null) {
      _completeIfReady();
      return;
    }
    final total = expectedBytes;
    if (total == null || total <= 0) {
      callback(
        FileDownloadStatus(
          progress: 0.8,
          receivedBytes: writtenBytes,
          totalBytes: null,
          eta: null,
        ),
      );
      _completeIfReady();
      return;
    }
    final progress = writtenBytes / total;
    final safeProgress = progress.clamp(0.0, 0.95);
    final elapsed = DateTime.now().difference(_startedAt);
    Duration? eta;
    if (writtenBytes > 0 &&
        elapsed.inMilliseconds > 0 &&
        writtenBytes < total) {
      final bytesPerMs = writtenBytes / elapsed.inMilliseconds;
      if (bytesPerMs > 0) {
        final remainingMs = ((total - writtenBytes) / bytesPerMs).round();
        eta = Duration(milliseconds: remainingMs);
      }
    }
    callback(
      FileDownloadStatus(
        progress: safeProgress,
        receivedBytes: writtenBytes,
        totalBytes: total,
        eta: eta,
      ),
    );
    _completeIfReady();
  }

  void addBytes(int count) {
    writtenBytes += count;
    reportProgress();
  }

  Future<void> waitForCompletion() async {
    _completeIfReady();
    if (_completion.isCompleted) {
      return;
    }
    await _completion.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        if (_completion.isCompleted) {
          return;
        }
        if (isCancelled) {
          _completion.complete();
          return;
        }
        final total = expectedBytes;
        if (total != null && total > 0 && writtenBytes != total) {
          _completion.completeError(
            StateError(
              'Download truncated: expected $total bytes, received $writtenBytes bytes.',
            ),
          );
          return;
        }
        _completion.complete();
      },
    );
  }

  void _completeIfReady() {
    if (_completion.isCompleted) {
      return;
    }
    if (isCancelled) {
      _completion.complete();
      return;
    }
    if (!_processExited) {
      return;
    }
    final total = expectedBytes;
    if (total != null && total > 0) {
      if (writtenBytes >= total) {
        _completion.complete();
      }
      return;
    }
    _completion.complete();
  }
}

class _PendingTransferServer {
  final Completer<_TransferEndpoint> _ready = Completer<_TransferEndpoint>();
  final StringBuffer _stdoutBuffer = StringBuffer();
  String stderr = '';

  void handleStdout(String chunk) {
    _stdoutBuffer.write(chunk);
    final lines = _stdoutBuffer.toString().split('\n');
    if (!chunk.endsWith('\n')) {
      final trailing = lines.removeLast();
      _stdoutBuffer
        ..clear()
        ..write(trailing);
    } else {
      _stdoutBuffer.clear();
    }
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic> &&
            decoded['event'] == 'ready' &&
            decoded['port'] is int &&
            decoded['token'] is String &&
            !_ready.isCompleted) {
          _ready.complete(
            _TransferEndpoint(
              port: decoded['port'] as int,
              token: decoded['token'] as String,
            ),
          );
          return;
        }
      } catch (_) {
        // Ignore unrelated command output.
      }
    }
  }

  Future<_TransferEndpoint> waitForReady() {
    return _ready.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        throw TimeoutException(
          'Temporary download server did not become ready.',
          const Duration(seconds: 10),
        );
      },
    );
  }
}

class FileDownloadStatus {
  const FileDownloadStatus({
    required this.progress,
    required this.receivedBytes,
    required this.totalBytes,
    required this.eta,
  });

  final double progress;
  final int receivedBytes;
  final int? totalBytes;
  final Duration? eta;
}

enum DownloadState { running, completed, failed, cancelled }

class DownloadRecord {
  const DownloadRecord({
    required this.sourcePath,
    required this.fileName,
    required this.state,
    required this.startedAt,
    this.status,
    this.targetPath,
    this.error,
    this.finishedAt,
  });

  final String sourcePath;
  final String fileName;
  final String? targetPath;
  final DownloadState state;
  final FileDownloadStatus? status;
  final String? error;
  final DateTime startedAt;
  final DateTime? finishedAt;

  DownloadRecord copyWith({
    String? sourcePath,
    String? fileName,
    String? targetPath,
    DownloadState? state,
    FileDownloadStatus? status,
    String? error,
    DateTime? startedAt,
    DateTime? finishedAt,
  }) {
    return DownloadRecord(
      sourcePath: sourcePath ?? this.sourcePath,
      fileName: fileName ?? this.fileName,
      targetPath: targetPath ?? this.targetPath,
      state: state ?? this.state,
      status: status ?? this.status,
      error: error ?? this.error,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
    );
  }
}

class _DirectoryCacheEntry {
  const _DirectoryCacheEntry({required this.entries, required this.loadedAt});

  final List<FileSystemEntry> entries;
  final DateTime loadedAt;
}

class _FilePreviewCacheEntry {
  const _FilePreviewCacheEntry({
    required this.bytes,
    required this.content,
    required this.isHumanReadable,
    required this.loadedAt,
  });

  final Uint8List bytes;
  final String? content;
  final bool isHumanReadable;
  final DateTime loadedAt;
}

class _PreparedUserInput {
  const _PreparedUserInput({
    required this.input,
    required this.uploadedImagePaths,
  });

  final List<Map<String, dynamic>> input;
  final List<String> uploadedImagePaths;
}

class _TransferEndpoint {
  const _TransferEndpoint({required this.port, required this.token});

  final int port;
  final String token;
}

class _DownloadCancelled implements Exception {
  const _DownloadCancelled();
}
