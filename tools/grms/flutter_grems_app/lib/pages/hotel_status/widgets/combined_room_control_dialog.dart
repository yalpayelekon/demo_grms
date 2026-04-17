import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/api_result.dart';
import '../../../models/lighting_device.dart';
import '../../../models/rcu_models.dart';
import '../../../models/room_models.dart';
import '../../../models/service_models.dart';
import '../../../providers/api_providers.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/demo_room_snapshot_provider.dart';
import '../../../providers/hotel_status_provider.dart';
import '../../../providers/lighting_devices_provider.dart';
import '../../../providers/room_runtime_provider.dart';
import '../../../providers/room_service_provider.dart';
import '../../../lighting/lighting_alarm_style.dart';
import '../../../lighting/lighting_device_merge.dart';
import 'lighting_dialog.dart';

class CombinedRoomControlDialog extends ConsumerStatefulWidget {
  const CombinedRoomControlDialog({super.key, required this.room});

  final RoomData room;

  @override
  ConsumerState<CombinedRoomControlDialog> createState() =>
      _CombinedRoomControlDialogState();
}

class _CombinedRoomControlDialogState
    extends ConsumerState<CombinedRoomControlDialog> {
  late double _setPoint;
  late bool _isOn;
  late int _mode;
  late int _fanMode;

  late double _initialSetPoint;
  late bool _initialIsOn;
  late int _initialMode;
  late int _initialFanMode;

  bool _savingHvac = false;
  bool _loadingHvac = false;
  RoomData? _latestRoom;
  ProviderSubscription<RoomData?>? _roomRuntimeSubscription;

  String? _lightingError;
  final Map<String, String> _deviceSubmitStatus = {};

  static const _adminColumnWidths = <double>[340.0, 340.0, 340.0];
  static const _viewerColumnWidths = <double>[210.0, 288.0, 246.0];

  RoomData get _latestRoomView {
    return ref.read(roomRuntimeRoomViewProvider(widget.room.number)) ??
        ref.read(hotelStatusProvider).rooms[widget.room.number] ??
        _latestRoom ??
        widget.room;
  }

  @override
  void initState() {
    super.initState();
    _hydrateHvacFromRoom(widget.room);
    _roomRuntimeSubscription = ref.listenManual<RoomData?>(
      roomRuntimeRoomViewProvider(widget.room.number),
      _onRoomRuntimeChanged,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureLightingConfigsLoaded();
    });
  }

  Future<void> _ensureLightingConfigsLoaded() async {
    await ref.read(lightingDevicesProvider.notifier).ensureConfigLoaded();
    if (ref.read(roomSnapshotProvider(widget.room.number)).snapshot == null) {
      await ref
          .read(roomSnapshotProvider(widget.room.number).notifier)
          .refreshNow();
    }
  }

  @override
  void dispose() {
    _roomRuntimeSubscription?.close();
    super.dispose();
  }

  void _onRoomRuntimeChanged(RoomData? previous, RoomData? next) {
    if (next == null || !mounted) {
      return;
    }
    final changed = previous != next;
    if (!changed) {
      return;
    }

    setState(() {
      _latestRoom = next;
      if (!_hasHvacChanges) {
        _hydrateHvacFromRoom(next);
      }
    });
  }

  void _hydrateHvacFromRoom(RoomData room) {
    _latestRoom = room;
    final detail = room.hvacDetail;
    _setPoint = detail?.setPoint ?? 22.0;
    _isOn = (detail?.onOff ?? (room.hvac == HvacStatus.off ? 0 : 1)) == 1;
    _mode = _normalizeMode(detail?.mode);
    _fanMode = _normalizeFanMode(detail?.fanMode);

    _initialSetPoint = _setPoint;
    _initialIsOn = _isOn;
    _initialMode = _mode;
    _initialFanMode = _fanMode;
  }

  int _normalizeMode(int? raw) {
    final value = raw ?? 0;
    if (value >= 0 && value <= 3) {
      return value;
    }
    return 0;
  }

  int _normalizeFanMode(int? raw) {
    final value = raw ?? 4;
    if (value >= 1 && value <= 4) {
      return value;
    }
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
    if (refreshed != null) {
      setState(() {
        if (!_hasHvacChanges) {
          _hydrateHvacFromRoom(refreshed);
        } else {
          _latestRoom = refreshed;
        }
      });
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

  List<LightingDeviceSummary> _buildMergedDevices(
    LightingDevicesResponse? live,
  ) {
    final configs = ref.read(lightingDevicesProvider.notifier).configs;
    return mergeLightingConfigsWithLive(configs: configs, live: live);
  }

  Future<void> _triggerScene(int scene) async {
    final lightingNotifier = ref.read(
      roomLightingRuntimeProvider(widget.room.number).notifier,
    );
    final requestId =
        '${widget.room.number}-scene-${DateTime.now().microsecondsSinceEpoch}';
    final tappedAt = DateTime.now();
    lightingNotifier.startScene(scene, requestId, tappedAt);

    final api = ref.read(roomControlApiProvider);
    final result = await api.triggerLightingScene(
      widget.room.number,
      scene,
      clientRequestId: requestId,
      clientTappedAtMs: tappedAt.millisecondsSinceEpoch,
    );

    if (!mounted) {
      return;
    }

    if (result is Failure<LightingSceneTriggerResponse>) {
      lightingNotifier.failScene(requestId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to trigger scene: ${result.error.message}'),
        ),
      );
      return;
    }

    lightingNotifier.ackScene(requestId);
  }

  Future<void> _toggleDeviceLevel(LightingDeviceSummary device) async {
    final lightingNotifier = ref.read(
      roomLightingRuntimeProvider(widget.room.number).notifier,
    );
    final key = '${device.type.name}-${device.address}';
    final isOn = device.actualLevel > 0;
    final level = isOn ? 0 : 100;
    setState(() {
      _deviceSubmitStatus[key] = 'saving';
    });
    final requestId =
        '${widget.room.number}-level-${device.type.name}-${device.address}-${DateTime.now().microsecondsSinceEpoch}';
    lightingNotifier.startDeviceWrite(device, level, requestId);

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

    if (result is Failure<void>) {
      lightingNotifier.failDeviceWrite(device, requestId);
      setState(() {
        _deviceSubmitStatus[key] = 'error';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to toggle: ${result.error.message}')),
      );
      return;
    }

    lightingNotifier.ackDeviceWrite(device, requestId);
    setState(() {
      _deviceSubmitStatus[key] = 'saved';
    });
  }

  void _switchToLightingDialog() {
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final dialogContext = rootNavigator.context;
    final room = _latestRoomView;

    rootNavigator.pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog<void>(
        context: dialogContext,
        builder: (context) => LightingDialog(room: room),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isAdmin = authState.user?.role == UserRole.admin;
    final hotelState = ref.watch(hotelStatusProvider);
    final runtimeRoom = ref.watch(
      roomRuntimeRoomViewProvider(widget.room.number),
    );
    final lightingRuntime = ref.watch(
      roomLightingRuntimeProvider(widget.room.number),
    );
    final room =
        runtimeRoom ??
        hotelState.rooms[widget.room.number] ??
        _latestRoom ??
        widget.room;
    final columnWidths = isAdmin ? _adminColumnWidths : _viewerColumnWidths;
    final dividerWidth = isAdmin ? 16.0 : 12.0;
    final requiredWidth =
        columnWidths.reduce((sum, width) => sum + width) +
        dividerWidth * (columnWidths.length - 1);
    final dialogWidth = math
        .min(
          MediaQuery.of(context).size.width * (isAdmin ? 0.96 : 0.8),
          isAdmin ? 1560.0 : requiredWidth + 56.0,
        )
        .toDouble();
    final dialogMaxHeight = math
        .min(
          MediaQuery.of(context).size.height * (isAdmin ? 0.92 : 0.8),
          isAdmin ? 920.0 : 660.0,
        )
        .toDouble();
    final dialogMinHeight = isAdmin ? dialogMaxHeight : 0.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: dialogWidth,
        constraints: BoxConstraints(
          minHeight: dialogMinHeight,
          maxHeight: dialogMaxHeight,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF1F222B),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    'Room ${room.number} Control Center',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: _switchToLightingDialog,
                    icon: const Icon(Icons.lightbulb_outline, size: 18),
                    label: const Text('Room Plan'),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Flexible(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final useFluidLayout =
                        isAdmin && constraints.maxWidth >= 1300.0;
                    final content = useFluidLayout
                        ? _buildColumnsRow(
                            room: room,
                            lightingRuntime: lightingRuntime,
                            isAdmin: isAdmin,
                            fixedWidth: false,
                            columnWidths: columnWidths,
                            dividerWidth: dividerWidth,
                          )
                        : () {
                            final fixedRow = _buildColumnsRow(
                              room: room,
                              lightingRuntime: lightingRuntime,
                              isAdmin: isAdmin,
                              fixedWidth: true,
                              columnWidths: columnWidths,
                              dividerWidth: dividerWidth,
                            );
                            if (constraints.maxWidth >= requiredWidth) {
                              return Center(
                                child: SizedBox(
                                  width: requiredWidth,
                                  child: fixedRow,
                                ),
                              );
                            }
                            return SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(
                                width: requiredWidth,
                                child: fixedRow,
                              ),
                            );
                          }();

                    if (isAdmin) {
                      return content;
                    }

                    return SingleChildScrollView(child: content);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColumnsRow({
    required RoomData room,
    required RoomLightingRuntimeState lightingRuntime,
    required bool isAdmin,
    required bool fixedWidth,
    required List<double> columnWidths,
    required double dividerWidth,
  }) {
    final lighting = _buildLightingCard(
      room: room,
      lightingRuntime: lightingRuntime,
      isAdmin: isAdmin,
    );
    final hvac = _buildHvacCard(room: room);
    final service = _buildServiceCard(room: room, isAdmin: isAdmin);

    Widget withWrapper(Widget child, double width) {
      if (fixedWidth) {
        return SizedBox(width: width, child: child);
      }
      return Expanded(child: child);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        withWrapper(lighting, columnWidths[0]),
        VerticalDivider(
          color: Colors.white.withOpacity(0.12),
          width: dividerWidth,
        ),
        withWrapper(hvac, columnWidths[1]),
        VerticalDivider(
          color: Colors.white.withOpacity(0.12),
          width: dividerWidth,
        ),
        withWrapper(service, columnWidths[2]),
      ],
    );
  }

  Widget _buildLightingCard({
    required RoomData room,
    required RoomLightingRuntimeState lightingRuntime,
    required bool isAdmin,
  }) {
    final devices = _buildMergedDevices(lightingRuntime.lighting);
    final scenes = <int, String>{
      1: 'Bright',
      2: 'Dimmed',
      3: 'TV',
      4: 'Dining',
      5: 'Night',
    };

    return _cardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            iconPath: room.lightingOn
                ? 'assets/images/room_status/LightingOn.png'
                : 'assets/images/room_status/LightingOff.png',
            title: 'Lighting',
          ),
          const SizedBox(height: 12),
          if (lightingRuntime.lighting == null)
            const LinearProgressIndicator(minHeight: 2),
          if (_lightingError != null) ...[
            const SizedBox(height: 8),
            Text(
              _lightingError!,
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          const Text(
            'Scenes',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Wrap(
            direction: isAdmin ? Axis.horizontal : Axis.vertical,
            spacing: 8,
            runSpacing: 8,
            children: scenes.entries.map((entry) {
              final selectedScene = lightingRuntime.selectedScene == entry.key;
              return SizedBox(
                width: isAdmin ? 102 : 96,
                child: FilledButton.tonal(
                  onPressed: () => _triggerScene(entry.key),
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                      horizontal: isAdmin ? 16 : 12,
                      vertical: isAdmin ? 14 : 10,
                    ),
                    backgroundColor: selectedScene
                        ? const Color(0xFFFFC107).withOpacity(0.25)
                        : null,
                  ),
                  child: Text(entry.value),
                ),
              );
            }).toList(),
          ),
          if (isAdmin) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 14),
            const Text(
              'Devices',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 8),
            if (devices.isEmpty)
              const Text(
                'No lighting devices available',
                style: TextStyle(color: Colors.grey),
              )
            else
              Column(children: devices.map(_buildDeviceToggleRow).toList()),
          ],
        ],
      ),
    );
  }

  Widget _buildDeviceToggleRow(LightingDeviceSummary device) {
    final key = '${device.type.name}-${device.address}';
    final isOn = device.actualLevel > 0;
    final isAlarm = device.alarm;
    final status = _deviceSubmitStatus[key] ?? 'idle';
    final alarmLabel = lightingAlarmLabel(device);
    final displayName = displayLightingDeviceName(device);

    Color pinColor() {
      if (isAlarm) {
        return const Color(0xFFD32F2F);
      }
      return isOn ? const Color(0xFFFFEB3B) : const Color(0xFF1565C0);
    }

    return InkWell(
      onTap: () => _toggleDeviceLevel(device),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isAlarm
              ? const Color(0xFFD32F2F).withOpacity(0.12)
              : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isAlarm
                ? const Color(0xFFFF5252)
                : Colors.white.withOpacity(0.08),
          ),
        ),
        child: Row(
          children: [
            if (alarmLabel != null)
              Tooltip(
                message: alarmLabel,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: pinColor(),
                    border: Border.all(
                      color: const Color(0xFFFFCDD2),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFD32F2F).withOpacity(0.7),
                        blurRadius: 10,
                        spreadRadius: 1.5,
                      ),
                    ],
                  ),
                ),
              )
            else
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: pinColor(),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.85),
                    width: 1.5,
                  ),
                ),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$displayName (${device.address})',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              status == 'saving'
                  ? '...'
                  : status == 'saved'
                  ? 'OK'
                  : '',
              style: TextStyle(
                fontSize: 11,
                color: status == 'saving'
                    ? Colors.amberAccent
                    : Colors.white.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHvacCard({required RoomData room}) {
    final detail = room.hvacDetail;
    final running =
        (detail?.onOff ?? (room.hvac == HvacStatus.off ? 0 : 1)) == 1;
    final authState = ref.watch(authProvider);
    final isAdmin = authState.user?.role == UserRole.admin;
    final chipGap = isAdmin ? 8.0 : 6.0;
    final sectionGap = isAdmin ? 16.0 : 12.0;

    return _cardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            iconPath: _hvacIconForStatus(room.hvac),
            title: 'HVAC',
          ),
          const SizedBox(height: 12),
          if (_loadingHvac) const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildStatChip(
                  'Room Temp',
                  detail?.roomTemperature != null
                      ? '${detail!.roomTemperature!.toStringAsFixed(1)} C'
                      : '-',
                  dense: !isAdmin,
                ),
              ),
              SizedBox(width: chipGap),
              Expanded(
                child: _buildStatChip(
                  'Running',
                  running ? 'On' : 'Off',
                  dense: !isAdmin,
                ),
              ),
            ],
          ),
          SizedBox(height: chipGap),
          Row(
            children: [
              Expanded(
                child: _buildStatChip('Mode', _modeLabel, dense: !isAdmin),
              ),
              SizedBox(width: chipGap),
              Expanded(
                child: _buildStatChip('Fan', _fanLabel, dense: !isAdmin),
              ),
            ],
          ),
          SizedBox(height: sectionGap),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Power',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              Switch(
                value: _isOn,
                onChanged: (value) => setState(() => _isOn = value),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Set Point: ${_setPoint.toStringAsFixed(1)} C',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Slider(
            value: _setPoint.clamp(16.0, 30.0),
            min: 16,
            max: 30,
            divisions: 28,
            label: _setPoint.toStringAsFixed(1),
            onChanged: (value) => setState(() => _setPoint = value),
          ),
          const SizedBox(height: 6),
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
          if (isAdmin) const Spacer() else const SizedBox(height: 16),
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

  Widget _buildServiceCard({required RoomData room, required bool isAdmin}) {
    final entries =
        ref
            .watch(roomServiceProvider)
            .where((entry) => entry.roomNumber == room.number)
            .toList()
          ..sort((a, b) => b.eventTimestamp.compareTo(a.eventTimestamp));

    RoomServiceEntry? latest(ServiceType type) {
      for (final entry in entries) {
        if (entry.serviceType == type) return entry;
      }
      return null;
    }

    final dndEntry = latest(ServiceType.dnd);
    final murEntry = latest(ServiceType.mur);
    final laundryEntry = latest(ServiceType.laundry);

    return _cardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            iconPath: _serviceIconForState(ServiceType.mur, room.mur.label),
            title: 'Service Requests',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _serviceIconTile(
                label: 'DND',
                iconPath: _serviceIconForState(
                  ServiceType.dnd,
                  dndEntry?.serviceState ?? room.dnd.label,
                ),
                dense: !isAdmin,
              ),
              const SizedBox(width: 6),
              _serviceIconTile(
                label: 'MUR',
                iconPath: _serviceIconForState(
                  ServiceType.mur,
                  murEntry?.serviceState ?? room.mur.label,
                ),
                dense: !isAdmin,
              ),
              const SizedBox(width: 6),
              _serviceIconTile(
                label: 'Laundry',
                iconPath: _serviceIconForState(
                  ServiceType.laundry,
                  laundryEntry?.serviceState ?? room.laundry.label,
                ),
                dense: !isAdmin,
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          _serviceRow(
            title: 'DND',
            entry: dndEntry,
            fallbackState: room.dnd.label,
            allowAck: false,
          ),
          const SizedBox(height: 8),
          _serviceRow(
            title: 'MUR',
            entry: murEntry,
            fallbackState: room.mur.label,
            allowAck: true,
          ),
          const SizedBox(height: 8),
          _serviceRow(
            title: 'Laundry',
            entry: laundryEntry,
            fallbackState: room.laundry.label,
            allowAck: true,
          ),
          if (isAdmin) const Spacer() else const SizedBox(height: 16),
          Text(
            'Recent room events: ${entries.length}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _serviceRow({
    required String title,
    required RoomServiceEntry? entry,
    required String fallbackState,
    required bool allowAck,
  }) {
    final stateText = entry?.serviceState ?? fallbackState;
    final timestampText = entry?.activationTime ?? '-';
    final canToggle =
        allowAck &&
        entry != null &&
        entry.acknowledgement != ServiceAcknowledgement.none;

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
                  style: const TextStyle(fontWeight: FontWeight.w600),
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
          if (canToggle)
            InkWell(
              onTap: () => ref
                  .read(roomServiceProvider.notifier)
                  .toggleAcknowledgement(entry.id),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color:
                      entry.acknowledgement ==
                          ServiceAcknowledgement.acknowledged
                      ? Colors.green.withOpacity(0.18)
                      : Colors.red.withOpacity(0.18),
                ),
                child: Text(
                  entry.acknowledgement.label,
                  style: TextStyle(
                    fontSize: 11,
                    color:
                        entry.acknowledgement ==
                            ServiceAcknowledgement.acknowledged
                        ? Colors.greenAccent
                        : Colors.redAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
          else
            Text('-', style: TextStyle(color: Colors.white.withOpacity(0.6))),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, String value, {bool dense = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 7 : 8,
      ),
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
              fontSize: dense ? 10 : 11,
              color: Colors.white.withOpacity(0.65),
            ),
          ),
          SizedBox(height: dense ? 3 : 4),
          Text(
            value,
            style: TextStyle(
              fontSize: dense ? 12 : 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader({required String iconPath, required String title}) {
    return Row(
      children: [
        Image.asset(iconPath, width: 20, height: 20, fit: BoxFit.contain),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _serviceIconTile({
    required String label,
    required String iconPath,
    bool dense = false,
  }) {
    return Flexible(
      fit: FlexFit.tight,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 3 : 4,
          vertical: dense ? 4 : 5,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              iconPath,
              width: dense ? 14 : 16,
              height: dense ? 14 : 16,
              fit: BoxFit.contain,
            ),
            SizedBox(height: dense ? 1 : 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: dense ? 8.5 : 9.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardShell({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: child,
    );
  }

  String _hvacIconForStatus(HvacStatus status) {
    const basePath = 'assets/images/room_status/';
    switch (status) {
      case HvacStatus.cold:
        return '${basePath}HvacActiveCold.png';
      case HvacStatus.hot:
        return '${basePath}HvacActiveHot.png';
      default:
        return '${basePath}HvacActive.png';
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
}
