import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/preferences.dart';
import '../models/room_service_settings.dart';

class SettingsRepository {
  static const _preferencesKey = 'grems_preferences';
  static const _roomServiceSettingsKey = 'grems_room_service_settings';

  Future<Preferences> loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_preferencesKey);
    if (raw == null) return Preferences.defaults;
    return Preferences.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
  }

  Future<void> savePreferences(Preferences value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_preferencesKey, jsonEncode(value.toJson()));
  }

  Future<RoomServiceSettings> loadRoomServiceSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_roomServiceSettingsKey);
    if (raw == null) return RoomServiceSettings.defaults;
    return RoomServiceSettings.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
  }

  Future<void> saveRoomServiceSettings(RoomServiceSettings value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_roomServiceSettingsKey, jsonEncode(value.toJson()));
  }
}
