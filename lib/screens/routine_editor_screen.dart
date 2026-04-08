import 'package:flutter/material.dart';

import '../models/activity.dart';
import '../models/routine.dart';
import '../services/alarm_service.dart';
import 'activity_editor_dialog.dart';

class RoutineEditorScreen extends StatefulWidget {
  final Routine? routine;
  final List<Activity> activities;
  final void Function(Activity) onActivityCreated;

  const RoutineEditorScreen({
    super.key,
    this.routine,
    required this.activities,
    required this.onActivityCreated,
  });

  @override
  State<RoutineEditorScreen> createState() => _RoutineEditorScreenState();
}

class _RoutineEditorScreenState extends State<RoutineEditorScreen> {
  late final TextEditingController _nameController;
  late List<_EditableStep> _cycleSteps;
  late int _repeatCount;
  late bool _hasBreak;
  late _EditableStep _breakStep;
  late bool _autoAdvance;
  late String _transitionSound;
  List<String> _customSounds = [];

  List<Activity> get _activities => widget.activities;

  @override
  void initState() {
    super.initState();
    final routine = widget.routine;
    _nameController =
        TextEditingController(text: routine?.name ?? 'Mi rutina');

    _cycleSteps = routine?.cycle
            .map((s) => _EditableStep(s.activityId, s.duration.inMinutes,
                description: s.description))
            .toList() ??
        [
          _EditableStep('sitting', 45),
          _EditableStep('standing', 15),
        ];

    _repeatCount = routine?.repeatCount ?? 1;
    _hasBreak = routine?.breakStep != null;
    _breakStep = routine?.breakStep != null
        ? _EditableStep(
            routine!.breakStep!.activityId,
            routine.breakStep!.duration.inMinutes,
            description: routine.breakStep!.description,
          )
        : _EditableStep('stretching', 5);
    _autoAdvance = routine?.autoAdvance ?? false;
    _transitionSound = routine?.transitionSound ?? 'Glass.aiff';
    _loadCustomSounds();
  }

  Future<void> _loadCustomSounds() async {
    final sounds = await AlarmService.loadCustomSounds();
    if (mounted) setState(() => _customSounds = sounds);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Activity _resolveActivity(String id) =>
      _activities.firstWhere((a) => a.id == id,
          orElse: () => Activity.defaults.first);

  void _addStep() {
    setState(() => _cycleSteps.add(_EditableStep('sitting', 15)));
  }

  void _removeStep(int index) {
    if (_cycleSteps.length <= 1) return;
    setState(() => _cycleSteps.removeAt(index));
  }

  void _moveStep(int from, int to) {
    if (to < 0 || to >= _cycleSteps.length) return;
    setState(() {
      final step = _cycleSteps.removeAt(from);
      _cycleSteps.insert(to, step);
    });
  }

  Future<void> _createActivity() async {
    final activity = await showDialog<Activity>(
      context: context,
      builder: (_) => const ActivityEditorDialog(),
    );
    if (activity == null) return;
    widget.onActivityCreated(activity);
    setState(() {});
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty || _cycleSteps.isEmpty) return;

    final routine = Routine(
      id: widget.routine?.id ??
          'custom-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      cycle: _cycleSteps
          .map((s) => RoutineStep(
                activityId: s.activityId,
                duration: Duration(minutes: s.minutes),
                description: s.description,
              ))
          .toList(),
      repeatCount: _repeatCount,
      breakStep: _hasBreak
          ? RoutineStep(
              activityId: _breakStep.activityId,
              duration: Duration(minutes: _breakStep.minutes),
              description: _breakStep.description,
            )
          : null,
      autoAdvance: _autoAdvance,
      transitionSound: _transitionSound,
    );

    Navigator.of(context).pop(routine);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white70,
        title: Text(widget.routine != null ? 'Editar rutina' : 'Nueva rutina'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Guardar',
                style: TextStyle(color: Color(0xFF6C9BFF))),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _buildNameField(),
          const SizedBox(height: 28),
          _buildSectionHeader('Tu ciclo', 'Se repite $_repeatCount vez${_repeatCount > 1 ? 'es' : ''}'),
          const SizedBox(height: 12),
          ..._buildCycleSteps(),
          const SizedBox(height: 8),
          _buildAddStepRow(),
          const SizedBox(height: 28),
          _buildRepeatSection(),
          const SizedBox(height: 28),
          _buildBreakSection(),
          const SizedBox(height: 28),
          _buildTransitionSection(),
          const SizedBox(height: 32),
          _buildPreview(),
        ],
      ),
    );
  }

  Widget _buildNameField() {
    return TextField(
      controller: _nameController,
      style: const TextStyle(color: Colors.white, fontSize: 18),
      decoration: InputDecoration(
        labelText: 'Nombre de la rutina',
        labelStyle: const TextStyle(color: Colors.white38),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.white12),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Color(0xFF6C9BFF)),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 8),
        Text(subtitle,
            style: const TextStyle(color: Colors.white24, fontSize: 12)),
      ],
    );
  }

  List<Widget> _buildCycleSteps() {
    return List.generate(_cycleSteps.length, (index) {
      return _buildStepRow(_cycleSteps[index], index);
    });
  }

  Widget _buildStepRow(_EditableStep step, int index) {
    final activity = _resolveActivity(step.activityId);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: activity.color.withAlpha(10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: activity.color.withAlpha(30)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: activity.color.withAlpha(40),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: activity.color,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: _buildActivityDropdown(step)),
                _buildDurationControl(step),
                if (_cycleSteps.length > 1) ...[
                  _iconBtn(Icons.arrow_upward,
                      index > 0 ? () => _moveStep(index, index - 1) : null),
                  _iconBtn(
                      Icons.arrow_downward,
                      index < _cycleSteps.length - 1
                          ? () => _moveStep(index, index + 1)
                          : null),
                  _iconBtn(Icons.close, () => _removeStep(index)),
                ],
              ],
            ),
            _buildDescriptionField(step),
          ],
        ),
      ),
    );
  }

  Widget _buildDescriptionField(_EditableStep step) {
    return Padding(
      padding: const EdgeInsets.only(left: 32, top: 6),
      child: TextField(
        controller: TextEditingController(text: step.description),
        onChanged: (v) => step.description = v,
        maxLines: null,
        style: const TextStyle(color: Colors.white54, fontSize: 12),
        decoration: const InputDecoration(
          hintText: 'Descripción (ej: Andá por agua o estirá las piernas)',
          hintStyle: TextStyle(color: Colors.white12, fontSize: 12),
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 6),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildActivityDropdown(_EditableStep step) {
    return PopupMenuButton<String>(
      color: const Color(0xFF2A2A4E),
      onSelected: (id) {
        if (id == '__create__') {
          _createActivity();
          return;
        }
        setState(() => step.activityId = id);
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_resolveActivity(step.activityId).emoji,
              style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              _resolveActivity(step.activityId).label,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.arrow_drop_down, color: Colors.white24, size: 18),
        ],
      ),
      itemBuilder: (_) => [
        ..._activities.map((a) => PopupMenuItem(
              value: a.id,
              child: Row(
                children: [
                  Text(a.emoji, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Text(a.label,
                      style: const TextStyle(color: Colors.white70)),
                ],
              ),
            )),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: '__create__',
          child: Row(
            children: [
              Icon(Icons.add_circle_outline,
                  size: 16, color: Color(0xFF6C9BFF)),
              SizedBox(width: 8),
              Text('Crear actividad',
                  style: TextStyle(color: Color(0xFF6C9BFF))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDurationControl(_EditableStep step) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _iconBtn(Icons.remove, step.minutes > 1
            ? () => setState(() => step.minutes = (step.minutes - 1).clamp(1, 120))
            : null),
        SizedBox(
          width: 52,
          child: Text(
            '${step.minutes} min',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
        _iconBtn(Icons.add, step.minutes < 120
            ? () => setState(() => step.minutes = (step.minutes + 1).clamp(1, 120))
            : null),
      ],
    );
  }

  Widget _buildAddStepRow() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _addStep,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Agregar paso'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white38,
              side: const BorderSide(color: Colors.white12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRepeatSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(10)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '¿Cuántas veces repetir el ciclo antes del descanso?',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _roundBtn(Icons.remove, _repeatCount > 1
                  ? () => setState(() => _repeatCount--)
                  : null),
              const SizedBox(width: 16),
              Text(
                '$_repeatCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(width: 16),
              _roundBtn(Icons.add, _repeatCount < 10
                  ? () => setState(() => _repeatCount++)
                  : null),
            ],
          ),
          Center(
            child: Text(
              _repeatCount == 1 ? 'vez' : 'veces',
              style: const TextStyle(color: Colors.white24, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakSection() {
    final activity = _resolveActivity(_breakStep.activityId);

    return Container(
      decoration: BoxDecoration(
        color: _hasBreak ? activity.color.withAlpha(8) : Colors.white.withAlpha(5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _hasBreak ? activity.color.withAlpha(25) : Colors.white.withAlpha(10),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Descanso después de los $_repeatCount ciclo${_repeatCount > 1 ? 's' : ''}',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
              Switch(
                value: _hasBreak,
                onChanged: (v) => setState(() => _hasBreak = v),
                activeThumbColor: const Color(0xFF6C9BFF),
              ),
            ],
          ),
          if (_hasBreak) ...[
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(5),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: _buildActivityDropdownFor(_breakStep)),
                      _buildDurationControl(_breakStep),
                    ],
                  ),
                  _buildDescriptionField(_breakStep),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActivityDropdownFor(_EditableStep step) {
    return PopupMenuButton<String>(
      color: const Color(0xFF2A2A4E),
      onSelected: (id) {
        if (id == '__create__') {
          _createActivity();
          return;
        }
        setState(() => step.activityId = id);
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_resolveActivity(step.activityId).emoji,
              style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              _resolveActivity(step.activityId).label,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.arrow_drop_down, color: Colors.white24, size: 18),
        ],
      ),
      itemBuilder: (_) => [
        ..._activities.map((a) => PopupMenuItem(
              value: a.id,
              child: Row(
                children: [
                  Text(a.emoji, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Text(a.label,
                      style: const TextStyle(color: Colors.white70)),
                ],
              ),
            )),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: '__create__',
          child: Row(
            children: [
              Icon(Icons.add_circle_outline,
                  size: 16, color: Color(0xFF6C9BFF)),
              SizedBox(width: 8),
              Text('Crear actividad',
                  style: TextStyle(color: Color(0xFF6C9BFF))),
            ],
          ),
        ),
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

  Widget _buildTransitionSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(10)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Transición entre pasos',
            style: TextStyle(
              color: Colors.white60,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          // Auto advance
          Row(
            children: [
              const Icon(Icons.skip_next, color: Colors.white24, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Avance automático',
                        style: TextStyle(color: Colors.white70, fontSize: 14)),
                    Text(
                      _autoAdvance
                          ? 'Pasa al siguiente paso sin confirmar'
                          : 'Requiere confirmación para continuar',
                      style: const TextStyle(
                          color: Colors.white24, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Checkbox(
                value: _autoAdvance,
                onChanged: (v) => setState(() => _autoAdvance = v ?? false),
                activeColor: const Color(0xFF6C9BFF),
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 20),
          // Sound
          Row(
            children: [
              const Icon(Icons.music_note, color: Colors.white24, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Sonido de transición',
                        style: TextStyle(color: Colors.white70, fontSize: 14)),
                    Text(
                      _soundDisplayName(_transitionSound),
                      style: const TextStyle(
                          color: Colors.white24, fontSize: 11),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (sound) {
                  if (sound == '_import_') {
                    _importSound();
                    return;
                  }
                  setState(() => _transitionSound = sound);
                  AlarmService.playPreview(sound);
                },
                color: const Color(0xFF2A2A4E),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _soundDisplayName(_transitionSound),
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
                  for (final sound in AlarmService.systemSounds) {
                    final name = _soundDisplayName(sound);
                    final selected = sound == _transitionSound;
                    items.add(PopupMenuItem(
                      value: sound,
                      child: Row(
                        children: [
                          Icon(
                            selected ? Icons.check : Icons.music_note,
                            size: 16,
                            color: selected
                                ? const Color(0xFF6C9BFF)
                                : Colors.white24,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(name,
                                style: TextStyle(
                                  color: selected
                                      ? const Color(0xFF6C9BFF)
                                      : Colors.white70,
                                  fontSize: 13,
                                )),
                          ),
                          IconButton(
                            onPressed: () => AlarmService.playPreview(sound),
                            icon: const Icon(Icons.play_arrow,
                                size: 16, color: Colors.white24),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                          ),
                        ],
                      ),
                    ));
                  }
                  if (_customSounds.isNotEmpty) {
                    items.add(const PopupMenuDivider());
                    for (final sound in _customSounds) {
                      final name = _soundDisplayName(sound);
                      final selected = sound == _transitionSound;
                      items.add(PopupMenuItem(
                        value: sound,
                        child: Row(
                          children: [
                            Icon(
                              selected ? Icons.check : Icons.audiotrack,
                              size: 16,
                              color: selected
                                  ? const Color(0xFF6C9BFF)
                                  : Colors.white24,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(name,
                                  style: TextStyle(
                                    color: selected
                                        ? const Color(0xFF6C9BFF)
                                        : Colors.white70,
                                    fontSize: 13,
                                  )),
                            ),
                            IconButton(
                              onPressed: () => AlarmService.playPreview(sound),
                              icon: const Icon(Icons.play_arrow,
                                  size: 16, color: Colors.white24),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                            ),
                          ],
                        ),
                      ));
                    }
                  }
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
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _importSound() async {
    final name = await AlarmService.importSound();
    if (name != null && mounted) {
      await _loadCustomSounds();
      setState(() => _transitionSound = name);
    }
  }

  Widget _buildPreview() {
    final expandedSteps = <_PreviewItem>[];
    for (var r = 0; r < _repeatCount; r++) {
      for (final s in _cycleSteps) {
        expandedSteps.add(_PreviewItem(s.activityId, s.minutes, false));
      }
    }
    if (_hasBreak) {
      expandedSteps
          .add(_PreviewItem(_breakStep.activityId, _breakStep.minutes, true));
    }

    final totalMinutes = expandedSteps.fold(0, (sum, s) => sum + s.minutes);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(5),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Vista previa',
                  style: TextStyle(
                      color: Colors.white60,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('$totalMinutes min total  ·  ↻ Se repite',
                  style:
                      const TextStyle(color: Colors.white24, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 4,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = 0; i < expandedSteps.length; i++) ...[
                _previewChip(expandedSteps[i]),
                if (i < expandedSteps.length - 1 && expandedSteps[i + 1].isBreak)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.more_horiz,
                        size: 16, color: Colors.white24),
                  )
                else if (i < expandedSteps.length - 1)
                  const Icon(Icons.arrow_forward,
                      size: 12, color: Colors.white12),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _previewChip(_PreviewItem item) {
    final activity = _resolveActivity(item.activityId);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: activity.color.withAlpha(item.isBreak ? 35 : 20),
        borderRadius: BorderRadius.circular(6),
        border: item.isBreak
            ? Border.all(color: activity.color.withAlpha(50))
            : null,
      ),
      child: Text(
        '${activity.emoji} ${item.minutes}m',
        style: TextStyle(color: activity.color, fontSize: 12),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback? onPressed) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 14),
        padding: EdgeInsets.zero,
        color: onPressed == null ? Colors.white12 : Colors.white30,
      ),
    );
  }

  Widget _roundBtn(IconData icon, VoidCallback? onPressed) {
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withAlpha(10),
          foregroundColor: onPressed == null ? Colors.white12 : Colors.white54,
          shape: const CircleBorder(),
        ),
      ),
    );
  }
}

class _EditableStep {
  String activityId;
  int minutes;
  String description;
  _EditableStep(this.activityId, this.minutes, {this.description = ''});
}

class _PreviewItem {
  final String activityId;
  final int minutes;
  final bool isBreak;
  _PreviewItem(this.activityId, this.minutes, this.isBreak);
}
