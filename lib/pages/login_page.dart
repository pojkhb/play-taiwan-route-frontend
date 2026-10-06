import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _server = TextEditingController(text: Api.instance.baseUrl);
  final _account = TextEditingController(text: Api.instance.userName ?? '');
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _login() async {
    if (_account.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = '請輸入帳號與密碼');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Api.instance.login(_server.text, _account.text, _password.text);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Pal.ink,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 380),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Pal.parchment,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Pal.gold, width: 3),
              boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 24)],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.explore, size: 56, color: Pal.cinnabar),
                const SizedBox(height: 8),
                const Text('Play Taiwan 尋寶地圖',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Pal.ink, letterSpacing: 2)),
                const SizedBox(height: 4),
                const Text('劇本交通路線・同心圓・公車捷運', textAlign: TextAlign.center, style: TextStyle(color: Pal.inkSoft)),
                const SizedBox(height: 20),
                TextField(
                  controller: _server,
                  decoration: const InputDecoration(labelText: '後端網址', prefixIcon: Icon(Icons.dns_outlined)),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _account,
                  decoration: const InputDecoration(labelText: '帳號（名稱或信箱）', prefixIcon: Icon(Icons.person_outline)),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _password,
                  obscureText: true,
                  onSubmitted: (_) => _login(),
                  decoration: const InputDecoration(labelText: '密碼', prefixIcon: Icon(Icons.lock_outline)),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Pal.cinnabar)),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _loading ? null : _login,
                  icon: _loading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.login),
                  label: const Text('登入出發'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
