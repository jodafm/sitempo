import 'package:flutter/services.dart';

class WindowService {
  static const _channel = MethodChannel('com.sitempo/statusbar');

  static Future<void> bringToFront() async {
    await _channel.invokeMethod('bringToFront');
  }
}
