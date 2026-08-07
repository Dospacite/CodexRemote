part of workspace_home_page;

class _GitDiffView extends StatelessWidget {
  const _GitDiffView({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = text.split('\n');
    final rows = lines.map((line) => _GitDiffLine.fromRaw(line)).toList();
    final style = theme.textTheme.bodyMedium?.copyWith(
      fontFamily: 'monospace',
      height: 1.25,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        key: const ValueKey<String>('git-diff-view'),
        width: double.infinity,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.35,
          ),
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: rows.map((row) {
                return ColoredBox(
                  color: row.backgroundColor(theme.colorScheme),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: Text(
                      row.displayText,
                      style: style?.copyWith(
                        color: row.foregroundColor(theme.colorScheme),
                        fontWeight: row.isEmphasized
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class _GitDiffLine {
  const _GitDiffLine({required this.displayText, required this.kind});

  factory _GitDiffLine.fromRaw(String raw) {
    if (raw.startsWith('diff --git') ||
        raw.startsWith('index ') ||
        raw.startsWith('--- ') ||
        raw.startsWith('+++ ')) {
      return _GitDiffLine(displayText: raw, kind: _GitDiffLineKind.header);
    }
    if (raw.startsWith('@@')) {
      return _GitDiffLine(displayText: raw, kind: _GitDiffLineKind.hunk);
    }
    if (raw.startsWith('+')) {
      return _GitDiffLine(displayText: raw, kind: _GitDiffLineKind.addition);
    }
    if (raw.startsWith('-')) {
      return _GitDiffLine(displayText: raw, kind: _GitDiffLineKind.removal);
    }
    if (raw.contains(' • ')) {
      return _GitDiffLine(displayText: raw, kind: _GitDiffLineKind.meta);
    }
    return _GitDiffLine(displayText: raw, kind: _GitDiffLineKind.context);
  }

  final String displayText;
  final _GitDiffLineKind kind;

  bool get isEmphasized {
    return switch (kind) {
      _GitDiffLineKind.header ||
      _GitDiffLineKind.hunk ||
      _GitDiffLineKind.meta => true,
      _GitDiffLineKind.addition ||
      _GitDiffLineKind.removal ||
      _GitDiffLineKind.context => false,
    };
  }

  Color backgroundColor(ColorScheme scheme) {
    return switch (kind) {
      _GitDiffLineKind.addition => Colors.green.withValues(alpha: 0.14),
      _GitDiffLineKind.removal => Colors.red.withValues(alpha: 0.14),
      _GitDiffLineKind.hunk => scheme.tertiary.withValues(alpha: 0.12),
      _GitDiffLineKind.meta => scheme.primary.withValues(alpha: 0.08),
      _GitDiffLineKind.header => scheme.surfaceContainerHighest.withValues(
        alpha: 0.6,
      ),
      _GitDiffLineKind.context => Colors.transparent,
    };
  }

  Color foregroundColor(ColorScheme scheme) {
    return switch (kind) {
      _GitDiffLineKind.addition => Colors.green.shade800,
      _GitDiffLineKind.removal => Colors.red.shade800,
      _GitDiffLineKind.hunk => scheme.tertiary,
      _GitDiffLineKind.meta => scheme.primary,
      _GitDiffLineKind.header => scheme.onSurfaceVariant,
      _GitDiffLineKind.context => scheme.onSurface,
    };
  }
}

enum _GitDiffLineKind { meta, header, hunk, addition, removal, context }
