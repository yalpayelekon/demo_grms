import 'package:flutter/foundation.dart';

void debugLog(String message) {
  if (!kDebugMode) {
    return;
  }
  final now = DateTime.now().toIso8601String();
  debugPrint('$now $message');
}
