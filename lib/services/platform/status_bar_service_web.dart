import 'package:web/web.dart' as web;

class StatusBarService {
  static Future<void> update({
    required String time,
    required String emoji,
  }) async {
    web.document.title = '$emoji $time — sitempo';
  }

  static Future<void> clear() async {
    web.document.title = 'sitempo';
  }
}
