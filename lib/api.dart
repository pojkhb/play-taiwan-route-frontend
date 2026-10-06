import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 後端回傳 isSuccess = false 或連線失敗時丟出，message 直接顯示給使用者。
class ApiException implements Exception {
  ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 呼叫 Play Taiwan 後端（ASP.NET Core）。回應格式為 { isSuccess, message, Result }。
class Api {
  Api._();
  static final Api instance = Api._();

  /// 登入後的 JWT，null 代表未登入（畫面依這個切換登入頁 / 主頁）
  final ValueNotifier<String?> token = ValueNotifier(null);

  String baseUrl = defaultBaseUrl();
  String? userName;

  /// Android 模擬器連本機要用 10.0.2.2；Windows / 網頁直接用 localhost。
  static String defaultBaseUrl() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:5501';
    }
    return 'http://localhost:5501';
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    baseUrl = prefs.getString('base_url') ?? baseUrl;
    userName = prefs.getString('user_name');
    token.value = prefs.getString('token');
  }

  Future<void> login(String server, String account, String password) async {
    baseUrl = server.trim().replaceAll(RegExp(r'/+$'), '');
    final result = await post('/api/Auth/Login', {'auth_name': account.trim(), 'auth_pswd': password}, auth: false);
    final prefs = await SharedPreferences.getInstance();
    userName = result['auth_name'] as String? ?? account;
    await prefs.setString('base_url', baseUrl);
    await prefs.setString('user_name', userName!);
    await prefs.setString('token', result['token'] as String);
    token.value = result['token'] as String;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    token.value = null;
  }

  Future<dynamic> get(String path, [Map<String, Object?>? query]) async {
    final params = <String, String>{
      for (final e in (query ?? {}).entries)
        if (e.value != null) e.key: '${e.value}',
    };
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: params.isEmpty ? null : params);
    return _send(() => http.get(uri, headers: _headers(true)));
  }

  Future<dynamic> post(String path, Object body, {bool auth = true}) {
    final uri = Uri.parse('$baseUrl$path');
    return _send(() => http.post(uri, headers: _headers(auth), body: jsonEncode(body)));
  }

  Map<String, String> _headers(bool auth) => {
        'Content-Type': 'application/json',
        if (auth && token.value != null) 'Authorization': 'Bearer ${token.value}',
      };

  Future<dynamic> _send(Future<http.Response> Function() request) async {
    http.Response response;
    try {
      response = await request().timeout(const Duration(seconds: 90));
    } catch (e) {
      throw ApiException('連不到後端（$baseUrl），請確認後端有啟動：$e');
    }

    if (response.statusCode == 401) {
      await logout();
      throw ApiException('登入已過期，請重新登入');
    }

    Map<String, dynamic> data;
    try {
      data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('後端回應格式錯誤（HTTP ${response.statusCode}）');
    }

    if (data['isSuccess'] != true) {
      throw ApiException(data['message'] as String? ?? '發生錯誤（HTTP ${response.statusCode}）');
    }
    return data['Result'];
  }
}
