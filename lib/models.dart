import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

double _d(Object? v) => (v as num?)?.toDouble() ?? 0;
int _i(Object? v) => (v as num?)?.toInt() ?? 0;
List<Map<String, dynamic>> _list(Object? v) => ((v as List?) ?? const []).cast<Map<String, dynamic>>();

/// [[經度, 緯度], ...] → LatLng 清單
List<LatLng> parseLine(Object? v) => ((v as List?) ?? const [])
    .map((p) => LatLng(_d((p as List)[1]), _d(p[0])))
    .toList();

/// "#RRGGBB" → Color
Color hexColor(String? hex, [Color fallback = const Color(0xFF757575)]) {
  if (hex == null || hex.isEmpty) return fallback;
  final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
  return value == null ? fallback : Color(0xFF000000 | value);
}

class PlacePoint {
  PlacePoint({required this.lat, required this.lng, this.name});
  final double lat;
  final double lng;
  final String? name;

  LatLng get latLng => LatLng(lat, lng);

  factory PlacePoint.fromJson(Map<String, dynamic> j) =>
      PlacePoint(lat: _d(j['lat']), lng: _d(j['lng']), name: j['name'] as String?);

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng, 'name': name};
}

// ─────────────────────────── 劇本交通路線 ───────────────────────────

class TransportAvailability {
  TransportAvailability.fromJson(Map<String, dynamic> j)
      : mode = j['mode'] as String,
        enabled = j['enabled'] == true,
        reason = j['reason'] as String? ?? '',
        nearestName = j['nearest_name'] as String?;

  final String mode;
  final bool enabled;
  final String reason;
  final String? nearestName;
}

class RouteStopPoint {
  RouteStopPoint.fromJson(Map<String, dynamic> j)
      : snId = j['sn_id'] as int?,
        order = _i(j['order']),
        name = j['name'] as String? ?? '',
        title = j['title'] as String?,
        point = LatLng(_d(j['lat']), _d(j['lng']));

  final int? snId;
  final int order;
  final String name;
  final String? title;
  final LatLng point;
}

class RouteStory {
  RouteStory.fromJson(Map<String, dynamic> j)
      : storyId = _i(j['story_id']),
        title = j['story_title'] as String? ?? '',
        city = j['city_name'] as String? ?? '',
        district = j['district_name'] as String? ?? '',
        suggestedStart = j['suggested_start'] == null ? null : PlacePoint.fromJson(j['suggested_start'] as Map<String, dynamic>),
        nodes = _list(j['nodes']).map(RouteStopPoint.fromJson).toList();

  final int storyId;
  final String title;
  final String city;
  final String district;
  final PlacePoint? suggestedStart;
  final List<RouteStopPoint> nodes;
}

class RouteSegment {
  RouteSegment.fromJson(Map<String, dynamic> j)
      : mode = j['mode'] as String? ?? '步行',
        color = hexColor(j['color'] as String?),
        minutes = _d(j['minutes']),
        waitMinutes = _d(j['wait_minutes']),
        distanceKm = _d(j['distance_km']),
        points = parseLine(j['coordinates']),
        routeName = j['route_name'] as String?,
        routeTypeName = j['route_type_name'] as String?,
        headsign = j['headsign'] as String?,
        boardName = j['board_name'] as String?,
        alightName = j['alight_name'] as String?,
        stopCount = _i(j['stop_count']),
        stops = _list(j['stops']).map(PlacePoint.fromJson).toList(),
        instruction = j['instruction'] as String? ?? '';

  final String mode;
  final Color color;
  final double minutes;
  final double waitMinutes;
  final double distanceKm;
  final List<LatLng> points;
  final String? routeName;
  final String? routeTypeName;
  final String? headsign;
  final String? boardName;
  final String? alightName;
  final int stopCount;
  final List<PlacePoint> stops;
  final String instruction;

  bool get isRide => mode == '公車' || mode == '捷運';
}

class RouteOption {
  RouteOption.fromJson(Map<String, dynamic> j)
      : mode = j['mode'] as String? ?? '',
        minutes = _d(j['minutes']),
        distanceKm = _d(j['distance_km']),
        summary = j['summary'] as String? ?? '',
        isChosen = j['is_chosen'] == true,
        segments = _list(j['segments']).map(RouteSegment.fromJson).toList();

  final String mode;
  final double minutes;
  final double distanceKm;
  final String summary;
  final bool isChosen;
  final List<RouteSegment> segments;
}

class RouteLeg {
  RouteLeg.fromJson(Map<String, dynamic> j)
      : legOrder = _i(j['leg_order']),
        direction = j['direction'] as String? ?? '去程',
        fromName = j['from_name'] as String? ?? '',
        toName = j['to_name'] as String? ?? '',
        options = _list(j['options']).map(RouteOption.fromJson).toList();

  final int legOrder;
  final String direction;
  final String fromName;
  final String toName;

  /// 所有方案，第一個是後端採用的（最快）
  final List<RouteOption> options;

  bool get isReturn => direction == '返程';
}

class RoutePlan {
  RoutePlan.fromJson(Map<String, dynamic> j)
      : storyTitle = j['story_title'] as String?,
        start = PlacePoint.fromJson(j['start'] as Map<String, dynamic>),
        stops = _list(j['stops']).map(RouteStopPoint.fromJson).toList(),
        legs = _list(j['legs']).map(RouteLeg.fromJson).toList(),
        warnings = ((j['warnings'] as List?) ?? const []).cast<String>();

  final String? storyTitle;
  final PlacePoint start;
  final List<RouteStopPoint> stops;
  final List<RouteLeg> legs;
  final List<String> warnings;
}

class MetroStation {
  MetroStation.fromJson(Map<String, dynamic> j)
      : name = j['station_name'] as String? ?? '',
        point = LatLng(_d(j['lat']), _d(j['lng']));

  final String name;
  final LatLng point;
}

class MetroLine {
  MetroLine.fromJson(Map<String, dynamic> j)
      : systemName = j['system_name'] as String? ?? '',
        lineName = j['line_name'] as String? ?? '',
        color = hexColor(j['line_color'] as String?, const Color(0xFF00897B)),
        stations = _list(j['stations']).map(MetroStation.fromJson).toList(),
        shape = ((j['shape'] as List?) ?? const []).map(parseLine).toList();

  final String systemName;
  final String lineName;
  final Color color;
  final List<MetroStation> stations;
  final List<List<LatLng>> shape;
}

// ─────────────────────────── 同心圓（等時圈） ───────────────────────────

class IsoBand {
  IsoBand.fromJson(Map<String, dynamic> j)
      : transport = j['transport'] as String? ?? '',
        minutes = _i(j['minutes']),
        polygons = ((j['polygons'] as List?) ?? const [])
            .map((poly) => (poly as List).map(parseLine).toList())
            .toList();

  final String transport;
  final int minutes;

  /// 每個多邊形：第一個環是外框，其餘是破洞
  final List<List<List<LatLng>>> polygons;
}

class ReachableAttraction {
  ReachableAttraction.fromJson(Map<String, dynamic> j)
      : uid = j['uid'] as String? ?? '',
        name = j['name'] as String? ?? '',
        point = LatLng(_d(j['lat']), _d(j['lon'])),
        travelMinutes = _d(j['travel_minutes']),
        distanceKm = _d(j['travel_distance_km']),
        reachableBy = j['reachable_by'] as String? ?? '',
        ring = _i(j['ring']),
        reachableMinutes = _i(j['reachable_minutes']);

  final String uid;
  final String name;
  final LatLng point;
  final double travelMinutes;
  final double distanceKm;
  final String reachableBy;
  final int ring;
  final int reachableMinutes;
}

class ReachableResult {
  ReachableResult.fromJson(Map<String, dynamic> j)
      : contourMinutes = ((j['contour_minutes'] as List?) ?? const []).map(_i).toList(),
        totalReachable = _i(j['total_reachable']),
        attractions = _list(j['attractions']).map(ReachableAttraction.fromJson).toList(),
        isochrones = _list(j['isochrones']).map(IsoBand.fromJson).toList();

  final List<int> contourMinutes;
  final int totalReachable;
  final List<ReachableAttraction> attractions;
  final List<IsoBand> isochrones;
}

// ─────────────────────────── 周邊好去 ───────────────────────────

class NearbyPlace {
  NearbyPlace.fromJson(Map<String, dynamic> j)
      : placeId = _i(j['place_id']),
        category = j['category'] as String?,
        type = j['type'] as String?,
        name = j['name'] as String? ?? '',
        address = j['address'] as String?,
        openTime = j['open_time'] as String?,
        photoUrls = ((j['photo_urls'] as List?) ?? const []).cast<String>(),
        mapsUrl = j['maps_deeplink_url'] as String?,
        point = _nearbyPoint(j);

  /// 座標；舊版後端沒有 lat/lng 欄位時，從 Google Maps 連結的 query=緯度,經度 取
  static LatLng? _nearbyPoint(Map<String, dynamic> j) {
    if (j['lat'] != null && j['lng'] != null) return LatLng(_d(j['lat']), _d(j['lng']));
    final m = RegExp(r'query=(-?[\d.]+),(-?[\d.]+)').firstMatch(j['maps_deeplink_url'] as String? ?? '');
    return m == null ? null : LatLng(double.parse(m.group(1)!), double.parse(m.group(2)!));
  }

  final int placeId;
  final String? category;
  final String? type;
  final String name;
  final String? address;
  final String? openTime;
  final List<String> photoUrls;
  final String? mapsUrl;
  final LatLng? point;

  bool get isFood => category == '飲食';

  /// 卡片上的分類標籤：資料庫的 Attraction 顯示成「景點」
  String get categoryLabel => switch (category) {
        null || '' => '其他',
        'Attraction' => '景點',
        final c => c,
      };
}

// ─────────────────────────── 公車 ───────────────────────────

class BusRouteBrief {
  BusRouteBrief.fromJson(Map<String, dynamic> j)
      : brId = _i(j['br_id']),
        routeName = j['route_name'] as String? ?? '',
        routeType = _i(j['route_type']);

  final int brId;
  final String routeName;
  final int routeType;

  bool get isTripper => routeType == 3;
}

class BusStopNearby {
  BusStopNearby.fromJson(Map<String, dynamic> j)
      : bsId = _i(j['bs_id']),
        name = j['stop_name'] as String? ?? '',
        point = LatLng(_d(j['lat']), _d(j['lng'])),
        distanceM = _i(j['distance_m']),
        routes = _list(j['routes']).map(BusRouteBrief.fromJson).toList();

  final int bsId;
  final String name;
  final LatLng point;
  final int distanceM;
  final List<BusRouteBrief> routes;
}

class BusArrival {
  BusArrival.fromJson(Map<String, dynamic> j)
      : routeName = j['route_name'] as String? ?? '',
        subRouteName = j['sub_route_name'] as String? ?? '',
        estimateMinutes = j['estimate_minutes'] as int?,
        statusText = j['status_text'] as String? ?? '';

  final String routeName;
  final String subRouteName;
  final int? estimateMinutes;
  final String statusText;
}

class BusPatternStop {
  BusPatternStop.fromJson(Map<String, dynamic> j)
      : sequence = _i(j['stop_sequence']),
        name = j['stop_name'] as String? ?? '',
        point = LatLng(_d(j['lat']), _d(j['lng']));

  final int sequence;
  final String name;
  final LatLng point;
}

class BusPattern {
  BusPattern.fromJson(Map<String, dynamic> j)
      : subRouteName = j['sub_route_name'] as String? ?? '',
        directionName = j['direction_name'] as String? ?? '',
        headsign = j['headsign'] as String?,
        stops = _list(j['stops']).map(BusPatternStop.fromJson).toList(),
        shape = parseLine(j['shape']),
        departures = _list(j['departures'])
            .map((d) => (d['service_days'] as String? ?? '', ((d['times'] as List?) ?? const []).cast<String>()))
            .toList();

  final String subRouteName;
  final String directionName;
  final String? headsign;
  final List<BusPatternStop> stops;
  final List<LatLng> shape;
  final List<(String, List<String>)> departures;

  /// 線形沒有資料時用站牌連線
  List<LatLng> get line => shape.length >= 2 ? shape : stops.map((s) => s.point).toList();
}

class BusRouteDetail {
  BusRouteDetail.fromJson(Map<String, dynamic> j)
      : routeName = j['route_name'] as String? ?? '',
        routeTypeName = j['route_type_name'] as String? ?? '',
        cityName = j['city_name'] as String?,
        departure = j['departure_stop_name'] as String?,
        destination = j['destination_stop_name'] as String?,
        fareDesc = j['fare_desc'] as String?,
        headwayDesc = j['headway_desc'] as String?,
        tripperTheme = (j['tripper'] as Map<String, dynamic>?)?['theme'] as String?,
        patterns = _list(j['patterns']).map(BusPattern.fromJson).toList();

  final String routeName;
  final String routeTypeName;
  final String? cityName;
  final String? departure;
  final String? destination;
  final String? fareDesc;
  final String? headwayDesc;
  final String? tripperTheme;
  final List<BusPattern> patterns;
}

class TaiwanTripRoute {
  TaiwanTripRoute.fromJson(Map<String, dynamic> j)
      : brId = _i(j['br_id']),
        routeName = j['route_name'] as String? ?? '',
        cityName = j['city_name'] as String? ?? '',
        departure = j['departure_stop_name'] as String? ?? '',
        destination = j['destination_stop_name'] as String? ?? '',
        theme = j['theme'] as String?,
        stopCount = _i(j['stop_count']);

  final int brId;
  final String routeName;
  final String cityName;
  final String departure;
  final String destination;
  final String? theme;
  final int stopCount;
}
