import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/api_result.dart';
import '../models/backend_error.dart';
import '../models/demo_rcu_settings.dart';
import 'api_providers.dart';
import 'auth_provider.dart';

class DemoRcuSettingsNotifier extends AsyncNotifier<DemoRcuSettings> {
  @override
  Future<DemoRcuSettings> build() async {
    final api = ref.read(settingsApiProvider);
    final result = await api.getDemoRcuSettings();
    switch (result) {
      case Success<DemoRcuSettings>(value: final value):
        return value;
      case Failure<DemoRcuSettings>(error: final error):
        throw error;
    }
  }

  Future<BackendError?> save({required String host, required int port}) async {
    final role = ref.read(authProvider).role;
    if (role != UserRole.admin) {
      return BackendError(message: 'Admin access required', retryable: false);
    }

    state = const AsyncLoading();
    final api = ref.read(settingsApiProvider);
    final result = await api.updateDemoRcuSettings(host: host, port: port);
    switch (result) {
      case Success<DemoRcuSettings>(value: final value):
        state = AsyncData(value);
        return null;
      case Failure<DemoRcuSettings>(error: final error):
        state = AsyncError(error, StackTrace.current);
        return error;
    }
  }

  Future<void> reload() async {
    ref.invalidateSelf();
    await future;
  }
}

final demoRcuSettingsProvider =
    AsyncNotifierProvider<DemoRcuSettingsNotifier, DemoRcuSettings>(
      DemoRcuSettingsNotifier.new,
    );
