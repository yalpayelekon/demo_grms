import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RoomServiceSettings {
  final int murDelayThresholdSeconds;
  final int laundryDelayThresholdSeconds;

  RoomServiceSettings({
    this.murDelayThresholdSeconds = 10,
    this.laundryDelayThresholdSeconds = 10,
  });

  RoomServiceSettings copyWith({
    int? murDelayThresholdSeconds,
    int? laundryDelayThresholdSeconds,
  }) {
    return RoomServiceSettings(
      murDelayThresholdSeconds: murDelayThresholdSeconds ?? this.murDelayThresholdSeconds,
      laundryDelayThresholdSeconds: laundryDelayThresholdSeconds ?? this.laundryDelayThresholdSeconds,
    );
  }

  Map<String, dynamic> toJson() => {
        'murDelayThresholdSeconds': murDelayThresholdSeconds,
        'laundryDelayThresholdSeconds': laundryDelayThresholdSeconds,
      };

  factory RoomServiceSettings.fromJson(Map<String, dynamic> json) => RoomServiceSettings(
        murDelayThresholdSeconds: json['murDelayThresholdSeconds'] as int? ?? 10,
        laundryDelayThresholdSeconds: json['laundryDelayThresholdSeconds'] as int? ?? 10,
      );
}

class RoomServiceSettingsState {
  final RoomServiceSettings settings;
  final bool isInitialized;

  RoomServiceSettingsState({
    required this.settings,
    this.isInitialized = false,
  });

  RoomServiceSettingsState copyWith({
    RoomServiceSettings? settings,
    bool? isInitialized,
  }) {
    return RoomServiceSettingsState(
      settings: settings ?? this.settings,
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }
}

class RoomServiceSettingsNotifier extends Notifier<RoomServiceSettingsState> {
  static const String _storageKey = 'grems_room_service_settings';

  @override
  RoomServiceSettingsState build() {
    _init();
    return RoomServiceSettingsState(settings: RoomServiceSettings());
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_storageKey);
    if (jsonStr != null) {
      try {
        final decoded = RoomServiceSettings.fromJson(jsonDecode(jsonStr));
        state = state.copyWith(settings: decoded, isInitialized: true);
        return;
      } catch (e) {
        prefs.remove(_storageKey);
      }
    }
    state = state.copyWith(isInitialized: true);
  }

  Future<void> updateSettings({
    int? murDelayThresholdSeconds,
    int? laundryDelayThresholdSeconds,
  }) async {
    final updatedSettings = state.settings.copyWith(
      murDelayThresholdSeconds: murDelayThresholdSeconds,
      laundryDelayThresholdSeconds: laundryDelayThresholdSeconds,
    );
    state = state.copyWith(settings: updatedSettings);
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(updatedSettings.toJson()));
  }

  Future<void> resetSettings() async {
    final defaultSettings = RoomServiceSettings();
    state = state.copyWith(settings: defaultSettings);
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}

final roomServiceSettingsProvider = NotifierProvider<RoomServiceSettingsNotifier, RoomServiceSettingsState>(RoomServiceSettingsNotifier.new);

