import 'package:flutter/material.dart';

import 'api.dart';
import 'pages/home_page.dart';
import 'pages/login_page.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.instance.load();
  runApp(const PlayTaiwanDemo());
}

class PlayTaiwanDemo extends StatelessWidget {
  const PlayTaiwanDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Play Taiwan 路線展示',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: ValueListenableBuilder<String?>(
        valueListenable: Api.instance.token,
        builder: (context, token, _) => token == null ? const LoginPage() : const HomePage(),
      ),
    );
  }
}
