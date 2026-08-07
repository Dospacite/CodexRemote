part of automation_pages;

class _AutomationCard extends StatelessWidget {
  const _AutomationCard({
    required this.automation,
    required this.isRunning,
    required this.onToggleEnabled,
    required this.onEdit,
    required this.onCopyToCurrentThread,
    required this.onDelete,
  });

  final AutomationDefinition automation;
  final bool isRunning;
  final ValueChanged<bool> onToggleEnabled;
  final VoidCallback onEdit;
  final VoidCallback? onCopyToCurrentThread;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trigger = automation.triggerNode;
    final actions = automation.actionNodes;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    automation.name.trim().isEmpty
                        ? 'Untitled automation'
                        : automation.name,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Switch(value: automation.enabled, onChanged: onToggleEnabled),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              trigger == null
                  ? 'No trigger configured'
                  : trigger.path.trim().isEmpty
                  ? trigger.kind.title
                  : '${trigger.kind.title} • ${trigger.path}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Text(
              actions.isEmpty
                  ? 'No actions configured'
                  : actions.map((node) => node.kind.title).join(' → '),
              style: theme.textTheme.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isRunning
                        ? theme.colorScheme.primary.withValues(alpha: 0.12)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    isRunning
                        ? 'Running'
                        : automation.enabled
                        ? 'Enabled'
                        : 'Disabled',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isRunning
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const Spacer(),
                _AutomationActionButton(label: 'Edit', onTap: onEdit),
                if (onCopyToCurrentThread != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _AutomationActionButton(
                      label: 'Copy',
                      onTap: onCopyToCurrentThread!,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _AutomationActionButton(
                    label: 'Delete',
                    onTap: onDelete,
                    destructive: true,
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

class _AutomationActionButton extends StatelessWidget {
  const _AutomationActionButton({
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final bool destructive;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = destructive ? scheme.error : scheme.primary;
    final background = destructive
        ? scheme.error.withValues(alpha: 0.10)
        : scheme.primary.withValues(alpha: 0.10);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 16, color: foreground),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AutomationIconAction extends StatelessWidget {
  const _AutomationIconAction({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Icon(icon, size: 20, color: theme.colorScheme.primary),
        ),
      ),
    );
  }
}
