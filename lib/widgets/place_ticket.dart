import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../theme.dart';

/// 周邊好去的票券卡片：雙線框、右邊一條票根，票根分隔線頂端有一個圓孔。
/// 點地圖上的周邊地點時浮在地圖上，票根上的 × 關閉。
class PlaceTicket extends StatelessWidget {
  const PlaceTicket({super.key, required this.place, this.nearest, this.onClose});

  final NearbyPlace place;

  /// 最近的劇本節點與距離（公尺）
  final (RouteStopPoint, double)? nearest;
  final VoidCallback? onClose;

  static const frame = Color(0xFFA88D62);
  static const paper = Color(0xFFEFE5CB);
  static const card = Color(0xFFEBDFC0);
  static const _photoBg = Color(0xFFE0D0A8);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: frame, width: 2),
            boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 10, offset: Offset(0, 3))],
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: frame.withValues(alpha: 0.7)),
            ),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(10, 8, 8, 8), child: _content(context))),
                Container(
                  width: 5,
                  decoration: BoxDecoration(border: Border.symmetric(vertical: BorderSide(color: frame.withValues(alpha: 0.8)))),
                ),
                SizedBox(
                  width: 30,
                  child: onClose == null
                      ? null
                      : Align(
                          alignment: Alignment.bottomCenter,
                          child: IconButton(
                            tooltip: '關閉',
                            onPressed: onClose,
                            icon: const Icon(Icons.close, size: 18, color: Pal.inkSoft),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                          ),
                        ),
                ),
              ]),
            ),
          ),
        ),
        Positioned(
          top: -9,
          right: 29,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(color: paper, shape: BoxShape.circle, border: Border.all(color: frame, width: 2)),
          ),
        ),
      ]),
    );
  }

  Widget _content(BuildContext context) {
    final near = nearest;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(place.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Pal.cinnabar, height: 1.25)),
      const SizedBox(height: 2),
      Text.rich(TextSpan(children: [
        TextSpan(
          text: place.openTime ?? '營業時間未提供',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Pal.ink),
        ),
        if (near != null)
          TextSpan(
            text: '・距「${near.$1.name}」${_formatMeters(near.$2)}',
            style: const TextStyle(fontSize: 11, color: Pal.inkSoft),
          ),
      ])),
      const SizedBox(height: 8),
      // 沒有照片時放兩個空框；只有一張時放大一點，不留空位
      Row(children: [
        if (place.photoUrls.isEmpty)
          for (var i = 0; i < 2; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            _photo(null),
          ]
        else if (place.photoUrls.length == 1)
          _photo(place.photoUrls.first, width: 168, height: 104)
        else
          for (var i = 0; i < 2; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            _photo(place.photoUrls[i]),
          ],
      ]),
      if (place.photoUrls.any(_isCommons)) _commonsCredit(context, place.photoUrls.firstWhere(_isCommons)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: Wrap(spacing: 6, runSpacing: 4, children: [
            _chip(place.categoryLabel),
            if (place.type != null && place.type!.isNotEmpty) _chip(place.type!),
          ]),
        ),
        if (place.mapsUrl != null) _goButton(context, place.mapsUrl!),
      ]),
    ]);
  }

  static bool _isCommons(String url) => url.contains('wikimedia.org/wikipedia/commons/');

  /// Commons 縮圖網址 …/commons/thumb/a/ab/檔名/960px-檔名 → 檔案頁（上面有作者與授權）
  static String _commonsFilePage(String url) {
    final segments = Uri.parse(url).pathSegments;
    final i = segments.indexOf('thumb');
    final file = i >= 0 && segments.length > i + 3 ? segments[i + 3] : segments.last;
    return 'https://commons.wikimedia.org/wiki/File:$file';
  }

  /// 照片來自 Wikimedia Commons（CC 授權需要標示出處），點了開檔案頁看作者與授權
  Widget _commonsCredit(BuildContext context, String url) => InkWell(
        onTap: () => launchUrl(Uri.parse(_commonsFilePage(url)), mode: LaunchMode.externalApplication),
        child: const Padding(
          padding: EdgeInsets.only(top: 3),
          child: Text('照片：Wikimedia Commons（點此看作者與授權）', style: TextStyle(fontSize: 10, color: Pal.inkSoft)),
        ),
      );

  Widget _photo(String? url, {double width = 92, double height = 64}) {
    const placeholder = Icon(Icons.image_outlined, color: frame, size: 22);
    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _photoBg,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: frame.withValues(alpha: 0.5)),
      ),
      child: url == null ? placeholder : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder),
    );
  }

  Widget _chip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        decoration: BoxDecoration(
          color: paper,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: frame, width: 1.2),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12, color: Pal.ink)),
      );

  Widget _goButton(BuildContext context, String url) => InkWell(
        onTap: () async {
          final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          if (!ok && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('無法開啟地圖')));
          }
        },
        borderRadius: BorderRadius.circular(4),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('前往地址', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Pal.cinnabar)),
            SizedBox(width: 3),
            Icon(Icons.near_me_outlined, size: 14, color: Pal.cinnabar),
          ]),
        ),
      );

  static String _formatMeters(double m) => m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';
}
