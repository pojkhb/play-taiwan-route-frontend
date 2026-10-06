import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:play_taiwan_demo/models.dart';
import 'package:play_taiwan_demo/widgets/map_kit.dart';

void main() {
  test('後端座標 [經度, 緯度] 轉成 LatLng', () {
    final line = parseLine([
      [120.6869, 24.1372],
      [120.6784, 24.1386],
    ]);
    expect(line.first.latitude, 24.1372);
    expect(line.first.longitude, 120.6869);
  });

  test('往東走的方位角約 90 度', () {
    final deg = bearing(const LatLng(24.0, 120.0), const LatLng(24.0, 120.01));
    expect(deg, closeTo(90, 0.5));
  });

  test('沿線放箭頭：長路線多個、短路線不放', () {
    final long = [const LatLng(24.0, 120.0), const LatLng(24.0, 120.02)];
    final short = [const LatLng(24.0, 120.0), const LatLng(24.0, 120.0001)];
    expect(arrowMarkers(long, const Color(0xFF000000)).length, greaterThan(1));
    expect(arrowMarkers(short, const Color(0xFF000000)), isEmpty);
  });
}
