part of workspace_home_page;

class _AgentMarkdownMessage extends StatelessWidget {
  const _AgentMarkdownMessage({
    required this.text,
    required this.style,
    required this.onOpenFileReference,
  });

  final String text;
  final TextStyle? style;
  final Future<void> Function(String path, {int? line}) onOpenFileReference;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedStyle = style ?? theme.textTheme.bodyLarge;
    return SelectionArea(
      child: MarkdownBody(
        data: _linkifyPlainFileReferences(text),
        softLineBreak: true,
        onTapLink: (String linkText, String? href, String title) {
          if (href == null || href.isEmpty) {
            return;
          }
          final resolved = _parseReferenceTarget(href);
          if (resolved == null) {
            return;
          }
          unawaited(onOpenFileReference(resolved.path, line: resolved.line));
        },
        styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
          p: resolvedStyle,
          h1: theme.textTheme.headlineSmall?.copyWith(
            color: resolvedStyle?.color,
            fontWeight: FontWeight.w700,
          ),
          h2: theme.textTheme.titleLarge?.copyWith(
            color: resolvedStyle?.color,
            fontWeight: FontWeight.w700,
          ),
          h3: theme.textTheme.titleMedium?.copyWith(
            color: resolvedStyle?.color,
            fontWeight: FontWeight.w700,
          ),
          code: theme.textTheme.bodyMedium?.copyWith(
            fontFamily: 'monospace',
            color: theme.colorScheme.onSurface,
          ),
          codeblockDecoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.dividerColor),
          ),
          a: resolvedStyle?.copyWith(
            color: theme.colorScheme.primary,
            decoration: TextDecoration.underline,
          ),
          blockquotePadding: const EdgeInsets.only(left: 12),
          blockquoteDecoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: theme.colorScheme.primary, width: 2),
            ),
          ),
        ),
        builders: <String, MarkdownElementBuilder>{
          'a': _MarkdownFileLinkBuilder(
            onOpenFileReference: onOpenFileReference,
            style: resolvedStyle?.copyWith(
              color: theme.colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
          ),
        },
      ),
    );
  }
}

class _MarkdownFileLinkBuilder extends MarkdownElementBuilder {
  _MarkdownFileLinkBuilder({
    required this.onOpenFileReference,
    required this.style,
  });

  final Future<void> Function(String path, {int? line}) onOpenFileReference;
  final TextStyle? style;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final href = element.attributes['href'];
    final resolved = href == null ? null : _parseReferenceTarget(href);
    final linkStyle = style ?? preferredStyle ?? parentStyle;
    return Text.rich(
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: resolved == null
              ? null
              : () {
                  unawaited(
                    onOpenFileReference(resolved.path, line: resolved.line),
                  );
                },
          child: Text(element.textContent, style: linkStyle),
        ),
      ),
    );
  }
}
