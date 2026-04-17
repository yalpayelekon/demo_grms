import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/api_result.dart';
import '../../../config/app_config.dart';
import '../../../models/coordinates_models.dart';
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
import '../../../providers/service_icon_positions_provider.dart';
import 'combined_room_control_dialog.dart';

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
  final Map<String, String> _deviceSubmitStatus = {};
  int? _lastTriggeredScene;
  bool _isEditMode = false;
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

  Future<void> _handleDeviceSubmit(LightingDeviceSummary device) async {
    final key = '${device.type.name}-${device.address}';
    final level = int.tryParse(_deviceLevelControllers[key]?.text ?? '0');
    final lightingNotifier = ref.read(
      roomLightingRuntimeProvider(widget.room.number).notifier,
    );
    final requestId =
        '${widget.room.number}-level-${device.type.name}-${device.address}-${DateTime.now().microsecondsSinceEpoch}';

    if (level == null) {
      setState(() => _deviceSubmitStatus[key] = 'error');
      return;
    }

    lightingNotifier.startDeviceWrite(device, level, requestId);
    setState(() => _deviceSubmitStatus[key] = 'saving');

    final api = ref.read(roomControlApiProvider);
    final result = await api.setLightingLevel(
      widget.room.number,
      device.address,
      level,
      type: device.type,
    );

    if (!mounted) {
      return;
    }
    setState(() {
      if (result is Success<void>) {
        lightingNotifier.ackDeviceWrite(device, requestId);
        _deviceSubmitStatus[key] = 'saved';
        if (kDebugMode) {
          debugPrint(
            'LightingDialog: set level success room=${widget.room.number} '
            'address=${device.address} level=$level',
          );
        }
      } else if (result is Failure<void>) {
        lightingNotifier.failDeviceWrite(device, requestId);
        _deviceSubmitStatus[key] = 'error';
        _errorMessage = result.error.message;
        if (kDebugMode) {
          debugPrint(
            'LightingDialog: set level failed room=${widget.room.number} '
            'address=${device.address} error=${result.error.message}',
          );
        }
      }
    });
  }

  Future<void> _triggerScene(int scene) async {
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

  @override
  Widget build(BuildContext context) {
    ref.watch(lightingDevicesProvider);
    final authState = ref.watch(authProvider);
    final isAdmin = authState.user?.role == UserRole.admin;
    final isViewer = authState.user?.role == UserRole.viewer;
    final showVisualLayout = isViewer || isAdmin;
    final dialogWidth = MediaQuery.of(context).size.width * 0.88;
    final isCompactTablet = dialogWidth < 1150;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: dialogWidth,
        height: MediaQuery.of(context).size.height * 0.82,
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
                      isCompactTablet: isCompactTablet,
                    )
                  : _buildConsoleLayout(),
            ),
          ],
        ),
      ),
    );
  }

  void _switchToCombinedRoomDialog() {
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final dialogContext = rootNavigator.context;
    final room = _latestRoom;

    rootNavigator.pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog<void>(
        context: dialogContext,
        builder: (context) => CombinedRoomControlDialog(room: room),
      );
    });
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
              OutlinedButton.icon(
                onPressed: _switchToCombinedRoomDialog,
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('Room Control Center'),
              ),
              const SizedBox(width: 8),
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
    required bool isCompactTablet,
  }) {
    final mergedDevices = _buildMergedDevices();
    final activeDevice = mergedDevices.isEmpty
        ? null
        : mergedDevices.firstWhere(
            (device) =>
                '${device.type.name}-${device.address}' == _activeDeviceKey,
            orElse: () => mergedDevices.first,
          );
    final sideFlex = isCompactTablet ? 2 : 1;

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
          flex: 6,
          child: Container(
            margin: const EdgeInsets.fromLTRB(20, 8, 16, 20),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
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
                              'assets/images/room_layout.png',
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
                                (device) =>
                                    _buildDevicePin(device, isAdmin: isAdmin),
                              ),
                          ..._buildServiceIconPins(
                            room: room,
                            entries: serviceEntries,
                            isAdmin: isAdmin,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          flex: sideFlex,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 20, 20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_warningMessage != null)
                    Text(
                      _warningMessage!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber.shade300,
                      ),
                    ),
                  const SizedBox(height: 12),
                  _buildSceneControlCard(),
                  if (isAdmin) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Device Control',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (activeDevice != null)
                      _buildDeviceCard(
                        activeDevice,
                        canControl: true,
                        compact: true,
                      )
                    else
                      Text(
                        'No devices available',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.65),
                          fontSize: 12,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      'Power Consumption: ${_formatPowerConsumption(activeDevice)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.75),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      value: _isEditMode,
                      title: const Text(
                        'Edit Positions',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        _isEditMode
                            ? 'Drag pins or use arrow keys for fine movement.'
                            : 'Turn on to move lighting devices.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.65),
                          fontSize: 12,
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
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSceneControlCard() {
    final scenes = <int, String>{
      1: 'Bright',
      2: 'Dimmed',
      3: 'TV',
      4: 'Dining',
      5: 'Night',
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
                width: 112,
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

  static const Map<String, Offset> _defaultServiceIconCenters = {
    'dnd': Offset(1250, 205),
    'mur': Offset(1320, 205),
    'laundry': Offset(1390, 205),
    'close': Offset(1460, 205),
  };

  List<Widget> _buildServiceIconPins({
    required RoomData room,
    required List<RoomServiceEntry> entries,
    required bool isAdmin,
  }) {
    final savedPositions = ref.watch(serviceIconPositionsProvider);
    final iconSize = 26.0 * _pinScale;
    final canDrag = isAdmin && _isEditMode;

    Widget buildOne(ServiceType type) {
      final typeKey = type.name.toLowerCase();
      final key = 'service-$typeKey';
      final center =
          savedPositions[typeKey] ?? _defaultServiceIconCenters[typeKey];
      if (center == null) {
        return const SizedBox.shrink();
      }

      final centerX = _normalizeToCanvas(center.dx, _layoutCanvasWidth);
      final centerY = _normalizeToCanvas(center.dy, _layoutCanvasHeight);
      final dragOffset = _dragCanvasPositions[key];
      final left =
          dragOffset?.dx ??
          _clamp(centerX - (iconSize / 2), 0, _layoutCanvasWidth - iconSize);
      final top =
          dragOffset?.dy ??
          _clamp(centerY - (iconSize / 2), 0, _layoutCanvasHeight - iconSize);

      final state = _serviceStateFor(type, room, entries);
      final iconPath = _serviceIconForState(type, state);

      return Positioned(
        left: left,
        top: top,
        child: GestureDetector(
          onPanStart: canDrag
              ? (_) {
                  setState(() {
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
                      local.dx - (iconSize / 2),
                      0,
                      _layoutCanvasWidth - iconSize,
                    ),
                    _clamp(
                      local.dy - (iconSize / 2),
                      0,
                      _layoutCanvasHeight - iconSize,
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
                  await _persistDraggedServiceIcon(
                    serviceType: typeKey,
                    key: key,
                    iconSize: iconSize,
                  );
                }
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: iconSize,
            height: iconSize,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.20),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: canDrag
                    ? Colors.lightBlueAccent
                    : Colors.white.withOpacity(0.35),
                width: canDrag ? 2 : 1,
              ),
            ),
            child: Image.asset(iconPath, fit: BoxFit.contain),
          ),
        ),
      );
    }

    return <Widget>[
      buildOne(ServiceType.dnd),
      buildOne(ServiceType.mur),
      buildOne(ServiceType.laundry),
      _buildDummyCloseIconPin(canDrag: canDrag, iconSize: iconSize),
    ];
  }

  Widget _buildDummyCloseIconPin({
    required bool canDrag,
    required double iconSize,
  }) {
    const typeKey = 'close';
    final key = 'service-$typeKey';
    final savedPositions = ref.watch(serviceIconPositionsProvider);
    final center =
        savedPositions[typeKey] ?? _defaultServiceIconCenters[typeKey];
    if (center == null) {
      return const SizedBox.shrink();
    }

    final centerX = _normalizeToCanvas(center.dx, _layoutCanvasWidth);
    final centerY = _normalizeToCanvas(center.dy, _layoutCanvasHeight);
    final dragOffset = _dragCanvasPositions[key];
    final left =
        dragOffset?.dx ??
        _clamp(centerX - (iconSize / 2), 0, _layoutCanvasWidth - iconSize);
    final top =
        dragOffset?.dy ??
        _clamp(centerY - (iconSize / 2), 0, _layoutCanvasHeight - iconSize);

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onPanStart: canDrag
            ? (_) {
                setState(() {
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
                    local.dx - (iconSize / 2),
                    0,
                    _layoutCanvasWidth - iconSize,
                  ),
                  _clamp(
                    local.dy - (iconSize / 2),
                    0,
                    _layoutCanvasHeight - iconSize,
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
                await _persistDraggedServiceIcon(
                  serviceType: typeKey,
                  key: key,
                  iconSize: iconSize,
                );
              }
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: iconSize,
          height: iconSize,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.20),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: canDrag
                  ? Colors.lightBlueAccent
                  : Colors.white.withOpacity(0.35),
              width: canDrag ? 2 : 1,
            ),
          ),
          child: Icon(
            Icons.power_settings_new,
            color: Colors.white,
            size: iconSize - 4,
          ),
        ),
      ),
    );
  }

  String _serviceStateFor(
    ServiceType type,
    RoomData room,
    List<RoomServiceEntry> entries,
  ) {
    for (final entry in entries) {
      if (entry.serviceType == type) {
        return entry.serviceState;
      }
    }
    switch (type) {
      case ServiceType.dnd:
        return room.dnd.label;
      case ServiceType.mur:
        return room.mur.label;
      case ServiceType.laundry:
        return room.laundry.label;
    }
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

  Future<void> _persistDraggedServiceIcon({
    required String serviceType,
    required String key,
    required double iconSize,
  }) async {
    final dragOffset = _dragCanvasPositions[key];
    if (dragOffset == null) {
      setState(() {
        _draggingKey = null;
      });
      return;
    }

    final centerX = _clamp(
      dragOffset.dx + (iconSize / 2),
      0,
      _layoutCanvasWidth,
    );
    final centerY = _clamp(
      dragOffset.dy + (iconSize / 2),
      0,
      _layoutCanvasHeight,
    );

    final existing =
        ref.read(serviceIconPositionsProvider)[serviceType] ??
        _defaultServiceIconCenters[serviceType] ??
        Offset(centerX, centerY);

    final persistedX = _denormalizeFromCanvas(
      sourceTemplate: existing.dx,
      canvasValue: centerX,
      canvasSize: _layoutCanvasWidth,
    );
    final persistedY = _denormalizeFromCanvas(
      sourceTemplate: existing.dy,
      canvasValue: centerY,
      canvasSize: _layoutCanvasHeight,
    );

    final next = <String, Offset>{
      ...ref.read(serviceIconPositionsProvider),
      serviceType: Offset(persistedX, persistedY),
    };
    // Ensure all three keys exist so backend file is deterministic.
    for (final entry in _defaultServiceIconCenters.entries) {
      next.putIfAbsent(entry.key, () => entry.value);
    }

    final payload = <Map<String, dynamic>>[
      for (final entry in next.entries)
        {'serviceType': entry.key, 'x': entry.value.dx, 'y': entry.value.dy},
    ];

    final result = await ref
        .read(coordinatesApiProvider)
        .saveServiceIcons(payload);
    if (mounted) {
      if (result is Failure<void>) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to save service icon: ${result.error.message}',
            ),
          ),
        );
      } else {
        ref
            .read(serviceIconPositionsProvider.notifier)
            .applyFromPayload(
              payload
                  .map((e) => ServiceIconConfig.fromJson(e))
                  .toList(growable: false),
            );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Service icon position updated ($serviceType)'),
          ),
        );
      }
    }

    setState(() {
      _draggingKey = null;
      _dragCanvasPositions.remove(key);
    });
  }

  double _normalizeToCanvas(double source, double canvasSize) {
    const legacyMax = 240.0;
    if (source <= legacyMax) {
      return (source / legacyMax) * canvasSize;
    }
    return math.max(0, source);
  }

  String _formatPowerConsumption(LightingDeviceSummary? device) {
    final power = device?.powerW;
    if (power == null || power.isNaN || power.isInfinite || power < 0) {
      return '-';
    }
    if (power == power.roundToDouble()) {
      return '${power.toStringAsFixed(0)} W';
    }
    return '${power.toStringAsFixed(1)} W';
  }

  Widget _buildDeviceCard(
    LightingDeviceSummary device, {
    required bool canControl,
    bool compact = false,
  }) {
    final key = '${device.type.name}-${device.address}';
    final status = _deviceSubmitStatus[key] ?? 'idle';
    final actualLevel = device.actualLevel.round();
    final commandedLevel = (device.targetLevel ?? device.actualLevel).round();
    final hasPendingTarget = commandedLevel > 0 && actualLevel == 0;
    final deviceMetaText = 'Actual: $actualLevel';
    final isAlarm = device.alarm;
    final alarmText = lightingAlarmLabel(device);
    final displayName = displayLightingDeviceName(device);

    return Container(
      padding: EdgeInsets.all(compact ? 10 : 16),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 14 : 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              if (alarmText != null) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: alarmText,
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFFF8A80),
                    size: 18,
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: compact ? 4 : 8),
          if (!compact)
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
                Expanded(
                  child: Text(
                    deviceMetaText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.6),
                    ),
                  ),
                ),
              ],
            )
          else
            Text(
              'Address:${device.address}   $deviceMetaText',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withOpacity(0.6),
              ),
            ),
          if (hasPendingTarget) ...[
            SizedBox(height: compact ? 4 : 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withOpacity(0.6)),
              ),
              child: Text(
                'Pending/Not reached',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.amber.shade200,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          SizedBox(height: compact ? 6 : 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth;
              final requestedFieldWidth = compact ? 64.0 : 84.0;
              final targetFieldWidth = math.max(
                64.0,
                math.min(requestedFieldWidth, availableWidth),
              );
              final isStacked = availableWidth < 185;

              if (isStacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: targetFieldWidth,
                      child: TextField(
                        controller: _deviceLevelControllers[key],
                        keyboardType: TextInputType.number,
                        maxLength: 3,
                        decoration: const InputDecoration(
                          labelText: 'Target',
                          isDense: true,
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => _handleDeviceSubmit(device),
                        child: Text(status == 'saving' ? '...' : 'Set Level'),
                      ),
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  SizedBox(
                    width: targetFieldWidth,
                    child: TextField(
                      controller: _deviceLevelControllers[key],
                      keyboardType: TextInputType.number,
                      maxLength: 3,
                      decoration: const InputDecoration(
                        labelText: 'Target',
                        isDense: true,
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _handleDeviceSubmit(device),
                      child: Text(status == 'saving' ? '...' : 'Set Level'),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
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
