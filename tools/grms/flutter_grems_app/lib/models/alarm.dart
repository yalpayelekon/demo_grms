class Alarm {
  const Alarm({
    required this.id,
    required this.room,
    required this.incidentTime,
    required this.category,
    required this.acknowledgement,
    required this.acknowledgementTime,
    required this.status,
    required this.details,
  });

  final String id;
  final String room;
  final String incidentTime;
  final String category;
  final String acknowledgement;
  final String acknowledgementTime;
  final String status;
  final String details;
}
