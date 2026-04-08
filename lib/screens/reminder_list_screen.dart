import 'dart:io';

import 'package:flutter/material.dart';

import '../models/reminder.dart';
import '../services/notification_service.dart';
import 'reminder_editor_dialog.dart';

class ReminderListScreen extends StatefulWidget {
  final List<Reminder> reminders;
  final Set<String> completedIds;
  final void Function(Reminder)? onComplete;

  const ReminderListScreen({
    super.key,
    required this.reminders,
    this.completedIds = const {},
    this.onComplete,
  });

  @override
  State<ReminderListScreen> createState() => _ReminderListScreenState();
}

class _ReminderListScreenState extends State<ReminderListScreen>
    with WidgetsBindingObserver {
  late List<Reminder> _reminders;
  late Set<String> _completedIds;
  String? _permissionStatus;

  @override
  void initState() {
    super.initState();
    _reminders = List.of(widget.reminders);
    _completedIds = Set.of(widget.completedIds);
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermission();
    }
  }

  Future<void> _checkPermission() async {
    final status = await NotificationService.checkPermission();
    if (mounted) {
      setState(() => _permissionStatus = status);
    }
  }

  Future<void> _openNotificationSettings() async {
    await Process.run('open', [
      'x-apple.systempreferences:com.apple.preference.notifications',
    ]);
  }

  Future<void> _addReminder() async {
    final result = await showDialog<Reminder>(
      context: context,
      builder: (_) => const ReminderEditorDialog(),
    );
    if (result == null) return;
    setState(() => _reminders.add(result));
  }

  Future<void> _editReminder(int index) async {
    final result = await showDialog<Reminder>(
      context: context,
      builder: (_) => ReminderEditorDialog(reminder: _reminders[index]),
    );
    if (result == null) return;
    setState(() => _reminders[index] = result);
  }

  void _deleteReminder(int index) {
    setState(() => _reminders.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.of(context).pop((_reminders, _completedIds));
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1A1A2E),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A1A2E),
          foregroundColor: Colors.white70,
          title: const Text('Tareas'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop((_reminders, _completedIds)),
          ),
          actions: [
            IconButton(
              onPressed: _addReminder,
              icon: const Icon(Icons.add),
              color: const Color(0xFF6C9BFF),
              tooltip: 'Nueva tarea',
            ),
          ],
        ),
        body: Column(
          children: [
            if (_permissionStatus == 'denied') _buildPermissionBanner(),
            Expanded(
              child: _reminders.isEmpty
                  ? const Center(
                      child: Text(
                        'Sin tareas',
                        style: TextStyle(color: Colors.white24),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: _reminders.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, index) => _buildReminderCard(index),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionBanner() {
    return Container(
      width: double.infinity,
      color: Colors.orange.withAlpha(30),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Las notificaciones están desactivadas',
              style: TextStyle(color: Colors.orange.shade300, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: _openNotificationSettings,
            child: Text(
              'Activar',
              style: TextStyle(color: Colors.orange.shade300),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReminderCard(int index) {
    final r = _reminders[index];
    final isCompleted = _completedIds.contains(r.id);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: r.enabled ? 1.0 : 0.5,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(r.enabled ? 8 : 4),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: Colors.white.withAlpha(r.enabled ? 12 : 6)),
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: GestureDetector(
            onTap: () {
              setState(() {
                if (isCompleted) {
                  _completedIds.remove(r.id);
                } else {
                  _completedIds.add(r.id);
                  widget.onComplete?.call(r);
                }
              });
            },
            child: Icon(
              isCompleted
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              color: isCompleted
                  ? Colors.greenAccent.shade700
                  : Colors.white24,
              size: 24,
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  r.label,
                  style: TextStyle(
                    color: isCompleted ? Colors.white38 : Colors.white70,
                    fontSize: 15,
                    decoration:
                        isCompleted ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              if (isCompleted)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.shade700.withAlpha(30),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Completada',
                    style: TextStyle(
                      color: Colors.greenAccent.shade700,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(r.emoji, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Text(
                    'Cada ${r.intervalMinutes} min',
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
              if (r.description.isNotEmpty)
                Text(
                  r.description,
                  style: const TextStyle(
                    color: Colors.white24,
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
          ),
          trailing: PopupMenuButton<String>(
            color: const Color(0xFF2A2A4E),
            icon:
                const Icon(Icons.more_vert, size: 18, color: Colors.white24),
            onSelected: (action) {
              if (action == 'edit') _editReminder(index);
              if (action == 'delete') _deleteReminder(index);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'edit',
                child: Text('Editar',
                    style: TextStyle(color: Colors.white70)),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Eliminar',
                    style: TextStyle(color: Colors.redAccent)),
              ),
            ],
          ),
          onTap: () => _editReminder(index),
        ),
      ),
    );
  }
}
