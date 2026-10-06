import 'package:flutter/foundation.dart';

/// 分頁之間共用的狀態：目前的分頁。
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState instance = AppState._();

  int tab = 0;

  void goTab(int index) {
    tab = index;
    notifyListeners();
  }
}
