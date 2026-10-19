import 'package:flutter/material.dart';

import '../data/dtc_database.dart';

class Palette {
  static const bg = Color(0xFF070B12);
  static const panel = Color(0xFF0B111B);
  static const panel2 = Color(0xFF0E1520);
  static const line = Color(0xFF1C2A3A);
  static const track = Color(0xFF14202E);
  static const text = Color(0xFFE6F1FF);
  static const muted = Color(0xFF8FA3BC);
  static const cyan = Color(0xFF3EE6FF);
  static const onCyan = Color(0xFF04131A);
  static const amber = Color(0xFFFFB547);
  static const red = Color(0xFFFF6B6B);
  static const green = Color(0xFF4ADE9A);
}

const mono = 'monospace';

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: Palette.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: Palette.cyan,
      onPrimary: Palette.onCyan,
      surface: Palette.panel,
      onSurface: Palette.text,
      error: Palette.red,
    ),
    textTheme: base.textTheme.apply(bodyColor: Palette.text, displayColor: Palette.text),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xFF0A0F18),
      indicatorColor: Palette.cyan.withValues(alpha: 0.14),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? Palette.cyan : const Color(0xFF7F93AC)),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) =>
            TextStyle(fontSize: 11, color: s.contains(WidgetState.selected) ? Palette.cyan : const Color(0xFF7F93AC)),
      ),
    ),
    dialogTheme: const DialogThemeData(backgroundColor: Palette.panel2),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Palette.panel2),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Palette.panel2,
      contentTextStyle: TextStyle(color: Palette.text),
    ),
  );
}

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.border});
  final Widget child;
  final EdgeInsets padding;
  final Color? border;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Palette.panel,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: border ?? Palette.line),
    ),
    child: child,
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(text.toUpperCase(), style: const TextStyle(fontSize: 12, letterSpacing: 2, color: Palette.muted)),
        ),
        ?trailing,
      ],
    ),
  );
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.outlined = false,
    this.color,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool outlined;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Palette.cyan;
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 10)],
        Flexible(
          child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ],
    );
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    const size = Size.fromHeight(54);
    return outlined
        ? OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: c,
              side: BorderSide(color: c),
              minimumSize: size,
              shape: shape,
              backgroundColor: c.withValues(alpha: 0.08),
            ),
            child: child,
          )
        : FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: c,
              foregroundColor: Palette.onCyan,
              minimumSize: size,
              shape: shape,
            ),
            child: child,
          );
  }
}

Color severityColor(Severity s) => switch (s) {
  Severity.high => Palette.red,
  Severity.medium => Palette.amber,
  Severity.low => Palette.green,
};

class Pill extends StatelessWidget {
  const Pill(this.text, this.color, {super.key});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1, color: color),
    ),
  );
}

class NeedConnection extends StatelessWidget {
  const NeedConnection(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Palette.muted, fontSize: 15),
      ),
    ),
  );
}
