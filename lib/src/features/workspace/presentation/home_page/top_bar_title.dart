part of workspace_home_page;

class _TopBarTitle extends StatelessWidget {
  const _TopBarTitle({
    required this.controller,
    required this.onRenameActiveThread,
  });

  final AppController controller;
  final VoidCallback onRenameActiveThread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: controller.activeThreadId != null ? onRenameActiveThread : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              _titleText(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 2),
            Text(
              _subtitleText(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  String _titleText() {
    final activeName = controller.activeThreadName?.trim() ?? '';
    if (activeName.isNotEmpty) {
      return activeName;
    }
    return 'Codex Remote';
  }

  String _subtitleText() {
    if (controller.activeThreadCwd.trim().isNotEmpty) {
      return controller.activeThreadCwd.trim();
    }
    if (controller.settings.connectionMode == ConnectionMode.relay) {
      final bridgeLabel = controller.settings.relayBridgeLabel.trim();
      if (bridgeLabel.isNotEmpty) {
        return bridgeLabel;
      }
      if (controller.settings.relayUrl.trim().isNotEmpty) {
        return controller.settings.relayUrl.trim();
      }
    }
    return controller.settings.serverUrl;
  }
}
