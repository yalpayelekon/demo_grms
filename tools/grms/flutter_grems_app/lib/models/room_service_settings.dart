class RoomServiceSettings {
  const RoomServiceSettings({
    required this.murDelayThresholdSeconds,
    required this.laundryDelayThresholdSeconds,
  });

  final int murDelayThresholdSeconds;
  final int laundryDelayThresholdSeconds;

  static const defaults = RoomServiceSettings(murDelayThresholdSeconds: 10, laundryDelayThresholdSeconds: 10);

  RoomServiceSettings copyWith({int? murDelayThresholdSeconds, int? laundryDelayThresholdSeconds}) => RoomServiceSettings(
        murDelayThresholdSeconds: murDelayThresholdSeconds ?? this.murDelayThresholdSeconds,
        laundryDelayThresholdSeconds: laundryDelayThresholdSeconds ?? this.laundryDelayThresholdSeconds,
      );

  Map<String, dynamic> toJson() => {
        'murDelayThresholdSeconds': murDelayThresholdSeconds,
        'laundryDelayThresholdSeconds': laundryDelayThresholdSeconds,
      };

  factory RoomServiceSettings.fromJson(Map<String, dynamic> json) => RoomServiceSettings(
        murDelayThresholdSeconds: (json['murDelayThresholdSeconds'] as num?)?.toInt() ?? defaults.murDelayThresholdSeconds,
        laundryDelayThresholdSeconds: (json['laundryDelayThresholdSeconds'] as num?)?.toInt() ?? defaults.laundryDelayThresholdSeconds,
      );
}
