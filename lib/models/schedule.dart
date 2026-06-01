import '../utils/image_utils.dart';

class ScheduleEntry {
  final String? id;
  final String title;
  final String? slug;
  final String url;
  final String? image;
  final String airingDay;
  final String? airingTime;
  final String? scheduleLabel;
  final double? episodeNumber;
  final String? type;

  ScheduleEntry({
    this.id,
    required this.title,
    this.slug,
    required this.url,
    this.image,
    required this.airingDay,
    this.airingTime,
    this.scheduleLabel,
    this.episodeNumber,
    this.type,
  });

  String get displayTime => scheduleLabel ?? airingTime ?? '';

  factory ScheduleEntry.fromJson(Map<String, dynamic> json) {
    return ScheduleEntry(
      id: json['id']?.toString(),
      title: json['title']?.toString() ?? 'Sin título',
      slug: json['slug']?.toString(),
      url: json['url']?.toString() ?? '',
      image: pickAnimeImageUrl(json) ?? normalizeAnimeImageUrl(json['image']?.toString()),
      airingDay: json['airingDay']?.toString() ?? '',
      airingTime: json['airingTime']?.toString(),
      scheduleLabel: json['scheduleLabel']?.toString(),
      episodeNumber: json['episodeNumber'] != null
          ? double.tryParse(json['episodeNumber'].toString())
          : null,
      type: json['type']?.toString(),
    );
  }
}

class ScheduleDay {
  final String day;
  final List<ScheduleEntry> items;

  ScheduleDay({required this.day, required this.items});

  factory ScheduleDay.fromJson(Map<String, dynamic> json) {
    final raw = json['items'] as List? ?? [];
    return ScheduleDay(
      day: json['day']?.toString() ?? '',
      items: raw.map((e) => ScheduleEntry.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

class WeeklySchedule {
  final List<ScheduleDay> days;
  final int totalItems;

  WeeklySchedule({required this.days, required this.totalItems});

  factory WeeklySchedule.fromJson(Map<String, dynamic> json) {
    final rawDays = json['days'] as List? ?? [];
    return WeeklySchedule(
      days: rawDays.map((d) => ScheduleDay.fromJson(d as Map<String, dynamic>)).toList(),
      totalItems: int.tryParse(json['totalItems']?.toString() ?? '') ?? 0,
    );
  }

  List<ScheduleEntry> itemsForDay(String day) {
    for (final entry in days) {
      if (entry.day == day) return entry.items;
    }
    return [];
  }
}

const scheduleDayLabels = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
];

String scheduleDayForDate(DateTime date) {
  final index = date.weekday - 1;
  if (index < 0 || index >= scheduleDayLabels.length) return scheduleDayLabels.first;
  return scheduleDayLabels[index];
}
