part of workspace_home_page;

class _MessageContentText extends StatelessWidget {
  const _MessageContentText({
    required this.text,
    required this.style,
    required this.canEdit,
    required this.onEdit,
    required this.onOpenFileReference,
  });

  final String text;
  final TextStyle? style;
  final bool canEdit;
  final VoidCallback onEdit;
  final Future<void> Function(String path, {int? line}) onOpenFileReference;

  @override
  Widget build(BuildContext context) {
    return SelectableText.rich(
      _buildSpans(context),
      contextMenuBuilder:
          (BuildContext context, EditableTextState editableTextState) {
            final items = <ContextMenuButtonItem>[
              ...editableTextState.contextMenuButtonItems,
              if (canEdit)
                ContextMenuButtonItem(
                  label: 'Edit',
                  onPressed: () {
                    ContextMenuController.removeAny();
                    onEdit();
                  },
                ),
            ];
            return AdaptiveTextSelectionToolbar.buttonItems(
              anchors: editableTextState.contextMenuAnchors,
              buttonItems: items,
            );
          },
      style: style,
    );
  }

  TextSpan _buildSpans(BuildContext context) {
    final matches = <_MessageReferenceMatch>[
      ..._matchMarkdownReferences(text),
      ..._matchPlainReferences(text),
    ]..sort((left, right) => left.start.compareTo(right.start));

    final filteredMatches = <_MessageReferenceMatch>[];
    var lastEnd = 0;
    for (final match in matches) {
      if (match.start < lastEnd) {
        continue;
      }
      filteredMatches.add(match);
      lastEnd = match.end;
    }

    if (filteredMatches.isEmpty) {
      return TextSpan(text: text, style: style);
    }

    final linkStyle = style?.copyWith(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
    );
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in filteredMatches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              unawaited(onOpenFileReference(match.path, line: match.line));
            },
            child: Text(match.displayText, style: linkStyle),
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return TextSpan(style: style, children: spans);
  }
}
