import 'package:flutter/material.dart';

import '../api.dart';
import '../app_state.dart';
import 'bus_page.dart';
import 'route_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static const _tabs = [
    (Icons.alt_route, '劇本交通路線'),
    (Icons.directions_bus, '公車站牌'),
  ];

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    final user = Api.instance.userName;
    // 手機寬度：標題只放分頁名稱，帳號收進登出按鈕的提示，AppBar 才放得下
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Row(children: [
            const Icon(Icons.explore),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                narrow ? _tabs[state.tab].$2 : 'Play Taiwan・${_tabs[state.tab].$2}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
          actions: [
            if (user != null && !narrow)
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(user, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                ),
              ),
            IconButton(
              tooltip: user == null ? '登出' : '登出（$user）',
              icon: const Icon(Icons.logout),
              onPressed: () => Api.instance.logout(),
            ),
          ],
        ),
        body: IndexedStack(
          index: state.tab,
          children: const [RoutePage(), BusPage()],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: state.tab,
          onDestinationSelected: state.goTab,
          destinations: [for (final t in _tabs) NavigationDestination(icon: Icon(t.$1), label: t.$2)],
        ),
      ),
    );
  }
}
