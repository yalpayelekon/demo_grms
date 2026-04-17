import '../models/lighting_device.dart';

const String lightingGearAlarmTooltip = 'Gear Alarm';

String? lightingAlarmLabel(LightingDeviceSummary device) {
  if (!device.alarm) {
    return null;
  }
  return lightingGearAlarmTooltip;
}

String displayLightingDeviceName(LightingDeviceSummary device) {
  final trimmed = device.name.trim();
  if (trimmed.isEmpty || trimmed.contains('\uFFFD')) {
    return 'Device ${device.address}';
  }
  final visibleChars = trimmed.runes.where((rune) => rune > 0x20).length;
  if (visibleChars < 2) {
    return 'Device ${device.address}';
  }
  return trimmed;
}
