import 'dart:convert';

class Reminder {
  final String id;
  final String emoji;
  final String label;
  final int intervalMinutes;
  final String description;
  final bool isDefault;
  final bool enabled;
  final bool repeat;
  final int alertCount;
  final String alertSound;
  final String? startTime; // HH:mm format, null = no restriction
  final String? endTime;   // HH:mm format, null = no restriction
  final String? webhookUrl; // URL to call on task completion
  final bool autoDelete; // delete task when completed

  const Reminder({
    required this.id,
    required this.emoji,
    required this.label,
    required this.intervalMinutes,
    this.description = '',
    this.isDefault = false,
    this.enabled = true,
    this.repeat = true,
    this.alertCount = 3,
    this.alertSound = 'Glass.aiff',
    this.startTime,
    this.endTime,
    this.webhookUrl,
    this.autoDelete = false,
  });

  bool isInTimeWindow() {
    if (startTime == null && endTime == null) return true;
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    if (startTime != null) {
      final parts = startTime!.split(':');
      final startMinutes = int.parse(parts[0]) * 60 + int.parse(parts[1]);
      if (nowMinutes < startMinutes) return false;
    }
    if (endTime != null) {
      final parts = endTime!.split(':');
      final endMinutes = int.parse(parts[0]) * 60 + int.parse(parts[1]);
      if (nowMinutes > endMinutes) return false;
    }
    return true;
  }


  Map<String, dynamic> toJson() => {
        'id': id,
        'emoji': emoji,
        'label': label,
        'intervalMinutes': intervalMinutes,
        if (description.isNotEmpty) 'description': description,
        'isDefault': isDefault,
        'enabled': enabled,
        'repeat': repeat,
        'alertCount': alertCount,
        'alertSound': alertSound,
        if (startTime != null) 'startTime': startTime,
        if (endTime != null) 'endTime': endTime,
        if (webhookUrl != null) 'webhookUrl': webhookUrl,
        'autoDelete': autoDelete,
      };

  factory Reminder.fromJson(Map<String, dynamic> json) => Reminder(
        id: json['id'] as String,
        emoji: json['emoji'] as String,
        label: json['label'] as String,
        intervalMinutes: json['intervalMinutes'] as int,
        description: json['description'] as String? ?? '',
        isDefault: json['isDefault'] as bool? ?? false,
        enabled: json['enabled'] as bool? ?? true,
        repeat: json['repeat'] as bool? ?? true,
        alertCount: json['alertCount'] as int? ?? 3,
        alertSound: json['alertSound'] as String? ?? 'Glass.aiff',
        startTime: json['startTime'] as String?,
        endTime: json['endTime'] as String?,
        webhookUrl: json['webhookUrl'] as String?,
        autoDelete: json['autoDelete'] as bool? ?? false,
      );

  Reminder copyWith({
    String? emoji,
    String? label,
    int? intervalMinutes,
    String? description,
    bool? enabled,
    bool? repeat,
    int? alertCount,
    String? alertSound,
    String? Function()? startTime,
    String? Function()? endTime,
    String? Function()? webhookUrl,
    bool? autoDelete,
  }) =>
      Reminder(
        id: id,
        emoji: emoji ?? this.emoji,
        label: label ?? this.label,
        intervalMinutes: intervalMinutes ?? this.intervalMinutes,
        description: description ?? this.description,
        isDefault: isDefault,
        enabled: enabled ?? this.enabled,
        repeat: repeat ?? this.repeat,
        alertCount: alertCount ?? this.alertCount,
        alertSound: alertSound ?? this.alertSound,
        startTime: startTime != null ? startTime() : this.startTime,
        endTime: endTime != null ? endTime() : this.endTime,
        webhookUrl: webhookUrl != null ? webhookUrl() : this.webhookUrl,
        autoDelete: autoDelete ?? this.autoDelete,
      );

  static String encode(List<Reminder> reminders) =>
      jsonEncode(reminders.map((r) => r.toJson()).toList());

  static List<Reminder> decode(String json) => (jsonDecode(json) as List)
      .map((r) => Reminder.fromJson(r as Map<String, dynamic>))
      .toList();

  static const availableEmojis = [
    '💧', '👀', '🪥', '🧘', '☕', '🍎', '💊', '🫁',
    '🖐️', '🚶', '🧴', '🌿', '📱', '🎵', '😤', '🧊',
  ];

  static const List<Reminder> defaults = [];
}
