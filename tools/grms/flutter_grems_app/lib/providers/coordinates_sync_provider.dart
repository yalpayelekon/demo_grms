import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/api_result.dart';
import '../models/coordinates_models.dart';
import '../config/app_config.dart';
import 'api_providers.dart';
import 'lighting_devices_provider.dart';
import 'service_icon_positions_provider.dart';
import 'zones_provider.dart';

@visibleForTesting
Uri buildCoordinatesWsUri(String apiBaseUrl, {Uri? currentBase}) {
  final parsedBase = Uri.parse(apiBaseUrl);
  Uri resolvedBase = parsedBase.hasScheme && parsedBase.host.isNotEmpty
      ? parsedBase
      : (currentBase ?? Uri.base).resolveUri(parsedBase);
  if (resolvedBase.host.isEmpty) {
    final fallback = currentBase ?? Uri.base;
    resolvedBase = Uri(
      scheme: fallback.scheme,
      host: fallback.host,
      port: fallback.hasPort ? fallback.port : null,
      path: '/',
    );
  }
  final wsScheme = resolvedBase.scheme == 'https' ? 'wss' : 'ws';

  return Uri(
    scheme: wsScheme,
    host: resolvedBase.host,
    port: resolvedBase.hasPort ? resolvedBase.port : null,
    path: '/testcomm/coordinates/stream',
  );
}

bool shouldApplyBackendLightingCoordinates({
  required LightingCoordinatesSourceMode mode,
  required bool isDebugBuild,
}) {
  switch (mode) {
    case LightingCoordinatesSourceMode.assetInDebugBackendInRelease:
      return !isDebugBuild;
    case LightingCoordinatesSourceMode.backendAlways:
      return true;
    case LightingCoordinatesSourceMode.assetAlways:
      return false;
  }
}

final lightingCoordinatesSourceModeOverrideProvider =
    StateProvider<LightingCoordinatesSourceMode?>((ref) => null);

final effectiveLightingCoordinatesSourceModeProvider =
    Provider<LightingCoordinatesSourceMode>((ref) {
      final override = ref.watch(lightingCoordinatesSourceModeOverrideProvider);
      if (override != null) {
        return override;
      }
      return ref.watch(appConfigProvider).lightingCoordinatesSourceMode;
    });

@immutable
class CoordinatesSyncState {
  const CoordinatesSyncState({
    this.connected = false,
    this.reconnectAttempt = 0,
    this.lastError,
  });

  final bool connected;
  final int reconnectAttempt;
  final String? lastError;

  CoordinatesSyncState copyWith({
    bool? connected,
    int? reconnectAttempt,
    String? lastError,
    bool clearError = false,
  }) {
    return CoordinatesSyncState(
      connected: connected ?? this.connected,
      reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

class CoordinatesSyncNotifier extends Notifier<CoordinatesSyncState> {
  WebSocketChannel? _channel;
  StreamSubscription? _channelSubscription;
  Timer? _reconnectTimer;
  String? _lastZonesPayloadDigest;

  @override
  CoordinatesSyncState build() {
    unawaited(_startSync());
    ref.onDispose(() {
      _reconnectTimer?.cancel();
      unawaited(_channelSubscription?.cancel());
      _channel?.sink.close();
    });
    return const CoordinatesSyncState();
  }

  Future<void> _startSync() async {
    await _refreshFromRest();
    _connectWebSocket();
  }

  Future<void> _refreshFromRest() async {
    final result = await ref.read(coordinatesApiProvider).getCoordinates();
    if (result is Failure<CoordinatesPayload>) {
      state = state.copyWith(lastError: result.error.message);
      return;
    }

    final payload = (result as Success<CoordinatesPayload>).value;
    _applyPayload(payload);
    state = state.copyWith(clearError: true);
  }

  Uri _coordinatesWsUri() {
    final baseUrl = ref.read(appConfigProvider).apiBaseUrl;
    return buildCoordinatesWsUri(baseUrl);
  }

  Future<void> _connectWebSocket() async {
    _reconnectTimer?.cancel();

    try {
      final channel = WebSocketChannel.connect(_coordinatesWsUri());
      await channel.ready;
      _channel = channel;
      _channelSubscription = channel.stream.listen(
        _onSocketMessage,
        onError: (error) => _scheduleReconnect(error.toString()),
        onDone: () => _scheduleReconnect('Coordinates stream closed'),
      );
      state = state.copyWith(connected: true, clearError: true);
    } catch (error) {
      _scheduleReconnect(error.toString());
    }
  }

  void _onSocketMessage(dynamic event) {
    Map<String, dynamic>? message;
    try {
      if (event is String) {
        message = jsonDecode(event) as Map<String, dynamic>;
      } else if (event is List<int>) {
        message = jsonDecode(utf8.decode(event)) as Map<String, dynamic>;
      }
    } catch (error) {
      debugPrint('CoordinatesSync: failed to decode ws message: $error');
      return;
    }

    if (message == null) {
      return;
    }

    final payloadRaw = message['payload'] as Map<String, dynamic>?;
    if (payloadRaw == null) {
      return;
    }

    final payload = CoordinatesPayload.fromJson(payloadRaw);
    _applyPayload(payload);
    state = state.copyWith(
      connected: true,
      reconnectAttempt: 0,
      clearError: true,
    );
  }

  void _applyPayload(CoordinatesPayload payload) {
    final zonesDigest = jsonEncode(payload.zones);
    if (zonesDigest != _lastZonesPayloadDigest) {
      _lastZonesPayloadDigest = zonesDigest;
      ref.read(zonesProvider.notifier).applyCoordinatesPayload(payload.zones);
    } else if (kDebugMode) {
      debugPrint('CoordinatesSync: skipped unchanged zones payload');
    }

    if (payload.serviceIcons.isNotEmpty) {
      ref
          .read(serviceIconPositionsProvider.notifier)
          .applyFromPayload(payload.serviceIcons);
    }

    final sourceMode = ref.read(effectiveLightingCoordinatesSourceModeProvider);
    final shouldApply = shouldApplyBackendLightingCoordinates(
      mode: sourceMode,
      isDebugBuild: kDebugMode,
    );

    if (shouldApply) {
      if (payload.lightingDevices.isEmpty) {
        if (kDebugMode) {
          debugPrint(
            'CoordinatesSync: backend coordinates empty; falling back to local template',
          );
        }
        return;
      }
      ref
          .read(lightingDevicesProvider.notifier)
          .applyCoordinateLightingPayload(payload.lightingDevices);
      if (kDebugMode) {
        debugPrint(
          'CoordinatesSync: applied backend lighting coordinates '
          'mode=$sourceMode count=${payload.lightingDevices.length}',
        );
      }
      return;
    }

    if (kDebugMode) {
      debugPrint(
        'CoordinatesSync: skipped backend lighting coordinates '
        'mode=$sourceMode debug=$kDebugMode',
      );
    }
  }

  void _scheduleReconnect(String error) {
    state = state.copyWith(
      connected: false,
      reconnectAttempt: state.reconnectAttempt + 1,
      lastError: error,
    );

    _channelSubscription?.cancel();
    _channelSubscription = null;
    _channel?.sink.close();
    _channel = null;

    final attempt = state.reconnectAttempt.clamp(1, 6).toInt();
    final delaySeconds = 1 << (attempt - 1); // 1,2,4,8,16,32
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      await _refreshFromRest();
      _connectWebSocket();
    });
  }
}

final coordinatesSyncProvider =
    NotifierProvider<CoordinatesSyncNotifier, CoordinatesSyncState>(
      CoordinatesSyncNotifier.new,
    );
