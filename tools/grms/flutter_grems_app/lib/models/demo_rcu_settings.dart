class DemoRcuSettings {
  const DemoRcuSettings({
    required this.room,
    required this.host,
    required this.port,
  });

  final String room;
  final String host;
  final int port;

  factory DemoRcuSettings.fromJson(Map<String, dynamic> json) =>
      DemoRcuSettings(
        room: json['room'] as String? ?? 'Demo 101',
        host: json['host'] as String? ?? '',
        port: (json['port'] as num?)?.toInt() ?? 5556,
      );
}
