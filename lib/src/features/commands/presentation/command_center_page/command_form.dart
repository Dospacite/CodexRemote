part of command_center_page;

class _CommandForm extends StatelessWidget {
  const _CommandForm({
    required this.cwdController,
    required this.timeoutController,
    required this.outputCapController,
    required this.sandboxMode,
    required this.allowNetwork,
    required this.disableTimeout,
    required this.disableOutputCap,
    required this.onWorkingDirectoryChanged,
    required this.onSandboxChanged,
    required this.onAllowNetworkChanged,
    required this.onDisableTimeoutChanged,
    required this.onDisableOutputCapChanged,
    required this.onTimeoutChanged,
    required this.onOutputCapChanged,
  });

  final TextEditingController cwdController;
  final TextEditingController timeoutController;
  final TextEditingController outputCapController;
  final SandboxMode sandboxMode;
  final bool allowNetwork;
  final bool disableTimeout;
  final bool disableOutputCap;
  final ValueChanged<String> onWorkingDirectoryChanged;
  final ValueChanged<SandboxMode> onSandboxChanged;
  final ValueChanged<bool> onAllowNetworkChanged;
  final ValueChanged<bool> onDisableTimeoutChanged;
  final ValueChanged<bool> onDisableOutputCapChanged;
  final ValueChanged<String> onTimeoutChanged;
  final ValueChanged<String> onOutputCapChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          controller: cwdController,
          onChanged: onWorkingDirectoryChanged,
          decoration: const InputDecoration(labelText: 'Working directory'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<SandboxMode>(
          initialValue: sandboxMode,
          decoration: const InputDecoration(labelText: 'Sandbox'),
          items: SandboxMode.values
              .map(
                (SandboxMode item) => DropdownMenuItem<SandboxMode>(
                  value: item,
                  child: Text(item.name),
                ),
              )
              .toList(),
          onChanged: (SandboxMode? value) {
            if (value != null) {
              onSandboxChanged(value);
            }
          },
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Network'),
          value: allowNetwork,
          onChanged: onAllowNetworkChanged,
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Disable timeout'),
          value: disableTimeout,
          onChanged: onDisableTimeoutChanged,
        ),
        if (!disableTimeout) ...<Widget>[
          TextField(
            controller: timeoutController,
            onChanged: onTimeoutChanged,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Timeout ms'),
          ),
          const SizedBox(height: 8),
        ],
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Disable output cap'),
          value: disableOutputCap,
          onChanged: onDisableOutputCapChanged,
        ),
        if (!disableOutputCap)
          TextField(
            controller: outputCapController,
            onChanged: onOutputCapChanged,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Output cap bytes'),
          ),
      ],
    );
  }
}
