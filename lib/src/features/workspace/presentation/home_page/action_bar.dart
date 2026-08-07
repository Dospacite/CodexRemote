part of workspace_home_page;

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.controller,
    required this.pulse,
    required this.pop,
    required this.onOpenThreads,
    required this.onOpenFiles,
    required this.onOpenCommands,
    required this.onOpenAutomations,
    required this.onToggleConnection,
    required this.onOpenDownloads,
  });

  final AppController controller;
  final Animation<double> pulse;
  final Animation<double> pop;
  final VoidCallback onOpenThreads;
  final VoidCallback onOpenFiles;
  final VoidCallback onOpenCommands;
  final VoidCallback onOpenAutomations;
  final VoidCallback onToggleConnection;
  final VoidCallback onOpenDownloads;

  Widget _animatedActionIcon({required Widget icon, required bool animate}) {
    if (!animate) {
      return icon;
    }
    return AnimatedBuilder(
      animation: pulse,
      builder: (BuildContext context, Widget? child) {
        final scale = 1 + (pulse.value * 0.05);
        return Transform.scale(scale: scale, child: child);
      },
      child: icon,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeCount = controller.activeDownloadCount;
    final totalDownloads = controller.downloadRecords.length;
    final hasRunningAutomation = controller.automations.any(
      (item) => controller.isAutomationRunning(item.id),
    );
    final buttonStyle = IconButton.styleFrom(
      visualDensity: const VisualDensity(horizontal: -0.5, vertical: -0.5),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      minimumSize: const Size(56, 50),
      tapTargetSize: MaterialTapTargetSize.padded,
      alignment: Alignment.centerLeft,
    );
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.dividerColor),
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            IconButton(
              tooltip: 'Threads',
              style: buttonStyle,
              onPressed: controller.isLoadingHistory ? null : onOpenThreads,
              iconSize: 26,
              icon: controller.isLoadingHistory
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const Icon(Icons.menu, size: 26),
            ),
            IconButton(
              tooltip: controller.isConnected ? 'Disconnect' : 'Connect',
              style: buttonStyle,
              onPressed: onToggleConnection,
              iconSize: 26,
              icon: Icon(
                controller.isConnected ? Icons.link_off : Icons.link,
                size: 26,
              ),
            ),
            IconButton(
              tooltip: 'Command',
              style: buttonStyle,
              onPressed: onOpenCommands,
              iconSize: 26,
              icon: const Icon(Icons.terminal, size: 26),
            ),
            IconButton(
              tooltip: 'Files',
              style: buttonStyle,
              onPressed: onOpenFiles,
              iconSize: 26,
              icon: const Icon(Icons.folder_outlined, size: 26),
            ),
            Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                IconButton(
                  tooltip: 'Automations',
                  style: buttonStyle,
                  onPressed: onOpenAutomations,
                  iconSize: 26,
                  icon: _animatedActionIcon(
                    animate: hasRunningAutomation,
                    icon: const Icon(Icons.account_tree_outlined, size: 26),
                  ),
                ),
                if (hasRunningAutomation)
                  Positioned(
                    top: 6,
                    right: 8,
                    child: SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        key: const ValueKey<String>(
                          'automation-running-indicator',
                        ),
                        strokeWidth: 1.8,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                IconButton(
                  tooltip: 'Downloads',
                  style: buttonStyle,
                  onPressed: onOpenDownloads,
                  iconSize: 26,
                  icon: _animatedActionIcon(
                    animate: activeCount > 0,
                    icon: Icon(
                      activeCount > 0
                          ? Icons.downloading_rounded
                          : Icons.download_outlined,
                      size: 26,
                    ),
                  ),
                ),
                if (totalDownloads > 0)
                  Positioned(
                    top: 3,
                    right: 3,
                    child: SizedBox(
                      width: 22,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: activeCount > 0
                                ? theme.colorScheme.primary
                                : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            activeCount > 0
                                ? '$activeCount'
                                : '$totalDownloads',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: activeCount > 0
                                  ? theme.colorScheme.onPrimary
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FooterActionButton extends StatelessWidget {
  const _FooterActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: theme.colorScheme.onSurface),
          const SizedBox(width: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterIconButton extends StatelessWidget {
  const _FooterIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 40),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ),
        child: Icon(icon, size: 18, color: theme.colorScheme.onSurface),
      ),
    );
  }
}
