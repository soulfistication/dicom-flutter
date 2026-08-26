import 'package:flutter/material.dart';

/// Design tokens matching the web app's CSS variables.
abstract final class AppColors {
  static const bg = Color(0xFFF2F3F7);
  static const surface = Color(0xFFFFFFFF);
  static const text = Color(0xFF1A1C22);
  static const text2 = Color(0xFF6B7280);
  static const text3 = Color(0xFF9AA1AC);
  static const accent = Color(0xFF2F7BFF);
  static const accentWeak = Color(0x242F7BFF);
  static const border = Color(0xFFE6E8EE);
  static const danger = Color(0xFFE5484D);
  static const viewerBg = Color(0xFF05070C);
}

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      primary: AppColors.accent,
      surface: AppColors.surface,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
  );
}

String formatBytes(int n) {
  if (n < 1024) return '$n B';
  if (n < 1024 * 1024) return '${(n / 1024).round()} KB';
  return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String formatDate(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ampm = d.hour >= 12 ? 'PM' : 'AM';
  final min = d.minute.toString().padLeft(2, '0');
  return '${months[d.month - 1]} ${d.day}, ${d.year}, $h:$min $ampm';
}
