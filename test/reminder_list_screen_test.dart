import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:sitempo/screens/reminder_list_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const notificationsChannel = MethodChannel('com.sitempo/notifications');

  void setPermissionResponse(String status) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, (call) async {
      if (call.method == 'checkPermission') return status;
      return null;
    });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, null);
  });

  Widget buildScreen() {
    return const MaterialApp(
      home: ReminderListScreen(reminders: []),
    );
  }

  group('ReminderListScreen permission banner', () {
    testWidgets('no banner when permission is "granted"', (tester) async {
      setPermissionResponse('granted');
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Las notificaciones están desactivadas'), findsNothing);
      expect(find.text('Activar'), findsNothing);
    });

    testWidgets('shows banner with text and Activar button when "denied"',
        (tester) async {
      setPermissionResponse('denied');
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(
          find.text('Las notificaciones están desactivadas'), findsOneWidget);
      expect(find.text('Activar'), findsOneWidget);
    });

    testWidgets('no banner when permission is "notDetermined"', (tester) async {
      setPermissionResponse('notDetermined');
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Las notificaciones están desactivadas'), findsNothing);
      expect(find.text('Activar'), findsNothing);
    });
  });
}
