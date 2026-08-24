import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_grems_app/models/room_models.dart';
import 'package:flutter_grems_app/models/service_models.dart';
import 'package:flutter_grems_app/providers/room_service_provider.dart';
import 'package:flutter_grems_app/widgets/room_card.dart';

void main() {
  test('live yellow MUR snapshot maps to Started', () {
    expect(mapSnapshotServiceState(ServiceType.mur, 'Yellow'), 'Started');
  });
  group('deriveRoomStatus', () {
    test('uses rented housekeeping only while MUR is started', () {
      const occupancy = RoomOccupancy(occupied: false, rented: true);

      expect(
        deriveRoomStatus(
          currentStatus: RoomStatus.rentedVacant,
          occupancy: occupancy,
          mur: MurStatus.started,
        ),
        RoomStatus.rentedHK,
      );
      expect(
        deriveRoomStatus(
          currentStatus: RoomStatus.rentedVacant,
          occupancy: occupancy,
          mur: MurStatus.requested,
        ),
        RoomStatus.rentedVacant,
      );
      expect(
        deriveRoomStatus(
          currentStatus: RoomStatus.rentedHK,
          occupancy: occupancy,
          mur: MurStatus.delayed,
        ),
        RoomStatus.rentedVacant,
      );
    });

    test('uses unrented housekeeping while MUR is started', () {
      expect(
        deriveRoomStatus(
          currentStatus: RoomStatus.unrentedVacant,
          occupancy: const RoomOccupancy(occupied: false, rented: false),
          mur: MurStatus.started,
        ),
        RoomStatus.unrentedHK,
      );
    });

    test('finished and canceled MUR restore occupancy status', () {
      const occupied = RoomOccupancy(occupied: true, rented: true);
      const unrented = RoomOccupancy(occupied: false, rented: false);

      expect(
        deriveRoomStatus(
          currentStatus: RoomStatus.rentedHK,
          occupancy: occupied,
          mur: MurStatus.finished,
        ),
        RoomStatus.rentedOccupied,
      );
      expect(
        deriveRoomStatus(
          currentStatus: RoomStatus.unrentedHK,
          occupancy: unrented,
          mur: MurStatus.canceled,
        ),
        RoomStatus.unrentedVacant,
      );
    });
  });

  for (final scenario in <({RoomStatus status, String asset})>[
    (
      status: RoomStatus.rentedHK,
      asset: 'assets/images/room_status/greenhousekeeping.png',
    ),
    (
      status: RoomStatus.unrentedHK,
      asset: 'assets/images/room_status/whitehousekeeping.png',
    ),
  ]) {
    testWidgets('${scenario.status.label} uses housekeeping artwork', (
      tester,
    ) async {
      final room = RoomData(
        number: 'Demo 101',
        status: scenario.status,
        hasAlarm: false,
        lightingOn: false,
        hvac: HvacStatus.off,
        dnd: DndStatus.off,
        mur: MurStatus.started,
        laundry: LaundryStatus.finished,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(width: 120, height: 120, child: RoomCard(room: room)),
        ),
      );

      expect(_assetNames(tester), contains(scenario.asset));
    });
  }

  testWidgets('alarm styling still overrides housekeeping artwork', (
    tester,
  ) async {
    const room = RoomData(
      number: 'Demo 101',
      status: RoomStatus.rentedHK,
      hasAlarm: true,
      lightingOn: false,
      hvac: HvacStatus.off,
      dnd: DndStatus.off,
      mur: MurStatus.started,
      laundry: LaundryStatus.finished,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(width: 120, height: 120, child: RoomCard(room: room)),
      ),
    );

    expect(
      _assetNames(tester),
      contains('assets/images/room_status/redhousekeeping.png'),
    );
  });
}

Iterable<String> _assetNames(WidgetTester tester) => tester
    .widgetList<Image>(find.byType(Image))
    .map((image) => image.image)
    .whereType<AssetImage>()
    .map((image) => image.assetName);
