import 'package:flutter/material.dart';

import '../models/activity.dart';

class ActivityEditorDialog extends StatefulWidget {
  final Activity? activity;

  const ActivityEditorDialog({super.key, this.activity});

  @override
  State<ActivityEditorDialog> createState() => _ActivityEditorDialogState();
}

class _ActivityEditorDialogState extends State<ActivityEditorDialog> {
  late final TextEditingController _nameController;
  late String _selectedEmoji;
  late int _selectedColor;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.activity?.label ?? '');
    _selectedEmoji = widget.activity?.emoji ?? Activity.availableEmojis[0];
    _selectedColor =
        widget.activity?.colorValue ?? Activity.availableColors[0];
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final activity = Activity(
      id: widget.activity?.id ??
          'custom-${DateTime.now().millisecondsSinceEpoch}',
      label: name,
      emoji: _selectedEmoji,
      colorValue: _selectedColor,
    );

    Navigator.of(context).pop(activity);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E3A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Nueva actividad',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _nameController,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Nombre (ej: Yoga, Café, Respiración)',
                  hintStyle: const TextStyle(color: Colors.white24),
                  prefixText: '$_selectedEmoji  ',
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
              const SizedBox(height: 20),
              _buildSectionLabel('Emoji'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: Activity.availableEmojis.map((emoji) {
                  final isSelected = emoji == _selectedEmoji;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedEmoji = emoji),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white.withAlpha(20)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected
                              ? Colors.white38
                              : Colors.transparent,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(emoji, style: const TextStyle(fontSize: 20)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              _buildSectionLabel('Color'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: Activity.availableColors.map((colorVal) {
                  final isSelected = colorVal == _selectedColor;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedColor = colorVal),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Color(colorVal),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color:
                              isSelected ? Colors.white : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                  );
                }).toList(),
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
                    child: const Text('Crear'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
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
}
