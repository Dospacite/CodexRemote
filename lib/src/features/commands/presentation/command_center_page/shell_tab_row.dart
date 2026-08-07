part of command_center_page;

class _ShellTabRow extends StatelessWidget {
  const _ShellTabRow({
    required this.sessions,
    required this.activeSessionId,
    required this.labelForSession,
    required this.onSessionSelected,
    required this.onCloseSession,
    required this.onCreateShell,
  });

  final List<ShellSession> sessions;
  final String? activeSessionId;
  final String Function(ShellSession session) labelForSession;
  final ValueChanged<String> onSessionSelected;
  final ValueChanged<String> onCloseSession;
  final VoidCallback onCreateShell;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey<String>('command-shell-tab-row'),
      height: 40,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.dividerColor),
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: sessions
                    .map((ShellSession session) {
                      final isActive = session.id == activeSessionId;
                      final scheme = theme.colorScheme;
                      final background = isActive
                          ? scheme.primary.withValues(alpha: 0.14)
                          : scheme.surfaceContainerHighest.withValues(
                              alpha: 0.55,
                            );
                      final foreground = isActive
                          ? scheme.primary
                          : scheme.onSurface;
                      final statusColor = session.isRunning
                          ? Colors.green
                          : scheme.outline;
                      return SizedBox(
                        width: 120,
                        height: double.infinity,
                        child: InkWell(
                          key: ValueKey<String>(
                            'command-shell-tab-${session.id}',
                          ),
                          onTap: () => onSessionSelected(session.id),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: background,
                              border: Border(
                                right: BorderSide(color: theme.dividerColor),
                                left: BorderSide(
                                  color: sessions.first.id == session.id
                                      ? Colors.transparent
                                      : theme.dividerColor.withValues(alpha: 0),
                                ),
                                bottom: BorderSide(
                                  color: isActive
                                      ? scheme.primary
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                            child: Row(
                              children: <Widget>[
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: statusColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    labelForSession(session),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: foreground,
                                      fontWeight: isActive
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Close shell tab',
                                  visualDensity: const VisualDensity(
                                    horizontal: -4,
                                    vertical: -4,
                                  ),
                                  splashRadius: 18,
                                  onPressed: () => onCloseSession(session.id),
                                  icon: Icon(
                                    Icons.close_rounded,
                                    size: 16,
                                    color: foreground.withValues(alpha: 0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
            ),
          ),
          IconButton(
            tooltip: 'New shell tab',
            onPressed: onCreateShell,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }
}
