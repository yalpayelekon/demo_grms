import 'package:json_annotation/json_annotation.dart';

part 'enums.g.dart';

@JsonEnum(alwaysCreate: true)
enum AppState {
  @JsonValue('CONFIGURATION_STATE')
  configurationState,
  @JsonValue('RUN_STATE')
  runState,
}

@JsonEnum(alwaysCreate: true, valueField: 'value')
enum DeviceFeature {
  general(0, 'General'),
  doorbell(1, 'Doorbell'),
  masterContact(2, 'Master Contact'),
  fcuContact(3, 'FCU Contact'),
  idle(255, 'Idle');

  const DeviceFeature(this.value, this.description);

  final int value;
  final String description;

  static DeviceFeature fromValue(int value) =>
      DeviceFeature.values.firstWhere((item) => item.value == value,
          orElse: () => DeviceFeature.idle);
}

@JsonEnum(alwaysCreate: true, valueField: 'value')
enum DeviceSituation {
  idle(0),
  active(1),
  passive(2),
  pendent(3);

  const DeviceSituation(this.value);

  final int value;

  static DeviceSituation fromValue(int value) =>
      DeviceSituation.values.firstWhere((item) => item.value == value,
          orElse: () => DeviceSituation.idle);
}

@JsonEnum(alwaysCreate: true, valueField: 'value')
enum DeviceType {
  idle(0, 'Idle'),
  digidimButton135(1, 'Digidim Button135'),
  digidimMiniInputUnit(2, 'Digidim MiniInputUnit'),
  digidim320Sensor(3, 'Digidim 320 Sensor'),
  digidimButtonEx13x(4, 'Digidim Button ex 13X'),
  elekonMiniInputUnit8(5, 'Elekon MiniInputUnit 8'),
  onboardInputs(6, 'Onboard Inputs'),
  onboardRelayOutput(7, 'Onboard RelayOutput'),
  onboardTriacDimmer(8, 'Onboard TriacDimmer'),
  onboardTriacSsRelay(9, 'Onboard TriacSSRelay'),
  daliGear(10, 'Dali Gear'),
  elekonMiniInputUnit4(11, 'Elekon MiniInputUnit 4'),
  elekonTinyIo(12, 'Elekon TinyIO'),
  elekonDndPanel(13, 'Elekon DNDPanel'),
  unknown(254, 'Unknown'),
  mask(255, 'Mask');

  const DeviceType(this.value, this.description);

  final int value;
  final String description;

  static DeviceType fromValue(int value) =>
      DeviceType.values.firstWhere((item) => item.value == value,
          orElse: () => DeviceType.unknown);
}

@JsonEnum(alwaysCreate: true, valueField: 'value')
enum DeviceVariety {
  idle(0),
  daliController(1),
  daliGear(2),
  digidimController(3),
  digidimGear(4),
  elekonController(5),
  elekonGear(6),
  onboardController(7),
  onboardGear(8),
  rs485(9),
  unknown(254),
  mask(255);

  const DeviceVariety(this.value);

  final int value;

  static DeviceVariety fromValue(int value) =>
      DeviceVariety.values.firstWhere((item) => item.value == value,
          orElse: () => DeviceVariety.unknown);
}

@JsonEnum(alwaysCreate: true, valueField: 'value')
enum InstanceBehavior {
  idle(0, 'IDLE'),
  eventgen(1, 'EVENTGEN'),
  singlepress(2, 'SINGLEPRESS'),
  timedpress(3, 'TIMEDPRESS'),
  toggle(4, 'TOGGLE'),
  modifier(5, 'MODIFIER'),
  touchdim(6, 'TOUCHDIM'),
  edgemode(7, 'EDGEMODE'),
  analog(8, 'ANALOG'),
  dndDnd(9, 'DND_DND'),
  dndLaundry(10, 'DND_LOUNDRY'),
  dndMakeuproom(11, 'DND_MAKEUPROOM'),
  dndDoorcontact(12, 'DND_DOORCONTACT'),
  mask(255, 'MASK');

  const InstanceBehavior(this.value, this.description);

  final int value;
  final String description;

  static InstanceBehavior fromValue(int value) =>
      InstanceBehavior.values.firstWhere((item) => item.value == value,
          orElse: () => InstanceBehavior.idle);
}

@JsonEnum(alwaysCreate: true, valueField: 'value')
enum InstanceFunction {
  idle(0, 'Idle'),
  callscene(1, 'CallScene'),
  directlvl(2, 'DirectLevel'),
  up(3, 'Up'),
  down(4, 'Down'),
  max(5, 'Max'),
  min(6, 'Min'),
  off(7, 'Off'),
  lastlvl(8, 'LastLevel'),
  mask(255, 'Mask');

  const InstanceFunction(this.value, this.description);

  final int value;
  final String description;

  static InstanceFunction fromValue(int value) =>
      InstanceFunction.values.firstWhere((item) => item.value == value,
          orElse: () => InstanceFunction.idle);
}

@JsonEnum(alwaysCreate: true)
enum MurState {
  @JsonValue('PASSIVE')
  passive,
  @JsonValue('ACTIVE')
  active,
  @JsonValue('PROGRESS')
  progress,
}
