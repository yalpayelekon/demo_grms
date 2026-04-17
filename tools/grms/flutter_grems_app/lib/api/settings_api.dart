import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/api_result.dart';
import '../models/backend_error.dart';
import '../models/demo_rcu_settings.dart';

class SettingsApi {
  SettingsApi({required this.baseUrl, this.roleProvider, http.Client? client})
    : _client = client ?? http.Client();

  final String baseUrl;
  final Future<String?> Function()? roleProvider;
  final http.Client _client;

  Future<ApiResult<DemoRcuSettings>> getDemoRcuSettings() {
    return _requestJson(
      method: 'GET',
      path: '$baseUrl/testcomm/settings/demo-rcu',
      parse: DemoRcuSettings.fromJson,
    );
  }

  Future<ApiResult<DemoRcuSettings>> updateDemoRcuSettings({
    required String host,
    required int port,
  }) {
    return _requestJson(
      method: 'PUT',
      path: '$baseUrl/testcomm/settings/demo-rcu',
      payload: {'host': host, 'port': port},
      parse: DemoRcuSettings.fromJson,
      includeRoleHeader: true,
    );
  }

  Future<ApiResult<T>> _requestJson<T>({
    required String method,
    required String path,
    required T Function(Map<String, dynamic>) parse,
    Object? payload,
    bool includeRoleHeader = false,
  }) async {
    final response = await _safeSend(
      method: method,
      uri: Uri.parse(path),
      payload: payload,
      includeRoleHeader: includeRoleHeader,
    );

    if (response.error != null) {
      return ApiResult.failure(response.error!);
    }

    final raw = response.response!;
    if (raw.statusCode < 200 || raw.statusCode >= 300) {
      return ApiResult.failure(
        BackendError.fromHttp(statusCode: raw.statusCode, body: raw.body),
      );
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(raw.body);
    } on FormatException catch (error) {
      return ApiResult.failure(
        BackendError(
          message: 'Invalid JSON response: $error',
          statusCode: raw.statusCode,
          retryable: false,
        ),
      );
    }

    if (decoded is! Map<String, dynamic>) {
      return ApiResult.failure(
        BackendError(
          message:
              'Expected JSON object response but received ${decoded.runtimeType}',
          statusCode: raw.statusCode,
          retryable: false,
        ),
      );
    }

    return ApiResult.success(parse(decoded));
  }

  Future<_SafeResponse> _safeSend({
    required String method,
    required Uri uri,
    Object? payload,
    required bool includeRoleHeader,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (includeRoleHeader) {
      final role = await roleProvider?.call();
      if (role != null && role.isNotEmpty) {
        headers['X-User-Role'] = role;
      }
    }

    try {
      switch (method) {
        case 'GET':
          return _SafeResponse(
            response: await _client.get(uri, headers: headers),
          );
        case 'PUT':
          return _SafeResponse(
            response: await _client.put(
              uri,
              headers: headers,
              body: payload == null ? null : jsonEncode(payload),
            ),
          );
        default:
          return _SafeResponse(
            error: BackendError(
              message: 'Unsupported HTTP method: $method',
              retryable: false,
            ),
          );
      }
    } catch (error) {
      return _SafeResponse(error: BackendError.network(error));
    }
  }
}

class _SafeResponse {
  const _SafeResponse({this.response, this.error});

  final http.Response? response;
  final BackendError? error;
}
