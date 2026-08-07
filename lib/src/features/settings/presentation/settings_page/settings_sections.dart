part of settings_page;

class _ConnectionSection extends StatelessWidget {
  const _ConnectionSection({
    required this.connectionMode,
    required this.serverController,
    required this.websocketBearerTokenController,
    required this.relayUrlController,
    required this.pairingCodeController,
    required this.isPairing,
    required this.pairingError,
    required this.pairingSuccess,
    required this.relayDeviceId,
    required this.relayBridgeLabel,
    required this.onConnectionModeChanged,
    required this.onScanQrCode,
    required this.onPairDevice,
    required this.onClearPairing,
  });

  final ConnectionMode connectionMode;
  final TextEditingController serverController;
  final TextEditingController websocketBearerTokenController;
  final TextEditingController relayUrlController;
  final TextEditingController pairingCodeController;
  final bool isPairing;
  final String? pairingError;
  final String? pairingSuccess;
  final String relayDeviceId;
  final String relayBridgeLabel;
  final ValueChanged<ConnectionMode> onConnectionModeChanged;
  final VoidCallback onScanQrCode;
  final VoidCallback onPairDevice;
  final VoidCallback onClearPairing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        DropdownButtonFormField<ConnectionMode>(
          initialValue: connectionMode,
          decoration: const InputDecoration(labelText: 'Connection mode'),
          items: ConnectionMode.values.map((ConnectionMode value) {
            return DropdownMenuItem<ConnectionMode>(
              value: value,
              child: Text(value.name),
            );
          }).toList(),
          onChanged: (ConnectionMode? value) {
            if (value != null) {
              onConnectionModeChanged(value);
            }
          },
        ),
        const SizedBox(height: 12),
        if (connectionMode == ConnectionMode.direct)
          _DirectConnectionSection(
            serverController: serverController,
            websocketBearerTokenController: websocketBearerTokenController,
          )
        else
          _RelayConnectionSection(
            relayUrlController: relayUrlController,
            pairingCodeController: pairingCodeController,
            isPairing: isPairing,
            pairingError: pairingError,
            pairingSuccess: pairingSuccess,
            relayDeviceId: relayDeviceId,
            relayBridgeLabel: relayBridgeLabel,
            textTheme: theme.textTheme,
            colorScheme: theme.colorScheme,
            onScanQrCode: onScanQrCode,
            onPairDevice: onPairDevice,
            onClearPairing: onClearPairing,
          ),
      ],
    );
  }
}

class _DirectConnectionSection extends StatelessWidget {
  const _DirectConnectionSection({
    required this.serverController,
    required this.websocketBearerTokenController,
  });

  final TextEditingController serverController;
  final TextEditingController websocketBearerTokenController;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        TextField(
          controller: serverController,
          decoration: const InputDecoration(
            labelText: 'Websocket URL',
            hintText: 'ws://192.168.1.20:8080',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: websocketBearerTokenController,
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
      ],
    );
  }
}

class _RelayConnectionSection extends StatelessWidget {
  const _RelayConnectionSection({
    required this.relayUrlController,
    required this.pairingCodeController,
    required this.isPairing,
    required this.pairingError,
    required this.pairingSuccess,
    required this.relayDeviceId,
    required this.relayBridgeLabel,
    required this.textTheme,
    required this.colorScheme,
    required this.onScanQrCode,
    required this.onPairDevice,
    required this.onClearPairing,
  });

  final TextEditingController relayUrlController;
  final TextEditingController pairingCodeController;
  final bool isPairing;
  final String? pairingError;
  final String? pairingSuccess;
  final String relayDeviceId;
  final String relayBridgeLabel;
  final TextTheme textTheme;
  final ColorScheme colorScheme;
  final VoidCallback onScanQrCode;
  final VoidCallback onPairDevice;
  final VoidCallback onClearPairing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          controller: relayUrlController,
          decoration: const InputDecoration(
            labelText: 'Relay URL',
            hintText: 'https://relay.example.com',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: pairingCodeController,
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
            onPressed: isPairing ? null : onScanQrCode,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan QR code'),
          ),
        ),
        if (relayDeviceId.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Paired bridge: ${relayBridgeLabel.isEmpty ? relayDeviceId : relayBridgeLabel}',
              style: textTheme.bodySmall,
            ),
          ),
        if (pairingError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              pairingError!,
              style: textTheme.bodySmall?.copyWith(color: colorScheme.error),
            ),
          ),
        if (pairingSuccess != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              pairingSuccess!,
              style: textTheme.bodySmall?.copyWith(color: colorScheme.primary),
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                onPressed: isPairing ? null : onPairDevice,
                child: Text(isPairing ? 'Pairing...' : 'Pair device'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: relayDeviceId.isEmpty ? null : onClearPairing,
                child: const Text('Clear pairing'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PreferencesSection extends StatelessWidget {
  const _PreferencesSection({
    required this.themePreference,
    required this.sandboxMode,
    required this.approvalPolicy,
    required this.allowNetwork,
    required this.threadLoadTimeoutController,
    required this.resumeThreadId,
    required this.onThemeChanged,
    required this.onSandboxChanged,
    required this.onApprovalPolicyChanged,
    required this.onAllowNetworkChanged,
  });

  final ThemePreference themePreference;
  final SandboxMode sandboxMode;
  final String approvalPolicy;
  final bool allowNetwork;
  final TextEditingController threadLoadTimeoutController;
  final String resumeThreadId;
  final ValueChanged<ThemePreference> onThemeChanged;
  final ValueChanged<SandboxMode> onSandboxChanged;
  final ValueChanged<String> onApprovalPolicyChanged;
  final ValueChanged<bool> onAllowNetworkChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        DropdownButtonFormField<ThemePreference>(
          initialValue: themePreference,
          decoration: const InputDecoration(labelText: 'Theme'),
          items: ThemePreference.values.map((item) {
            return DropdownMenuItem<ThemePreference>(
              value: item,
              child: Text(item.name),
            );
          }).toList(),
          onChanged: (ThemePreference? value) {
            if (value != null) {
              onThemeChanged(value);
            }
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<SandboxMode>(
          initialValue: sandboxMode,
          decoration: const InputDecoration(labelText: 'Sandbox'),
          items: SandboxMode.values.map((item) {
            return DropdownMenuItem<SandboxMode>(
              value: item,
              child: Text(item.name),
            );
          }).toList(),
          onChanged: (SandboxMode? value) {
            if (value != null) {
              onSandboxChanged(value);
            }
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: approvalPolicy,
          decoration: const InputDecoration(labelText: 'Approval policy'),
          items:
              const <String>[
                'untrusted',
                'on-request',
                'on-failure',
                'never',
              ].map((item) {
                return DropdownMenuItem<String>(value: item, child: Text(item));
              }).toList(),
          onChanged: (String? value) {
            if (value != null) {
              onApprovalPolicyChanged(value);
            }
          },
        ),
        const SizedBox(height: 12),
        SwitchListTile.adaptive(
          value: allowNetwork,
          contentPadding: EdgeInsets.zero,
          title: const Text('Allow network in workspace-write mode'),
          onChanged: onAllowNetworkChanged,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: threadLoadTimeoutController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Thread load timeout ms',
            helperText:
                'Used for thread list, thread read, and thread resume requests.',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Last thread: ${resumeThreadId.isEmpty ? 'none' : resumeThreadId}',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _SettingsFooter extends StatelessWidget {
  const _SettingsFooter({required this.onClose, required this.onSave});

  final VoidCallback onClose;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: OutlinedButton(onPressed: onClose, child: const Text('Close')),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(onPressed: onSave, child: const Text('Save')),
        ),
      ],
    );
  }
}
