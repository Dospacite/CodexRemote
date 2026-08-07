part of workspace_home_page;

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.onEditMessage,
    required this.onOpenFileReference,
  });

  final ActivityEntry entry;
  final ValueChanged<ActivityEntry> onEditMessage;
  final Future<void> Function(String path, {int? line}) onOpenFileReference;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isUserMessage = entry.kind == EntryKind.user;
    final isAgentMessage = entry.kind == EntryKind.agent;
    final isSystemMessage = entry.kind == EntryKind.system;
    final isPendingUserMessage = isUserMessage && entry.isLocalPending;
    final normalizedMessageText =
        (entry.body.isEmpty ? entry.title : entry.body).trim();
    final isContextCompacting =
        isSystemMessage &&
        normalizedMessageText.toLowerCase().contains('context compact');
    final isCard =
        entry.kind == EntryKind.command ||
        entry.kind == EntryKind.fileChange ||
        entry.kind == EntryKind.tool;
    final systemBorderColor = Color.alphaBlend(
      const Color(0xFFFFA24C).withValues(alpha: 0.7),
      scheme.outlineVariant,
    );
    final systemTextColor = Color.alphaBlend(
      const Color(0xFFFFC48A).withValues(alpha: 0.9),
      scheme.onSurfaceVariant,
    );
    final tone = switch (entry.kind) {
      EntryKind.user => scheme.primary.withValues(alpha: 0.16),
      EntryKind.agent => theme.colorScheme.surface,
      EntryKind.reasoning => Colors.transparent,
      EntryKind.command => scheme.surface,
      EntryKind.fileChange => scheme.surface,
      EntryKind.tool => scheme.surface,
      EntryKind.system => const Color(0xFFFFA24C).withValues(alpha: 0.04),
    };
    final pendingUserBorderColor = scheme.outlineVariant.withValues(alpha: 0.8);
    final pendingUserTextColor = scheme.onSurfaceVariant.withValues(
      alpha: 0.58,
    );

    final monospace =
        entry.kind == EntryKind.command ||
        entry.kind == EntryKind.fileChange ||
        entry.title.contains('MCP') ||
        entry.body.contains('{') ||
        entry.body.contains('diff');
    final messageText = normalizedMessageText;
    final canEditMessage =
        entry.kind == EntryKind.user && messageText.trim().isNotEmpty;
    final cardTitle = entry.kind == EntryKind.fileChange
        ? _summarizeFileChangeTitle(entry.body, fallback: entry.title)
        : entry.title;

    if (isContextCompacting) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Divider(
                color: theme.dividerColor,
                thickness: 1,
                height: 1,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Context Compacting',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: systemTextColor,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            Expanded(
              child: Divider(
                color: theme.dividerColor,
                thickness: 1,
                height: 1,
              ),
            ),
          ],
        ),
      );
    }

    Widget? bodyContent;
    if (isCard && entry.body.isNotEmpty) {
      if (entry.kind == EntryKind.fileChange) {
        bodyContent = _ExpandableEntryBody(
          text: entry.body,
          previewText: _collapsedPreviewText(entry.body),
          child: _GitDiffView(text: entry.body),
        );
      } else if (monospace) {
        bodyContent = _MonospaceOutputView(
          text: entry.body,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontFamily: 'monospace',
            height: 1.2,
          ),
        );
      } else {
        bodyContent = SelectableText(
          entry.body,
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
        );
      }

      if (entry.kind == EntryKind.tool || entry.kind == EntryKind.command) {
        bodyContent = _ExpandableEntryBody(
          text: entry.body,
          previewText: _collapsedPreviewText(entry.body),
          child: bodyContent,
        );
      }
    }

    final bubbleContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (isCard)
          Row(
            children: <Widget>[
              Expanded(
                child: Text(cardTitle, style: theme.textTheme.titleMedium),
              ),
              if (entry.status.isNotEmpty)
                Text(entry.status, style: theme.textTheme.bodySmall),
            ],
          )
        else
          isAgentMessage
              ? _AgentMarkdownMessage(
                  text: messageText,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    height: 1.5,
                    color: theme.colorScheme.onSurface,
                  ),
                  onOpenFileReference: onOpenFileReference,
                )
              : _MessageContentText(
                  text: messageText,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    height: 1.5,
                    color: isSystemMessage
                        ? systemTextColor
                        : isPendingUserMessage
                        ? pendingUserTextColor
                        : theme.colorScheme.onSurface,
                    fontWeight: isSystemMessage ? FontWeight.w300 : null,
                  ),
                  canEdit: canEditMessage,
                  onEdit: () => onEditMessage(entry),
                  onOpenFileReference: onOpenFileReference,
                ),
        if (entry.secondary.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(entry.secondary, style: theme.textTheme.bodySmall),
        ],
        if (bodyContent != null) ...<Widget>[
          const SizedBox(height: 10),
          bodyContent,
        ],
        if (entry.isStreaming) ...<Widget>[
          const SizedBox(height: 10),
          const LinearProgressIndicator(minHeight: 2),
        ],
      ],
    );

    return Container(
      width: double.infinity,
      alignment: isUserMessage ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: isUserMessage || isAgentMessage
              ? MediaQuery.sizeOf(context).width * 0.84
              : double.infinity,
        ),
        padding: EdgeInsets.all(
          isCard || isUserMessage || isAgentMessage || isSystemMessage ? 14 : 0,
        ),
        decoration: BoxDecoration(
          color: isPendingUserMessage ? Colors.transparent : tone,
          border: isPendingUserMessage
              ? Border.all(color: pendingUserBorderColor, width: 0.9)
              : isSystemMessage
              ? Border.all(color: systemBorderColor, width: 1)
              : isCard || isAgentMessage
              ? Border.all(color: theme.dividerColor)
              : null,
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: isPendingUserMessage ? Clip.antiAlias : Clip.none,
        child: isPendingUserMessage
            ? Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: _PendingMessageSheen(
                      color: scheme.primary.withValues(alpha: 0.12),
                    ),
                  ),
                  bubbleContent,
                ],
              )
            : bubbleContent,
      ),
    );
  }
}

String _collapsedPreviewText(String text) {
  final lines = text
      .split('\n')
      .map((line) => line.trimRight())
      .where((line) => line.isNotEmpty)
      .take(2)
      .toList();
  if (lines.isEmpty) {
    return text.trim();
  }
  return lines.join('\n');
}

String _summarizeFileChangeTitle(String text, {required String fallback}) {
  final lines = text.split('\n');
  String fileName = fallback;
  var added = 0;
  var removed = 0;

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }
    if (fileName == fallback) {
      if (line.contains(' • ')) {
        fileName = line.split(' • ').first.trim();
      } else if (line.startsWith('+++ ')) {
        fileName = line.substring(4).replaceFirst(RegExp(r'^[ab]/'), '').trim();
      } else if (line.startsWith('diff --git ')) {
        final parts = line.split(' ');
        if (parts.length >= 4) {
          fileName = parts[2].replaceFirst(RegExp(r'^[ab]/'), '').trim();
        }
      }
    }
    if (rawLine.startsWith('+') && !rawLine.startsWith('+++ ')) {
      added += 1;
    } else if (rawLine.startsWith('-') && !rawLine.startsWith('--- ')) {
      removed += 1;
    }
  }

  final segments = <String>[fileName];
  if (added > 0) {
    segments.add('+$added');
  }
  if (removed > 0) {
    segments.add('-$removed');
  }
  return segments.join('  ');
}
