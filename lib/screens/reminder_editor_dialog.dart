import 'package:flutter/material.dart';

import '../models/reminder.dart';
import '../services/alarm_service.dart';

class ReminderEditorDialog extends StatefulWidget {
  final Reminder? reminder;

  const ReminderEditorDialog({super.key, this.reminder});

  @override
  State<ReminderEditorDialog> createState() => _ReminderEditorDialogState();
}

class _ReminderEditorDialogState extends State<ReminderEditorDialog> {
  late final TextEditingController _labelController;
  late final TextEditingController _descController;
  late String _emoji;
  late int _intervalMinutes;
  late bool _repeat;
  late bool _autoDelete;
  late int _alertCount;
  late String _alertSound;
  late final TextEditingController _webhookController;
  List<String> _customSounds = [];
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  @override
  void initState() {
    super.initState();
    _labelController =
        TextEditingController(text: widget.reminder?.label ?? '');
    _descController =
        TextEditingController(text: widget.reminder?.description ?? '');
    _emoji = widget.reminder?.emoji ?? Reminder.availableEmojis[0];
    _intervalMinutes = widget.reminder?.intervalMinutes ?? 30;
    _repeat = widget.reminder?.repeat ?? true;
    _autoDelete = widget.reminder?.autoDelete ?? false;
    _alertCount = widget.reminder?.alertCount ?? 3;
    _alertSound = widget.reminder?.alertSound ?? 'Glass.aiff';
    _webhookController =
        TextEditingController(text: widget.reminder?.webhookUrl ?? '');
    _startTime = _parseTime(widget.reminder?.startTime);
    _endTime = _parseTime(widget.reminder?.endTime);
    _loadCustomSounds();
  }

  Future<void> _loadCustomSounds() async {
    final sounds = await AlarmService.loadCustomSounds();
    if (mounted) setState(() => _customSounds = sounds);
  }

  TimeOfDay? _parseTime(String? time) {
    if (time == null) return null;
    final parts = time.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String? _formatTime(TimeOfDay? time) {
    if (time == null) return null;
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _displayTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  Future<void> _pickTime({required bool isStart}) async {
    final initial = isStart
        ? (_startTime ?? const TimeOfDay(hour: 8, minute: 0))
        : (_endTime ?? const TimeOfDay(hour: 18, minute: 0));
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF6C9BFF),
            surface: Color(0xFF1E1E3A),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
    _descController.dispose();
    _webhookController.dispose();
    super.dispose();
  }

  void _save() {
    final label = _labelController.text.trim();
    if (label.isEmpty) return;

    final reminder = Reminder(
      id: widget.reminder?.id ??
          'custom-${DateTime.now().millisecondsSinceEpoch}',
      emoji: _emoji,
      label: label,
      intervalMinutes: _intervalMinutes,
      description: _descController.text.trim(),
      repeat: _repeat,
      autoDelete: _autoDelete,
      alertCount: _alertCount,
      alertSound: _alertSound,
      startTime: _formatTime(_startTime),
      endTime: _formatTime(_endTime),
      webhookUrl: _webhookController.text.trim().isEmpty
          ? null
          : _webhookController.text.trim(),
    );
    Navigator.of(context).pop(reminder);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.reminder != null;

    return Dialog(
      backgroundColor: const Color(0xFF1E1E3A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEditing ? 'Editar tarea' : 'Nueva tarea',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                // Emoji picker
                _sectionLabel('Emoji'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: Reminder.availableEmojis.map((e) {
                    final selected = e == _emoji;
                    return GestureDetector(
                      onTap: () => setState(() => _emoji = e),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: selected
                              ? Colors.white.withAlpha(20)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color:
                                selected ? Colors.white38 : Colors.transparent,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(e, style: const TextStyle(fontSize: 20)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                // Label
                TextField(
                  controller: _labelController,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'Nombre (ej: Tomar agua)',
                    hintStyle: const TextStyle(color: Colors.white24),
                    prefixText: '$_emoji  ',
                    prefixStyle: const TextStyle(fontSize: 20),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.white12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFF6C9BFF)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Interval
                _sectionLabel('Cada cuánto recordar'),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _roundBtn(Icons.remove, _intervalMinutes > 1
                        ? () => setState(() => _intervalMinutes -= 1)
                        : null),
                    const SizedBox(width: 16),
                    Text(
                      '$_intervalMinutes',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text('min',
                        style: TextStyle(color: Colors.white38, fontSize: 14)),
                    const SizedBox(width: 12),
                    _roundBtn(Icons.add, _intervalMinutes < 480
                        ? () => setState(() => _intervalMinutes += 1)
                        : null),
                  ],
                ),
                const SizedBox(height: 20),
                // Repeat toggle
                _optionRow(
                  icon: Icons.repeat,
                  label: 'Repetir',
                  subtitle: _repeat
                      ? 'Se repite cada $_intervalMinutes min'
                      : 'Solo una vez',
                  trailing: Switch(
                    value: _repeat,
                    onChanged: (v) => setState(() => _repeat = v),
                    activeTrackColor: const Color(0xFF6C9BFF),
                  ),
                ),
                const SizedBox(height: 8),
                // Auto-delete on complete
                _optionRow(
                  icon: Icons.delete_sweep_outlined,
                  label: 'Eliminar al completar',
                  subtitle: _autoDelete
                      ? 'Se elimina automáticamente'
                      : 'Se mantiene en la lista',
                  trailing: Checkbox(
                    value: _autoDelete,
                    onChanged: (v) => setState(() => _autoDelete = v ?? false),
                    activeColor: const Color(0xFF6C9BFF),
                  ),
                ),
                const SizedBox(height: 8),
                // Alert count
                _optionRow(
                  icon: Icons.volume_up,
                  label: 'Sonidos de alerta',
                  subtitle: _alertCount == 0
                      ? 'Sin sonido'
                      : '$_alertCount ${_alertCount == 1 ? 'vez' : 'veces'}',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _roundBtn(Icons.remove, _alertCount > 0
                          ? () => setState(() => _alertCount--)
                          : null),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 24,
                        child: Text(
                          '$_alertCount',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _roundBtn(Icons.add, _alertCount < 20
                          ? () => setState(() => _alertCount++)
                          : null),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Sound picker
                _optionRow(
                  icon: Icons.music_note,
                  label: 'Sonido',
                  subtitle: _soundDisplayName(_alertSound),
                  trailing: PopupMenuButton<String>(
                    onSelected: (sound) {
                      if (sound == '_import_') {
                        _importCustomSound();
                        return;
                      }
                      setState(() => _alertSound = sound);
                      AlarmService.playPreview(sound);
                    },
                    color: const Color(0xFF2A2A4E),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _soundDisplayName(_alertSound),
                            style: const TextStyle(
                              color: Color(0xFF6C9BFF),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_drop_down,
                              color: Colors.white38, size: 16),
                        ],
                      ),
                    ),
                    itemBuilder: (_) {
                      final items = <PopupMenuEntry<String>>[];
                      // System sounds
                      for (final sound in AlarmService.systemSounds) {
                        items.add(_soundMenuItem(sound, isCustom: false));
                      }
                      // Custom sounds
                      if (_customSounds.isNotEmpty) {
                        items.add(const PopupMenuDivider());
                        for (final sound in _customSounds) {
                          items.add(_soundMenuItem(sound, isCustom: true));
                        }
                      }
                      // Import button
                      items.add(const PopupMenuDivider());
                      items.add(const PopupMenuItem(
                        value: '_import_',
                        child: Row(
                          children: [
                            Icon(Icons.add_circle_outline,
                                size: 16, color: Color(0xFF6C9BFF)),
                            SizedBox(width: 8),
                            Text('Importar sonido...',
                                style: TextStyle(
                                    color: Color(0xFF6C9BFF), fontSize: 13)),
                          ],
                        ),
                      ));
                      return items;
                    },
                  ),
                ),
                const Divider(color: Colors.white10, height: 24),
                // Horario activo
                _sectionLabel('Horario activo'),
                const SizedBox(height: 8),
                _timeRow(
                  label: 'Desde',
                  value: _startTime,
                  onPick: () => _pickTime(isStart: true),
                  onClear: () => setState(() => _startTime = null),
                ),
                const SizedBox(height: 8),
                _timeRow(
                  label: 'Hasta',
                  value: _endTime,
                  onPick: () => _pickTime(isStart: false),
                  onClear: () => setState(() => _endTime = null),
                ),
                const Divider(color: Colors.white10, height: 24),
                // Webhook
                _sectionLabel('Webhook (opcional)'),
                const SizedBox(height: 8),
                TextField(
                  controller: _webhookController,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'https://...',
                    hintStyle: const TextStyle(color: Colors.white12),
                    prefixIcon: const Icon(Icons.webhook,
                        color: Colors.white24, size: 18),
                    helperText: 'Se llama con POST al completar la tarea',
                    helperStyle:
                        const TextStyle(color: Colors.white12, fontSize: 11),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.white12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFF6C9BFF)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Description
                TextField(
                  controller: _descController,
                  maxLines: 2,
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Descripción (opcional)',
                    hintStyle: const TextStyle(color: Colors.white12),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.white12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFF6C9BFF)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancelar',
                          style: TextStyle(color: Colors.white38)),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF6C9BFF),
                      ),
                      child: Text(isEditing ? 'Guardar' : 'Crear'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _optionRow({
    required IconData icon,
    required String label,
    required String subtitle,
    required Widget trailing,
  }) {
    return Row(
      children: [
        Icon(icon, color: Colors.white24, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 14)),
              Text(subtitle,
                  style:
                      const TextStyle(color: Colors.white24, fontSize: 11)),
            ],
          ),
        ),
        trailing,
      ],
    );
  }

  String _soundDisplayName(String sound) {
    return sound
        .replaceAll('.aiff', '')
        .replaceAll('.mp3', '')
        .replaceAll('.wav', '')
        .replaceAll('.m4a', '');
  }

  PopupMenuItem<String> _soundMenuItem(String sound, {required bool isCustom}) {
    final name = _soundDisplayName(sound);
    final selected = sound == _alertSound;
    return PopupMenuItem(
      value: sound,
      child: Row(
        children: [
          Icon(
            selected
                ? Icons.check
                : isCustom
                    ? Icons.audiotrack
                    : Icons.music_note,
            size: 16,
            color: selected ? const Color(0xFF6C9BFF) : Colors.white24,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(name,
                style: TextStyle(
                  color:
                      selected ? const Color(0xFF6C9BFF) : Colors.white70,
                  fontSize: 13,
                )),
          ),
          IconButton(
            onPressed: () => AlarmService.playPreview(sound),
            icon: const Icon(Icons.play_arrow, size: 16, color: Colors.white24),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ],
      ),
    );
  }

  Future<void> _importCustomSound() async {
    final name = await AlarmService.importSound();
    if (name != null && mounted) {
      await _loadCustomSounds();
      setState(() => _alertSound = name);
    }
  }

  Widget _timeRow({
    required String label,
    required TimeOfDay? value,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) {
    return _optionRow(
      icon: Icons.access_time,
      label: label,
      subtitle: value != null ? _displayTime(value) : 'Sin límite',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            GestureDetector(
              onTap: onClear,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, color: Colors.white24, size: 16),
              ),
            ),
          GestureDetector(
            onTap: onPick,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                value != null ? _displayTime(value) : 'Elegir',
                style: TextStyle(
                  color: value != null
                      ? const Color(0xFF6C9BFF)
                      : Colors.white38,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white38,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 1,
      ),
    );
  }

  Widget _roundBtn(IconData icon, VoidCallback? onPressed) {
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withAlpha(10),
          foregroundColor: onPressed == null ? Colors.white12 : Colors.white54,
          shape: const CircleBorder(),
        ),
      ),
    );
  }
}
