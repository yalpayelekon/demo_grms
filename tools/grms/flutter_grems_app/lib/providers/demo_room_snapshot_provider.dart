import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/room_runtime_snapshot.dart';
import 'api_providers.dart';

class DemoRoomSnapshotState {
  const DemoRoomSnapshotState({
    this.snapshot,
    this.runtimeSnapshot,
    this.snapshotVersion = 0,
    this.connected = false,
    this.source = 'live',
    this.targetUnreachable = false,
    this.message,
    this.reconnectAttempt = 0,
  });

  final Map<String, dynamic>? snapshot;
  final RoomRuntimeSnapshot? runtimeSnapshot;
  final int snapshotVersion;
  final bool connected;
  final String source;
  final bool targetUnreachable;
  final String? message;
  final int reconnectAttempt;

  DemoRoomSnapshotState copyWith({
    Map<String, dynamic>? snapshot,
    RoomRuntimeSnapshot? runtimeSnapshot,
    bool clearRuntimeSnapshot = false,
    bool clearSnapshot = false,
    int? snapshotVersion,
    bool? connected,
    String? source,
    bool? targetUnreachable,
    String? message,
    bool clearMessage = false,
    int? reconnectAttempt,
  }) {
    return DemoRoomSnapshotState(
      snapshot: clearSnapshot ? null : (snapshot ?? this.snapshot),
      runtimeSnapshot: clearRuntimeSnapshot
          ? null
          : (runtimeSnapshot ?? this.runtimeSnapshot),
      snapshotVersion: snapshotVersion ?? this.snapshotVersion,
      connected: connected ?? this.connected,
      source: source ?? this.source,
      targetUnreachable: targetUnreachable ?? this.targetUnreachable,
      message: clearMessage ? null : (message ?? this.message),
      reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
    );
  }
}

class RoomSnapshotNotifier
    extends FamilyNotifier<DemoRoomSnapshotState, String> {
  static const String demoRoomNumber = 'Demo 101';

  final http.Client _snapshotHttpClient = http.Client();
  final http.Client _sseHttpClient = http.Client();
  StreamSubscription<String>? _sseSubscription;
  Timer? _pollTimer;
  Timer? _reconnectTimer;
  bool _sseConnected = false;
  int _reconnectAttempts = 0;
  late final String _roomNumber;

  @override
  DemoRoomSnapshotState build(String roomNumber) {
    _roomNumber = roomNumber;
    _start();
    ref.onDispose(() {
      _reconnectTimer?.cancel();
      _pollTimer?.cancel();
      _sseSubscription?.cancel();
      _snapshotHttpClient.close();
      _sseHttpClient.close();
    });
    return const DemoRoomSnapshotState();
  }

  void _start() {
    _fetchSnapshot();
    _connectSse();
    _startPolling();
  }

  Future<void> refreshNow() async {
    await _fetchSnapshot();
  }

  void _startPolling() {
    _pollTimer ??= Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_sseConnected) {
        _fetchSnapshot();
      }
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectAttempts += 1;
    final seconds = min(30, 1 << _reconnectAttempts.clamp(0, 5));
    state = state.copyWith(
      connected: false,
      targetUnreachable: true,
      message: 'Target unreachable. Reconnecting in ${seconds}s…',
      reconnectAttempt: _reconnectAttempts,
    );
    _reconnectTimer = Timer(Duration(seconds: seconds), _connectSse);
  }

  Future<void> _fetchSnapshot() async {
    final baseUrl = ref.read(appConfigProvider).apiBaseUrl;
    final uri = Uri.parse(
      '$baseUrl/testcomm/rooms/${Uri.encodeComponent(_roomNumber)}',
    );

    try {
      final response = await _snapshotHttpClient.get(uri);
      if (response.statusCode != 200) {
        return;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        _applySnapshot(decoded);
      } else if (decoded is Map) {
        _applySnapshot(Map<String, dynamic>.from(decoded));
      }
      state = state.copyWith(
        connected: _sseConnected,
        targetUnreachable: false,
        clearMessage: true,
      );
    } catch (_) {
      // Keep existing state while polling/fallback continues.
    }
  }

  Future<void> _connectSse() async {
    if (_sseSubscription != null) {
      return;
    }

    final baseUrl = ref.read(appConfigProvider).apiBaseUrl;
    final uri = Uri.parse(
      '$baseUrl/testcomm/rooms/${Uri.encodeComponent(_roomNumber)}/stream',
    );

    try {
      final req = http.Request('GET', uri);
      final streamed = await _sseHttpClient.send(req);

      if (streamed.statusCode != 200) {
        _sseConnected = false;
        _startPolling();
        _scheduleReconnect();
        return;
      }

      _sseConnected = true;
      _reconnectAttempts = 0;
      _stopPolling();
      state = state.copyWith(
        connected: true,
        targetUnreachable: false,
        reconnectAttempt: 0,
        clearMessage: true,
      );

      var eventName = 'message';
      _sseSubscription = streamed.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              final trimmed = line.trimRight();
              if (trimmed.isEmpty) {
                eventName = 'message';
                return;
              }
              if (trimmed.startsWith(':')) {
                return;
              }
              if (trimmed.startsWith('event:')) {
                eventName = trimmed.substring(6).trim();
                return;
              }
              if (!trimmed.startsWith('data:') || eventName != 'snapshot') {
                return;
              }
              final dataStr = trimmed.substring(5).trim();
              try {
                final decoded = jsonDecode(dataStr);
                if (decoded is Map<String, dynamic>) {
                  _applySnapshot(decoded);
                } else if (decoded is Map) {
                  _applySnapshot(Map<String, dynamic>.from(decoded));
                }
              } catch (_) {
                // Ignore malformed SSE payloads.
              }
            },
            onDone: _onSseDisconnected,
            onError: (_) => _onSseDisconnected(),
            cancelOnError: true,
          );
    } catch (_) {
      _onSseDisconnected();
    }
  }

  void _onSseDisconnected() {
    _sseSubscription = null;
    _sseConnected = false;
    _startPolling();
    _scheduleReconnect();
  }

  void _applySnapshot(Map<String, dynamic> snapshot) {
    final meta = snapshot['_meta'];
    final source = meta is Map && meta['source'] is String
        ? (meta['source'] as String).trim()
        : '';
    final runtimeSnapshot = RoomRuntimeSnapshot.fromSnapshot(
      snapshot,
      receivedAt: DateTime.now(),
    );
    if (kDebugMode) {
      final version = state.snapshotVersion + 1;
      final prevSnapshot = state.snapshot;
      final lightingDevices = snapshot['lightingDevices'];
      List<dynamic>? prevDevices;
      if (prevSnapshot is Map<String, dynamic>) {
        final rawPrevDevices = prevSnapshot['lightingDevices'];
        if (rawPrevDevices is List) {
          prevDevices = rawPrevDevices;
        }
      }

      int changedCount = 0;

      if (lightingDevices is List && prevDevices is List) {
        // Map previous devices by (type,address) so we can diff levels.
        final prevByKey = <String, Map<String, dynamic>>{};
        for (final item in prevDevices) {
          if (item is! Map) continue;
          final map = Map<String, dynamic>.from(item);
          final address = map['address'];
          if (address == null) continue;
          final type = (map['type'] as String?)?.toLowerCase() ?? '';
          final key = '$type-$address';
          prevByKey[key] = map;
        }

        for (final item in lightingDevices) {
          if (item is! Map) continue;
          final map = Map<String, dynamic>.from(item);
          final address = map['address'];
          if (address == null) continue;
          final type = (map['type'] as String?)?.toLowerCase() ?? '';
          final key = '$type-$address';

          final prev = prevByKey[key];
          if (prev == null) {
            continue;
          }

          double toDouble(dynamic v) {
            if (v is num) return v.toDouble();
            if (v is String) {
              final parsed = double.tryParse(v);
              if (parsed != null) return parsed;
            }
            return 0;
          }

          final prevActual = toDouble(prev['actualLevel']);
          final prevTarget = toDouble(prev['targetLevel']);
          final nextActual = toDouble(map['actualLevel']);
          final nextTarget = toDouble(map['targetLevel']);

          final changed = prevActual != nextActual || prevTarget != nextTarget;
          if (changed) {
            changedCount += 1;
            debugPrint(
              'DemoRoomSnapshotNotifier: lighting change '
              'version=$version source=${source.isEmpty ? state.source : source} '
              'addr=$address type=$type '
              'actual $prevActual -> $nextActual '
              'target $prevTarget -> $nextTarget',
            );
          }
        }
      }

      if (changedCount == 0) {
        debugPrint(
          'DemoRoomSnapshotNotifier: applySnapshot(no lighting change) '
          'version=$version source=${source.isEmpty ? state.source : source}',
        );
      }
    }
    state = state.copyWith(
      snapshot: snapshot,
      runtimeSnapshot: runtimeSnapshot,
      snapshotVersion: state.snapshotVersion + 1,
      source: source.isEmpty ? state.source : source,
      targetUnreachable: false,
      clearMessage: true,
    );
  }
}

final roomSnapshotProvider =
    NotifierProviderFamily<RoomSnapshotNotifier, DemoRoomSnapshotState, String>(
      RoomSnapshotNotifier.new,
    );

final demoRoomSnapshotProvider = Provider<DemoRoomSnapshotState>((ref) {
  return ref.watch(roomSnapshotProvider(RoomSnapshotNotifier.demoRoomNumber));
});

final roomRuntimeSnapshotProvider =
    Provider.family<RoomRuntimeSnapshot?, String>((ref, roomNumber) {
      return ref.watch(roomSnapshotProvider(roomNumber)).runtimeSnapshot;
    });

final demoRoomRuntimeSnapshotProvider = Provider<RoomRuntimeSnapshot?>((ref) {
  return ref.watch(
    roomRuntimeSnapshotProvider(RoomSnapshotNotifier.demoRoomNumber),
  );
});
