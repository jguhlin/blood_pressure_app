class Event {
  final String id;
  final String title;
  final DateTime date;
  const Event({required this.id, required this.title, required this.date});
  Event copyWith({String? title, DateTime? date}) =>
      Event(id: id, title: title ?? this.title, date: date ?? this.date);
}
