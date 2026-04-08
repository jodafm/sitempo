import 'package:flutter/services.dart';

class StatusBarService {
  static const _channel = MethodChannel('com.sitempo/statusbar');

  static Future<void> update({
    required String time,
    required String emoji,
  }) async {
    await _channel.invokeMethod('update', {
      'time': time,
      'emoji': emoji,
    });
  }

  static Future<void> clear() async {
    await _channel.invokeMethod('clear');
  }
}
