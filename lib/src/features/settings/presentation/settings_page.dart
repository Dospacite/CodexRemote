import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../app_controller.dart';
import '../../../models.dart';

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
              DropdownButtonFormField<ConnectionMode>(
                initialValue: _connectionMode,
                decoration: const InputDecoration(labelText: 'Connection mode'),
                items: ConnectionMode.values.map((ConnectionMode value) {
                  return DropdownMenuItem<ConnectionMode>(
                    value: value,
                    child: Text(value.name),
                  );
                }).toList(),
                onChanged: (ConnectionMode? value) {
                  if (value != null) {
                    setState(() {
                      _connectionMode = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              if (_connectionMode == ConnectionMode.direct) ...<Widget>[
                TextField(
                  controller: _serverController,
                  decoration: const InputDecoration(
                    labelText: 'Websocket URL',
                    hintText: 'ws://192.168.1.20:8080',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _websocketBearerTokenController,
                  autocorrect: false,
                  enableSuggestions: false,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Websocket bearer token',
                    hintText: 'Optional Authorization: Bearer token',
                    helperText:
                        'Sent during the websocket handshake when app-server auth is enabled.',
                  ),
                ),
              ] else ...<Widget>[
                TextField(
                  controller: _relayUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Relay URL',
                    hintText: 'https://relay.example.com',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pairingCodeController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Pairing code',
                    hintText: 'crp1....',
                    helperText:
                        'Paste the pairing code or scan the QR shown by codex-remote-cli.',
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isPairing ? null : _scanRelayQrCode,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan QR code'),
                  ),
                ),
                if (widget.controller.settings.relayDeviceId.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Paired bridge: ${widget.controller.settings.relayBridgeLabel.isEmpty ? widget.controller.settings.relayDeviceId : widget.controller.settings.relayBridgeLabel}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                if (_pairingError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _pairingError!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                if (_pairingSuccess != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _pairingSuccess!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isPairing ? null : _pairRelayDevice,
                        child: Text(_isPairing ? 'Pairing...' : 'Pair device'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            widget.controller.settings.relayDeviceId.isEmpty
                            ? null
                            : _clearRelayPairing,
                        child: const Text('Clear pairing'),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<ThemePreference>(
                initialValue: _themePreference,
                decoration: const InputDecoration(labelText: 'Theme'),
                items: ThemePreference.values.map((item) {
                  return DropdownMenuItem<ThemePreference>(
                    value: item,
                    child: Text(item.name),
                  );
                }).toList(),
                onChanged: (ThemePreference? value) {
                  if (value != null) {
                    setState(() => _themePreference = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<SandboxMode>(
                initialValue: _sandboxMode,
                decoration: const InputDecoration(labelText: 'Sandbox'),
                items: SandboxMode.values.map((item) {
                  return DropdownMenuItem<SandboxMode>(
                    value: item,
                    child: Text(item.name),
                  );
                }).toList(),
                onChanged: (SandboxMode? value) {
                  if (value != null) {
                    setState(() => _sandboxMode = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _approvalPolicy,
                decoration: const InputDecoration(labelText: 'Approval policy'),
                items:
                    const <String>[
                      'untrusted',
                      'on-request',
                      'on-failure',
                      'never',
                    ].map((item) {
                      return DropdownMenuItem<String>(
                        value: item,
                        child: Text(item),
                      );
                    }).toList(),
                onChanged: (String? value) {
                  if (value != null) {
                    setState(() => _approvalPolicy = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                value: _allowNetwork,
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow network in workspace-write mode'),
                onChanged: (bool value) {
                  setState(() => _allowNetwork = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _threadLoadTimeoutController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Thread load timeout ms',
                  helperText:
                      'Used for thread list, thread read, and thread resume requests.',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Last thread: ${widget.controller.settings.resumeThreadId.isEmpty ? 'none' : widget.controller.settings.resumeThreadId}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _save,
                      child: const Text('Save'),
                    ),
                  ),
                ],
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

class _RelayPairingQrScannerPage extends StatefulWidget {
  const _RelayPairingQrScannerPage();

  @override
  State<_RelayPairingQrScannerPage> createState() =>
      _RelayPairingQrScannerPageState();
}

class _RelayPairingQrScannerPageState
    extends State<_RelayPairingQrScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handledCode = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Pairing QR')),
      body: Stack(
        children: <Widget>[
          MobileScanner(
            controller: _controller,
            onDetect: (BarcodeCapture capture) {
              if (_handledCode) {
                return;
              }
              for (final barcode in capture.barcodes) {
                final rawValue = barcode.rawValue?.trim() ?? '';
                if (!rawValue.startsWith('crp1.')) {
                  continue;
                }
                _handledCode = true;
                _controller.stop();
                Navigator.of(context).pop(rawValue);
                return;
              }
            },
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 24,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Point the camera at the relay pairing QR code.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
