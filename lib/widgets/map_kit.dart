import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme.dart';

const _distance = Distance();

/// 舊地圖的泛黃色調（一半原色 + 一半 sepia）
const _sepia = ColorFilter.matrix(<double>[
  0.70, 0.38, 0.09, 0, 0,
  0.17, 0.84, 0.08, 0, 0,
  0.14, 0.27, 0.57, 0, 0,
  0, 0, 0, 1, 0,
]);

/// 藏寶圖底圖（OpenStreetMap + 泛黃濾鏡）
Widget treasureTiles() => TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'tw.playtaiwan.play_taiwan_demo',
      tileBuilder: (context, tile, _) => ColorFiltered(colorFilter: _sepia, child: tile),
    );

Widget osmAttribution() => const SimpleAttributionWidget(
      source: Text('OpenStreetMap contributors'),
      backgroundColor: Color(0xCCF3E4C1),
    );

/// 預設的地圖互動（不允許旋轉，箭頭方向才不會亂掉）
const mapInteraction = InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate);


/// 寬螢幕（電腦、平板橫放）：左邊地圖、右邊面板；窄螢幕（手機）：地圖在上、面板從下方拉起。
class MapWithPanel extends StatelessWidget {
  const MapWithPanel({super.key, required this.map, required this.panel});

  final Widget map;
  final Widget Function(ScrollController? controller) panel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 900) {
        return Row(children: [
          Expanded(child: map),
          Container(
            width: 400,
            decoration: const BoxDecoration(
              color: Pal.parchment,
              border: Border(left: BorderSide(color: Pal.ink, width: 3)),
            ),
            // 有底色的 Container 會蓋掉 ListTile 的點擊水波，面板內容要再包一層 Material
            child: Material(type: MaterialType.transparency, child: panel(null)),
          ),
        ]);
      }
      return Stack(children: [
        Positioned.fill(child: map),
        DraggableScrollableSheet(
          initialChildSize: 0.42,
          minChildSize: 0.12,
          maxChildSize: 0.92,
          builder: (context, controller) => Container(
            decoration: const BoxDecoration(
              color: Pal.parchment,
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              boxShadow: [BoxShadow(color: Color(0x55000000), blurRadius: 12)],
            ),
            child: Material(type: MaterialType.transparency, child: panel(controller)),
          ),
        ),
      ]);
    });
  }
}


/// 方位角（度，北 = 0、順時針）
double bearing(LatLng a, LatLng b) {
  final lat1 = a.latitudeInRad, lat2 = b.latitudeInRad;
  final dLon = (b.longitude - a.longitude) * math.pi / 180;
  final y = math.sin(dLon) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

double lineLength(List<LatLng> pts) {
  double m = 0;
  for (var i = 1; i < pts.length; i++) {
    m += _distance.distance(pts[i - 1], pts[i]);
  }
  return m;
}

/// 折線上距起點 target 公尺的位置與行進方向
(LatLng, double) pointAlong(List<LatLng> pts, double target) {
  double walked = 0;
  for (var i = 1; i < pts.length; i++) {
    final seg = _distance.distance(pts[i - 1], pts[i]);
    if (seg > 0 && walked + seg >= target) {
      final t = (target - walked) / seg;
      final p = LatLng(
        pts[i - 1].latitude + (pts[i].latitude - pts[i - 1].latitude) * t,
        pts[i - 1].longitude + (pts[i].longitude - pts[i - 1].longitude) * t,
      );
      return (p, bearing(pts[i - 1], pts[i]));
    }
    walked += seg;
  }
  return (pts.last, pts.length >= 2 ? bearing(pts[pts.length - 2], pts.last) : 0);
}

/// 沿線等距放方向箭頭。去程：實心箭頭；返程：空心箭頭。
List<Marker> arrowMarkers(List<LatLng> pts, Color color, {bool hollow = false, double spacing = 380}) {
  if (pts.length < 2) return const [];
  final length = lineLength(pts);
  if (length < 40) return const [];

  final count = (length / spacing).floor().clamp(1, 10);
  return List.generate(count, (i) {
    final (point, deg) = pointAlong(pts, length * (i + 0.5) / count);
    return Marker(
      point: point,
      width: 22,
      height: 22,
      child: IgnorePointer(child: ArrowIcon(color: color, hollow: hollow, degrees: deg)),
    );
  });
}

class ArrowIcon extends StatelessWidget {
  const ArrowIcon({super.key, required this.color, required this.degrees, this.hollow = false, this.size = 20});

  final Color color;
  final double degrees;
  final bool hollow;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: degrees * math.pi / 180,
      child: Stack(alignment: Alignment.center, children: [
        Icon(Icons.navigation, size: size, color: hollow ? color : Colors.white),
        Icon(Icons.navigation, size: size * 0.62, color: hollow ? Colors.white : color),
      ]),
    );
  }
}

/// 交通方式徽章（放在每一段路線中間）：圓形圖示，公車/捷運加上路線名
class ModeBadge extends StatelessWidget {
  const ModeBadge({super.key, required this.mode, required this.color, this.label, this.faded = false});

  final String mode;
  final Color color;
  final String? label;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final style = modeStyle(mode, lineColor: color);
    return Opacity(
      opacity: faded ? 0.35 : 1,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 3)],
          ),
          child: Icon(style.icon, size: 15, color: Colors.white),
        ),
        if (label != null && label!.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(left: 2),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color, width: 1.5),
            ),
            child: Text(label!, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
          ),
      ]),
    );
  }
}

/// 編號印章（劇本節點、同心圓景點）
class SealMarker extends StatelessWidget {
  const SealMarker({super.key, required this.text, this.label, this.color = Pal.cinnabar, this.faded = false});

  final String text;
  final String? label;
  final Color color;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: faded ? 0.4 : 1,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFF7E7C4), width: 2),
            boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        ),
        if (label != null)
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xEEF3E4C1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Pal.inkSoft, width: 0.8),
            ),
            child: Text(label!, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Pal.ink, fontWeight: FontWeight.w600)),
          ),
      ]),
    );
  }
}

/// 印章 Marker：圓心對準座標，名稱在下方
Marker sealMarker(LatLng point, String text, {String? label, Color color = Pal.cinnabar, bool faded = false}) => Marker(
      point: point,
      width: 130,
      height: 56,
      alignment: const Alignment(0, 0.5),
      child: SealMarker(text: text, label: label, color: color, faded: faded),
    );

/// 路線中間點（依長度），放交通方式徽章用
LatLng midpoint(List<LatLng> pts) => pointAlong(pts, lineLength(pts) / 2).$1;

/// 鏡頭留白：寬螢幕避開左上角圖例；手機避開下方拉起的面板（約 42% 高），左右留地標名稱的寬度
EdgeInsets mapFitPadding(BuildContext context, {double base = 50}) {
  final size = MediaQuery.sizeOf(context);
  if (size.width >= 900) return EdgeInsets.fromLTRB(base + 110, base, base, base);
  return EdgeInsets.fromLTRB(base * 0.9, base + 20, base * 0.9, size.height * 0.42 + base * 0.6);
}

/// 把地圖鏡頭拉到能看到所有點
void fitTo(MapController controller, List<LatLng> points, {EdgeInsets padding = const EdgeInsets.all(60)}) {
  if (points.isEmpty) return;
  if (points.length == 1) {
    controller.move(points.first, 16);
    return;
  }
  controller.fitCamera(CameraFit.coordinates(coordinates: points, padding: padding, maxZoom: 17));
}

void showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Pal.cinnabar));
}
