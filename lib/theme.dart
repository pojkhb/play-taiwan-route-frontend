import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// 藏寶圖配色
class Pal {
  static const parchment = Color(0xFFF3E4C1);
  static const parchmentDeep = Color(0xFFE7D3A4);
  static const ink = Color(0xFF3B2A1A);
  static const inkSoft = Color(0xFF6B5237);
  static const cinnabar = Color(0xFF9E2A17);
  static const gold = Color(0xFFB8862B);
  static const moss = Color(0xFF4F6B3A);
  static const plum = Color(0xFF5A3D78);
  static const disabled = Color(0xFFB9AE98);

  /// 同心圓各圈顏色（內 → 外）
  static const rings = [cinnabar, gold, moss, plum];
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Pal.cinnabar,
    brightness: Brightness.light,
    surface: Pal.parchment,
    primary: Pal.cinnabar,
    secondary: Pal.gold,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Pal.parchment,
    appBarTheme: const AppBarTheme(
      backgroundColor: Pal.ink,
      foregroundColor: Pal.parchment,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFFFBF3DF),
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Pal.parchmentDeep, width: 1.2),
      ),
    ),
    chipTheme: const ChipThemeData(backgroundColor: Color(0xFFFBF3DF)),
    navigationBarTheme: const NavigationBarThemeData(backgroundColor: Pal.parchmentDeep),
  );
}

/// 各交通方式在地圖上的畫法：顏色、線型、圖示都不一樣，一眼就分得出來
class ModeStyle {
  const ModeStyle({
    required this.icon,
    required this.color,
    required this.pattern,
    required this.width,
    this.casing = false,
  });

  final IconData icon;
  final Color color;
  final StrokePattern pattern;
  final double width;

  /// 公車、捷運加白色外框，看起來像實體路線
  final bool casing;
}

const allModes = ['步行', '腳踏車', '機車', '汽車', '公車', '捷運'];

ModeStyle modeStyle(String mode, {Color? lineColor}) {
  switch (mode) {
    case '步行':
      return const ModeStyle(icon: Icons.directions_walk, color: Color(0xFF2E7D32), pattern: StrokePattern.dotted(spacingFactor: 1.8), width: 5);
    case '腳踏車':
      return ModeStyle(icon: Icons.pedal_bike, color: const Color(0xFFEF6C00), pattern: StrokePattern.dashed(segments: const [14, 7]), width: 5);
    case '機車':
      return ModeStyle(icon: Icons.two_wheeler, color: const Color(0xFF7B1FA2), pattern: StrokePattern.dashed(segments: const [20, 6, 4, 6]), width: 5);
    case '汽車':
      return const ModeStyle(icon: Icons.directions_car, color: Color(0xFF37474F), pattern: StrokePattern.solid(), width: 6);
    case '公車':
      return const ModeStyle(icon: Icons.directions_bus, color: Color(0xFFC62828), pattern: StrokePattern.solid(), width: 7, casing: true);
    case '捷運':
      return ModeStyle(icon: Icons.subway, color: lineColor ?? const Color(0xFF00897B), pattern: const StrokePattern.solid(), width: 8, casing: true);
    default: // 轉乘
      return const ModeStyle(icon: Icons.transfer_within_a_station, color: Color(0xFF757575), pattern: StrokePattern.dotted(), width: 4);
  }
}
