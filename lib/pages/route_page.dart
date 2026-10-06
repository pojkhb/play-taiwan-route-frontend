import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/isochrone_kit.dart';
import '../widgets/map_kit.dart';
import '../widgets/place_ticket.dart';

/// 劇本交通路線：選劇本，或用同心圓抽出附近景點 → 選交通方式（沒有公車/捷運的區域會反灰）→
/// 規劃去程 + 返程，每一段用不同顏色、線型、圖示分出交通方式，沿線箭頭標示方向。
/// 劇本模式下，地圖上也標出劇本周邊好去的地點（飲食／其他），點一下看票券卡片。
class RoutePage extends StatefulWidget {
  const RoutePage({super.key});

  @override
  State<RoutePage> createState() => _RoutePageState();
}

class _RoutePageState extends State<RoutePage> {
  static const _defaultModes = {'步行', '公車', '捷運'};

  final _map = MapController();

  List<RouteStory> _stories = [];
  RouteStory? _story;
  PlacePoint? _start;

  /// 要去的地方：false = 劇本節點、true = 同心圓抽出的景點
  bool _isoMode = false;
  final _iso = IsochroneController();

  Map<String, TransportAvailability> _availability = {};
  final Set<String> _modes = {..._defaultModes};
  bool _includeReturn = true;
  bool _pickingStart = false;

  /// null = 依螢幕寬度決定（寬螢幕展開、手機收起）
  bool? _legendOpen;

  // 周邊好去：劇本附近的地點（不含劇本自己的節點），標在地圖上
  static const _nearbyTabs = ['飲食', '周邊好去', '其他'];
  static const _distance = Distance();
  List<NearbyPlace> _nearby = [];
  Map<int, (RouteStopPoint, double)> _nearest = {};

  /// 0 飲食、1 周邊好去（全部）、2 其他；null = 不顯示
  int? _nearbyTab = 1;
  NearbyPlace? _selectedPlace;

  bool _loadingStories = false;
  bool _checking = false;
  bool _planning = false;

  RoutePlan? _plan;
  final Map<int, int> _chosen = {};
  int? _focusLeg;
  List<MetroLine> _metroLines = [];

  @override
  void initState() {
    super.initState();
    _iso.addListener(_onIso);
    _loadStories();
  }

  @override
  void dispose() {
    _iso
      ..removeListener(_onIso)
      ..dispose();
    super.dispose();
  }

  List<PlacePoint> get _targets => _isoMode
      ? _iso.points
      : (_story?.nodes.map((n) => PlacePoint(lat: n.point.latitude, lng: n.point.longitude, name: n.name)).toList() ?? const []);

  // ─────────────────────────── 資料 ───────────────────────────

  void _onIso() {
    if (mounted) setState(() {});
  }

  Future<void> _loadStories() async {
    setState(() => _loadingStories = true);
    try {
      final result = await Api.instance.get('/api/Route/Stories') as List;
      _stories = result.cast<Map<String, dynamic>>().map(RouteStory.fromJson).toList();
      if (_story == null && _stories.isNotEmpty) _selectStory(_stories.first);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loadingStories = false);
    }
  }

  void _selectStory(RouteStory story) {
    final changed = story.storyId != _story?.storyId;
    setState(() {
      _story = story;
      _isoMode = false;
      _start = story.suggestedStart;
      _selectedPlace = null;
      if (changed) _nearby = [];
      _resetForNewPlaces();
    });
    _afterPlacesChanged();
    _loadNearby(story);
  }

  /// 劇本周邊好去的地點；劇本自己的節點已經是地圖上的編號印章，不重複標
  Future<void> _loadNearby(RouteStory story) async {
    try {
      final result = await Api.instance.get('/api/Map/${story.storyId}/Nearby') as List;
      final nodeNames = story.nodes.map((n) => n.name).toSet();
      final places = result
          .cast<Map<String, dynamic>>()
          .map(NearbyPlace.fromJson)
          .where((p) => p.point != null && !nodeNames.contains(p.name))
          .toList();
      final nearest = <int, (RouteStopPoint, double)>{
        if (story.nodes.isNotEmpty)
          for (final p in places) p.placeId: _nearestNode(story, p.point!),
      };
      if (!mounted || _story?.storyId != story.storyId) return;
      setState(() {
        _nearby = places;
        _nearest = nearest;
      });
    } catch (_) {
      // 周邊好去只是參考資訊，查不到不影響路線規劃
      if (mounted) setState(() => _nearby = []);
    }
  }

  (RouteStopPoint, double) _nearestNode(RouteStory story, LatLng p) {
    final node = story.nodes.reduce((a, b) => _distance(p, a.point) <= _distance(p, b.point) ? a : b);
    return (node, _distance(p, node.point));
  }

  List<NearbyPlace> get _visibleNearby => _isoMode
      ? const []
      : switch (_nearbyTab) {
          null => const [],
          0 => _nearby.where((p) => p.isFood).toList(),
          2 => _nearby.where((p) => !p.isFood).toList(),
          _ => _nearby,
        };

  /// 切換「要去的地方」：劇本 ↔ 同心圓。第一次切到同心圓時，中心點用目前的起點。
  void _setIsoMode(bool on) {
    if (on == _isoMode) return;
    if (!on) {
      if (_story != null) {
        _selectStory(_story!);
      } else {
        setState(() => _isoMode = false);
      }
      return;
    }
    if (_iso.result == null && _start != null) _iso.setCenter(_start!.latLng);
    setState(() {
      _isoMode = true;
      _pickingStart = false;
      _selectedPlace = null;
      _start = _iso.centerPoint;
      _resetForNewPlaces();
    });
    if (_targets.isEmpty) {
      _map.move(_iso.center, 14);
    } else {
      _afterPlacesChanged();
    }
  }

  /// 同心圓模式點地圖：換中心點，起點跟著換，舊的範圍與景點作廢
  void _setIsoCenter(LatLng point) {
    _iso.setCenter(point);
    setState(() {
      _start = _iso.centerPoint;
      _resetForNewPlaces();
    });
  }

  Future<void> _drawIsochrone() async {
    try {
      await _iso.search();
    } catch (e) {
      if (mounted) showError(context, e);
      return;
    }
    if (!mounted) return;
    setState(() {
      _start = _iso.centerPoint;
      _resetForNewPlaces();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        fitTo(_map, _iso.outline, padding: mapFitPadding(context, base: 20));
      } catch (_) {}
    });
    _checkAvailability();
    _loadMetroLines();
  }

  void _resetForNewPlaces() {
    _plan = null;
    _chosen.clear();
    _focusLeg = null;
    _modes
      ..clear()
      ..addAll(_defaultModes);
  }

  void _afterPlacesChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitPlaces());
    _checkAvailability();
    _loadMetroLines();
  }

  void _setStart(PlacePoint start) {
    setState(() {
      _start = start;
      _pickingStart = false;
      _plan = null;
      _chosen.clear();
      _focusLeg = null;
    });
    _checkAvailability();
  }

  /// 查這一帶有沒有公車、捷運；不能用的交通方式反灰並取消勾選
  Future<void> _checkAvailability() async {
    if (_targets.isEmpty) return;
    setState(() => _checking = true);
    try {
      final start = _start;
      final dynamic result = !_isoMode && _story != null
          ? await Api.instance.get('/api/Route/Availability', {'story_id': _story!.storyId, 'lat': start?.lat, 'lng': start?.lng})
          : await Api.instance.post('/api/Route/Availability', [
              if (start != null) start.toJson(),
              ..._targets.map((p) => p.toJson()),
            ]);
      final list = (result as List).cast<Map<String, dynamic>>().map(TransportAvailability.fromJson);
      setState(() {
        _availability = {for (final a in list) a.mode: a};
        _modes.removeWhere((m) => _availability[m]?.enabled == false);
        if (_modes.isEmpty) _modes.add('步行');
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  /// 附近的捷運路網，淡淡地畫在底圖上
  Future<void> _loadMetroLines() async {
    final center = _start ?? (_targets.isNotEmpty ? _targets.first : null);
    if (center == null) return;
    try {
      final result = await Api.instance.get('/api/Metro/Lines', {'lat': center.lat, 'lng': center.lng, 'radius_km': 15}) as List;
      if (mounted) setState(() => _metroLines = result.cast<Map<String, dynamic>>().map(MetroLine.fromJson).toList());
    } catch (_) {
      if (mounted) setState(() => _metroLines = []);
    }
  }

  Future<void> _planRoute() async {
    if (_targets.isEmpty) return;
    setState(() => _planning = true);
    try {
      final result = await Api.instance.post('/api/Route/Plan', {
        if (!_isoMode && _story != null) 'story_id': _story!.storyId,
        if (_isoMode) 'points': _targets.map((p) => p.toJson()).toList(),
        if (_start != null) 'start': _start!.toJson(),
        'transportation': allModes.where(_modes.contains).toList(),
        'include_return': _includeReturn,
      });
      setState(() {
        _plan = RoutePlan.fromJson(result as Map<String, dynamic>);
        _start = _plan!.start;
        _chosen.clear();
        _focusLeg = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitPlan());
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _planning = false);
    }
  }

  Future<void> _useMyLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw '沒有定位權限';
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      _setStart(PlacePoint(lat: pos.latitude, lng: pos.longitude, name: '我的位置'));
      _map.move(LatLng(pos.latitude, pos.longitude), 15);
    } catch (e) {
      if (mounted) showError(context, '無法取得定位：$e');
    }
  }

  // ─────────────────────────── 鏡頭 ───────────────────────────

  RouteOption _optionOf(int legIndex) => _plan!.legs[legIndex].options[_chosen[legIndex] ?? 0];

  void _fitPlaces() {
    try {
      fitTo(_map, [if (_start != null) _start!.latLng, ..._targets.map((p) => p.latLng)], padding: mapFitPadding(context));
    } catch (_) {}
  }

  void _fitPlan() {
    if (_plan == null) return;
    try {
      fitTo(_map, [
        for (var i = 0; i < _plan!.legs.length; i++)
          for (final s in _optionOf(i).segments) ...s.points,
      ], padding: mapFitPadding(context));
    } catch (_) {}
  }

  void _toggleFocus(int legIndex) {
    setState(() => _focusLeg = _focusLeg == legIndex ? null : legIndex);
    try {
      if (_focusLeg == null) {
        _fitPlan();
      } else {
        fitTo(_map, [for (final s in _optionOf(legIndex).segments) ...s.points], padding: mapFitPadding(context, base: 80));
      }
    } catch (_) {}
  }

  // ─────────────────────────── 畫面 ───────────────────────────

  @override
  Widget build(BuildContext context) {
    return MapWithPanel(map: _buildMap(), panel: _buildPanel);
  }

  Widget _buildMap() {
    final routeLines = <Polyline>[];
    final rideStops = <Marker>[];
    final arrows = <Marker>[];
    final badges = <Marker>[];

    final plan = _plan;
    if (plan != null) {
      for (var i = 0; i < plan.legs.length; i++) {
        final leg = plan.legs[i];
        final option = _optionOf(i);
        final faded = _focusLeg != null && _focusLeg != i;
        final alpha = faded ? 0.15 : (leg.isReturn ? 0.72 : 1.0);

        for (final seg in option.segments) {
          if (seg.points.length < 2) continue;
          final style = modeStyle(seg.mode, lineColor: seg.color);
          final color = seg.mode == '捷運' ? seg.color : style.color;

          routeLines.add(Polyline(
            points: seg.points,
            color: color.withValues(alpha: alpha),
            strokeWidth: style.width,
            pattern: style.pattern,
            borderStrokeWidth: style.casing ? 2.5 : 0,
            borderColor: Colors.white.withValues(alpha: alpha),
          ));
          if (faded) continue;

          arrows.addAll(arrowMarkers(seg.points, color, hollow: leg.isReturn));

          if (seg.isRide) {
            for (final stop in seg.stops) {
              rideStops.add(Marker(
                point: stop.latLng,
                width: 11,
                height: 11,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 2.5),
                  ),
                ),
              ));
            }
          }

          // 步行只在整段都是步行時放徽章，搭車前後的短步行不放，避免太亂
          final showBadge = seg.mode != '轉乘' && (seg.mode != '步行' || option.mode == '步行');
          if (showBadge) {
            badges.add(Marker(
              point: midpoint(seg.points),
              width: 140,
              height: 30,
              child: Center(child: ModeBadge(mode: seg.mode, color: color, label: seg.isRide ? seg.routeName : null)),
            ));
          }
        }
      }
    }

    final stops = plan?.stops.map((s) => (s.point, s.name)).toList() ??
        _targets.map((p) => (p.latLng, p.name ?? '')).toList();
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final showNearby = !_isoMode && _nearby.isNotEmpty;

    return Stack(children: [
      FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: const LatLng(24.1477, 120.6736),
          initialZoom: 13,
          interactionOptions: mapInteraction,
          onTap: (_, point) {
            if (_pickingStart) {
              _setStart(PlacePoint(lat: point.latitude, lng: point.longitude, name: '自選起點'));
            } else if (_isoMode) {
              _setIsoCenter(point);
            } else if (_selectedPlace != null) {
              setState(() => _selectedPlace = null);
            }
          },
        ),
        children: [
          treasureTiles(),
          if (_isoMode) isochroneLayer(_iso, faded: plan != null),
          // 捷運路網（淡色背景）
          PolylineLayer(polylines: [
            for (final line in _metroLines)
              for (final part in line.shape)
                Polyline(points: part, color: line.color.withValues(alpha: plan == null ? 0.55 : 0.25), strokeWidth: 4),
          ]),
          if (plan == null)
            MarkerLayer(markers: [
              for (final line in _metroLines)
                for (final st in line.stations)
                  Marker(
                    point: st.point,
                    width: 10,
                    height: 10,
                    child: Tooltip(
                      message: '${line.systemName} ${line.lineName}「${st.name}」站',
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: line.color, width: 2.5),
                        ),
                      ),
                    ),
                  ),
            ]),
          PolylineLayer(polylines: routeLines),
          MarkerLayer(markers: rideStops),
          MarkerLayer(markers: arrows),
          MarkerLayer(markers: badges),
          MarkerLayer(markers: [for (final p in _visibleNearby) _nearbyMarker(p)]),
          MarkerLayer(markers: [
            for (var i = 0; i < stops.length; i++) sealMarker(stops[i].$1, '${i + 1}', label: stops[i].$2),
            if (_start != null) sealMarker(_start!.latLng, '起', label: _start!.name, color: Pal.ink),
          ]),
          osmAttribution(),
        ],
      ),
      Positioned(left: 12, top: 12, child: _legend()),
      if (showNearby) Positioned(top: 12, right: 12, child: _nearbyFilter()),
      if (!_isoMode && _selectedPlace != null)
        Positioned(
          left: 12,
          right: 12,
          top: wide ? null : 56,
          bottom: wide ? 28 : null,
          child: Align(
            alignment: wide ? Alignment.bottomLeft : Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: PlaceTicket(
                place: _selectedPlace!,
                nearest: _nearest[_selectedPlace!.placeId],
                onClose: () => setState(() => _selectedPlace = null),
              ),
            ),
          ),
        ),
      if (_pickingStart || (_isoMode && _iso.result == null))
        Positioned(
          top: showNearby ? 56 : 12,
          right: 12,
          child: Material(
            color: Pal.cinnabar,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(_pickingStart ? '點地圖設定起點' : '點地圖設定同心圓中心',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
    ]);
  }

  /// 周邊好去的地點標記：飲食是金色刀叉、其他是綠色相機，選中的放大加深色框
  Marker _nearbyMarker(NearbyPlace p) {
    final selected = _selectedPlace?.placeId == p.placeId;
    final size = selected ? 32.0 : 26.0;
    return Marker(
      point: p.point!,
      width: size,
      height: size,
      child: GestureDetector(
        onTap: () => setState(() => _selectedPlace = selected ? null : p),
        child: Tooltip(
          message: p.name,
          child: _nearbyIcon(p.isFood, size: size, selected: selected),
        ),
      ),
    );
  }

  static Widget _nearbyIcon(bool food, {double size = 26, bool selected = false}) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: food ? Pal.gold : Pal.moss,
          borderRadius: BorderRadius.circular(size * 0.28),
          border: Border.all(color: selected ? Pal.ink : Colors.white, width: selected ? 2.5 : 2),
          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 3)],
        ),
        child: Icon(food ? Icons.restaurant : Icons.local_see, size: size * 0.58, color: Colors.white),
      );

  /// 地圖右上的周邊好去篩選：飲食／周邊好去（全部）／其他，再點一次選中的就隱藏
  Widget _nearbyFilter() {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < _nearbyTabs.length; i++) ...[
        if (i > 0) const SizedBox(width: 4),
        Tooltip(
          message: _nearbyTab == i ? '再點一次隱藏周邊地點' : '顯示周邊的${_nearbyTabs[i]}',
          child: Material(
            color: _nearbyTab == i ? const Color(0xFFDCC79A) : const Color(0xF2EFE5CB),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: BorderSide(color: _nearbyTab == i ? Pal.ink : PlaceTicket.frame, width: _nearbyTab == i ? 1.8 : 1.3),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => setState(() {
                _nearbyTab = _nearbyTab == i ? null : i;
                _selectedPlace = null;
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: Text(_nearbyTabs[i], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Pal.ink)),
              ),
            ),
          ),
        ),
      ],
    ]);
  }

  /// 圖例：各交通方式的線型 + 去程/返程箭頭。手機上預設收起（展開會蓋掉快一半的地圖），點一下切換。
  Widget _legend() {
    final open = _legendOpen ?? MediaQuery.sizeOf(context).width >= 900;
    return Material(
      color: const Color(0xEEF3E4C1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Pal.inkSoft)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _legendOpen = !open),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.legend_toggle, size: 14, color: Pal.ink),
              const Text(' 圖例', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Pal.ink)),
              Icon(open ? Icons.expand_less : Icons.expand_more, size: 16, color: Pal.ink),
            ]),
            if (open) ...[
              const SizedBox(height: 4),
              for (final mode in allModes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1.5),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(modeStyle(mode).icon, size: 14, color: modeStyle(mode).color),
                    const SizedBox(width: 4),
                    SizedBox(width: 34, height: 8, child: CustomPaint(painter: _LineSample(modeStyle(mode)))),
                    const SizedBox(width: 4),
                    Text(mode, style: const TextStyle(fontSize: 11, color: Pal.ink)),
                  ]),
                ),
              const Divider(height: 8),
              const Row(mainAxisSize: MainAxisSize.min, children: [
                ArrowIcon(color: Pal.ink, degrees: 90, size: 16),
                Text(' 去程   ', style: TextStyle(fontSize: 11)),
                ArrowIcon(color: Pal.ink, degrees: 90, size: 16, hollow: true),
                Text(' 返程', style: TextStyle(fontSize: 11)),
              ]),
              if (!_isoMode && _nearby.isNotEmpty) ...[
                const Divider(height: 8),
                for (final (food, label) in const [(true, '周邊飲食'), (false, '周邊景點・其他')])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1.5),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      _nearbyIcon(food, size: 16),
                      Text(' $label', style: const TextStyle(fontSize: 11, color: Pal.ink)),
                    ]),
                  ),
              ],
            ],
          ]),
        ),
      ),
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
        _sectionTitle('要去的地方', trailing: _isoMode
            ? null
            : IconButton(
                tooltip: '重新載入劇本',
                icon: _loadingStories
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh, size: 20),
                onPressed: _loadingStories ? null : _loadStories,
              )),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, icon: Icon(Icons.menu_book), label: Text('劇本')),
            ButtonSegment(value: true, icon: Icon(Icons.radar), label: Text('同心圓')),
          ],
          selected: {_isoMode},
          onSelectionChanged: (s) => _setIsoMode(s.first),
        ),
        const SizedBox(height: 10),
        if (_isoMode)
          IsochroneControls(
            iso: _iso,
            onSearch: _drawIsochrone,
            onShowPoint: (p) => _map.move(p, 16),
          )
        else
          DropdownButtonFormField<int>(
            initialValue: _story?.storyId,
            key: ValueKey(_story?.storyId),
            isExpanded: true,
            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
            hint: Text(_loadingStories ? '載入中…' : '沒有劇本，請先匯入測試資料'),
            items: [
              for (final s in _stories)
                DropdownMenuItem(
                  value: s.storyId,
                  child: Text('${s.title}（${s.city}${s.district}・${s.nodes.length} 站）', overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (id) => _selectStory(_stories.firstWhere((s) => s.storyId == id)),
          ),
        const SizedBox(height: 12),
        _sectionTitle('起點'),
        Row(children: [
          const Icon(Icons.flag, color: Pal.ink, size: 20),
          const SizedBox(width: 6),
          Expanded(child: Text(_start?.name ?? '尚未設定（預設用劇本建議起點）', style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 6, children: [
          OutlinedButton.icon(
            onPressed: () => setState(() {
              _pickingStart = !_pickingStart;
              _selectedPlace = null;
            }),
            icon: Icon(_pickingStart ? Icons.close : Icons.touch_app, size: 18),
            label: Text(_pickingStart ? '取消選取' : '點地圖選起點'),
          ),
          OutlinedButton.icon(onPressed: _useMyLocation, icon: const Icon(Icons.my_location, size: 18), label: const Text('我的位置')),
          if (!_isoMode && _story?.suggestedStart != null)
            TextButton(onPressed: () => _setStart(_story!.suggestedStart!), child: const Text('用建議起點')),
        ]),
        const SizedBox(height: 12),
        _sectionTitle('交通方式', trailing: _checking
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : null),
        _modeChips(),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _includeReturn,
          onChanged: (v) => setState(() => _includeReturn = v),
          title: const Text('規劃返程（最後一站回到起點）'),
        ),
        FilledButton.icon(
          onPressed: _planning || _targets.isEmpty ? null : _planRoute,
          icon: _planning
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.route),
          label: Text(_planning ? '規劃中…' : '規劃交通路線'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
        ),
        if (_plan != null) ..._planResult(_plan!),
      ],
    );
  }

  Widget _sectionTitle(String text, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Pal.cinnabar, letterSpacing: 1)),
          const SizedBox(width: 6),
          const Expanded(child: Divider(color: Pal.inkSoft)),
          ?trailing,
        ]),
      );

  Widget _modeChips() {
    final disabled = allModes.where((m) => _availability[m]?.enabled == false).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final mode in allModes)
          Tooltip(
            message: _availability[mode]?.reason ?? '',
            child: FilterChip(
              avatar: Icon(
                modeStyle(mode).icon,
                size: 18,
                color: _availability[mode]?.enabled == false ? Pal.disabled : modeStyle(mode).color,
              ),
              label: Text(mode),
              selected: _modes.contains(mode),
              selectedColor: modeStyle(mode).color.withValues(alpha: 0.22),
              showCheckmark: false,
              onSelected: _availability[mode]?.enabled == false
                  ? null
                  : (on) => setState(() {
                        on ? _modes.add(mode) : _modes.remove(mode);
                        if (_modes.isEmpty) _modes.add('步行');
                      }),
            ),
          ),
      ]),
      for (final mode in disabled)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('・$mode：${_availability[mode]!.reason}', style: const TextStyle(fontSize: 12, color: Pal.inkSoft)),
        ),
    ]);
  }

  List<Widget> _planResult(RoutePlan plan) {
    double outbound = 0, back = 0, km = 0;
    for (var i = 0; i < plan.legs.length; i++) {
      final o = _optionOf(i);
      if (plan.legs[i].isReturn) {
        back += o.minutes;
      } else {
        outbound += o.minutes;
      }
      km += o.distanceKm;
    }

    return [
      const SizedBox(height: 16),
      _sectionTitle('規劃結果'),
      Card(
        color: Pal.ink,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(children: [
            // 劇本名稱可能很長，放在卡片裡換行，不跟標題列的分隔線擠同一行
            if (plan.storyTitle != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: Text(plan.storyTitle!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Pal.parchment, fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _stat('去程', '${outbound.ceil()} 分'),
              _stat('返程', back > 0 ? '${back.ceil()} 分' : '—'),
              _stat('總距離', '${km.toStringAsFixed(1)} km'),
            ]),
          ]),
        ),
      ),
      for (final w in plan.warnings)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline, size: 16, color: Pal.gold),
            const SizedBox(width: 4),
            Expanded(child: Text(w, style: const TextStyle(fontSize: 12, color: Pal.inkSoft))),
          ]),
        ),
      const SizedBox(height: 6),
      const Text('點一段路線可以放大查看，並切換其他交通方式', style: TextStyle(fontSize: 12, color: Pal.inkSoft)),
      for (var i = 0; i < plan.legs.length; i++) _legCard(i, plan.legs[i]),
    ];
  }

  Widget _stat(String label, String value) => Column(children: [
        Text(label, style: const TextStyle(color: Pal.parchmentDeep, fontSize: 12)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      ]);

  Color _optionColor(RouteOption o) {
    final metro = o.segments.where((s) => s.mode == '捷運');
    return metro.isNotEmpty ? metro.first.color : modeStyle(o.mode).color;
  }

  Widget _legCard(int index, RouteLeg leg) {
    final option = _optionOf(index);
    final focused = _focusLeg == index;
    final color = _optionColor(option);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: focused ? color : Pal.parchmentDeep, width: focused ? 2.5 : 1.2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => _toggleFocus(index),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
            child: Row(children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: leg.isReturn ? Pal.inkSoft : Pal.cinnabar,
                child: Text('${leg.legOrder}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${leg.fromName} → ${leg.toName}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: leg.isReturn ? Pal.parchmentDeep : Pal.cinnabar.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(leg.direction, style: const TextStyle(fontSize: 11)),
                    ),
                    const SizedBox(width: 6),
                    Expanded(child: Text(option.summary, style: const TextStyle(fontSize: 12, color: Pal.inkSoft))),
                  ]),
                ]),
              ),
              const SizedBox(width: 6),
              Column(children: [
                Icon(modeStyle(option.mode).icon, color: color),
                Text('${option.minutes.ceil()} 分', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
              ]),
            ]),
          ),
        ),
        if (leg.options.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: Wrap(spacing: 6, runSpacing: 4, children: [
              for (var k = 0; k < leg.options.length; k++)
                ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(modeStyle(leg.options[k].mode).icon, size: 16, color: _optionColor(leg.options[k])),
                  label: Text('${leg.options[k].mode} ${leg.options[k].minutes.ceil()} 分'
                      '${k == 0 ? '・最快' : ''}', style: const TextStyle(fontSize: 12)),
                  selected: (_chosen[index] ?? 0) == k,
                  selectedColor: _optionColor(leg.options[k]).withValues(alpha: 0.2),
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _chosen[index] = k),
                ),
            ]),
          ),
        if (focused)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Pal.parchmentDeep))),
            child: Column(children: [for (final seg in option.segments) _segmentRow(seg)]),
          ),
      ]),
    );
  }

  Widget _segmentRow(RouteSegment seg) {
    final style = modeStyle(seg.mode, lineColor: seg.color);
    final color = seg.mode == '捷運' ? seg.color : style.color;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Icon(style.icon, size: 15, color: Colors.white),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(seg.instruction, style: const TextStyle(fontSize: 13)),
            if (seg.waitMinutes > 0)
              Text('候車約 ${seg.waitMinutes.ceil()} 分鐘', style: const TextStyle(fontSize: 11, color: Pal.inkSoft)),
            if (seg.isRide && seg.stops.length > 2)
              Text('經過：${seg.stops.skip(1).take(seg.stops.length - 2).map((s) => s.name).join('、')}',
                  style: const TextStyle(fontSize: 11, color: Pal.inkSoft)),
          ]),
        ),
        Text('${seg.minutes.ceil()} 分', style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}

/// 圖例上的線型樣本
class _LineSample extends CustomPainter {
  _LineSample(this.style);
  final ModeStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = style.color
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    final segments = style.pattern.segments;
    if (style.pattern.spacingFactor != null) {
      for (double x = 2; x < size.width; x += 7) {
        canvas.drawCircle(Offset(x, y), 1.8, paint);
      }
    } else if (segments != null) {
      double x = 0;
      var i = 0;
      while (x < size.width) {
        final len = segments[i % segments.length];
        if (i.isEven) canvas.drawLine(Offset(x, y), Offset((x + len * 0.6).clamp(0, size.width), y), paint);
        x += len * 0.6;
        i++;
      }
    } else {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LineSample oldDelegate) => oldDelegate.style != style;
}
