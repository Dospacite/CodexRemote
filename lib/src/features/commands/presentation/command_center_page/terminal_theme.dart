part of command_center_page;

TerminalTheme _buildTerminalTheme(ThemeData theme) {
  final scheme = theme.colorScheme;
  final isDark = scheme.brightness == Brightness.dark;
  final background = Color.alphaBlend(
    scheme.surface.withValues(alpha: isDark ? 0.92 : 0.98),
    theme.scaffoldBackgroundColor,
  );
  final foreground = scheme.onSurface;
  final muted = scheme.onSurface.withValues(alpha: isDark ? 0.65 : 0.58);
  final cursor = scheme.primary;
  final selection = scheme.primary.withValues(alpha: isDark ? 0.30 : 0.22);

  return TerminalTheme(
    cursor: cursor,
    selection: selection,
    foreground: foreground,
    background: background,
    black: background,
    white: foreground.withValues(alpha: 0.92),
    red: scheme.error,
    green: scheme.primary,
    yellow: Color.alphaBlend(
      scheme.secondary.withValues(alpha: 0.85),
      foreground.withValues(alpha: 0.15),
    ),
    blue: scheme.secondary,
    magenta:
        Color.lerp(scheme.primary, scheme.secondary, 0.5) ?? scheme.primary,
    cyan: Color.lerp(scheme.secondary, foreground, 0.22) ?? scheme.secondary,
    brightBlack: muted,
    brightRed: scheme.error.withValues(alpha: 0.85),
    brightGreen: scheme.primary.withValues(alpha: 0.90),
    brightYellow: Color.alphaBlend(
      scheme.secondary.withValues(alpha: 0.95),
      foreground.withValues(alpha: 0.22),
    ),
    brightBlue: scheme.secondary.withValues(alpha: 0.92),
    brightMagenta:
        (Color.lerp(scheme.primary, scheme.secondary, 0.6) ?? scheme.primary)
            .withValues(alpha: 0.95),
    brightCyan:
        (Color.lerp(scheme.secondary, foreground, 0.35) ?? scheme.secondary)
            .withValues(alpha: 0.95),
    brightWhite: foreground,
    searchHitBackground: scheme.secondary.withValues(alpha: 0.34),
    searchHitBackgroundCurrent: scheme.primary.withValues(alpha: 0.44),
    searchHitForeground: foreground,
  );
}
