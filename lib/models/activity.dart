import 'dart:ui';

class Activity {
  final String id;
  final String label;
  final String emoji;
  final int colorValue;
  final bool isDefault;

  const Activity({
    required this.id,
    required this.label,
    required this.emoji,
    required this.colorValue,
    this.isDefault = false,
  });

  Color get color => Color(colorValue);

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'emoji': emoji,
        'colorValue': colorValue,
        'isDefault': isDefault,
      };

  factory Activity.fromJson(Map<String, dynamic> json) => Activity(
        id: json['id'] as String,
        label: json['label'] as String,
        emoji: json['emoji'] as String,
        colorValue: json['colorValue'] as int,
        isDefault: json['isDefault'] as bool? ?? false,
      );

  Activity copyWith({String? label, String? emoji, int? colorValue}) =>
      Activity(
        id: id,
        label: label ?? this.label,
        emoji: emoji ?? this.emoji,
        colorValue: colorValue ?? this.colorValue,
        isDefault: isDefault,
      );

  static const availableEmojis = [
    '🪑', '🧍', '🙆', '🏋️', '🚶', '⚡', '👀', '🧘',
    '💪', '🏃', '🚴', '🤸', '☕', '💧', '🎯', '🖥️',
  ];

  static const availableColors = [
    0xFF6C9BFF, // blue
    0xFFFF8C42, // orange
    0xFF66BB6A, // green
    0xFFEF5350, // red
    0xFF26C6DA, // teal
    0xFFAB47BC, // purple
    0xFFFFCA28, // yellow
    0xFFEC407A, // pink
  ];

  static const List<Activity> defaults = [
    Activity(
      id: 'sitting',
      label: 'Sentado',
      emoji: '🪑',
      colorValue: 0xFF6C9BFF,
      isDefault: true,
    ),
    Activity(
      id: 'standing',
      label: 'De pie',
      emoji: '🧍',
      colorValue: 0xFFFF8C42,
      isDefault: true,
    ),
    Activity(
      id: 'stretching',
      label: 'Estiramiento',
      emoji: '🙆',
      colorValue: 0xFF66BB6A,
      isDefault: true,
    ),
    Activity(
      id: 'movement',
      label: 'Movimiento',
      emoji: '⚡',
      colorValue: 0xFFFFCA28,
      isDefault: true,
    ),
    Activity(
      id: 'walking',
      label: 'Caminata',
      emoji: '🚶',
      colorValue: 0xFF26C6DA,
      isDefault: true,
    ),
    Activity(
      id: 'squats',
      label: 'Sentadillas',
      emoji: '🏋️',
      colorValue: 0xFFEF5350,
      isDefault: true,
    ),
    Activity(
      id: 'visual-rest',
      label: 'Descanso visual',
      emoji: '👀',
      colorValue: 0xFFAB47BC,
      isDefault: true,
    ),
  ];
}
