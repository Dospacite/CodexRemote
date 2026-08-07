part of workspace_home_page;

class _ExpandableEntryBody extends StatefulWidget {
  const _ExpandableEntryBody({
    required this.text,
    required this.child,
    this.previewText,
  });

  final String text;
  final Widget child;
  final String? previewText;

  @override
  State<_ExpandableEntryBody> createState() => _ExpandableEntryBodyState();
}

class _ExpandableEntryBodyState extends State<_ExpandableEntryBody> {
  bool _isExpanded = false;

  bool get _shouldCollapse {
    final lines = '\n'.allMatches(widget.text).length + 1;
    return lines > 12 || widget.text.length > 900;
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldCollapse) {
      return widget.child;
    }

    final theme = Theme.of(context);
    final previewText = (widget.previewText ?? widget.text).trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AnimatedCrossFade(
          firstChild: Stack(
            children: <Widget>[
              SizedBox(
                width: double.infinity,
                child: Text(
                  previewText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    height: 1.25,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              if (previewText.contains('\n') || previewText.length > 120)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Container(
                      height: 18,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            theme.colorScheme.surface.withValues(alpha: 0),
                            theme.colorScheme.surface,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          secondChild: widget.child,
          crossFadeState: _isExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 140),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          key: ValueKey<String>(
            _isExpanded ? 'entry-body-collapse' : 'entry-body-expand',
          ),
          onPressed: () {
            setState(() {
              _isExpanded = !_isExpanded;
            });
          },
          icon: Icon(_isExpanded ? Icons.unfold_less : Icons.unfold_more),
          label: Text(_isExpanded ? 'Collapse' : 'Expand'),
        ),
      ],
    );
  }
}
