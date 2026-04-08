import 'package:flutter/services.dart';

class NotificationService {
  static const _channel = MethodChannel('com.sitempo/notifications');

  static Future<bool> requestPermission() async {
    final result = await _channel.invokeMethod<bool>('requestPermission');
    return result ?? false;
  }

  static Future<String> checkPermission() async {
    try {
      final result = await _channel.invokeMethod<String>('checkPermission');
      return result ?? 'notDetermined';
    } catch (_) {
      return 'notDetermined';
    }
  }

  static Future<void> show({
    required String title,
    String? body,
  }) async {
    await _channel.invokeMethod('show', {
      'title': title,
      'body': body ?? '',
    });
  }
}
