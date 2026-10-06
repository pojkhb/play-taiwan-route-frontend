import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/map_kit.dart';

/// 公車站牌：點地圖找附近站牌 → 即時到站 → 路線詳情（去程/返程線形、站牌、發車時間）；另可瀏覽台灣好行。
class BusPage extends StatefulWidget {
  const BusPage({super.key});

  @override
  State<BusPage> createState() => _BusPageState();
}

class _BusPageState extends State<BusPage> {
  static const _busRed = Color(0xFFC62828);
  static const _tripperGold = Pal.gold;

  final _map = MapController();
  int _tab = 0; // 0 附近站牌、1 台灣好行

  LatLng? _center;
  List<BusStopNearby> _stops = [];
  BusStopNearby? _stop;
  List<BusArrival>? _arrivals;

  List<TaiwanTripRoute>? _tripRoutes;
  String _filter = '';

  BusRouteDetail? _route;
  int _pattern = 0;
  bool _loading = false;

  Future<T?> _run<T>(Future<T> Function() action) async {
    setState(() => _loading = true);
    try {
      return await action();
    } catch (e) {
      if (mounted) showError(context, e);
      return null;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _searchNearby(LatLng p) async {
    setState(() {
      _center = p;
      _stop = null;
      _arrivals = null;
      _route = null;
      _tab = 0;
    });
    final r = await _run(() => Api.instance.get('/api/Bus/Nearby', {'lat': p.latitude, 'lng': p.longitude, 'radius': 500}));
    if (r != null) setState(() => _stops = (r as List).cast<Map<String, dynamic>>().map(BusStopNearby.fromJson).toList());
  }

  Future<void> _selectStop(BusStopNearby stop) async {
    setState(() {
      _stop = stop;
      _arrivals = null;
      _route = null;
    });
    _map.move(stop.point, 17);
    final r = await _run(() => Api.instance.get('/api/Bus/Stop/${stop.bsId}/Arrivals'));
    if (r != null) setState(() => _arrivals = (r as List).cast<Map<String, dynamic>>().map(BusArrival.fromJson).toList());
  }

  Future<void> _openRoute(int brId) async {
    final r = await _run(() => Api.instance.get('/api/Bus/Route/$brId'));
    if (r == null) return;
    setState(() {
      _route = BusRouteDetail.fromJson(r as Map<String, dynamic>);
      _pattern = 0;
    });
    _fitRoute();
  }

  Future<void> _loadTrips() async {
    if (_tripRoutes != null) return;
    final r = await _run(() => Api.instance.get('/api/Bus/TaiwanTrip'));
    if (r != null) setState(() => _tripRoutes = (r as List).cast<Map<String, dynamic>>().map(TaiwanTripRoute.fromJson).toList());
  }

  void _fitRoute() {
    final route = _route;
    if (route == null || route.patterns.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        fitTo(_map, route.patterns[_pattern].line, padding: mapFitPadding(context, base: 30));
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) => MapWithPanel(map: _buildMap(), panel: _buildPanel);

  Widget _buildMap() {
    final route = _route;
    final pattern = route == null || route.patterns.isEmpty ? null : route.patterns[_pattern];
    final lineColor = route?.tripperTheme != null || (route?.routeTypeName == '台灣好行') ? _tripperGold : _busRed;

    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: const LatLng(24.1372, 120.6869),
        initialZoom: 15,
        interactionOptions: mapInteraction,
        onTap: (_, p) => _searchNearby(p),
      ),
      children: [
        treasureTiles(),
        if (pattern != null) ...[
          PolylineLayer(polylines: [
            Polyline(points: pattern.line, color: lineColor, strokeWidth: 6, borderStrokeWidth: 2, borderColor: Colors.white),
          ]),
          MarkerLayer(markers: [
            ...arrowMarkers(pattern.line, lineColor, spacing: 600),
            for (final s in pattern.stops)
              Marker(
                point: s.point,
                width: 12,
                height: 12,
                child: Tooltip(
                  message: '${s.sequence}. ${s.name}',
                  child: Container(
                    decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: lineColor, width: 3)),
                  ),
                ),
              ),
            if (pattern.stops.isNotEmpty) sealMarker(pattern.stops.first.point, '起', label: pattern.stops.first.name, color: lineColor),
            if (pattern.stops.length > 1) sealMarker(pattern.stops.last.point, '迄', label: pattern.stops.last.name, color: Pal.ink),
          ]),
        ] else
          MarkerLayer(markers: [
            for (final s in _stops)
              Marker(
                point: s.point,
                width: 30,
                height: 30,
                child: GestureDetector(
                  onTap: () => _selectStop(s),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _stop?.bsId == s.bsId ? Pal.ink : (s.routes.any((r) => r.isTripper) ? _tripperGold : _busRed),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.directions_bus, size: 16, color: Colors.white),
                  ),
                ),
              ),
            if (_center != null) sealMarker(_center!, '我', color: Pal.ink),
          ]),
        osmAttribution(),
      ],
    );
  }

  Widget _buildPanel(ScrollController? controller) {
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (controller != null)
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(color: Pal.inkSoft, borderRadius: BorderRadius.circular(2)),
            ),
          ),
        if (_route != null)
          ..._routeDetail(_route!)
        else ...[
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, icon: Icon(Icons.near_me), label: Text('附近站牌')),
              ButtonSegment(value: 1, icon: Icon(Icons.landscape), label: Text('台灣好行')),
            ],
            selected: {_tab},
            onSelectionChanged: (s) {
              setState(() => _tab = s.first);
              if (_tab == 1) _loadTrips();
            },
          ),
          const SizedBox(height: 10),
          if (_loading) const LinearProgressIndicator(),
          if (_tab == 0) ..._nearbyList() else ..._tripList(),
        ],
      ],
    );
  }

  List<Widget> _nearbyList() {
    if (_center == null) {
      return const [Text('點地圖上任一個位置，找 500 公尺內的公車站牌。', style: TextStyle(color: Pal.inkSoft))];
    }
    return [
      Text('附近 ${_stops.length} 個站牌', style: const TextStyle(fontWeight: FontWeight.bold)),
      for (final s in _stops)
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: _stop?.bsId == s.bsId ? Pal.ink : Pal.parchmentDeep, width: _stop?.bsId == s.bsId ? 2 : 1.2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              InkWell(
                onTap: () => _selectStop(s),
                child: Row(children: [
                  const Icon(Icons.directions_bus, color: _busRed, size: 20),
                  const SizedBox(width: 6),
                  Expanded(child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold))),
                  Text('${s.distanceM} m', style: const TextStyle(fontSize: 12, color: Pal.inkSoft)),
                ]),
              ),
              const SizedBox(height: 6),
              Wrap(spacing: 4, runSpacing: 4, children: [
                for (final r in s.routes)
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(r.routeName, style: const TextStyle(fontSize: 12)),
                    backgroundColor: r.isTripper ? _tripperGold.withValues(alpha: 0.2) : null,
                    onPressed: () => _openRoute(r.brId),
                  ),
              ]),
              if (_stop?.bsId == s.bsId) ..._arrivalList(),
            ]),
          ),
        ),
    ];
  }

  List<Widget> _arrivalList() {
    final arrivals = _arrivals;
    return [
      const Divider(),
      Row(children: [
        const Text('即時到站', style: TextStyle(fontWeight: FontWeight.bold, color: Pal.cinnabar)),
        const Spacer(),
        IconButton(icon: const Icon(Icons.refresh, size: 18), onPressed: () => _selectStop(_stop!)),
      ]),
      if (arrivals == null)
        const Text('查詢中…', style: TextStyle(fontSize: 12))
      else if (arrivals.isEmpty)
        const Text('目前沒有到站資料', style: TextStyle(fontSize: 12, color: Pal.inkSoft))
      else
        for (final a in arrivals)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              SizedBox(width: 90, child: Text(a.routeName, style: const TextStyle(fontWeight: FontWeight.w600))),
              Expanded(child: Text(a.subRouteName, style: const TextStyle(fontSize: 12, color: Pal.inkSoft), overflow: TextOverflow.ellipsis)),
              Text(a.statusText,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: (a.estimateMinutes ?? 99) <= 3 ? Pal.cinnabar : Pal.ink,
                  )),
            ]),
          ),
    ];
  }

  List<Widget> _tripList() {
    final routes = _tripRoutes;
    if (routes == null) return const [Text('載入中…')];
    final filtered = routes.where((r) => _filter.isEmpty || '${r.routeName}${r.cityName}${r.theme ?? ''}'.contains(_filter)).toList();
    return [
      TextField(
        decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '搜尋路線、縣市', isDense: true, border: OutlineInputBorder()),
        onChanged: (v) => setState(() => _filter = v.trim()),
      ),
      const SizedBox(height: 6),
      Text('共 ${filtered.length} 條台灣好行', style: const TextStyle(fontWeight: FontWeight.bold)),
      for (final r in filtered)
        Card(
          child: ListTile(
            leading: const Icon(Icons.landscape, color: _tripperGold),
            title: Text(r.routeName),
            subtitle: Text('${r.cityName}・${r.departure} → ${r.destination}・${r.stopCount} 站'),
            onTap: () => _openRoute(r.brId),
          ),
        ),
    ];
  }

  List<Widget> _routeDetail(BusRouteDetail route) {
    final pattern = route.patterns.isEmpty ? null : route.patterns[_pattern];
    return [
      Row(children: [
        IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _route = null)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(route.routeName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('${route.routeTypeName}${route.cityName == null ? '' : '・${route.cityName}'}', style: const TextStyle(color: Pal.inkSoft)),
          ]),
        ),
      ]),
      if (route.departure != null) Text('${route.departure} ↔ ${route.destination ?? ''}'),
      if (route.fareDesc != null && route.fareDesc!.isNotEmpty)
        Text('票價：${route.fareDesc}', style: const TextStyle(fontSize: 12, color: Pal.inkSoft)),
      if (route.headwayDesc != null && route.headwayDesc!.isNotEmpty)
        Text('班距：${route.headwayDesc}', style: const TextStyle(fontSize: 12, color: Pal.inkSoft)),
      const SizedBox(height: 8),
      if (route.patterns.length > 1)
        DropdownButtonFormField<int>(
          initialValue: _pattern,
          key: ValueKey(route.routeName),
          isExpanded: true,
          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
          items: [
            for (var i = 0; i < route.patterns.length; i++)
              DropdownMenuItem(
                value: i,
                child: Text('${route.patterns[i].directionName}・${route.patterns[i].headsign ?? route.patterns[i].subRouteName}',
                    overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            setState(() => _pattern = v ?? 0);
            _fitRoute();
          },
        ),
      if (pattern != null) ...[
        for (final d in pattern.departures)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('發車時間：${d.$1}（${d.$2.length} 班）', style: const TextStyle(fontSize: 13)),
            children: [
              Wrap(spacing: 6, runSpacing: 4, children: [for (final t in d.$2) Text(t, style: const TextStyle(fontSize: 12))]),
            ],
          ),
        const SizedBox(height: 6),
        Text('站牌（${pattern.stops.length} 站）', style: const TextStyle(fontWeight: FontWeight.bold)),
        for (final s in pattern.stops)
          InkWell(
            onTap: () => _map.move(s.point, 17),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                SizedBox(width: 30, child: Text('${s.sequence}', style: const TextStyle(color: Pal.inkSoft))),
                Expanded(child: Text(s.name)),
              ]),
            ),
          ),
      ],
    ];
  }
}
