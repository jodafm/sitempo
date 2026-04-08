import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/activity.dart';
import '../models/reminder.dart';
import '../models/routine.dart';
import '../services/alarm_service.dart';
import '../services/notification_service.dart';
import '../services/reminder_repository.dart';
import '../services/reminder_service.dart';
import '../services/routine_repository.dart';
import '../services/status_bar_service.dart';
import '../services/window_service.dart';
import 'reminder_list_screen.dart';
import 'routine_editor_screen.dart';

class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  List<Routine> _routines = [];
  List<Activity> _activities = [];
  List<Reminder> _reminders = [];
  final ReminderService _reminderService = ReminderService();
  int _selectedRoutineIndex = 0;
  int _currentStepIndex = 0;
  Duration _remaining = Duration.zero;
  DateTime? _targetEnd;
  Timer? _timer;
  bool _isRunning = false;
  int _completedCycles = 0;
  bool _loading = true;
  bool _awaitingConfirmation = false;
  int? _pendingStepIndex;
  bool _pendingIsNewCycle = false;

  // Reminder modal queue
  final List<Reminder> _pendingReminders = [];
  bool _showingReminderModal = false;

  // Notification center
  final List<AppNotification> _notificationLog = [];

  Routine get _routine => _routines[_selectedRoutineIndex];
  List<RoutineStep> get _expandedSteps => _routine.expandedSteps;
  RoutineStep get _currentStep => _expandedSteps[_currentStepIndex];
  Activity get _currentActivity => _currentStep.resolveActivity(_activities);
  double get _progress =>
      1.0 - (_remaining.inSeconds / _currentStep.duration.inSeconds);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      RoutineRepository.loadRoutines(),
      RoutineRepository.loadActivities(),
      ReminderRepository.load(),
    ]);
    final routines = results[0] as List<Routine>;
    final activities = results[1] as List<Activity>;
    final reminders = results[2] as List<Reminder>;

    _reminderService.load(reminders);
    _reminderService.onFire = (reminder) {
      if (!mounted) return;
      _pendingReminders.add(reminder);
      _showNextReminderModal();
    };
    NotificationService.requestPermission();

    setState(() {
      _routines = routines;
      _activities = activities;
      _reminders = reminders;
      _remaining = routines[0].expandedSteps[0].duration;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    _reminderService.onFire = null;
    AlarmService.stopLoopingAlarm();
    super.dispose();
  }

  void _startPause() {
    if (_isRunning) {
      _timer?.cancel();
      // Save remaining for when we resume
      _targetEnd = null;
      setState(() => _isRunning = false);
    } else {
      _targetEnd = DateTime.now().add(_remaining);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      setState(() => _isRunning = true);
      AlarmService.playStart();
    }
  }

  void _tick() {
    _reminderService.tick();
    if (_targetEnd == null) return;
    final now = DateTime.now();
    final diff = _targetEnd!.difference(now);
    if (diff.inSeconds <= 0) {
      _advanceStep();
    } else {
      setState(() => _remaining = diff);
      _updateStatusBar();
    }
  }

  void _advanceStep() {
    final steps = _expandedSteps;
    final nextIndex = _currentStepIndex + 1;
    final isEndOfSequence = nextIndex >= steps.length;

    _timer?.cancel();

    if (_routine.autoAdvance) {
      _playTransitionSound();
      setState(() {
        _currentStepIndex = isEndOfSequence ? 0 : nextIndex;
        _remaining = _currentStep.duration;
        if (isEndOfSequence) _completedCycles++;
        _isRunning = true;
      });
      _targetEnd = DateTime.now().add(_remaining);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      _updateStatusBar();
      return;
    }

    _targetEnd = null;
    setState(() {
      _awaitingConfirmation = true;
      _isRunning = false;
      _pendingStepIndex = isEndOfSequence ? 0 : nextIndex;
      _pendingIsNewCycle = isEndOfSequence;
      _remaining = Duration.zero;
    });

    _startLoopingTransitionSound();
    _pulseController.repeat(reverse: true);
    WindowService.bringToFront();
  }

  void _playTransitionSound() {
    AlarmService.playSoundByName(_routine.transitionSound);
  }

  void _startLoopingTransitionSound() {
    AlarmService.stopLoopingAlarm();
    final path = AlarmService.resolveSoundPath(_routine.transitionSound);
    AlarmService.startLoopingAlarmWithPath(path);
  }

  void _confirmTransition() {
    AlarmService.stopLoopingAlarm();
    _pulseController.stop();
    _pulseController.reset();
    _playTransitionSound();

    setState(() {
      _currentStepIndex = _pendingStepIndex!;
      _remaining = _currentStep.duration;
      if (_pendingIsNewCycle) _completedCycles++;
      _awaitingConfirmation = false;
      _pendingStepIndex = null;
      _pendingIsNewCycle = false;
      _isRunning = true;
    });

    _targetEnd = DateTime.now().add(_remaining);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _updateStatusBar();
  }

  void _reset() {
    _timer?.cancel();
    _targetEnd = null;
    AlarmService.stopLoopingAlarm();
    _pulseController.stop();
    _pulseController.reset();
    _reminderService.reset();
    setState(() {
      _isRunning = false;
      _awaitingConfirmation = false;
      _pendingStepIndex = null;
      _pendingIsNewCycle = false;
      _currentStepIndex = 0;
      _remaining = _expandedSteps[0].duration;
      _completedCycles = 0;
    });
    StatusBarService.clear();
  }

  void _selectRoutine(int index) {
    _timer?.cancel();
    _targetEnd = null;
    setState(() {
      _selectedRoutineIndex = index;
      _isRunning = false;
      _currentStepIndex = 0;
      _remaining = _routines[index].expandedSteps[0].duration;
      _completedCycles = 0;
    });
    StatusBarService.clear();
  }

  void _updateStatusBar() {
    StatusBarService.update(
      time: _formatDuration(_remaining),
      emoji: _currentActivity.emoji,
    );
  }

  void _onActivityCreated(Activity activity) {
    setState(() => _activities.add(activity));
    RoutineRepository.saveActivities(_activities);
  }

  Future<void> _openEditor({Routine? routine}) async {
    final result = await Navigator.of(context).push<Routine>(
      MaterialPageRoute(
        builder: (_) => RoutineEditorScreen(
          routine: routine,
          activities: _activities,
          onActivityCreated: _onActivityCreated,
        ),
      ),
    );
    if (result == null) return;

    final existingIndex = _routines.indexWhere((r) => r.id == result.id);
    setState(() {
      if (existingIndex >= 0) {
        _routines[existingIndex] = result;
        if (_selectedRoutineIndex == existingIndex) {
          _currentStepIndex = 0;
          _remaining = result.expandedSteps[0].duration;
        }
      } else {
        _routines.add(result);
      }
    });
    await RoutineRepository.saveRoutines(_routines);
  }

  Future<void> _deleteRoutine(int index) async {
    if (_routines[index].isDefault) return;

    final wasSelected = _selectedRoutineIndex == index;
    setState(() {
      _routines.removeAt(index);
      if (_selectedRoutineIndex >= _routines.length) {
        _selectedRoutineIndex = 0;
      }
      if (wasSelected) {
        _currentStepIndex = 0;
        _remaining = _routine.expandedSteps[0].duration;
        _timer?.cancel();
        _isRunning = false;
      }
    });
    await RoutineRepository.saveRoutines(_routines);
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF1A1A2E),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final activity = _currentActivity;

    final alarmColor = _awaitingConfirmation
        ? const Color(0xFFFF6B6B)
        : activity.color;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildRoutineSelector(),
                    const SizedBox(height: 20),
                    if (_awaitingConfirmation)
                      _buildAlarmHeader()
                    else
                      _buildActivityLabel(activity),
                    const SizedBox(height: 20),
                    _buildTimerRing(alarmColor),
                    const SizedBox(height: 20),
                    if (_awaitingConfirmation)
                      _buildAlarmControls()
                    else
                      _buildControls(activity.color),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: () => _showRoutineDetail(),
                          icon: const Icon(Icons.list_alt, size: 20),
                          color: Colors.white24,
                          tooltip: 'Ver rutina',
                        ),
                        if (_notificationLog.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () => _showNotificationCenter(),
                            icon: Badge(
                              label: Text('${_notificationLog.length}',
                                  style: const TextStyle(fontSize: 9)),
                              child: const Icon(Icons.notifications_none, size: 20),
                            ),
                            color: Colors.white24,
                            tooltip: 'Centro de notificaciones',
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRoutineSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: PopupMenuButton<int>(
            onSelected: _selectRoutine,
            enabled: !_isRunning,
            color: const Color(0xFF2A2A4E),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      _routine.name,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down,
                      color: Colors.white38, size: 20),
                ],
              ),
            ),
            itemBuilder: (_) => List.generate(_routines.length, (i) {
              final r = _routines[i];
              return PopupMenuItem(
                value: i,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(r.name,
                          style: TextStyle(
                            color: i == _selectedRoutineIndex
                                ? const Color(0xFF6C9BFF)
                                : Colors.white70,
                          )),
                    ),
                    if (!r.isDefault) ...[
                      _popupAction(Icons.edit, () {
                        Navigator.of(context).pop();
                        _openEditor(routine: r);
                      }),
                      _popupAction(Icons.delete, () {
                        Navigator.of(context).pop();
                        _deleteRoutine(i);
                      }),
                    ],
                  ],
                ),
              );
            }),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: _isRunning ? null : () => _openEditor(),
          icon: const Icon(Icons.add, size: 20),
          color: Colors.white38,
          tooltip: 'Nueva rutina',
        ),
        IconButton(
          onPressed: _openReminders,
          icon: const Icon(Icons.notifications_outlined, size: 20),
          color: Colors.white38,
          tooltip: 'Tareas',
        ),
      ],
    );
  }

  Future<void> _openReminders() async {
    final result =
        await Navigator.of(context).push<(List<Reminder>, Set<String>)>(
      MaterialPageRoute(
        builder: (_) => ReminderListScreen(
          reminders: _reminders,
          completedIds: _reminderService.completedIds,
          onComplete: (reminder) => _completeReminder(reminder),
        ),
      ),
    );
    if (result == null) return;
    final (reminders, completedIds) = result;
    setState(() => _reminders = reminders);
    _reminderService.load(reminders);
    _reminderService.syncCompletedIds(completedIds);
    await ReminderRepository.save(reminders);
  }

  void _showRoutineDetail() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(child: _buildTimeline()),
      ),
    );
  }

  void _showNotificationCenter() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.notifications_none,
                      color: Colors.white38, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'Centro de notificaciones',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      setState(() => _notificationLog.clear());
                      Navigator.of(context).pop();
                    },
                    child: const Text(
                      'Limpiar',
                      style: TextStyle(color: Colors.white24, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  itemCount: _notificationLog.length,
                  separatorBuilder: (_, _) =>
                      const Divider(color: Colors.white10, height: 1),
                  itemBuilder: (_, i) {
                    final n = _notificationLog[i];
                    final time =
                        '${n.timestamp.hour.toString().padLeft(2, '0')}:${n.timestamp.minute.toString().padLeft(2, '0')}:${n.timestamp.second.toString().padLeft(2, '0')}';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            n.type.icon,
                            color: n.type.color,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(n.emoji,
                              style: const TextStyle(fontSize: 14)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        n.label,
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (n.webhookStatus != null) ...[
                                      const SizedBox(width: 6),
                                      _webhookBadge(n),
                                    ],
                                  ],
                                ),
                                Text(
                                  n.message,
                                  style: TextStyle(
                                    color: n.type.color.withAlpha(150),
                                    fontSize: 11,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Text(
                            time,
                            style: const TextStyle(
                                color: Colors.white24, fontSize: 11),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _webhookBadge(AppNotification n) {
    final Color bg;
    final Color fg;
    final String text;
    switch (n.webhookStatus!) {
      case WebhookStatus.pending:
        bg = Colors.white.withAlpha(15);
        fg = Colors.white38;
        text = 'webhook...';
      case WebhookStatus.success:
        bg = const Color(0xFF69F0AE).withAlpha(25);
        fg = const Color(0xFF69F0AE);
        text = 'webhook ${n.webhookDetail ?? 'ok'}';
      case WebhookStatus.error:
        bg = const Color(0xFFFF5252).withAlpha(25);
        fg = const Color(0xFFFF5252);
        text = 'webhook error';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(color: fg, fontSize: 9, fontWeight: FontWeight.w600)),
    );
  }

  Widget _popupAction(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 16, color: Colors.white24),
      ),
    );
  }

  Widget _buildActivityLabel(Activity activity) {
    return Column(
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
          'Paso ${_currentStepIndex + 1} de ${_expandedSteps.length}',
          style: const TextStyle(fontSize: 13, color: Colors.white38),
        ),
        if (_currentStep.description.isNotEmpty)
          Text(
            _currentStep.description,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.white54,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
      ],
    );
  }

  Widget _buildTimerRing(Color color) {
    Widget ring = SizedBox(
      width: 220,
      height: 220,
      child: CustomPaint(
        painter: _TimerRingPainter(progress: _progress, color: color),
        child: Center(
          child: Text(
            _formatDuration(_remaining),
            style: const TextStyle(
              fontSize: 52,
              fontWeight: FontWeight.w300,
              color: Colors.white,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );

    if (_awaitingConfirmation) {
      ring = AnimatedBuilder(
        animation: _pulseController,
        builder: (_, child) {
          final scale = 1.0 + (_pulseController.value * 0.06);
          final glowOpacity = 0.15 + (_pulseController.value * 0.35);
          return Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF6B6B).withValues(alpha: glowOpacity),
                  blurRadius: 40,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: Transform.scale(scale: scale, child: child),
          );
        },
        child: ring,
      );
    }

    return ring;
  }

  Widget _buildTimeline() {
    final steps = _expandedSteps;
    final cycleLength = _routine.cycle.length;
    final hasBreak = _routine.breakStep != null;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(10)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Rutina',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                'Ciclo ${_completedCycles + 1}  ·  ${_routine.totalMinutes} min',
                style: const TextStyle(color: Colors.white24, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < steps.length; i++) ...[
            // Cycle header
            if (i % cycleLength == 0 && i < steps.length - (hasBreak ? 1 : 0))
              _buildCycleHeader(i ~/ cycleLength + 1, _routine.repeatCount),
            // Break header
            if (hasBreak && i == steps.length - 1)
              _buildBreakHeader(),
            // Step row
            _buildTimelineStep(i, steps[i]),
            if (i < steps.length - 1) const SizedBox(height: 2),
          ],
          const SizedBox(height: 10),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.loop, size: 14, color: Colors.white24),
                const SizedBox(width: 4),
                const Text(
                  'Se repite',
                  style: TextStyle(color: Colors.white24, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCycleHeader(int cycleNumber, int total) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Text(
        total > 1 ? 'Ciclo $cycleNumber de $total' : 'Ciclo',
        style: const TextStyle(
          color: Colors.white24,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildBreakHeader() {
    return const Padding(
      padding: EdgeInsets.only(bottom: 6, top: 8),
      child: Text(
        '— Descanso —',
        style: TextStyle(
          color: Colors.white24,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildTimelineStep(int index, RoutineStep step) {
    final activity = step.resolveActivity(_activities);
    final isCurrent = index == _currentStepIndex;
    final isCompleted = index < _currentStepIndex;
    final isFuture = index > _currentStepIndex;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: isCurrent ? 10 : 6,
      ),
      decoration: BoxDecoration(
        color: isCurrent
            ? activity.color.withAlpha(25)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: isCurrent
            ? Border.all(color: activity.color.withAlpha(50))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Status indicator
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: isCurrent
                      ? activity.color.withAlpha(50)
                      : isCompleted
                          ? Colors.white.withAlpha(10)
                          : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isCurrent
                        ? activity.color
                        : isCompleted
                            ? Colors.white.withAlpha(30)
                            : Colors.white.withAlpha(12),
                    width: isCurrent ? 2 : 1,
                  ),
                ),
                alignment: Alignment.center,
                child: isCompleted
                    ? const Icon(Icons.check, size: 12, color: Colors.white30)
                    : Text(
                        activity.emoji,
                        style: TextStyle(fontSize: isCurrent ? 11 : 9),
                      ),
              ),
              const SizedBox(width: 10),
              // Activity name
              Expanded(
                child: Text(
                  activity.label,
                  style: TextStyle(
                    color: isCurrent
                        ? activity.color
                        : isCompleted
                            ? Colors.white24
                            : isFuture
                                ? Colors.white38
                                : Colors.white54,
                    fontSize: isCurrent ? 14 : 13,
                    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                    decoration:
                        isCompleted ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              // Duration / remaining
              Text(
                isCurrent
                    ? _formatDuration(_remaining)
                    : '${step.duration.inMinutes} min',
                style: TextStyle(
                  color: isCurrent ? activity.color : Colors.white24,
                  fontSize: isCurrent ? 14 : 12,
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          if (isCurrent && step.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 32, top: 4),
              child: Text(
                step.description,
                style: TextStyle(
                  color: activity.color.withAlpha(150),
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildControls(Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildControlButton(
          icon: Icons.refresh,
          label: 'Reiniciar',
          onPressed: _reset,
          color: Colors.white24,
        ),
        const SizedBox(width: 24),
        _buildControlButton(
          icon: _isRunning ? Icons.pause : Icons.play_arrow,
          label: _isRunning ? 'Pausar' : 'Iniciar',
          onPressed: _awaitingConfirmation ? null : _startPause,
          color: color,
          isPrimary: true,
        ),
        const SizedBox(width: 24),
        _buildControlButton(
          icon: Icons.skip_next,
          label: 'Saltar',
          onPressed: _isRunning ? _advanceStep : null,
          color: Colors.white24,
        ),
      ],
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required Color color,
    bool isPrimary = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: isPrimary ? 64 : 48,
          height: isPrimary ? 64 : 48,
          child: IconButton(
            onPressed: onPressed,
            icon: Icon(icon, size: isPrimary ? 32 : 24),
            style: IconButton.styleFrom(
              backgroundColor: isPrimary ? color.withAlpha(40) : null,
              foregroundColor: onPressed == null ? Colors.white12 : color,
              shape: const CircleBorder(),
              side: BorderSide(
                color: onPressed == null ? Colors.white12 : color.withAlpha(80),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: onPressed == null ? Colors.white12 : Colors.white38,
          ),
        ),
      ],
    );
  }

  Widget _buildAlarmHeader() {
    final steps = _expandedSteps;
    final isLastStep = _pendingIsNewCycle;
    final pendingIdx = _pendingStepIndex;
    final nextStep =
        (pendingIdx != null && !isLastStep) ? steps[pendingIdx] : null;
    final nextActivity = nextStep?.resolveActivity(_activities);

    return Column(
      children: [
        const Text(
          '⏰',
          style: TextStyle(fontSize: 48),
        ),
        const SizedBox(height: 8),
        const Text(
          'PASO COMPLETADO',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFFFF6B6B),
            letterSpacing: 3,
          ),
        ),
        const SizedBox(height: 12),
        if (isLastStep)
          const Text(
            '¡Ciclo completo! Continuar para reiniciar.',
            style: TextStyle(color: Colors.white54, fontSize: 14),
          )
        else if (nextActivity != null) ...[
          Text(
            'Siguiente: ${nextActivity.emoji} ${nextActivity.label}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (nextStep!.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                nextStep.description,
                style: const TextStyle(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: Colors.white38,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildAlarmControls() {
    return Column(
      children: [
        SizedBox(
          width: 200,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _confirmTransition,
            icon: const Icon(Icons.play_arrow, size: 28),
            label: const Text(
              'Continuar',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B6B),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _reset,
          child: const Text(
            'Reiniciar',
            style: TextStyle(color: Colors.white24, fontSize: 13),
          ),
        ),
      ],
    );
  }

  void _completeReminder(Reminder reminder) {
    _reminderService.complete(reminder.id);
    final hasWebhook = reminder.webhookUrl != null && reminder.webhookUrl!.isNotEmpty;
    final notif = _logNotification(
      emoji: reminder.emoji,
      label: reminder.label,
      message: 'Tarea completada',
      type: NotificationType.taskCompleted,
      webhookStatus: hasWebhook ? WebhookStatus.pending : null,
    );
    if (hasWebhook) {
      _fireWebhook(reminder, 'completed', notif);
    }
    if (reminder.autoDelete) {
      setState(() {
        _reminders.removeWhere((r) => r.id == reminder.id);
      });
      _reminderService.load(_reminders);
      ReminderRepository.save(_reminders);
    }
  }

  Future<void> _fireWebhook(Reminder reminder, String event, AppNotification notif) async {
    try {
      final uri = Uri.parse(reminder.webhookUrl!);
      final body = jsonEncode({
        'task': reminder.label,
        'emoji': reminder.emoji,
        'id': reminder.id,
        'event': event,
        'timestamp': DateTime.now().toIso8601String(),
      });
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: body,
      );
      if (mounted) {
        final ok = response.statusCode >= 200 && response.statusCode < 300;
        setState(() {
          notif.webhookStatus = ok ? WebhookStatus.success : WebhookStatus.error;
          notif.webhookDetail = '${response.statusCode}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          notif.webhookStatus = WebhookStatus.error;
          notif.webhookDetail = e.toString();
        });
      }
    }
  }

  AppNotification _logNotification({
    required String emoji,
    required String label,
    required String message,
    required NotificationType type,
    WebhookStatus? webhookStatus,
  }) {
    final notif = AppNotification(
      emoji: emoji,
      label: label,
      message: message,
      type: type,
      timestamp: DateTime.now(),
      webhookStatus: webhookStatus,
    );
    setState(() => _notificationLog.insert(0, notif));
    return notif;
  }

  void _showNextReminderModal() {
    if (_showingReminderModal || _pendingReminders.isEmpty) return;
    final reminder = _pendingReminders.removeAt(0);
    _showingReminderModal = true;

    if (reminder.alertCount > 0) {
      AlarmService.startNotificationAlert(
        count: reminder.alertCount,
        sound: reminder.alertSound,
      );
    }

    final hasWebhook = reminder.webhookUrl != null && reminder.webhookUrl!.isNotEmpty;
    final notif = _logNotification(
      emoji: reminder.emoji,
      label: reminder.label,
      message: 'Tarea disparada',
      type: NotificationType.taskTriggered,
      webhookStatus: hasWebhook ? WebhookStatus.pending : null,
    );

    if (hasWebhook) {
      _fireWebhook(reminder, 'triggered', notif);
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ReminderModal(
        reminder: reminder,
        onComplete: () {
          AlarmService.stopNotificationAlert();
          _completeReminder(reminder);
          Navigator.of(context).pop();
        },
        onDismiss: () {
          AlarmService.stopNotificationAlert();
          Navigator.of(context).pop();
        },
      ),
    ).then((_) {
      _showingReminderModal = false;
      _showNextReminderModal();
    });
  }
}

class _TimerRingPainter extends CustomPainter {
  final double progress;
  final Color color;

  _TimerRingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    const strokeWidth = 6.0;

    final bgPaint = Paint()
      ..color = Colors.white.withAlpha(15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);

    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_TimerRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

enum NotificationType {
  taskTriggered(Icons.notifications_active, Color(0xFF6C9BFF)),
  taskCompleted(Icons.check_circle, Color(0xFF69F0AE));

  final IconData icon;
  final Color color;
  const NotificationType(this.icon, this.color);
}

enum WebhookStatus { pending, success, error }

class AppNotification {
  final String emoji;
  final String label;
  final String message;
  final NotificationType type;
  final DateTime timestamp;
  WebhookStatus? webhookStatus;
  String? webhookDetail;

  AppNotification({
    required this.emoji,
    required this.label,
    required this.message,
    required this.type,
    required this.timestamp,
    this.webhookStatus,
    this.webhookDetail,
  });
}

class _ReminderModal extends StatelessWidget {
  final Reminder reminder;
  final VoidCallback onComplete;
  final VoidCallback onDismiss;

  const _ReminderModal({
    required this.reminder,
    required this.onComplete,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E3A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(reminder.emoji, style: const TextStyle(fontSize: 40)),
              const SizedBox(height: 12),
              Text(
                reminder.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              if (reminder.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  reminder.description,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              if (reminder.repeat)
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: onDismiss,
                        child: const Text(
                          'Aún no',
                          style: TextStyle(color: Colors.white38),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: onComplete,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.greenAccent.shade700,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('Completada'),
                    ),
                  ),
                ],
              )
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onComplete,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF6C9BFF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Continuar'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

