import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DateFormat {
  mmmDdYyyy('MMM DD, YYYY'),
  ddMmYyyy('DD/MM/YYYY'),
  mmDdYyyy('MM/DD/YYYY'),
  yyyyMmDd('YYYY-MM-DD'),
  ddMmmYyyy('DD MMM YYYY');

  final String label;
  const DateFormat(this.label);

  static DateFormat fromString(String label) {
    return DateFormat.values.firstWhere(
      (e) => e.label == label,
      orElse: () => DateFormat.mmmDdYyyy,
    );
  }
}

enum TimeFormat {
  h12('12h'),
  h24('24h');

  final String label;
  const TimeFormat(this.label);

  static TimeFormat fromString(String label) {
    return TimeFormat.values.firstWhere(
      (e) => e.label == label,
      orElse: () => TimeFormat.h12,
    );
  }
}

class Preferences {
  final DateFormat dateFormat;
  final TimeFormat timeFormat;
  final String city;

  Preferences({
    this.dateFormat = DateFormat.mmmDdYyyy,
    this.timeFormat = TimeFormat.h12,
    this.city = 'Copenhagen',
  });

  Preferences copyWith({
    DateFormat? dateFormat,
    TimeFormat? timeFormat,
    String? city,
  }) {
    return Preferences(
      dateFormat: dateFormat ?? this.dateFormat,
      timeFormat: timeFormat ?? this.timeFormat,
      city: city ?? this.city,
    );
  }

  Map<String, dynamic> toJson() => {
    'dateFormat': dateFormat.label,
    'timeFormat': timeFormat.label,
    'city': city,
  };

  factory Preferences.fromJson(Map<String, dynamic> json) => Preferences(
    dateFormat: DateFormat.fromString(json['dateFormat'] as String? ?? ''),
    timeFormat: TimeFormat.fromString(json['timeFormat'] as String? ?? ''),
    city: json['city'] as String? ?? 'Copenhagen',
  );
}

class PreferencesState {
  final Preferences preferences;
  final bool isInitialized;

  PreferencesState({required this.preferences, this.isInitialized = false});

  PreferencesState copyWith({Preferences? preferences, bool? isInitialized}) {
    return PreferencesState(
      preferences: preferences ?? this.preferences,
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }
}

class PreferencesNotifier extends Notifier<PreferencesState> {
  static const String _storageKey = 'grems_preferences';

  @override
  PreferencesState build() {
    _init();
    return PreferencesState(preferences: Preferences());
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_storageKey);
    if (jsonStr != null) {
      try {
        final decoded = Preferences.fromJson(jsonDecode(jsonStr));
        state = state.copyWith(preferences: decoded, isInitialized: true);
        return;
      } catch (e) {
        prefs.remove(_storageKey);
      }
    }
    state = state.copyWith(isInitialized: true);
  }

  Future<void> updatePreferences({
    DateFormat? dateFormat,
    TimeFormat? timeFormat,
    String? city,
  }) async {
    final updatedPreferences = state.preferences.copyWith(
      dateFormat: dateFormat,
      timeFormat: timeFormat,
      city: city,
    );
    state = state.copyWith(preferences: updatedPreferences);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(updatedPreferences.toJson()));
  }

  Future<void> resetPreferences() async {
    final defaultPreferences = Preferences();
    state = state.copyWith(preferences: defaultPreferences);

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}

final preferencesProvider =
    NotifierProvider<PreferencesNotifier, PreferencesState>(
      PreferencesNotifier.new,
    );
