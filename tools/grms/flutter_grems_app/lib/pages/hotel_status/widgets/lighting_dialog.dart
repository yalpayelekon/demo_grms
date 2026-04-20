import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/api_result.dart';
import '../../../config/app_config.dart';
import '../../../models/lighting_device.dart';
import '../../../models/rcu_models.dart';
import '../../../models/room_models.dart';
import '../../../models/service_models.dart';
import '../../../providers/api_providers.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/coordinates_sync_provider.dart';
import '../../../providers/demo_room_snapshot_provider.dart';
import '../../../lighting/lighting_alarm_style.dart';
import '../../../lighting/lighting_device_merge.dart';
import '../../../providers/hotel_status_provider.dart';
import '../../../providers/lighting_devices_provider.dart';
import '../../../providers/room_alias_provider.dart';
import '../../../providers/room_runtime_provider.dart';
import '../../../providers/room_service_provider.dart';

class LightingDialog extends ConsumerStatefulWidget {
  const LightingDialog({super.key, required this.room});

  final RoomData room;

  @override
  ConsumerState<LightingDialog> createState() => _LightingDialogState();
}

class _LightingDialogState extends ConsumerState<LightingDialog> {
  static const double _layoutCanvasWidth = 1536;
  static const double _layoutCanvasHeight = 1060;
  static const double _pinScale = 1.56;
  static const double _pinSizeInactive = 28.0 * _pinScale;
  static const double _pinSizeActive = _pinSizeInactive * 1.5;
  bool _isLoading = false;
  String? _errorMessage;
  String? _warningMessage;

  RcuMenuResponse? _menuResponse;
  int? _lastSelectedOption;

  LightingDevicesResponse? _lightingResponse;
  String? _activeDeviceKey;
  final Map<String, TextEditingController> _deviceLevelControllers = {};
  int? _lastTriggeredScene;
  bool _isEditMode = false;
  double _setPoint = 22.0;
  bool _isOn = false;
  int _mode = 0;
  int _fanMode = 4;
  double _initialSetPoint = 22.0;
  bool _initialIsOn = false;
  int _initialMode = 0;
  int _initialFanMode = 4;
  bool _savingHvac = false;
  bool _loadingHvac = false;
  bool _updatingBlinds = false;
  bool _masterPowerEnabled = true;
  bool _masterPowerDirty = false;
  final GlobalKey _layoutStackKey = GlobalKey();
  final Map<String, Offset> _dragCanvasPositions = <String, Offset>{};
  String? _draggingKey;
  final FocusNode _layoutFocusNode = FocusNode(debugLabel: 'lighting-layout');
  Timer? _keyboardPersistTimer;
  ProviderSubscription<RoomLightingRuntimeState>? _roomLightingSubscription;
  ProviderSubscription<RoomData?>? _roomRuntimeSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _init();
    });
  }

  @override
  void reassemble() {
    super.reassemble();
    if (!kDebugMode) {
      return;
    }
    Future<void>(() async {
      final sourceMode = ref.read(
        effectiveLightingCoordinatesSourceModeProvider,
      );
      if (sourceMode == LightingCoordinatesSourceMode.backendAlways) {
        if (kDebugMode) {
          debugPrint(
            'LightingDialog: skipping asset hot-reload refresh because backend coordinates are authoritative.',
          );
        }
        return;
      }
      await ref
          .read(lightingDevicesProvider.notifier)
          .reloadAssetConfigsForHotReload();
      if (!mounted) {
        return;
      }
      setState(() {
        _updateDeviceControllers();
      });
    });
  }

  Future<void> _init() async {
    _attachRoomRuntimeListeners();
    _hydrateHvacFromRoom(_latestRoom);
    await ref.read(lightingDevicesProvider.notifier).ensureConfigLoaded();
    if (ref.read(roomSnapshotProvider(widget.room.number)).snapshot == null) {
      await ref
          .read(roomSnapshotProvider(widget.room.number).notifier)
          .refreshNow();
    }
    final authState = ref.read(authProvider);
    final role = authState.user?.role;
    final isConsoleUser = role == UserRole.operator;

    if (isConsoleUser) {
      await _loadMenu(null);
    }
  }

  @override
  void dispose() {
    _roomLightingSubscription?.close();
    _roomRuntimeSubscription?.close();
    for (final controller in _deviceLevelControllers.values) {
      controller.dispose();
    }
    _keyboardPersistTimer?.cancel();
    _layoutFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadMenu(
    int? choice, {
    Map<String, dynamic>? parameters,
  }) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final api = ref.read(roomControlApiProvider);
    final result = await api.fetchRcuMenu(
      RcuMenuRequest(
        roomNumber: widget.room.number,
        choice: choice,
        parameters: parameters,
      ),
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _isLoading = false;
      if (result is Success<RcuMenuResponse>) {
        _menuResponse = result.value;
      } else if (result is Failure<RcuMenuResponse>) {
        _errorMessage = result.error.message;
      }
    });
  }

  void _attachRoomRuntimeListeners() {
    _roomLightingSubscription ??= ref.listenManual<RoomLightingRuntimeState>(
      roomLightingRuntimeProvider(widget.room.number),
      (previous, next) {
        if (!mounted) {
          return;
        }
        setState(() {
          _lightingResponse = next.lighting;
          _warningMessage = next.lighting == null
              ? 'Live device levels are unavailable. Showing template layout.'
              : null;
          _updateDeviceControllers();
        });
      },
    );
    _roomRuntimeSubscription ??= ref.listenManual<RoomData?>(
      roomRuntimeRoomViewProvider(widget.room.number),
      (previous, next) {
        if (!mounted || next == null) {
          return;
        }
        setState(() {});
        if (!_hasHvacChanges) {
          _hydrateHvacFromRoom(next);
        }
      },
    );
    final currentLighting = ref.read(
      roomLightingRuntimeProvider(widget.room.number),
    );
    if (_lightingResponse == null && currentLighting.lighting != null) {
      _lightingResponse = currentLighting.lighting;
      _warningMessage = null;
      _updateDeviceControllers();
    }
  }

  void _hydrateHvacFromRoom(RoomData room) {
    final detail = room.hvacDetail;
    _setPoint = detail?.setPoint ?? 22.0;
    _isOn = (detail?.onOff ?? (room.hvac == HvacStatus.off ? 0 : 1)) == 1;
    _mode = _normalizeMode(detail?.mode);
    _fanMode = _normalizeFanMode(detail?.fanMode);
    _initialSetPoint = _setPoint;
    _initialIsOn = _isOn;
    _initialMode = _mode;
    _initialFanMode = _fanMode;
    if (_masterPowerDirty) {
      if (room.lightingOn == _masterPowerEnabled) {
        _masterPowerDirty = false;
      }
    } else {
      _masterPowerEnabled = room.lightingOn;
    }
  }

  int _normalizeMode(int? raw) {
    final value = raw ?? 0;
    if (value >= 0 && value <= 3) return value;
    return 0;
  }

  int _normalizeFanMode(int? raw) {
    final value = raw ?? 4;
    if (value >= 1 && value <= 4) return value;
    return 4;
  }

  bool get _hasHvacChanges {
    final setPointChanged = (_setPoint - _initialSetPoint).abs() >= 0.1;
    return _isOn != _initialIsOn ||
        setPointChanged ||
        _mode != _initialMode ||
        _fanMode != _initialFanMode;
  }

  String get _modeLabel {
    switch (_mode) {
      case 0:
        return 'Heat';
      case 1:
        return 'Cool';
      case 2:
        return 'Fan Only';
      case 3:
        return 'Auto';
      default:
        return 'Heat';
    }
  }

  String get _fanLabel {
    switch (_fanMode) {
      case 1:
        return 'Low';
      case 2:
        return 'Medium';
      case 3:
        return 'High';
      default:
        return 'Auto';
    }
  }

  Future<void> _refreshHvacFromBackend() async {
    setState(() => _loadingHvac = true);
    await ref
        .read(roomSnapshotProvider(widget.room.number).notifier)
        .refreshNow();
    if (!mounted) {
      return;
    }
    final refreshed = ref.read(roomRuntimeRoomViewProvider(widget.room.number));
    if (refreshed != null && !_hasHvacChanges) {
      _hydrateHvacFromRoom(refreshed);
    }
    setState(() => _loadingHvac = false);
  }

  Future<void> _saveHvac() async {
    setState(() => _savingHvac = true);
    final notifier = ref.read(hotelStatusProvider.notifier);
    final result = await notifier.updateHvac(widget.room.number, {
      'onOff': _isOn ? 1 : 0,
      'setPoint': _setPoint.toStringAsFixed(1),
      'mode': _mode,
      'fanMode': _fanMode,
    });
    if (!mounted) {
      return;
    }
    setState(() => _savingHvac = false);
    if (result is Failure<void>) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update HVAC: ${result.error.message}'),
        ),
      );
      return;
    }
    setState(() {
      _initialSetPoint = _setPoint;
      _initialIsOn = _isOn;
      _initialMode = _mode;
      _initialFanMode = _fanMode;
    });
    unawaited(_refreshHvacFromBackend());
  }

  List<LightingDeviceSummary> _buildMergedDevices() {
    final configs = ref.read(lightingDevicesProvider.notifier).configs;
    return mergeLightingConfigsWithLive(
      configs: configs,
      live: _lightingResponse,
    );
  }

  void _updateDeviceControllers() {
    final merged = _buildMergedDevices();
    for (final device in merged) {
      final key = '${device.type.name}-${device.address}';
      _deviceLevelControllers.putIfAbsent(
        key,
        () => TextEditingController(
          text: (device.targetLevel ?? device.actualLevel).round().toString(),
        ),
      );
    }

    if (_activeDeviceKey == null && merged.isNotEmpty) {
      _activeDeviceKey = '${merged.first.type.name}-${merged.first.address}';
      return;
    }

    final activeStillExists = merged.any(
      (device) => '${device.type.name}-${device.address}' == _activeDeviceKey,
    );
    if (!activeStillExists && merged.isNotEmpty) {
      _activeDeviceKey = '${merged.first.type.name}-${merged.first.address}';
    }
  }

  RoomData get _latestRoom {
    return ref.read(roomRuntimeRoomViewProvider(widget.room.number)) ??
        ref.read(hotelStatusProvider).rooms[widget.room.number] ??
        widget.room;
  }

  Future<void> _triggerScene(int scene) async {
    if (scene == 6) {
      await _toggleMasterPower();
      return;
    }
    final tappedAt = DateTime.now();
    final clientTappedAtMs = tappedAt.millisecondsSinceEpoch;
    final clientRequestId = 'scene-$clientTappedAtMs-$scene';
    final lightingNotifier = ref.read(
      roomLightingRuntimeProvider(widget.room.number).notifier,
    );
    if (kDebugMode) {
      debugPrint(
        'LightingDialog: scene tap room=${widget.room.number} '
        'scene=$scene requestId=$clientRequestId '
        'at=${tappedAt.toIso8601String()} tappedAtMs=$clientTappedAtMs',
      );
    }
    setState(() => _lastTriggeredScene = scene);
    lightingNotifier.startScene(scene, clientRequestId, tappedAt);
    final api = ref.read(roomControlApiProvider);
    try {
      final result = await api.triggerLightingScene(
        widget.room.number,
        scene,
        clientRequestId: clientRequestId,
        clientTappedAtMs: clientTappedAtMs,
      );
      if (!mounted) {
        return;
      }
      if (result is Success<LightingSceneTriggerResponse> &&
          result.value.triggered) {
        lightingNotifier.ackScene(clientRequestId);
        return;
      }
      final errorText = result is Failure<LightingSceneTriggerResponse>
          ? result.error.message
          : 'Scene call was not accepted by backend.';
      lightingNotifier.failScene(clientRequestId);
      setState(() => _errorMessage = errorText);
    } catch (error) {
      if (!mounted) {
        return;
      }
      lightingNotifier.failScene(clientRequestId);
      setState(() => _errorMessage = '$error');
    }
  }

  Future<bool> _sendRawCommand(
    String hexCommand, {
    String? successMessage,
    String? failurePrefix,
    String? requestId,
  }) async {
    final api = ref.read(roomControlApiProvider);
    final effectiveRequestId =
        requestId ?? 'raw-${DateTime.now().millisecondsSinceEpoch}';
    final result = await api.sendRawCommand(
      widget.room.number,
      hexCommand,
      clientRequestId: effectiveRequestId,
    );
    if (!mounted) {
      return false;
    }
    if (result is Failure<Map<String, dynamic>>) {
      final prefix = failurePrefix ?? 'Command failed';
      final message = '$prefix: ${result.error.message}';
      setState(() => _errorMessage = message);
      debugPrint(
        'LightingDialog: raw command failed room=${widget.room.number} '
        'requestId=$effectiveRequestId hex="$hexCommand" error="$message"',
      );
      return false;
    }
    if (successMessage != null && successMessage.isNotEmpty) {
      debugPrint(
        'LightingDialog: raw command success room=${widget.room.number} '
        'requestId=$effectiveRequestId hex="$hexCommand" message="$successMessage"',
      );
    }
    // Avoid immediate post-write polling race; schedule a delayed refresh.
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 700), () async {
        if (!mounted) {
          return;
        }
        await ref.read(roomSnapshotProvider(widget.room.number).notifier).refreshNow();
      }),
    );
    return true;
  }

  Future<void> _toggleMasterPower() async {
    final startedAt = DateTime.now();
    final requestId = 'raw-${startedAt.millisecondsSinceEpoch}';
    final nextEnabled = !_masterPowerEnabled;
    // Device semantics are inverted for this command family:
    // 0x0000 => enable master lighting, 0x0001 => disable.
    final hex = nextEnabled
        ? '3E 0B00 030403 0110040500070000'
        : '3E 0B00 030403 0110040500070001';
    final lightingNotifier = ref.read(
      roomLightingRuntimeProvider(widget.room.number).notifier,
    );
    lightingNotifier.startMasterPowerToggle(nextEnabled, requestId, startedAt);
    setState(() {
      _masterPowerEnabled = nextEnabled;
      _masterPowerDirty = true;
      _lastTriggeredScene = 6;
    });
    final ok = await _sendRawCommand(
      hex,
      successMessage: nextEnabled
          ? 'Master power enabled.'
          : 'Master power disabled.',
      failurePrefix: 'Master power command failed',
      requestId: requestId,
    );
    if (!ok) {
      lightingNotifier.failMasterPowerToggle(requestId);
      if (mounted) {
        setState(() {
          _masterPowerEnabled = !nextEnabled;
          _masterPowerDirty = false;
        });
      }
      return;
    }
    lightingNotifier.ackMasterPowerToggle(requestId);
    if (!mounted) {
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(lightingDevicesProvider);
    final authState = ref.watch(authProvider);
    final isAdmin = authState.user?.role == UserRole.admin;
    final isViewer = authState.user?.role == UserRole.viewer;
    final isTestUser = authState.user?.username.toLowerCase() == 'test';
    final showVisualLayout = isViewer || isAdmin;
    final dialogWidth = math.min(
      MediaQuery.of(context).size.width * 0.96,
      1880.0,
    );
    const wideMainFlex = 7.0;
    const wideSideFlex = 3.0;
    const wideLayoutHorizontalChrome = 84.0;
    final estimatedWideSidePanelWidth =
        ((dialogWidth - wideLayoutHorizontalChrome) * wideSideFlex) /
        (wideMainFlex + wideSideFlex);
    final isCompactTablet =
        dialogWidth < 1150 || estimatedWideSidePanelWidth < 420;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: dialogWidth,
        height: math.min(MediaQuery.of(context).size.height * 0.9, 980.0),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          children: [
            _buildHeader(isViewer: isViewer, isAdmin: isAdmin),
            Expanded(
              child: showVisualLayout
                  ? _buildVisualLayout(
                      isAdmin: isAdmin,
                      isTestUser: isTestUser,
                      isCompactTablet: isCompactTablet,
                    )
                  : _buildConsoleLayout(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader({required bool isViewer, required bool isAdmin}) {
    final title = 'Room Plan';

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$title - ${widget.room.number}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              if (isViewer)
                Text(
                  'Lighting Overview',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVisualLayout({
    required bool isAdmin,
    required bool isTestUser,
    required bool isCompactTablet,
  }) {
    final mergedDevices = _buildMergedDevices();
    final sideFlex = isCompactTablet ? 4 : 3;

    final room = _latestRoom;
    final effectiveBackendRoomNumber = ref.read(
      effectiveBackendRoomNumberProvider(room.number),
    );
    final serviceEntries =
        ref
            .watch(roomServiceProvider)
            .where(
              (entry) =>
                  entry.roomNumber == room.number ||
                  entry.roomNumber == effectiveBackendRoomNumber,
            )
            .toList()
          ..sort((a, b) => b.eventTimestamp.compareTo(a.eventTimestamp));

    return Row(
      children: [
        Expanded(
          flex: 7,
          child: Container(
            margin: const EdgeInsets.fromLTRB(20, 8, 16, 20),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isAdmin && !isTestUser) ...[
                  _buildEditPositionsToggle(),
                  const SizedBox(height: 10),
                ],
                Expanded(
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: _layoutCanvasWidth,
                        height: _layoutCanvasHeight,
                        child: Focus(
                          focusNode: _layoutFocusNode,
                          onKeyEvent: _handleLayoutKeyEvent,
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: () {
                              if (isAdmin && _isEditMode) {
                                _layoutFocusNode.requestFocus();
                              }
                            },
                            child: Stack(
                              key: _layoutStackKey,
                              children: [
                                Positioned.fill(
                                  child: Image.asset(
                                    'assets/images/room_layout_web.png',
                                    fit: BoxFit.fill,
                                    filterQuality: FilterQuality.high,
                                    cacheWidth: 3072,
                                    cacheHeight: 2120,
                                  ),
                                ),
                                ...mergedDevices
                                    .where(
                                      (device) =>
                                          device.x != null && device.y != null,
                                    )
                                    .map(
                                      (device) => _buildDevicePin(
                                        device,
                                        isAdmin: isAdmin,
                                      ),
                                    ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: sideFlex,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_warningMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _warningMessage!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber.shade300,
                      ),
                    ),
                  ),
                Expanded(
                  child: isCompactTablet
                      ? SingleChildScrollView(
                          child: Column(
                            children: [
                              _buildSceneControlCard(),
                              const SizedBox(height: 10),
                              _buildBlindsControlCard(),
                              const SizedBox(height: 10),
                              _buildHvacCard(room),
                              const SizedBox(height: 10),
                              _buildServiceCard(room, serviceEntries),
                            ],
                          ),
                        )
                      : Column(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Row(
                                children: [
                                  Expanded(child: _buildSceneControlCard()),
                                  const SizedBox(width: 10),
                                  Expanded(child: _buildBlindsControlCard()),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Expanded(
                              flex: 7,
                              child: Row(
                                children: [
                                  Expanded(child: _buildHvacCard(room)),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _buildServiceCard(room, serviceEntries),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditPositionsToggle() {
    return SwitchListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      value: _isEditMode,
      title: const Text(
        'Edit Positions',
        style: TextStyle(color: Colors.white),
      ),
      subtitle: Text(
        _isEditMode
            ? 'Drag pins or use arrow keys for fine movement.'
            : 'Move lighting pins.',
        style: TextStyle(
          color: Colors.white.withOpacity(0.65),
          fontSize: 11,
        ),
      ),
      onChanged: (value) {
        setState(() {
          _isEditMode = value;
          if (!value) {
            _dragCanvasPositions.clear();
            _draggingKey = null;
            _keyboardPersistTimer?.cancel();
            _layoutFocusNode.unfocus();
          } else {
            _layoutFocusNode.requestFocus();
          }
        });
      },
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildBlindsControlCard() {
    final blindsCount = _buildMergedDevices().where(_isBlindDevice).length;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Blinds Control',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            blindsCount > 0
                ? '$blindsCount blind device${blindsCount == 1 ? '' : 's'} detected'
                : 'No blind devices found',
            style: TextStyle(
              color: Colors.white.withOpacity(0.65),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  onPressed: _updatingBlinds
                      ? null
                      : () => _setBlindsLevel(targetLevel: 100),
                  child: const Text('Open'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonal(
                  onPressed: _updatingBlinds
                      ? null
                      : () => _setBlindsLevel(targetLevel: 0),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _isBlindDevice(LightingDeviceSummary device) {
    final haystack = '${device.name} ${device.feature ?? ''}'.toLowerCase();
    return haystack.contains('blind') ||
        haystack.contains('curtain') ||
        haystack.contains('shade');
  }

  Future<void> _setBlindsLevel({required int targetLevel}) async {
    setState(() => _updatingBlinds = true);
    final hex = targetLevel > 0
        ? '3E 0B00 030403 0010020500000000'
        : '3E 0B00 030403 0010020700000000';
    await _sendRawCommand(
      hex,
      successMessage: targetLevel > 0
          ? 'Blinds opened successfully.'
          : 'Blinds closed successfully.',
      failurePrefix: 'Blinds update failed',
    );
    if (mounted) {
      setState(() => _updatingBlinds = false);
    }
  }

  String _serviceCommandHex(ServiceType serviceType) {
    return switch (serviceType) {
      ServiceType.dnd => '3E 0B00 030403 0F10090000000000',
      ServiceType.laundry => '3E 0B00 030403 0F100A0000000000',
      ServiceType.mur => '3E 0B00 030403 0F100B0000000000',
    };
  }

  Future<void> _applyServiceAction({
    required String roomNumber,
    required ServiceType serviceType,
    required String serviceState,
  }) async {
    final ok = await _sendRawCommand(
      _serviceCommandHex(serviceType),
      failurePrefix: '${serviceType.label} command failed',
    );
    if (!mounted || !ok) {
      return;
    }
    ref.read(roomServiceProvider.notifier).applyServiceAction(
      roomNumber: roomNumber,
      serviceType: serviceType,
      serviceState: serviceState,
    );
  }

  Widget _buildHvacCard(RoomData room) {
    final detail = room.hvacDetail;
    final running =
        (detail?.onOff ?? (room.hvac == HvacStatus.off ? 0 : 1)) == 1;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'HVAC Control',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          if (_loadingHvac) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 2),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildStatChip(
                  'Room Temp',
                  detail?.roomTemperature != null
                      ? '${detail!.roomTemperature!.toStringAsFixed(1)} C'
                      : '-',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatChip('Running', running ? 'On' : 'Off'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildStatChip('Mode', _modeLabel)),
              const SizedBox(width: 8),
              Expanded(child: _buildStatChip('Fan', _fanLabel)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Power',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Switch(
                value: _isOn,
                onChanged: (value) => setState(() => _isOn = value),
              ),
            ],
          ),
          Text(
            'Set Point: ${_setPoint.toStringAsFixed(1)} C',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          Slider(
            value: _setPoint.clamp(16.0, 30.0),
            min: 16,
            max: 30,
            divisions: 28,
            label: _setPoint.toStringAsFixed(1),
            onChanged: (value) => setState(() => _setPoint = value),
          ),
          DropdownButtonFormField<int>(
            value: _mode,
            decoration: const InputDecoration(labelText: 'Mode', isDense: true),
            items: const [
              DropdownMenuItem(value: 0, child: Text('Heat')),
              DropdownMenuItem(value: 1, child: Text('Cool')),
              DropdownMenuItem(value: 2, child: Text('Fan Only')),
              DropdownMenuItem(value: 3, child: Text('Auto')),
            ],
            onChanged: (value) => setState(() => _mode = _normalizeMode(value)),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            value: _fanMode,
            decoration: const InputDecoration(labelText: 'Fan', isDense: true),
            items: const [
              DropdownMenuItem(value: 1, child: Text('Low')),
              DropdownMenuItem(value: 2, child: Text('Medium')),
              DropdownMenuItem(value: 3, child: Text('High')),
              DropdownMenuItem(value: 4, child: Text('Auto')),
            ],
            onChanged: (value) =>
                setState(() => _fanMode = _normalizeFanMode(value)),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton(
                onPressed: _savingHvac ? null : _refreshHvacFromBackend,
                child: const Text('Refresh'),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: (_savingHvac || !_hasHvacChanges) ? null : _saveHvac,
                child: Text(_savingHvac ? 'Saving...' : 'Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildServiceCard(RoomData room, List<RoomServiceEntry> entries) {
    RoomServiceEntry? latest(ServiceType type) {
      for (final entry in entries) {
        if (entry.serviceType == type) return entry;
      }
      return null;
    }

    final dndEntry = latest(ServiceType.dnd);
    final murEntry = latest(ServiceType.mur);
    final laundryEntry = latest(ServiceType.laundry);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Service Control',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _serviceIconTile(
                label: 'DND',
                iconPath: _serviceIconForState(
                  ServiceType.dnd,
                  dndEntry?.serviceState ?? room.dnd.label,
                ),
              ),
              const SizedBox(width: 6),
              _serviceIconTile(
                label: 'MUR',
                iconPath: _serviceIconForState(
                  ServiceType.mur,
                  murEntry?.serviceState ?? room.mur.label,
                ),
              ),
              const SizedBox(width: 6),
              _serviceIconTile(
                label: 'Laundry',
                iconPath: _serviceIconForState(
                  ServiceType.laundry,
                  laundryEntry?.serviceState ?? room.laundry.label,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _serviceRow(
            roomNumber: room.number,
            serviceType: ServiceType.dnd,
            title: 'DND',
            entry: dndEntry,
            fallbackState: room.dnd.label,
          ),
          const SizedBox(height: 8),
          _serviceRow(
            roomNumber: room.number,
            serviceType: ServiceType.mur,
            title: 'MUR',
            entry: murEntry,
            fallbackState: room.mur.label,
          ),
          const SizedBox(height: 8),
          _serviceRow(
            roomNumber: room.number,
            serviceType: ServiceType.laundry,
            title: 'Laundry',
            entry: laundryEntry,
            fallbackState: room.laundry.label,
          ),
        ],
      ),
    );
  }

  Widget _serviceRow({
    required String roomNumber,
    required ServiceType serviceType,
    required String title,
    required RoomServiceEntry? entry,
    required String fallbackState,
  }) {
    final rawState = entry?.serviceState ?? fallbackState;
    final stateText = _displayServiceState(serviceType, rawState);
    final isOn = stateText == 'On';
    final timestampText = entry?.activationTime ?? '-';
    final actionLabels = ('On', 'Off');
    final toggledDisplayState = isOn ? 'Off' : 'On';
    final toggledServiceState = _serviceStateFromDisplay(
      serviceType,
      toggledDisplayState,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$title: $stateText',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  timestampText,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 66,
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                backgroundColor: isOn
                    ? const Color(0xFFFFC107).withOpacity(0.24)
                    : null,
                foregroundColor: Colors.white,
              ),
              onPressed: () => _applyServiceAction(
                roomNumber: roomNumber,
                serviceType: serviceType,
                serviceState: toggledServiceState,
              ),
              child: Text(
                actionLabels.$1,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 66,
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                backgroundColor: !isOn
                    ? const Color(0xFFFFC107).withOpacity(0.24)
                    : null,
                foregroundColor: Colors.white,
              ),
              onPressed: () => _applyServiceAction(
                roomNumber: roomNumber,
                serviceType: serviceType,
                serviceState: toggledServiceState,
              ),
              child: Text(
                actionLabels.$2,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _displayServiceState(ServiceType type, String rawState) {
    final normalized = rawState.trim().toLowerCase();
    switch (type) {
      case ServiceType.dnd:
        const onStates = {'on', 'yellow', 'requested', 'active'};
        return onStates.contains(normalized) ? 'On' : 'Off';
      case ServiceType.mur:
      case ServiceType.laundry:
        const onStates = {'requested', 'started', 'yellow', 'on', 'active'};
        return onStates.contains(normalized) ? 'On' : 'Off';
    }
  }

  String _serviceStateFromDisplay(ServiceType type, String displayState) {
    final isOn = displayState.trim().toLowerCase() == 'on';
    switch (type) {
      case ServiceType.dnd:
        return isOn ? 'On' : 'Off';
      case ServiceType.mur:
      case ServiceType.laundry:
        return isOn ? 'Requested' : 'Finished';
    }
  }

  Widget _serviceIconTile({required String label, required String iconPath}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(iconPath, width: 16, height: 16, fit: BoxFit.contain),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 9.5, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withOpacity(0.65),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSceneControlCard() {
    final scenes = <int, String>{
      1: 'Bright',
      2: 'Dimmed',
      3: 'TV',
      4: 'Dining',
      5: 'Night',
      6: 'On/Off',
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Scene Control',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: scenes.entries.map((entry) {
              final isSelected = _lastTriggeredScene == entry.key;
              return SizedBox(
                width: 104,
                child: FilledButton.tonal(
                  onPressed: () => _triggerScene(entry.key),
                  style: FilledButton.styleFrom(
                    backgroundColor: isSelected
                        ? const Color(0xFFFFC107).withOpacity(0.28)
                        : null,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(entry.value),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDevicePin(
    LightingDeviceSummary device, {
    required bool isAdmin,
  }) {
    final key = '${device.type.name}-${device.address}';
    final isActive = _activeDeviceKey == key;
    final canDrag = isAdmin && _isEditMode;
    final pinSize = isActive ? _pinSizeActive : _pinSizeInactive;
    final dragOffset = _dragCanvasPositions[key];
    final centerX = _normalizeToCanvas(device.x!, _layoutCanvasWidth);
    final centerY = _normalizeToCanvas(device.y!, _layoutCanvasHeight);
    final left =
        dragOffset?.dx ??
        _clamp(centerX - (pinSize / 2), 0, _layoutCanvasWidth - pinSize);
    final top =
        dragOffset?.dy ??
        _clamp(centerY - (pinSize / 2), 0, _layoutCanvasHeight - pinSize);

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onTap: () => setState(() {
          _activeDeviceKey = key;
          if (canDrag) {
            _layoutFocusNode.requestFocus();
          }
        }),
        onPanStart: canDrag
            ? (_) {
                setState(() {
                  _activeDeviceKey = key;
                  _draggingKey = key;
                  _dragCanvasPositions[key] = Offset(left, top);
                  _layoutFocusNode.requestFocus();
                });
              }
            : null,
        onPanUpdate: canDrag
            ? (details) {
                final local = _globalToCanvasPoint(details.globalPosition);
                if (local == null) {
                  return;
                }
                final offset = Offset(
                  _clamp(
                    local.dx - (pinSize / 2),
                    0,
                    _layoutCanvasWidth - pinSize,
                  ),
                  _clamp(
                    local.dy - (pinSize / 2),
                    0,
                    _layoutCanvasHeight - pinSize,
                  ),
                );
                setState(() {
                  _dragCanvasPositions[key] = offset;
                });
              }
            : null,
        onPanEnd: canDrag
            ? (_) async {
                if (_draggingKey != key) {
                  return;
                }
                await _persistDraggedPosition(
                  device: device,
                  key: key,
                  pinSize: pinSize,
                );
              }
            : null,
        child: Tooltip(
          message: device.alarm ? lightingAlarmLabel(device)! : '',
          excludeFromSemantics: !device.alarm,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: pinSize,
            height: pinSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: device.alarm
                  ? const Color(0xFFD32F2F).withOpacity(isActive ? 0.34 : 0.2)
                  : (device.actualLevel > 0
                        ? const Color(0xFFFFEB3B)
                        : const Color(0xFF1565C0)),
              border: Border.all(
                color: device.alarm
                    ? const Color(0xFFFFCDD2)
                    : (canDrag ? Colors.lightBlueAccent : Colors.white),
                width: canDrag ? 3 : 2,
              ),
              boxShadow: device.alarm
                  ? [
                      BoxShadow(
                        color: const Color(0xFFD32F2F).withOpacity(0.65),
                        blurRadius: isActive ? 18 : 12,
                        spreadRadius: isActive ? 4 : 2,
                      ),
                    ]
                  : null,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                if (isActive)
                  Container(
                    width: pinSize + 8,
                    height: pinSize + 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: device.alarm
                            ? const Color(0xFFFFCDD2)
                            : const Color(0xFF90CAF9),
                        width: 2,
                      ),
                    ),
                  ),
                Container(
                  width: math.max(10, pinSize * 0.24),
                  height: math.max(10, pinSize * 0.24),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: device.alarm
                        ? const Color(0xFFFF8A80)
                        : (device.actualLevel > 0
                              ? const Color(0xFFFBC02D)
                              : const Color(0xFF1E88E5)),
                  ),
                ),
                if (canDrag)
                  Positioned(
                    bottom: -24,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        key,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _serviceIconForState(ServiceType type, String rawState) {
    final normalized = rawState.trim().toLowerCase();
    const basePath = 'assets/images/room_status/';
    switch (type) {
      case ServiceType.dnd:
        final isOn =
            normalized == 'on' ||
            normalized == 'yellow' ||
            normalized == 'requested' ||
            normalized == 'active';
        return isOn ? '${basePath}dndyellow.png' : '${basePath}dnd.png';
      case ServiceType.mur:
        if (normalized == 'delayed') return '${basePath}murDelayed.png';
        if (normalized == 'requested' ||
            normalized == 'started' ||
            normalized == 'yellow') {
          return '${basePath}muryellow.png';
        }
        return '${basePath}mur.png';
      case ServiceType.laundry:
        if (normalized == 'delayed') return '${basePath}lndDelayed.png';
        if (normalized == 'requested' ||
            normalized == 'started' ||
            normalized == 'yellow') {
          return '${basePath}lndyellow.png';
        }
        return '${basePath}lnd.png';
    }
  }

  double _normalizeToCanvas(double source, double canvasSize) {
    const legacyMax = 240.0;
    if (source <= legacyMax) {
      return (source / legacyMax) * canvasSize;
    }
    return math.max(0, source);
  }

  Offset? _globalToCanvasPoint(Offset globalPosition) {
    final ctx = _layoutStackKey.currentContext;
    if (ctx == null) {
      return null;
    }
    final renderBox = ctx.findRenderObject();
    if (renderBox is! RenderBox) {
      return null;
    }
    return renderBox.globalToLocal(globalPosition);
  }

  Future<void> _persistDraggedPosition({
    required LightingDeviceSummary device,
    required String key,
    required double pinSize,
    bool showSnackbar = true,
  }) async {
    final dragOffset = _dragCanvasPositions[key];
    if (dragOffset == null) {
      setState(() {
        _draggingKey = null;
      });
      return;
    }

    final notifier = ref.read(lightingDevicesProvider.notifier);
    final configs = notifier.configs;
    var index = configs.indexWhere(
      (cfg) => cfg.address == device.address && cfg.type == device.type,
    );
    if (index < 0) {
      index = configs.indexWhere((cfg) => cfg.address == device.address);
    }

    if (index < 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Device ${device.address} config not found.')),
        );
      }
      setState(() {
        _draggingKey = null;
        _dragCanvasPositions.remove(key);
      });
      return;
    }

    final existing = configs[index];
    final centerX = _clamp(
      dragOffset.dx + (pinSize / 2),
      0,
      _layoutCanvasWidth,
    );
    final centerY = _clamp(
      dragOffset.dy + (pinSize / 2),
      0,
      _layoutCanvasHeight,
    );

    final updated = LightingDeviceConfig(
      address: existing.address,
      name: existing.name,
      type: existing.type,
      x: _denormalizeFromCanvas(
        sourceTemplate: existing.x,
        canvasValue: centerX,
        canvasSize: _layoutCanvasWidth,
      ),
      y: _denormalizeFromCanvas(
        sourceTemplate: existing.y,
        canvasValue: centerY,
        canvasSize: _layoutCanvasHeight,
      ),
    );

    notifier.updateConfig(index, updated, persist: true);
    if (kDebugMode) {
      debugPrint(
        'LightingDialog: drag-persist device=${existing.address} type=${existing.type.name} '
        'x=${updated.x.toStringAsFixed(2)} y=${updated.y.toStringAsFixed(2)}',
      );
    }

    if (mounted && showSnackbar) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Position updated for ${existing.name}')),
      );
    }

    setState(() {
      _draggingKey = null;
      _dragCanvasPositions.remove(key);
    });
  }

  double _denormalizeFromCanvas({
    required double sourceTemplate,
    required double canvasValue,
    required double canvasSize,
  }) {
    const legacyMax = 240.0;
    final clampedCanvas = _clamp(canvasValue, 0, canvasSize);
    if (sourceTemplate <= legacyMax) {
      return (clampedCanvas / canvasSize) * legacyMax;
    }
    return clampedCanvas;
  }

  double _clamp(double value, double min, double max) {
    return math.min(max, math.max(min, value));
  }

  KeyEventResult _handleLayoutKeyEvent(FocusNode _, KeyEvent event) {
    if (!_isEditMode) {
      return KeyEventResult.ignored;
    }
    final authState = ref.read(authProvider);
    final isAdmin = authState.user?.role == UserRole.admin;
    if (!isAdmin) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final fastStep = HardwareKeyboard.instance.isShiftPressed;
    final step = fastStep ? 8.0 : 2.0;

    if (key == LogicalKeyboardKey.arrowLeft) {
      _nudgeActiveDevice(dx: -step, dy: 0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _nudgeActiveDevice(dx: step, dy: 0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _nudgeActiveDevice(dx: 0, dy: -step);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _nudgeActiveDevice(dx: 0, dy: step);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _nudgeActiveDevice({required double dx, required double dy}) {
    final key = _activeDeviceKey;
    if (key == null) {
      return;
    }
    final mergedDevices = _buildMergedDevices();
    LightingDeviceSummary? activeDevice;
    for (final device in mergedDevices) {
      final deviceKey = '${device.type.name}-${device.address}';
      if (deviceKey == key) {
        activeDevice = device;
        break;
      }
    }
    if (activeDevice == null ||
        activeDevice.x == null ||
        activeDevice.y == null) {
      return;
    }

    const pinSize = _pinSizeActive;
    final currentOffset =
        _dragCanvasPositions[key] ??
        Offset(
          _clamp(
            _normalizeToCanvas(activeDevice.x!, _layoutCanvasWidth) -
                (pinSize / 2),
            0,
            _layoutCanvasWidth - pinSize,
          ),
          _clamp(
            _normalizeToCanvas(activeDevice.y!, _layoutCanvasHeight) -
                (pinSize / 2),
            0,
            _layoutCanvasHeight - pinSize,
          ),
        );
    final nextOffset = Offset(
      _clamp(currentOffset.dx + dx, 0, _layoutCanvasWidth - pinSize),
      _clamp(currentOffset.dy + dy, 0, _layoutCanvasHeight - pinSize),
    );

    setState(() {
      _draggingKey = key;
      _dragCanvasPositions[key] = nextOffset;
    });

    _keyboardPersistTimer?.cancel();
    _keyboardPersistTimer = Timer(const Duration(milliseconds: 260), () async {
      await _persistDraggedPosition(
        device: activeDevice!,
        key: key,
        pinSize: pinSize,
        showSnackbar: false,
      );
    });
  }

  Widget _buildConsoleLayout() {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _menuResponse?.menuText ?? 'Loading Menu...',
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontFamily: 'Courier',
                  ),
                ),
                const Divider(color: Colors.white24, height: 24),
                Expanded(
                  child: ListView.builder(
                    itemCount: _menuResponse?.menuOptions.length ?? 0,
                    itemBuilder: (context, index) {
                      final option = _menuResponse!.menuOptions[index];
                      final isActive = _lastSelectedOption == option.id;
                      return ListTile(
                        dense: true,
                        selected: isActive,
                        title: Text(
                          '${option.id} ${option.label}',
                          style: const TextStyle(color: Colors.white),
                        ),
                        onTap: () {
                          setState(() => _lastSelectedOption = option.id);
                          _loadMenu(option.id);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isLoading) const LinearProgressIndicator(),
                const Text(
                  'Console Output',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        _errorMessage ?? _menuResponse?.outputText ?? 'Ready.',
                        style: const TextStyle(
                          color: Colors.green,
                          fontFamily: 'Courier',
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class LightingDevicePin extends StatelessWidget {
  const LightingDevicePin({
    super.key,
    required this.device,
    required this.isActive,
  });

  final LightingDeviceSummary device;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final isOn = (device.targetLevel ?? device.actualLevel) > 0;
    final isAlarm = device.alarm;
    final backgroundColor = isAlarm
        ? (isActive
              ? const Color(0xFFD32F2F).withOpacity(0.42)
              : const Color(0xFFD32F2F).withOpacity(0.18))
        : (isActive
              ? const Color(0xFFFFD54F).withOpacity(0.38)
              : Colors.white.withOpacity(0.14));
    final borderColor = isAlarm
        ? (isActive ? const Color(0xFFFFCDD2) : const Color(0xFFFF5252))
        : (isOn ? const Color(0xFFFFF59D) : Colors.grey.shade400);
    final indicatorColor = isAlarm
        ? const Color(0xFFFF8A80)
        : (isOn ? const Color(0xFFFFF176) : Colors.grey.shade500);
    final boxShadow = isAlarm
        ? [
            BoxShadow(
              color: const Color(0xFFD32F2F).withOpacity(0.85),
              blurRadius: 16,
              spreadRadius: isActive ? 5 : 3,
            ),
          ]
        : (isOn
              ? [
                  BoxShadow(
                    color: const Color(0xFFFFC107).withOpacity(0.85),
                    blurRadius: 14,
                    spreadRadius: isActive ? 4 : 2,
                  ),
                ]
              : null);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: isActive ? 34 : 28,
      height: isActive ? 34 : 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor,
        border: Border.all(color: borderColor, width: 2),
        boxShadow: boxShadow,
      ),
      alignment: Alignment.center,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: indicatorColor,
        ),
      ),
    );
  }
}

class LightingDeviceCard extends StatelessWidget {
  const LightingDeviceCard({
    super.key,
    required this.device,
    required this.status,
    required this.controller,
    required this.onSubmit,
  });

  final LightingDeviceSummary device;
  final String status;
  final TextEditingController controller;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final isAlarm = device.alarm;
    final alarmText = lightingAlarmLabel(device);
    final displayName = displayLightingDeviceName(device);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isAlarm
            ? const Color(0xFFD32F2F).withOpacity(0.12)
            : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isAlarm
              ? const Color(0xFFFF5252)
              : Colors.white.withOpacity(0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              if (alarmText != null)
                Tooltip(
                  message: alarmText,
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFFF8A80),
                    size: 18,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Address: ${device.address}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'Target: ${(device.targetLevel ?? device.actualLevel).round()}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 92,
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  maxLength: 3,
                  decoration: const InputDecoration(
                    labelText: 'Level',
                    isDense: true,
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: onSubmit,
                child: Text(status == 'saving' ? '...' : 'Set Level'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
