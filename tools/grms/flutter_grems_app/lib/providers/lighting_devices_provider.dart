import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/lighting_device.dart';
import '../services/lighting_device_config_loader.dart';
import 'state_merge_policy.dart';
import 'api_providers.dart';

@immutable
class LightingDeviceState {
  const LightingDeviceState({
    required this.deviceId,
    required this.isOn,
    required this.metadata,
  });

  final String deviceId;
  final bool isOn;
  final MergeMetadata metadata;

  LightingDeviceState copyWith({bool? isOn, MergeMetadata? metadata}) {
    return LightingDeviceState(
      deviceId: deviceId,
      isOn: isOn ?? this.isOn,
      metadata: metadata ?? this.metadata,
    );
  }
}

class LightingDeviceConfig {
  final int address;
  final String name;
  final double x;
  final double y;
  final LightingDeviceType type;

  const LightingDeviceConfig({
    required this.address,
    required this.name,
    required this.x,
    required this.y,
    this.type = LightingDeviceType.onboard,
  });
}

enum LightingConfigSource { backend, asset, fallback }

class LightingDevicesNotifier
    extends Notifier<Map<String, LightingDeviceState>> {
  final StateMergePolicy _mergePolicy = const StateMergePolicy();
  final LightingDeviceConfigLoader _configLoader =
      const LightingDeviceConfigLoader();
  List<LightingDeviceConfig> _configs = emergencyFallbackConfigs;
  Future<void>? _configLoadFuture;
  bool _hasCoordinateOverride = false;
  LightingConfigSource _configSource = LightingConfigSource.fallback;

  @override
  Map<String, LightingDeviceState> build() {
    _configLoadFuture = _loadTemplateConfigsIfNeeded();
    return {};
  }

  static const List<LightingDeviceConfig> emergencyFallbackConfigs = [
    LightingDeviceConfig(address: 12, x: 550, y: 233, name: 'Bed Left'),
    LightingDeviceConfig(address: 4, x: 905, y: 233, name: 'Bed Right'),
    LightingDeviceConfig(address: 3, x: 385, y: 230, name: 'Cove Top'),
    LightingDeviceConfig(address: 6, x: 385, y: 500, name: 'Cove Bottom'),
    LightingDeviceConfig(address: 15, x: 550, y: 580, name: 'Lambader'),
    LightingDeviceConfig(address: 10, x: 700, y: 500, name: 'Bed Top'),
    LightingDeviceConfig(address: 16, x: 1080, y: 490, name: 'Corridor Left'),
    LightingDeviceConfig(address: 8, x: 1210, y: 490, name: 'Corridor Right'),
    LightingDeviceConfig(address: 7, x: 1120, y: 295, name: 'Bathroom Left'),
    LightingDeviceConfig(address: 14, x: 1370, y: 300, name: 'Bathroom Right'),
  ];

  List<LightingDeviceConfig> get configs => List.unmodifiable(_configs);
  LightingConfigSource get configSource => _configSource;

  Future<void> ensureConfigLoaded() async {
    _configLoadFuture ??= _loadTemplateConfigsIfNeeded();
    await _configLoadFuture;
  }

  Future<void> reloadAssetConfigsForHotReload() async {
    try {
      final assetConfigs = await _configLoader.loadFromAsset();
      if (assetConfigs.isEmpty) {
        return;
      }
      _hasCoordinateOverride = false;
      _configs = assetConfigs;
      _configSource = LightingConfigSource.asset;
      _notifyConfigChanged();
      if (kDebugMode) {
        debugPrint(
          'LightingDevicesNotifier: hot-reload asset config applied '
          'count=${_configs.length}',
        );
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          'LightingDevicesNotifier: hot-reload asset refresh failed: $error',
        );
      }
    }
  }

  Future<void> _loadTemplateConfigsIfNeeded() async {
    if (_hasCoordinateOverride) {
      return;
    }
    try {
      final assetConfigs = await _configLoader.loadFromAsset();
      if (assetConfigs.isNotEmpty && !_hasCoordinateOverride) {
        _configs = assetConfigs;
        _configSource = LightingConfigSource.asset;
        if (kDebugMode) {
          debugPrint(
            'LightingDevicesNotifier: template source=asset '
            'count=${_configs.length}',
          );
        }
      } else if (kDebugMode) {
        if (!_hasCoordinateOverride) {
          _configSource = LightingConfigSource.fallback;
        }
        debugPrint(
          'LightingDevicesNotifier: template source=fallback '
          'count=${_configs.length}',
        );
      }
    } catch (error) {
      if (kDebugMode) {
        if (!_hasCoordinateOverride) {
          _configSource = LightingConfigSource.fallback;
        }
        if (_hasCoordinateOverride) {
          debugPrint(
            'LightingDevicesNotifier: asset templates unavailable; '
            'coordinates override already active (count=${_configs.length})',
          );
        } else {
          debugPrint(
            'LightingDevicesNotifier: failed to load asset templates; '
            'source=fallback count=${_configs.length} error=$error',
          );
        }
      }
    }
  }

  void applyCoordinateLightingPayload(List<LightingDeviceSummary> devices) {
    if (devices.isEmpty) {
      return;
    }
    _hasCoordinateOverride = true;

    _configs = devices
        .map(
          (device) => LightingDeviceConfig(
            address: device.address,
            name: device.name,
            x: device.x ?? 0,
            y: device.y ?? 0,
            type: device.type,
          ),
        )
        .toList(growable: false);
    _configSource = LightingConfigSource.backend;

    if (kDebugMode) {
      debugPrint(
        'LightingDevicesNotifier: template source=coordinates '
        'count=${_configs.length}',
      );
    }

    applyPollingSnapshot(
      devices.map(
        (device) => LightingDeviceState(
          deviceId: device.address.toString(),
          isOn: device.actualLevel > 0,
          metadata: MergeMetadata(
            source: MergeSource.pollingSnapshot,
            observedAt: DateTime.now(),
          ),
        ),
      ),
    );
  }

  void applyLocalOptimisticUpdate({
    required String deviceId,
    required bool isOn,
    int? version,
    DateTime? eventTimestamp,
  }) {
    _merge(
      LightingDeviceState(
        deviceId: deviceId,
        isOn: isOn,
        metadata: MergeMetadata(
          source: MergeSource.localOptimistic,
          observedAt: DateTime.now(),
          eventTimestamp: eventTimestamp,
          version: version,
        ),
      ),
    );
  }

  void applyWebsocketEvent({
    required String deviceId,
    required bool isOn,
    required DateTime observedAt,
    DateTime? eventTimestamp,
    int? version,
    bool isReplay = false,
  }) {
    _merge(
      LightingDeviceState(
        deviceId: deviceId,
        isOn: isOn,
        metadata: MergeMetadata(
          source: MergeSource.websocketEvent,
          observedAt: observedAt,
          eventTimestamp: eventTimestamp,
          version: version,
          isReplay: isReplay,
        ),
      ),
    );
  }

  void applyPollingSnapshot(Iterable<LightingDeviceState> snapshot) {
    for (final device in snapshot) {
      _merge(
        device.copyWith(
          metadata: MergeMetadata(
            source: MergeSource.pollingSnapshot,
            observedAt: device.metadata.observedAt,
            eventTimestamp: device.metadata.eventTimestamp,
            version: device.metadata.version,
          ),
        ),
      );
    }
  }

  void updateConfig(
    int index,
    LightingDeviceConfig config, {
    bool persist = true,
  }) {
    if (index < 0 || index >= _configs.length) return;
    _hasCoordinateOverride = true;
    _configs = List<LightingDeviceConfig>.from(_configs)..[index] = config;
    _notifyConfigChanged();
    if (persist) {
      _persistConfigs();
    }
  }

  void addConfig(LightingDeviceConfig config, {bool persist = true}) {
    _hasCoordinateOverride = true;
    _configs = List<LightingDeviceConfig>.from(_configs)..add(config);
    _notifyConfigChanged();
    if (persist) {
      _persistConfigs();
    }
  }

  void deleteConfig(int index, {bool persist = true}) {
    if (index < 0 || index >= _configs.length) return;
    _hasCoordinateOverride = true;
    _configs = List<LightingDeviceConfig>.from(_configs)..removeAt(index);
    _notifyConfigChanged();
    if (persist) {
      _persistConfigs();
    }
  }

  Future<void> resetConfigs({bool persist = true}) async {
    _hasCoordinateOverride = false;
    final loaded = await _configLoader.loadFromAsset();
    if (loaded.isNotEmpty) {
      _configs = loaded;
      _configSource = LightingConfigSource.asset;
    } else {
      _configs = emergencyFallbackConfigs;
      _configSource = LightingConfigSource.fallback;
    }
    _notifyConfigChanged();
    if (persist) {
      _persistConfigs();
    }
  }

  void _notifyConfigChanged() {
    state = Map<String, LightingDeviceState>.from(state);
  }

  void _persistConfigs() {
    final payload = _configs
        .map(
          (cfg) => {
            'address': cfg.address,
            'name': cfg.name,
            'x': cfg.x,
            'y': cfg.y,
            'type': cfg.type == LightingDeviceType.dali ? 'dali' : 'onboard',
          },
        )
        .toList(growable: false);
    unawaited(ref.read(coordinatesApiProvider).saveLightingDevices(payload));
  }

  void _merge(LightingDeviceState incoming) {
    final current = state[incoming.deviceId];
    final next = _mergePolicy.mergeEntity<LightingDeviceState>(
      current: current,
      incoming: incoming,
      metadataOf: (value) => value.metadata,
    );
    if (!identical(next, current)) {
      final updatedMap = Map<String, LightingDeviceState>.from(state);
      updatedMap[incoming.deviceId] = next;
      state = updatedMap;
    }
  }
}

final lightingDevicesProvider =
    NotifierProvider<LightingDevicesNotifier, Map<String, LightingDeviceState>>(
      LightingDevicesNotifier.new,
    );
