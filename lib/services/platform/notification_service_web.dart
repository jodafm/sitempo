import 'dart:js_interop';

import 'package:web/web.dart';

class NotificationService {
  static Future<bool> requestPermission() async {
    final jsResult = await Notification.requestPermission().toDart;
    return jsResult.toDart == 'granted';
  }

  static Future<String> checkPermission() async {
    final permission = Notification.permission;
    switch (permission) {
      case 'granted':
        return 'granted';
      case 'denied':
        return 'denied';
      default:
        return 'notDetermined';
    }
  }

  static Future<void> show({
    required String title,
    String? body,
  }) async {
    final permission = await checkPermission();
    if (permission != 'granted') return;
    Notification(title, NotificationOptions(body: body ?? ''));
  }

  static Future<void> openSystemSettings() async {
    // On web, "open settings" re-prompts the browser permission dialog
    await Notification.requestPermission().toDart;
  }
}
