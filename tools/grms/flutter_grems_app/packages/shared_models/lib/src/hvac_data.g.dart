// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hvac_data.dart';

// ***************************************************************************
// JsonSerializableGenerator
// ***************************************************************************

HvacData _$HvacDataFromJson(Map<String, dynamic> json) => HvacData(
      state: json['state'] as String,
      onOff: json['onOff'] as int?,
      roomTemperature: HvacData._toDouble(json['roomTemperature']),
      setPoint: HvacData._toDouble(json['setPoint']),
      mode: json['mode'] as int?,
      fanMode: json['fanMode'] as int?,
      comfortTemperature: HvacData._toDouble(json['comfortTemperature']),
      lowerSetpoint: HvacData._toDouble(json['lowerSetpoint']),
      upperSetpoint: HvacData._toDouble(json['upperSetpoint']),
      keylockFunction: json['keylockFunction'] as int?,
      occupancyInput: json['occupancyInput'] as int?,
      runningStatus: json['runningStatus'] as int?,
      comError: json['comError'] as int?,
      fidelio: json['fidelio'] as int?,
    );

Map<String, dynamic> _$HvacDataToJson(HvacData instance) => <String, dynamic>{
      'state': instance.state,
      'onOff': instance.onOff,
      'roomTemperature': instance.roomTemperature,
      'setPoint': instance.setPoint,
      'mode': instance.mode,
      'fanMode': instance.fanMode,
      'comfortTemperature': instance.comfortTemperature,
      'lowerSetpoint': instance.lowerSetpoint,
      'upperSetpoint': instance.upperSetpoint,
      'keylockFunction': instance.keylockFunction,
      'occupancyInput': instance.occupancyInput,
      'runningStatus': instance.runningStatus,
      'comError': instance.comError,
      'fidelio': instance.fidelio,
    };
