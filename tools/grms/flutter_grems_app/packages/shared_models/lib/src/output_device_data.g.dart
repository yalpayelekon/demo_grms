// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'output_device_data.dart';

// ***************************************************************************
// JsonSerializableGenerator
// ***************************************************************************

OutputDeviceData _$OutputDeviceDataFromJson(Map<String, dynamic> json) =>
    OutputDeviceData(
      address: json['address'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      variety: json['variety'] as String? ?? '',
      type: json['type'] as String? ?? '',
      actualLevel: json['actualLevel'] as int? ?? 0,
      targetLevel: json['targetLevel'] as int? ?? 0,
      status: json['status'] as String? ?? '',
      onboard: json['onboard'] as bool? ?? false,
    );

Map<String, dynamic> _$OutputDeviceDataToJson(OutputDeviceData instance) =>
    <String, dynamic>{
      'address': instance.address,
      'name': instance.name,
      'variety': instance.variety,
      'type': instance.type,
      'actualLevel': instance.actualLevel,
      'targetLevel': instance.targetLevel,
      'status': instance.status,
      'onboard': instance.onboard,
    };
