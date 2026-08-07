part of workspace_home_page;

class _QueuedPromptBar extends StatelessWidget {
  const _QueuedPromptBar({
    required this.controller,
    required this.onEditPrompt,
    required this.onPromotePrompt,
  });

  final AppController controller;
  final ValueChanged<String> onEditPrompt;
  final ValueChanged<String> onPromotePrompt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: controller.pendingPrompts.map((item) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              children: <Widget>[
                Icon(
                  item.mode == PendingPromptMode.steer
                      ? Icons.settings_outlined
                      : Icons.schedule_send_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _pendingPromptLabel(item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (item.mode != PendingPromptMode.steer)
                  IconButton(
                    key: ValueKey<String>('pending-prompt-promote-${item.id}'),
                    tooltip: 'Steer',
                    onPressed: () => onPromotePrompt(item.id),
                    visualDensity: const VisualDensity(
                      horizontal: -4,
                      vertical: -4,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 28,
                      height: 28,
                    ),
                    splashRadius: 16,
                    icon: const Icon(Icons.settings_outlined, size: 16),
                  ),
                IconButton(
                  tooltip: 'Edit',
                  onPressed: () => onEditPrompt(item.id),
                  visualDensity: const VisualDensity(
                    horizontal: -4,
                    vertical: -4,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  splashRadius: 16,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                ),
                IconButton(
                  tooltip: 'Cancel',
                  onPressed: () => controller.cancelPendingPrompt(item.id),
                  visualDensity: const VisualDensity(
                    horizontal: -4,
                    vertical: -4,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  splashRadius: 16,
                  icon: const Icon(Icons.close, size: 16),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  String _pendingPromptLabel(PendingPrompt item) {
    final trimmed = item.text.trim();
    final attachmentCount = item.attachments.length;
    if (trimmed.isNotEmpty && attachmentCount == 0) {
      return trimmed;
    }
    if (trimmed.isEmpty && attachmentCount > 0) {
      return attachmentCount == 1
          ? '1 attachment'
          : '$attachmentCount attachments';
    }
    if (attachmentCount > 0) {
      return '$trimmed • ${attachmentCount == 1 ? '1 attachment' : '$attachmentCount attachments'}';
    }
    return 'Pending message';
  }
}
