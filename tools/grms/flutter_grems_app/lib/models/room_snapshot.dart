class RoomSnapshot {
  const RoomSnapshot({
    required this.hvac,
    required this.lighting,
    required this.dnd,
    required this.mur,
    required this.laundry,
    required this.status,
    required this.hasAlarm,
    this.hvacDetail,
    this.serviceEvents = const [],
  });

  final dynamic hvac;
  final String lighting;
  final String dnd;
  final String mur;
  final String laundry;
  final String status;
  final bool hasAlarm;
  final Map<String, dynamic>? hvacDetail;
  final List<Map<String, dynamic>> serviceEvents;

  factory RoomSnapshot.fromJson(Map<String, dynamic> json) => RoomSnapshot(
        hvac: json['hvac'],
        lighting: json['lighting'] as String? ?? 'Off',
        dnd: json['dnd'] as String? ?? 'Off',
        mur: json['mur'] as String? ?? 'Requested',
        laundry: json['laundry'] as String? ?? 'Requested',
        status: json['status'] as String? ?? 'Unrented Vacant',
        hasAlarm: json['hasAlarm'] as bool? ?? false,
        hvacDetail: (json['hvacDetail'] as Map?)?.cast<String, dynamic>(),
        serviceEvents: ((json['serviceEvents'] as List?) ?? const [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList(),
      );
}
