library settings_page;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../app_controller.dart';
import '../../../models.dart';

part 'settings_page/relay_pairing_qr_scanner_page.dart';
part 'settings_page/settings_sections.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late ConnectionMode _connectionMode;
  late final TextEditingController _serverController;
  late final TextEditingController _websocketBearerTokenController;
  late final TextEditingController _relayUrlController;
  late final TextEditingController _pairingCodeController;
  late final TextEditingController _threadLoadTimeoutController;
  late ThemePreference _themePreference;
  late SandboxMode _sandboxMode;
  late String _approvalPolicy;
  late bool _allowNetwork;
  bool _isPairing = false;
  String? _pairingError;
  String? _pairingSuccess;

  @override
  void initState() {
    super.initState();
    final settings = widget.controller.settings;
    _connectionMode = settings.connectionMode;
    _serverController = TextEditingController(text: settings.serverUrl);
    _websocketBearerTokenController = TextEditingController(
      text: settings.websocketBearerToken,
    );
    _relayUrlController = TextEditingController(text: settings.relayUrl);
    _pairingCodeController = TextEditingController();
    _threadLoadTimeoutController = TextEditingController(
      text: settings.threadLoadTimeoutMs.toString(),
    );
    _themePreference = settings.themePreference;
    _sandboxMode = settings.sandboxMode;
    _approvalPolicy = settings.approvalPolicy;
    _allowNetwork = settings.allowNetwork;
  }

  @override
  void dispose() {
    _serverController.dispose();
    _websocketBearerTokenController.dispose();
    _relayUrlController.dispose();
    _pairingCodeController.dispose();
    _threadLoadTimeoutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _ConnectionSection(
                connectionMode: _connectionMode,
                serverController: _serverController,
                websocketBearerTokenController: _websocketBearerTokenController,
                relayUrlController: _relayUrlController,
                pairingCodeController: _pairingCodeController,
                isPairing: _isPairing,
                pairingError: _pairingError,
                pairingSuccess: _pairingSuccess,
                relayDeviceId: widget.controller.settings.relayDeviceId,
                relayBridgeLabel: widget.controller.settings.relayBridgeLabel,
                onConnectionModeChanged: (ConnectionMode value) {
                  setState(() {
                    _connectionMode = value;
                  });
                },
                onScanQrCode: _scanRelayQrCode,
                onPairDevice: _pairRelayDevice,
                onClearPairing: _clearRelayPairing,
              ),
              const SizedBox(height: 12),
              _PreferencesSection(
                themePreference: _themePreference,
                sandboxMode: _sandboxMode,
                approvalPolicy: _approvalPolicy,
                allowNetwork: _allowNetwork,
                threadLoadTimeoutController: _threadLoadTimeoutController,
                resumeThreadId: widget.controller.settings.resumeThreadId,
                onThemeChanged: (ThemePreference value) {
                  setState(() => _themePreference = value);
                },
                onSandboxChanged: (SandboxMode value) {
                  setState(() => _sandboxMode = value);
                },
                onApprovalPolicyChanged: (String value) {
                  setState(() => _approvalPolicy = value);
                },
                onAllowNetworkChanged: (bool value) {
                  setState(() => _allowNetwork = value);
                },
              ),
              const SizedBox(height: 12),
              _SettingsFooter(
                onClose: () => Navigator.of(context).pop(),
                onSave: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final parsedThreadLoadTimeoutMs = int.tryParse(
      _threadLoadTimeoutController.text.trim(),
    );
    final nextSettings = widget.controller.settings.copyWith(
      connectionMode: _connectionMode,
      serverUrl: _serverController.text.trim(),
      websocketBearerToken: _websocketBearerTokenController.text.trim(),
      relayUrl: _relayUrlController.text.trim(),
      themePreference: _themePreference,
      sandboxMode: _sandboxMode,
      approvalPolicy: _approvalPolicy,
      allowNetwork: _allowNetwork,
      threadLoadTimeoutMs:
          parsedThreadLoadTimeoutMs == null || parsedThreadLoadTimeoutMs <= 0
          ? 20000
          : parsedThreadLoadTimeoutMs,
    );
    await widget.controller.reconnectWithSettings(nextSettings);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _pairRelayDevice() async {
    await _pairRelayDeviceWithCode(_pairingCodeController.text);
  }

  Future<void> _pairRelayDeviceWithCode(String pairingCode) async {
    setState(() {
      _isPairing = true;
      _pairingError = null;
      _pairingSuccess = null;
    });
    try {
      await widget.controller.pairRelayDevice(pairingCode: pairingCode);
      _relayUrlController.text = widget.controller.settings.relayUrl;
      _pairingCodeController.clear();
      setState(() {
        _pairingSuccess = 'Device paired successfully.';
        _connectionMode = ConnectionMode.relay;
      });
    } catch (error) {
      setState(() {
        _pairingError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isPairing = false;
        });
      }
    }
  }

  Future<void> _scanRelayQrCode() async {
    final scannedCode = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => const _RelayPairingQrScannerPage(),
        fullscreenDialog: true,
      ),
    );
    if (!mounted || scannedCode == null || scannedCode.isEmpty) {
      return;
    }
    _pairingCodeController.text = scannedCode;
    await _pairRelayDeviceWithCode(scannedCode);
  }

  Future<void> _clearRelayPairing() async {
    await widget.controller.clearRelayPairing();
    _relayUrlController.clear();
    setState(() {
      _pairingError = null;
      _pairingSuccess = null;
      _connectionMode = ConnectionMode.direct;
    });
  }
}
