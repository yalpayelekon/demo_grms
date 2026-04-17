import '../models/lighting_device.dart';
import '../providers/lighting_devices_provider.dart';

List<LightingDeviceSummary> mergeLightingConfigsWithLive({
  required List<LightingDeviceConfig> configs,
  required LightingDevicesResponse? live,
}) {
  final liveDevices = <LightingDeviceSummary>[
    ...?live?.onboardOutputs,
    ...?live?.daliOutputs,
  ];

  final byAddressAndType = <String, LightingDeviceSummary>{
    for (final device in liveDevices)
      _deviceKey(device.address, device.type): device,
  };

  final byAddress = <int, LightingDeviceSummary>{};
  for (final device in liveDevices) {
    byAddress.putIfAbsent(device.address, () => device);
  }

  final merged = <LightingDeviceSummary>[
    for (final config in configs)
      _mergeTemplateWithLive(
        config: config,
        live:
            byAddressAndType[_deviceKey(config.address, config.type)] ??
            byAddress[config.address],
      ),
  ];

  return merged;
}

LightingDeviceSummary _mergeTemplateWithLive({
  required LightingDeviceConfig config,
  LightingDeviceSummary? live,
}) {
  return LightingDeviceSummary(
    address: config.address,
    name: live?.name.isNotEmpty == true ? live!.name : config.name,
    actualLevel: live?.actualLevel ?? 0,
    targetLevel: live?.targetLevel,
    powerW: live?.powerW,
    feature: live?.feature,
    alarm: live?.alarm ?? false,
    daliSituation: live?.daliSituation,
    type: live?.type ?? LightingDeviceType.dali,
    x: config.x,
    y: config.y,
  );
}

String _deviceKey(int address, LightingDeviceType type) {
  return '${type.name}-$address';
}
