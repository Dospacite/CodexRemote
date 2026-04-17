import 'package:flutter/material.dart';

class MonospaceOutputView extends StatelessWidget {
  const MonospaceOutputView({
    super.key,
    required this.text,
    required this.style,
    this.scrollable = true,
  });

  final String text;
  final TextStyle? style;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final displayText = _repairDisplayText(text);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final lineLengths = displayText.split('\n').map((line) => line.length);
        final longestLineLength = lineLengths.isEmpty
            ? 0
            : lineLengths.reduce((left, right) => left > right ? left : right);
        final fontSize = style?.fontSize ?? 12;
        final estimatedCharWidth = fontSize * 0.62;
        final contentWidth = (longestLineLength * estimatedCharWidth) + 24;
        final targetWidth =
            constraints.hasBoundedWidth && contentWidth < constraints.maxWidth
            ? constraints.maxWidth
            : contentWidth;
        final content = SizedBox(
          width: targetWidth,
          child: SelectionArea(
            child: Text(
              displayText,
              overflow: TextOverflow.visible,
              softWrap: false,
              textWidthBasis: TextWidthBasis.longestLine,
              strutStyle: const StrutStyle(forceStrutHeight: true, height: 1.2),
              style: style,
            ),
          ),
        );
        if (!scrollable) {
          return content;
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(child: content),
        );
      },
    );
  }

  String _repairDisplayText(String value) {
    final lines = value.split('\n');
    if (lines.length < 8) {
      return value;
    }

    final repaired = <String>[];
    final run = <String>[];

    void flushRun() {
      if (run.isEmpty) {
        return;
      }
      final nonEmpty = run.where((line) => line.isNotEmpty).toList();
      final mostlySingleChar =
          nonEmpty.length >= 6 &&
          nonEmpty.every((line) {
            final trimmed = line.trim();
            return line.runes.length == 1 || trimmed.runes.length == 1;
          });
      if (mostlySingleChar) {
        final joined = run.join();
        if (repaired.isNotEmpty && joined.startsWith(RegExp(r'\s'))) {
          repaired[repaired.length - 1] = '${repaired.last}$joined';
        } else {
          repaired.add(joined);
        }
      } else {
        repaired.addAll(run);
      }
      run.clear();
    }

    for (final line in lines) {
      final trimmed = line.trim();
      final isRepairableSingleChar =
          line.isEmpty || line.runes.length == 1 || trimmed.runes.length == 1;
      if (isRepairableSingleChar) {
        run.add(line);
      } else {
        flushRun();
        repaired.add(line);
      }
    }
    flushRun();

    return repaired.join('\n');
  }
}
