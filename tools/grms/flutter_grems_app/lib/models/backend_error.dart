import 'dart:convert';

class BackendError {
  final String message;
  final int? statusCode;
  final String? code;
  final Map<String, dynamic>? details;
  final bool retryable;

  const BackendError({
    required this.message,
    this.statusCode,
    this.code,
    this.details,
    required this.retryable,
  });

  factory BackendError.network(Object error) {
    return BackendError(
      message: 'Network request failed: $error',
      retryable: true,
    );
  }

  factory BackendError.fromHttp({
    required int statusCode,
    required String body,
  }) {
    final parsed = _parseJsonObject(body);
    final message =
        (parsed?['message'] as String?) ??
        (parsed?['error'] as String?) ??
        body.trim();

    return BackendError(
      message: message.isEmpty
          ? 'Request failed with status $statusCode'
          : message,
      statusCode: statusCode,
      code: parsed?['code'] as String?,
      details: parsed,
      retryable: _isRetryableStatus(statusCode),
    );
  }

  static Map<String, dynamic>? _parseJsonObject(String body) {
    if (body.trim().isEmpty) {
      return null;
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    return null;
  }

  static bool _isRetryableStatus(int statusCode) {
    return statusCode == 408 || statusCode == 429 || statusCode >= 500;
  }
}
