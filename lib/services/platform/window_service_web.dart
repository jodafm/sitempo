import 'package:web/web.dart' as web;

class WindowService {
  static Future<void> bringToFront() async {
    try {
      web.window.focus();
    } catch (_) {
      // Best effort — browsers may block window.focus() without user gesture
    }
  }
}
