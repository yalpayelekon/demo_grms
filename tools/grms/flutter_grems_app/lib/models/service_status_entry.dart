class ServiceStatusEntry {
  const ServiceStatusEntry({
    required this.id,
    required this.roomNumber,
    required this.serviceType,
    required this.serviceState,
    required this.activationTime,
    this.delayedMinutes = 0,
    this.acknowledgement,
  });

  final String id;
  final String roomNumber;
  final String serviceType;
  final String serviceState;
  final String activationTime;
  final int delayedMinutes;
  final String? acknowledgement;

  ServiceStatusEntry copyWith({
    String? serviceState,
    int? delayedMinutes,
    String? acknowledgement,
  }) =>
      ServiceStatusEntry(
        id: id,
        roomNumber: roomNumber,
        serviceType: serviceType,
        serviceState: serviceState ?? this.serviceState,
        activationTime: activationTime,
        delayedMinutes: delayedMinutes ?? this.delayedMinutes,
        acknowledgement: acknowledgement ?? this.acknowledgement,
      );
}
