import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/coordinates_models.dart';

class ServiceIconPositionsNotifier extends Notifier<Map<String, Offset>> {
  @override
  Map<String, Offset> build() => const <String, Offset>{};

  void applyFromPayload(List<ServiceIconConfig> icons) {
    if (icons.isEmpty) {
      return;
    }
    final next = <String, Offset>{
      for (final icon in icons) icon.serviceType: Offset(icon.x, icon.y),
    };
    state = Map.unmodifiable(next);
    if (kDebugMode) {
      debugPrint(
        'ServiceIconPositionsNotifier: applied service icon coordinates '
        'count=${next.length}',
      );
    }
  }
}

final serviceIconPositionsProvider =
    NotifierProvider<ServiceIconPositionsNotifier, Map<String, Offset>>(
  ServiceIconPositionsNotifier.new,
);

