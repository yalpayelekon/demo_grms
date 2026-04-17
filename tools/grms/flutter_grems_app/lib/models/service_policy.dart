import 'package:flutter_grems_app/models/room_models.dart';
import 'package:flutter_grems_app/models/service_models.dart';
import 'package:intl/intl.dart';

bool isDndRequestedState(String state) => state.trim().toLowerCase() == 'on';

bool isMurRequestedState(String state) =>
    state.trim().toLowerCase() == 'requested';

bool isLaundryRequestedState(String state) =>
    state.trim().toLowerCase() == 'requested';

class ServiceOverlay {
  const ServiceOverlay({
    required this.dnd,
    required this.mur,
    required this.laundry,
    this.murDelayedMinutes,
  });

  final DndStatus dnd;
  final MurStatus mur;
  final LaundryStatus laundry;
  final int? murDelayedMinutes;

  ServiceOverlay copyWith({
    DndStatus? dnd,
    MurStatus? mur,
    LaundryStatus? laundry,
    int? murDelayedMinutes,
  }) {
    return ServiceOverlay(
      dnd: dnd ?? this.dnd,
      mur: mur ?? this.mur,
      laundry: laundry ?? this.laundry,
      murDelayedMinutes: murDelayedMinutes ?? this.murDelayedMinutes,
    );
  }
}

ServiceOverlay normalizeOverlay(ServiceOverlay overlay) {
  final murRequested = overlay.mur == MurStatus.requested;
  final laundryRequested = overlay.laundry == LaundryStatus.requested;
  final dndRequested = overlay.dnd == DndStatus.on;

  if (!dndRequested) {
    return overlay;
  }

  if (murRequested || laundryRequested) {
    // Service requests take precedence when conflict exists.
    return overlay.copyWith(
      dnd: DndStatus.off,
      mur: murRequested ? MurStatus.requested : overlay.mur,
      laundry: laundryRequested ? LaundryStatus.requested : overlay.laundry,
    );
  }

  return overlay.copyWith(
    mur: murRequested ? MurStatus.finished : overlay.mur,
    laundry: laundryRequested ? LaundryStatus.finished : overlay.laundry,
  );
}

List<RoomServiceEntry> applyCrossCancelOnNewEntry(
  List<RoomServiceEntry> current,
  RoomServiceEntry incoming,
) {
  final output = List<RoomServiceEntry>.from(current);
  final room = incoming.roomNumber;
  final latest = _latestByTypeForRoom(output, room);
  final generated = <RoomServiceEntry>[];

  final baseTs = _maxTimestamp(output, incoming.eventTimestamp);
  var tsCursor = baseTs + 1;

  final incomingDndRequested =
      incoming.serviceType == ServiceType.dnd &&
      isDndRequestedState(incoming.serviceState);
  final incomingMurRequested =
      incoming.serviceType == ServiceType.mur &&
      isMurRequestedState(incoming.serviceState);
  final incomingLaundryRequested =
      incoming.serviceType == ServiceType.laundry &&
      isLaundryRequestedState(incoming.serviceState);

  if (incomingDndRequested) {
    final latestMur = latest[ServiceType.mur];
    if (latestMur != null && isMurRequestedState(latestMur.serviceState)) {
      generated.add(
        _makePolicyEvent(
          base: latestMur,
          serviceState: 'Canceled',
          eventTimestamp: tsCursor++,
          note: 'policy.cancel dnd->mur room=$room',
        ),
      );
    }
    final latestLaundry = latest[ServiceType.laundry];
    if (latestLaundry != null &&
        isLaundryRequestedState(latestLaundry.serviceState)) {
      generated.add(
        _makePolicyEvent(
          base: latestLaundry,
          serviceState: 'Canceled',
          eventTimestamp: tsCursor++,
          note: 'policy.cancel dnd->laundry room=$room',
        ),
      );
    }
  } else if (incomingMurRequested || incomingLaundryRequested) {
    final latestDnd = latest[ServiceType.dnd];
    if (latestDnd != null && isDndRequestedState(latestDnd.serviceState)) {
      generated.add(
        _makePolicyEvent(
          base: latestDnd,
          serviceState: 'Off',
          eventTimestamp: tsCursor++,
          note: 'policy.cancel service->dnd room=$room',
          acknowledgement: ServiceAcknowledgement.none,
        ),
      );
    }
  }

  output.insert(0, incoming);
  if (generated.isNotEmpty) {
    output.insertAll(0, generated.reversed.toList());
  }
  return output;
}

Map<ServiceType, String> latestStateByTypeForRoom(
  List<RoomServiceEntry> entries,
  String roomNumber,
) {
  final latest = _latestByTypeForRoom(entries, roomNumber);
  return latest.map((key, value) => MapEntry(key, value.serviceState));
}

Map<ServiceType, RoomServiceEntry> _latestByTypeForRoom(
  List<RoomServiceEntry> entries,
  String roomNumber,
) {
  final latest = <ServiceType, RoomServiceEntry>{};
  for (final e in entries) {
    if (e.roomNumber != roomNumber) {
      continue;
    }
    final existing = latest[e.serviceType];
    if (existing == null || e.eventTimestamp > existing.eventTimestamp) {
      latest[e.serviceType] = e;
    }
  }
  return latest;
}

int _maxTimestamp(List<RoomServiceEntry> entries, int incomingTs) {
  var maxTs = incomingTs;
  for (final e in entries) {
    if (e.eventTimestamp > maxTs) {
      maxTs = e.eventTimestamp;
    }
  }
  return maxTs;
}

RoomServiceEntry _makePolicyEvent({
  required RoomServiceEntry base,
  required String serviceState,
  required int eventTimestamp,
  required String note,
  ServiceAcknowledgement? acknowledgement,
}) {
  final when = DateTime.fromMillisecondsSinceEpoch(eventTimestamp);
  final fmt = DateFormat('yyyy-MM-dd HH:mm');
  final isCanceled = serviceState.toLowerCase() == 'canceled';
  return RoomServiceEntry(
    id: '${base.id}-policy-$eventTimestamp',
    roomNumber: base.roomNumber,
    floor: base.floor,
    serviceType: base.serviceType,
    serviceState: serviceState,
    activationTime: fmt.format(when),
    eventTimestamp: eventTimestamp,
    delayedMinutes: 0,
    acknowledgement:
        acknowledgement ??
        (isCanceled
            ? ServiceAcknowledgement.none
            : ServiceAcknowledgement.waitingAck),
    acknowledgementTime: isCanceled ? fmt.format(when) : null,
    note: note,
  );
}
