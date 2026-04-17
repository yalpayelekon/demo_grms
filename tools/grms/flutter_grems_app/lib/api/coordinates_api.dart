import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/api_result.dart';
import '../models/backend_error.dart';
import '../models/coordinates_models.dart';

class CoordinatesApi {
  final String baseUrl;
  final http.Client _client;
  final Future<String?> Function()? roleProvider;

  CoordinatesApi({
    required this.baseUrl,
    this.roleProvider,
    http.Client? client,
  }) : _client = client ?? http.Client();

  String get _coordinatesBase => '$baseUrl/testcomm/coordinates';

  Future<ApiResult<CoordinatesPayload>> getCoordinates() {
    return _requestJson(
      method: 'GET',
      path: _coordinatesBase,
      parse: CoordinatesPayload.fromJson,
    );
  }

  Future<ApiResult<void>> saveZones(Map<String, dynamic> zones) async {
    final unauthorized = await _requireRoleForMutation();
    if (unauthorized != null) {
      return ApiResult.failure(unauthorized);
    }

    return _requestNoContent(
      method: 'PUT',
      path: '$_coordinatesBase/zones',
      payload: zones,
      includeRoleHeader: true,
    );
  }

  Future<ApiResult<void>> saveLightingDevices(List<Map<String, dynamic>> devices) async {
    final unauthorized = await _requireRoleForMutation();
    if (unauthorized != null) {
      return ApiResult.failure(unauthorized);
    }

    return _requestNoContent(
      method: 'PUT',
      path: '$_coordinatesBase/lighting-devices',
      payload: devices,
      includeRoleHeader: true,
    );
  }

  Future<ApiResult<void>> saveServiceIcons(List<Map<String, dynamic>> icons) async {
    final unauthorized = await _requireRoleForMutation();
    if (unauthorized != null) {
      return ApiResult.failure(unauthorized);
    }

    return _requestNoContent(
      method: 'PUT',
      path: '$_coordinatesBase/service-icons',
      payload: icons,
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
          message: 'Expected JSON object response but received ${decoded.runtimeType}',
          statusCode: raw.statusCode,
          retryable: false,
        ),
      );
    }

    return ApiResult.success(parse(decoded));
  }

  Future<ApiResult<void>> _requestNoContent({
    required String method,
    required String path,
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
    if (raw.statusCode >= 200 && raw.statusCode < 300) {
      return ApiResult.success(null);
    }

    return ApiResult.failure(
      BackendError.fromHttp(statusCode: raw.statusCode, body: raw.body),
    );
  }


  Future<BackendError?> _requireRoleForMutation() async {
    final role = await roleProvider?.call();
    if (role == 'admin') {
      return null;
    }

    return BackendError(
      message: 'Unauthorized: admin role is required for this mutation.',
      statusCode: 403,
      code: 'role_forbidden',
      retryable: false,
    );
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
          return _SafeResponse(response: await _client.get(uri));
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
  final http.Response? response;
  final BackendError? error;

  const _SafeResponse({this.response, this.error});
}
