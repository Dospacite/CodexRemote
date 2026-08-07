part of workspace_home_page;

class _PendingMessageSheen extends StatefulWidget {
  const _PendingMessageSheen({required this.color});

  final Color color;

  @override
  State<_PendingMessageSheen> createState() => _PendingMessageSheenState();
}

class _PendingMessageSheenState extends State<_PendingMessageSheen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      key: const ValueKey<String>('pending-message-sheen'),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          final slide = Tween<double>(
            begin: -1.2,
            end: 1.2,
          ).transform(Curves.easeInOut.transform(_controller.value));
          return FractionalTranslation(
            translation: Offset(slide, 0),
            child: child,
          );
        },
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: 0.5,
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: <Color>[
                    Colors.transparent,
                    widget.color,
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
