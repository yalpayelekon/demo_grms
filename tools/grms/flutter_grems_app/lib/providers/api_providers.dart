import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/settings_api.dart';
import '../api/coordinates_api.dart';
import '../api/room_control_api.dart';
import '../config/app_config.dart';
import 'auth_provider.dart';
import 'room_alias_provider.dart';

final appConfigProvider = Provider<AppConfig>((ref) => defaultAppConfig);

final coordinatesApiProvider = Provider<CoordinatesApi>((ref) {
  final authState = ref.watch(authProvider);
  final config = ref.watch(appConfigProvider);
  return CoordinatesApi(
    baseUrl: config.apiBaseUrl,
    roleProvider: () async => authState.role.label,
  );
});

final roomControlApiProvider = Provider<RoomControlApi>((ref) {
  final authState = ref.watch(authProvider);
  final config = ref.watch(appConfigProvider);
  return RoomControlApi(
    baseUrl: config.apiBaseUrl,
    roleProvider: () async => authState.role.label,
    roomNumberResolver: (roomNumber) => ref.read(
      effectiveBackendRoomNumberProvider(roomNumber),
    ),
  );
});

final settingsApiProvider = Provider<SettingsApi>((ref) {
  final authState = ref.watch(authProvider);
  final config = ref.watch(appConfigProvider);
  return SettingsApi(
    baseUrl: config.apiBaseUrl,
    roleProvider: () async => authState.role.label,
  );
});
