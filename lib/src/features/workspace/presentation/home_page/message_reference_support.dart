part of workspace_home_page;

class _MessageReferenceMatch {
  const _MessageReferenceMatch({
    required this.start,
    required this.end,
    required this.displayText,
    required this.path,
    required this.line,
  });

  final int start;
  final int end;
  final String displayText;
  final String path;
  final int? line;
}

class _ResolvedReference {
  const _ResolvedReference({required this.path, required this.line});

  final String path;
  final int? line;
}

Iterable<_MessageReferenceMatch> _matchMarkdownReferences(String input) sync* {
  final pattern = RegExp(r'\[([^\]]+)\]\(([^)\s]+)\)');
  for (final match in pattern.allMatches(input)) {
    final target = match.group(2);
    if (target == null || target.isEmpty) {
      continue;
    }
    final resolved = _parseReferenceTarget(target);
    if (resolved == null) {
      continue;
    }
    yield _MessageReferenceMatch(
      start: match.start,
      end: match.end,
      displayText: match.group(1) ?? target,
      path: resolved.path,
      line: resolved.line,
    );
  }
}

Iterable<_MessageReferenceMatch> _matchPlainReferences(String input) sync* {
  final pattern = RegExp(
    r'(?<![\w/])((?:/|\.{1,2}/)?(?:[A-Za-z0-9._-]+/)+[A-Za-z0-9._-]+)(?::(\d+)|#L(\d+))',
  );
  for (final match in pattern.allMatches(input)) {
    final target = match.group(0);
    final path = match.group(1);
    if (target == null || path == null) {
      continue;
    }
    final line = int.tryParse(match.group(2) ?? match.group(3) ?? '');
    yield _MessageReferenceMatch(
      start: match.start,
      end: match.end,
      displayText: target,
      path: path,
      line: line,
    );
  }
}

_ResolvedReference? _parseReferenceTarget(String target) {
  final hashIndex = target.indexOf('#');
  String path = hashIndex >= 0 ? target.substring(0, hashIndex) : target;
  final hash = hashIndex >= 0 ? target.substring(hashIndex + 1) : '';
  int? line;

  final colonMatch = RegExp(r'^(.*):(\d+)$').firstMatch(path);
  if (colonMatch != null &&
      !path.startsWith('ws://') &&
      !path.startsWith('http://') &&
      !path.startsWith('https://')) {
    path = colonMatch.group(1) ?? path;
    line = int.tryParse(colonMatch.group(2) ?? '');
  }

  if (hash.startsWith('L')) {
    line = int.tryParse(hash.substring(1));
  }

  if (path.isEmpty) {
    return null;
  }
  return _ResolvedReference(path: path, line: line);
}

String _linkifyPlainFileReferences(String input) {
  final markdownMatches = _matchMarkdownReferences(input).toList();
  final plainMatches = _matchPlainReferences(input).where((plainMatch) {
    for (final markdownMatch in markdownMatches) {
      if (plainMatch.start >= markdownMatch.start &&
          plainMatch.end <= markdownMatch.end) {
        return false;
      }
    }
    return true;
  }).toList()..sort((left, right) => left.start.compareTo(right.start));

  if (plainMatches.isEmpty) {
    return input;
  }

  final buffer = StringBuffer();
  var cursor = 0;
  for (final match in plainMatches) {
    if (match.start < cursor) {
      continue;
    }
    buffer.write(input.substring(cursor, match.start));
    final href = match.line == null
        ? match.path
        : '${match.path}#L${match.line}';
    buffer.write('[${match.displayText}]($href)');
    cursor = match.end;
  }
  if (cursor < input.length) {
    buffer.write(input.substring(cursor));
  }
  return buffer.toString();
}
