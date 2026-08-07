import 'package:flutter/material.dart';

import '../../../app_controller.dart';
import '../../../models.dart';

class ThreadHistorySheet extends StatelessWidget {
  const ThreadHistorySheet({
    super.key,
    required this.controller,
    required this.onCreateThread,
  });

  final AppController controller;
  final Future<void> Function() onCreateThread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        return Container(
          margin: const EdgeInsets.only(right: 24),
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(22),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom:
                    MediaQuery.paddingOf(context).bottom +
                    MediaQuery.viewInsetsOf(context).bottom +
                    20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Threads',
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'New thread',
                        onPressed: onCreateThread,
                        icon: const Icon(Icons.add),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Refresh',
                        onPressed: controller.isLoadingHistory
                            ? null
                            : () => controller.loadThreadHistory(reset: true),
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  if (controller.threadHistoryError != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      controller.threadHistoryError!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.7,
                    child:
                        controller.threadHistory.isEmpty &&
                            controller.isLoadingHistory
                        ? const Center(child: CircularProgressIndicator())
                        : controller.threadHistory.isEmpty
                        ? Center(
                            child: Text(
                              'No saved threads were returned by the server.',
                              style: theme.textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.separated(
                            itemCount:
                                controller.threadHistory.length +
                                (controller.hasMoreThreadHistory ? 1 : 0),
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (BuildContext context, int index) {
                              if (index >= controller.threadHistory.length) {
                                return OutlinedButton(
                                  onPressed: controller.isLoadingHistory
                                      ? null
                                      : controller.loadThreadHistory,
                                  child: Text(
                                    controller.isLoadingHistory
                                        ? 'Loading'
                                        : 'Load more',
                                  ),
                                );
                              }

                              final thread = controller.threadHistory[index];
                              return _ThreadTile(
                                controller: controller,
                                thread: thread,
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({required this.controller, required this.thread});

  final AppController controller;
  final ThreadSummary thread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOpening = controller.openingThreadId == thread.id;
    final isFavorite = controller.isThreadFavorite(thread.id);
    final hasActiveTurn = controller.threadHasActiveTurn(thread.id);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Row(
                  children: <Widget>[
                    if (hasActiveTurn)
                      Container(
                        key: ValueKey<String>(
                          'thread-active-turn-${thread.id}',
                        ),
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        thread.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: isFavorite ? 'Unfavorite thread' : 'Favorite thread',
                onPressed: () => controller.toggleFavoriteThread(thread.id),
                icon: Icon(
                  isFavorite ? Icons.star : Icons.star_border,
                  color: isFavorite ? theme.colorScheme.primary : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            thread.preview.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              if (thread.updatedAt != null)
                _ThreadMeta(
                  label: 'Updated',
                  value: _formatDate(thread.updatedAt!),
                ),
              if (thread.cwd.isNotEmpty)
                _ThreadMeta(label: 'Cwd', value: thread.cwd),
              if (thread.agentNickname != null &&
                  thread.agentNickname!.isNotEmpty)
                _ThreadMeta(label: 'Agent', value: thread.agentNickname!),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isOpening
                  ? null
                  : () async {
                      await controller.resumeThreadFromHistory(thread.id);
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
              child: Text(isOpening ? 'Opening' : 'Open thread'),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime value) {
    final local = value;
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  String two(int n) {
    return n.toString().padLeft(2, '0');
  }
}

class _ThreadMeta extends StatelessWidget {
  const _ThreadMeta({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label: $value',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}
