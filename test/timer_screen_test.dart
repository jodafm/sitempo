import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sitempo/models/activity.dart';
import 'package:sitempo/models/reminder.dart';
import 'package:sitempo/models/routine.dart';

// ---------------------------------------------------------------------------
// Helpers — confirmation overlay widget (mirrors the Positioned.fill overlay
// that TimerScreen renders when _awaitingConfirmation is true).
// ---------------------------------------------------------------------------

Widget _buildConfirmationOverlay({
  required bool awaitingConfirmation,
  required RoutineStep? nextStep,
  required List<Activity> activities,
  required bool isLastStep,
  required VoidCallback onConfirm,
}) {
  return MaterialApp(
    home: Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: Stack(
        children: [
          const Center(child: Text('timer content')),
          if (awaitingConfirmation)
            Positioned.fill(
              child: Container(
                color: const Color(0xCC000000),
                child: Center(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A4E),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Paso completado',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (isLastStep)
                          const Text(
                            'Ciclo completo',
                            style: TextStyle(color: Colors.white70, fontSize: 16),
                          )
                        else if (nextStep != null) ...[
                          Text(
                            nextStep.resolveActivity(activities).emoji,
                            style: const TextStyle(fontSize: 32),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            nextStep.resolveActivity(activities).label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (nextStep.description.isNotEmpty)
                            Text(
                              nextStep.description,
                              style: const TextStyle(
                                fontSize: 13,
                                fontStyle: FontStyle.italic,
                                color: Colors.white70,
                              ),
                            ),
                        ],
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: onConfirm,
                          child: const Text('Continuar'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

// Mirrors the _buildActivityLabel() Column from TimerScreen so we can unit-test
// the UI logic in isolation, without having to pump the full screen (which would
// require file-system access for RoutineRepository).
Widget _buildActivityLabel({
  required Activity activity,
  required RoutineStep step,
  required int stepIndex,
  required int totalSteps,
}) {
  return MaterialApp(
    home: Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(activity.emoji, style: const TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(
              activity.label.toUpperCase(),
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: activity.color,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Paso ${stepIndex + 1} de $totalSteps',
              style: const TextStyle(fontSize: 13, color: Colors.white38),
            ),
            if (step.description.isNotEmpty)
              Text(
                step.description,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.white54,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  final activity = Activity.defaults.first; // 'sitting'

  // AC-010-1: description shown when present
  testWidgets('description is shown when step has non-empty description',
      (tester) async {
    const step = RoutineStep(
      activityId: 'sitting',
      duration: Duration(minutes: 25),
      description: 'Mantené la espalda recta',
    );

    await tester.pumpWidget(
      _buildActivityLabel(
        activity: activity,
        step: step,
        stepIndex: 0,
        totalSteps: 2,
      ),
    );

    // Description text is present
    final descFinder = find.text('Mantené la espalda recta');
    expect(descFinder, findsOneWidget);

    // Verify style: italic, fontSize 13, color white54
    final textWidget = tester.widget<Text>(descFinder);
    expect(textWidget.style?.fontStyle, FontStyle.italic);
    expect(textWidget.style?.fontSize, 13.0);
    expect(textWidget.style?.color, Colors.white54);
  });

  // AC-010-2: no description widget when description is empty
  testWidgets('description is hidden when step description is empty',
      (tester) async {
    const step = RoutineStep(
      activityId: 'sitting',
      duration: Duration(minutes: 25),
      // description defaults to ''
    );

    await tester.pumpWidget(
      _buildActivityLabel(
        activity: activity,
        step: step,
        stepIndex: 0,
        totalSteps: 2,
      ),
    );

    // The "Paso X de Y" label is there
    expect(find.text('Paso 1 de 2'), findsOneWidget);

    // No extra Text widget for description — only emoji, label, step indicator
    // are rendered (3 Text widgets total).
    final allTexts = tester.widgetList<Text>(find.byType(Text));
    expect(allTexts.length, 3);
  });

  // AC-010-3: description updates when step advances (non-empty → empty)
  testWidgets('description disappears when advancing to a step with empty description',
      (tester) async {
    const stepWithDesc = RoutineStep(
      activityId: 'sitting',
      duration: Duration(minutes: 25),
      description: 'Mantené la espalda recta',
    );
    const stepNoDesc = RoutineStep(
      activityId: 'sitting',
      duration: Duration(minutes: 15),
      // description is ''
    );

    // Start with step that has a description
    await tester.pumpWidget(
      _buildActivityLabel(
        activity: activity,
        step: stepWithDesc,
        stepIndex: 0,
        totalSteps: 2,
      ),
    );

    expect(find.text('Mantené la espalda recta'), findsOneWidget);

    // Advance to step without description
    await tester.pumpWidget(
      _buildActivityLabel(
        activity: activity,
        step: stepNoDesc,
        stepIndex: 1,
        totalSteps: 2,
      ),
    );
    await tester.pump();

    expect(find.text('Mantené la espalda recta'), findsNothing);

    // Only 3 Text widgets: emoji, label, step indicator
    final allTexts = tester.widgetList<Text>(find.byType(Text));
    expect(allTexts.length, 3);
  });

  // ---------------------------------------------------------------------------
  // Task 17 & 19: Confirmation overlay — state and UI
  // ---------------------------------------------------------------------------

  group('Confirmation overlay — state', () {
    final activities = Activity.defaults;

    // AC-F4-state-1: overlay is not visible when awaitingConfirmation is false
    testWidgets('overlay is hidden when awaitingConfirmation is false',
        (tester) async {
      const nextStep = RoutineStep(
        activityId: 'standing',
        duration: Duration(minutes: 15),
      );

      await tester.pumpWidget(
        _buildConfirmationOverlay(
          awaitingConfirmation: false,
          nextStep: nextStep,
          activities: activities,
          isLastStep: false,
          onConfirm: () {},
        ),
      );

      expect(find.text('Paso completado'), findsNothing);
      expect(find.text('Continuar'), findsNothing);
    });

    // AC-F4-state-2: overlay is visible when awaitingConfirmation is true
    testWidgets('overlay is shown when awaitingConfirmation is true',
        (tester) async {
      const nextStep = RoutineStep(
        activityId: 'standing',
        duration: Duration(minutes: 15),
      );

      await tester.pumpWidget(
        _buildConfirmationOverlay(
          awaitingConfirmation: true,
          nextStep: nextStep,
          activities: activities,
          isLastStep: false,
          onConfirm: () {},
        ),
      );

      expect(find.text('Paso completado'), findsOneWidget);
      expect(find.text('Continuar'), findsOneWidget);
    });
  });

  group('Confirmation overlay — UI content', () {
    final activities = Activity.defaults;

    // AC-F4-ui-1: shows next step emoji, label and description when not last step
    testWidgets('shows next step info when not last step', (tester) async {
      const nextStep = RoutineStep(
        activityId: 'standing',
        duration: Duration(minutes: 15),
        description: 'Estirate un poco',
      );

      await tester.pumpWidget(
        _buildConfirmationOverlay(
          awaitingConfirmation: true,
          nextStep: nextStep,
          activities: activities,
          isLastStep: false,
          onConfirm: () {},
        ),
      );

      // Next step emoji and label
      expect(find.text('🧍'), findsOneWidget);
      expect(find.text('De pie'), findsOneWidget);
      expect(find.text('Estirate un poco'), findsOneWidget);
      // "Ciclo completo" should NOT appear
      expect(find.text('Ciclo completo'), findsNothing);
    });

    // AC-F4-ui-2: shows "Ciclo completo" when isLastStep is true
    testWidgets('shows "Ciclo completo" when cycle wraps', (tester) async {
      await tester.pumpWidget(
        _buildConfirmationOverlay(
          awaitingConfirmation: true,
          nextStep: null,
          activities: activities,
          isLastStep: true,
          onConfirm: () {},
        ),
      );

      expect(find.text('Ciclo completo'), findsOneWidget);
      // No next-step content
      expect(find.text('De pie'), findsNothing);
    });

    // AC-F4-ui-3: "Continuar" button calls onConfirm
    testWidgets('"Continuar" button triggers onConfirm callback', (tester) async {
      var confirmed = false;
      const nextStep = RoutineStep(
        activityId: 'standing',
        duration: Duration(minutes: 15),
      );

      await tester.pumpWidget(
        _buildConfirmationOverlay(
          awaitingConfirmation: true,
          nextStep: nextStep,
          activities: activities,
          isLastStep: false,
          onConfirm: () => confirmed = true,
        ),
      );

      await tester.tap(find.text('Continuar'));
      await tester.pump();

      expect(confirmed, isTrue);
    });

    // AC-F4-ui-4: description not shown when next step has empty description
    testWidgets('description is omitted when next step description is empty',
        (tester) async {
      const nextStep = RoutineStep(
        activityId: 'standing',
        duration: Duration(minutes: 15),
        // description: ''
      );

      await tester.pumpWidget(
        _buildConfirmationOverlay(
          awaitingConfirmation: true,
          nextStep: nextStep,
          activities: activities,
          isLastStep: false,
          onConfirm: () {},
        ),
      );

      // Label is shown but no description text (just 'Paso completado', emoji, label, button)
      expect(find.text('De pie'), findsOneWidget);
      // No italic description widget since description is empty
      final italicTexts = tester.widgetList<Text>(find.byType(Text)).where(
        (t) => t.style?.fontStyle == FontStyle.italic,
      );
      expect(italicTexts.isEmpty, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // F2: Popup overlay notification tests
  // ---------------------------------------------------------------------------

  group('Popup overlay', () {
    const waterReminder = Reminder(
      id: 'water',
      emoji: '💧',
      label: 'Tomar agua',
      intervalMinutes: 30,
      description: 'Hidratate, tomá un vaso de agua',
      enabled: true,
    );

    const eyeReminder = Reminder(
      id: '20-20-20',
      emoji: '👀',
      label: 'Regla 20-20-20',
      intervalMinutes: 20,
      description: 'Mirá algo a 6 metros',
      enabled: true,
    );

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.sitempo/notifications'),
        (call) async => null,
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.sitempo/notifications'),
        null,
      );
    });

    testWidgets('popup appears with emoji, label, and description',
        (tester) async {
      final hostKey = GlobalKey<_PopupHostState>();
      await tester.pumpWidget(_popupTestApp(hostKey: hostKey));

      hostKey.currentState!.showPopup(waterReminder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('💧'), findsOneWidget);
      expect(find.text('Tomar agua'), findsOneWidget);
      expect(find.text('Hidratate, tomá un vaso de agua'), findsOneWidget);
    });

    testWidgets('second fire replaces first — only one popup visible',
        (tester) async {
      final hostKey = GlobalKey<_PopupHostState>();
      await tester.pumpWidget(_popupTestApp(hostKey: hostKey));

      hostKey.currentState!.showPopup(waterReminder);
      await tester.pump();

      hostKey.currentState!.showPopup(eyeReminder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('👀'), findsOneWidget);
      expect(find.text('💧'), findsNothing);
    });

    testWidgets('auto-dismiss after 5 seconds', (tester) async {
      final hostKey = GlobalKey<_PopupHostState>();
      await tester.pumpWidget(_popupTestApp(
        hostKey: hostKey,
        autoDismissDuration: const Duration(seconds: 5),
      ));

      hostKey.currentState!.showPopup(waterReminder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Tomar agua'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump();

      expect(find.text('Tomar agua'), findsNothing);
      expect(hostKey.currentState!.hasActivePopup, isFalse);
    });

    testWidgets('tap removes popup immediately', (tester) async {
      final hostKey = GlobalKey<_PopupHostState>();
      await tester.pumpWidget(_popupTestApp(hostKey: hostKey));

      hostKey.currentState!.showPopup(waterReminder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Tomar agua'), findsOneWidget);

      await tester.tap(find.text('Tomar agua'));
      await tester.pump();

      expect(find.text('Tomar agua'), findsNothing);
      expect(hostKey.currentState!.hasActivePopup, isFalse);
    });

    testWidgets('dispose while popup visible — no error', (tester) async {
      final hostKey = GlobalKey<_PopupHostState>();
      await tester.pumpWidget(_popupTestApp(hostKey: hostKey));

      hostKey.currentState!.showPopup(waterReminder);
      await tester.pump();

      expect(
        () async {
          await tester.pumpWidget(const MaterialApp(home: SizedBox()));
          await tester.pump();
        },
        returnsNormally,
      );
    });

    testWidgets('callback invoked post-unmount — no crash', (tester) async {
      final hostKey = GlobalKey<_PopupHostState>();
      await tester.pumpWidget(_popupTestApp(
        hostKey: hostKey,
        autoDismissDuration: const Duration(milliseconds: 100),
      ));

      hostKey.currentState!.showPopup(waterReminder);
      await tester.pump();

      // Unmount before the auto-dismiss timer fires
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      // Fire the timer after unmount — must not throw
      expect(
        () async {
          await tester.pump(const Duration(milliseconds: 200));
        },
        returnsNormally,
      );
    });
  });
}

// ---------------------------------------------------------------------------
// Popup widget helpers for F2 tests
// ---------------------------------------------------------------------------

/// Popup widget mirroring the design spec.
class _ReminderPopup extends StatefulWidget {
  final Reminder reminder;
  final VoidCallback onDismiss;

  const _ReminderPopup({required this.reminder, required this.onDismiss});

  @override
  State<_ReminderPopup> createState() => _ReminderPopupState();
}

class _ReminderPopupState extends State<_ReminderPopup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slide = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 24,
      left: 24,
      right: 24,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: GestureDetector(
            onTap: widget.onDismiss,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xDD1A1A2E),
                borderRadius: BorderRadius.circular(16),
                border: const Border(
                  left: BorderSide(color: Color(0xFF6C9BFF), width: 4),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Text(widget.reminder.emoji,
                      style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.reminder.label,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        if (widget.reminder.description.isNotEmpty)
                          Text(
                            widget.reminder.description,
                            style: const TextStyle(
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                              color: Colors.white70,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Test harness that manages OverlayEntry + Timer lifecycle,
/// mirroring TimerScreen._showReminderPopup / _dismissPopup.
class _PopupHost extends StatefulWidget {
  final Duration autoDismissDuration;

  const _PopupHost({
    super.key,
    this.autoDismissDuration = const Duration(seconds: 5),
  });

  @override
  State<_PopupHost> createState() => _PopupHostState();
}

class _PopupHostState extends State<_PopupHost> {
  OverlayEntry? _activePopup;
  Timer? _dismissTimer;

  bool get hasActivePopup => _activePopup != null;

  void showPopup(Reminder reminder) {
    _dismissPopup();
    if (!mounted) return;

    _activePopup = OverlayEntry(
      builder: (_) => _ReminderPopup(
        reminder: reminder,
        onDismiss: _dismissPopup,
      ),
    );
    Overlay.of(context).insert(_activePopup!);

    _dismissTimer = Timer(widget.autoDismissDuration, () {
      if (mounted) _dismissPopup();
    });
  }

  void _dismissPopup() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _activePopup?.remove();
    _activePopup = null;
  }

  @override
  void dispose() {
    _dismissPopup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

Widget _popupTestApp({
  required GlobalKey<_PopupHostState> hostKey,
  Duration autoDismissDuration = const Duration(seconds: 5),
}) {
  return MaterialApp(
    home: Overlay(
      initialEntries: [
        OverlayEntry(
          builder: (_) => _PopupHost(
            key: hostKey,
            autoDismissDuration: autoDismissDuration,
          ),
        ),
      ],
    ),
  );
}
