import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';

/// 同心圓（等時圈）：從中心點依交通方式畫出 10/20/30 分鐘可到達的範圍，範圍內隨機抽 8 個景點（每次不同）。
/// 劇本交通路線選「同心圓」時，抽到的景點就是要去的地方。
class IsochroneController extends ChangeNotifier {
  static const roadModes = ['步行', '腳踏車', '機車', '汽車'];
  static const contours = {
    '10 / 20 / 30 分鐘': [10, 20, 30],
    '5 / 10 / 15 分鐘': [5, 10, 15],
    '15 / 30 / 45 / 60 分鐘': [15, 30, 45, 60],
  };

  LatLng center = const LatLng(24.1372, 120.6869);
  final Set<String> modes = {'步行'};
  String contour = contours.keys.first;
  bool loading = false;
  ReachableResult? result;

  PlacePoint get centerPoint => PlacePoint(lat: center.latitude, lng: center.longitude, name: '同心圓中心');

  /// 抽到的景點（後端已排好順路順序）
  List<PlacePoint> get points => [
        for (final a in result?.attractions ?? const <ReachableAttraction>[])
          PlacePoint(lat: a.point.latitude, lng: a.point.longitude, name: a.name),
      ];

  /// 範圍外框上的所有點（鏡頭對焦用）
  List<LatLng> get outline => [
        for (final band in result?.isochrones ?? const <IsoBand>[])
          for (final poly in band.polygons)
            if (poly.isNotEmpty) ...poly.first,
      ];

  Color ringColor(int ring) => Pal.rings[(ring - 1).clamp(0, Pal.rings.length - 1)];

  /// 換中心點，舊的範圍與景點作廢
  void setCenter(LatLng point) {
    center = point;
    result = null;
    notifyListeners();
  }

  void toggleMode(String mode, bool on) {
    on ? modes.add(mode) : modes.remove(mode);
    if (modes.isEmpty) modes.add('步行');
    notifyListeners();
  }

  void setContour(String value) {
    contour = value;
    notifyListeners();
  }

  /// 查範圍與景點；失敗時丟出例外，由畫面顯示錯誤
  Future<void> search() async {
    loading = true;
    notifyListeners();
    try {
      final r = await Api.instance.post('/api/Story/ReachableAttractions', {
        'lat': center.latitude,
        'lng': center.longitude,
        'transportation': roadModes.where(modes.contains).toList(),
        'contour_minutes': contours[contour],
        'include_polygons': true,
      });
      result = ReachableResult.fromJson(r as Map<String, dynamic>);
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}

/// 地圖上的同心圓範圍：外圈先畫、內圈後畫，內圈才不會被蓋住。規劃出路線後調淡，不搶路線的顏色。
Widget isochroneLayer(IsochroneController iso, {bool faded = false}) {
  final minutes = iso.result?.contourMinutes ?? const <int>[];
  final bands = [...?iso.result?.isochrones]..sort((a, b) => b.minutes.compareTo(a.minutes));
  return PolygonLayer(polygons: [
    for (final band in bands)
      for (final poly in band.polygons)
        if (poly.isNotEmpty)
          Polygon(
            points: poly.first,
            holePointsList: poly.skip(1).toList(),
            color: iso.ringColor(minutes.indexOf(band.minutes) + 1).withValues(alpha: faded ? 0.06 : 0.14),
            borderColor: iso.ringColor(minutes.indexOf(band.minutes) + 1).withValues(alpha: faded ? 0.45 : 1),
            borderStrokeWidth: 2.5,
            pattern: StrokePattern.dashed(segments: const [10, 6]),
          ),
  ]);
}

/// 面板上的同心圓設定：交通方式、分鐘數、畫出按鈕，畫完列出抽到的景點
class IsochroneControls extends StatelessWidget {
  const IsochroneControls({super.key, required this.iso, required this.onSearch, required this.onShowPoint});

  final IsochroneController iso;
  final VoidCallback onSearch;
  final void Function(LatLng point) onShowPoint;

  @override
  Widget build(BuildContext context) {
    final result = iso.result;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('點地圖設定中心點，畫出交通時間內能到達的範圍，範圍內隨機抽出的景點就是要去的地方。',
          style: TextStyle(fontSize: 13, color: Pal.inkSoft)),
      const SizedBox(height: 2),
      Text('中心：${iso.center.latitude.toStringAsFixed(5)}, ${iso.center.longitude.toStringAsFixed(5)}',
          style: const TextStyle(fontSize: 12, color: Pal.inkSoft)),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final mode in IsochroneController.roadModes)
          FilterChip(
            avatar: Icon(modeStyle(mode).icon, size: 18, color: modeStyle(mode).color),
            label: Text(mode),
            selected: iso.modes.contains(mode),
            showCheckmark: false,
            selectedColor: modeStyle(mode).color.withValues(alpha: 0.22),
            onSelected: (on) => iso.toggleMode(mode, on),
          ),
      ]),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        initialValue: iso.contour,
        decoration: const InputDecoration(labelText: '同心圓', border: OutlineInputBorder(), isDense: true),
        items: [for (final k in IsochroneController.contours.keys) DropdownMenuItem(value: k, child: Text(k))],
        onChanged: (v) => iso.setContour(v ?? iso.contour),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: iso.loading ? null : onSearch,
        icon: iso.loading
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(result == null ? Icons.radar : Icons.casino_outlined),
        label: Text(iso.loading ? '計算中…' : result == null ? '畫出同心圓' : '重新抽景點'),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
      ),
      if (result != null) ...[
        const SizedBox(height: 10),
        Wrap(spacing: 10, children: [
          for (var i = 0; i < result.contourMinutes.length; i++)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 14, height: 14, color: iso.ringColor(i + 1).withValues(alpha: 0.5)),
              Text(' ${result.contourMinutes[i]} 分鐘', style: const TextStyle(fontSize: 12)),
            ]),
        ]),
        const SizedBox(height: 6),
        Text('範圍內共 ${result.totalReachable} 個景點，隨機抽出 ${result.attractions.length} 個（已排好順路順序）',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        if (result.attractions.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('範圍內沒有景點。Neo4j 連不上時會改用 place 表的景點，請確認有匯入測試資料。',
                style: TextStyle(fontSize: 12, color: Pal.inkSoft)),
          ),
        for (var i = 0; i < result.attractions.length; i++) _attractionRow(i, result.attractions[i]),
      ],
    ]);
  }

  Widget _attractionRow(int index, ReachableAttraction a) => InkWell(
        onTap: () => onShowPoint(a.point),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            CircleAvatar(
              radius: 11,
              backgroundColor: iso.ringColor(a.ring),
              child: Text('${index + 1}', style: const TextStyle(color: Colors.white, fontSize: 11)),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(a.name, overflow: TextOverflow.ellipsis)),
            Text('${a.reachableBy} ${a.travelMinutes.ceil()} 分・第 ${a.ring} 圈',
                style: const TextStyle(fontSize: 12, color: Pal.inkSoft)),
          ]),
        ),
      );
}
