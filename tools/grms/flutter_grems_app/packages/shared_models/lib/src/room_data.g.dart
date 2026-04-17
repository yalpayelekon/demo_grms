// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'room_data.dart';

// ***************************************************************************
// JsonSerializableGenerator
// ***************************************************************************

RoomData _$RoomDataFromJson(Map<String, dynamic> json) => RoomData(
      hvac: HvacData.fromDynamic(json['hvac']),
      lighting: json['lighting'] as String? ?? '',
      dnd: json['dnd'] as String? ?? '',
      mur: json['mur'] as String? ?? '',
      laundry: json['laundry'] as String? ?? '',
      status: json['status'] as String? ?? '',
      hasAlarm: json['hasAlarm'] as bool? ?? false,
      lightingDevices:
          (json['lightingDevices'] as List<dynamic>? ?? const [])
              .map((e) => OutputDeviceData.fromJson(e as Map<String, dynamic>))
              .toList(),
      serviceEvents: (json['serviceEvents'] as List<dynamic>? ?? const [])
          .map((e) => ServiceEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$RoomDataToJson(RoomData instance) => <String, dynamic>{
      'hvac': HvacData.toJsonDynamic(instance.hvac),
      'lighting': instance.lighting,
      'dnd': instance.dnd,
      'mur': instance.mur,
      'laundry': instance.laundry,
      'status': instance.status,
      'hasAlarm': instance.hasAlarm,
      'lightingDevices':
          instance.lightingDevices.map((e) => e.toJson()).toList(),
      'serviceEvents': instance.serviceEvents.map((e) => e.toJson()).toList(),
    };
