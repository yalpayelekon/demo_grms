import 'package:flutter_riverpod/flutter_riverpod.dart';

const demoBackendRoomNumber = 'Demo 101';

final mirroredDemoRoomNumberProvider = StateProvider<String?>((ref) => null);

final effectiveBackendRoomNumberProvider = Provider.family<String, String>((
  ref,
  roomNumber,
) {
  final mirroredRoomNumber = ref.watch(mirroredDemoRoomNumberProvider);
  if (_sameRoomNumber(roomNumber, mirroredRoomNumber)) {
    return demoBackendRoomNumber;
  }
  return roomNumber;
});

bool isMirroredDemoRoom(WidgetRef ref, String roomNumber) {
  return _sameRoomNumber(ref.read(mirroredDemoRoomNumberProvider), roomNumber);
}

bool _sameRoomNumber(String? a, String? b) {
  if (a == null || b == null) {
    return false;
  }
  return a.trim().toLowerCase() == b.trim().toLowerCase();
}
