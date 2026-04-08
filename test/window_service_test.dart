import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitempo/services/window_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.sitempo/statusbar');

  group('WindowService.bringToFront()', () {
    late List<MethodCall> log;

    setUp(() {
      log = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        log.add(call);
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    // AC-F4-window-1: bringToFront invokes "bringToFront" on com.sitempo/statusbar
    test('invokes "bringToFront" method on the statusbar channel', () async {
      await WindowService.bringToFront();

      expect(log.length, 1);
      expect(log.first.method, 'bringToFront');
    });
  });
}
