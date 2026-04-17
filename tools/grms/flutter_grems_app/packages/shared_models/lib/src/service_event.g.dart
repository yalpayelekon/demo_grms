// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'service_event.dart';

// ***************************************************************************
// JsonSerializableGenerator
// ***************************************************************************

ServiceEvent _$ServiceEventFromJson(Map<String, dynamic> json) => ServiceEvent(
      serviceType: $enumDecode(_$ServiceTypeEnumMap, json['serviceType']),
      eventType: $enumDecode(_$EventTypeEnumMap, json['eventType']),
      timestamp: (json['timestamp'] as num).toInt(),
      roomNumber: json['roomNumber'] as String,
      formattedTimestamp: json['formattedTimestamp'] as String?,
    );

Map<String, dynamic> _$ServiceEventToJson(ServiceEvent instance) => <String, dynamic>{
      'serviceType': _$ServiceTypeEnumMap[instance.serviceType]!,
      'eventType': _$EventTypeEnumMap[instance.eventType]!,
      'timestamp': instance.timestamp,
      'roomNumber': instance.roomNumber,
      'formattedTimestamp': instance.formattedTimestamp,
    };

const _$ServiceTypeEnumMap = {
  ServiceType.dnd: 'DND',
  ServiceType.mur: 'MUR',
  ServiceType.laundry: 'Laundry',
};

const _$EventTypeEnumMap = {
  EventType.requested: 'REQUESTED',
  EventType.canceled: 'CANCELED',
  EventType.started: 'STARTED',
  EventType.finished: 'FINISHED',
  EventType.activated: 'ACTIVATED',
  EventType.deactivated: 'DEACTIVATED',
};
