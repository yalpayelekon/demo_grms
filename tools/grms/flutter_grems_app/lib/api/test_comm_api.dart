import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_models/shared_models.dart';

import '../models/api_result.dart';
import '../models/backend_error.dart';
import '../models/lighting_device.dart';

class TestCommApi {
  final String baseUrl;
  final http.Client _client;

  TestCommApi({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  String get _roomBase => '$baseUrl/testcomm/rooms';

  Future<ApiResult<RoomData>> getRoomSnapshot(String roomNumber) {
    return _getJson(
      path: '$_roomBase/${Uri.encodeComponent(roomNumber)}',
      parse: (json) => RoomData.fromJson(json),
    );
  }

  Future<ApiResult<LightingDevicesResponse>> getLightingDevices(
    String roomNumber,
  ) async {
    final response = await _safeGet(
      Uri.parse('$_roomBase/${Uri.encodeComponent(roomNumber)}/lighting/devices'),
    );

    if (response.error != null) {
      return ApiResult.failure(response.error!);
    }

    final raw = response.response!;
    if (raw.statusCode == 404) {
      return ApiResult.success(
        LightingDevicesResponse(onboardOutputs: [], daliOutputs: []),
      );
    }

    return _handleJsonResponse(
      raw,
      (json) => LightingDevicesResponse.fromJson(json),
    );
  }

  Future<ApiResult<void>> setLightingLevel(
    String roomNumber,
    int address,
    int level,
    String type,
  ) async {
    final response = await _safePost(
      Uri.parse('$_roomBase/${Uri.encodeComponent(roomNumber)}/lighting/level'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'address': address,
        'level': level,
        'type': type,
      }),
    );

    if (response.error != null) {
      return ApiResult.failure(response.error!);
    }

    return _handleEmptyResponse(response.response!);
  }

  Future<ApiResult<HvacData>> getRoomHvac(String roomNumber) {
    return _getJson(
      path: '$_roomBase/${Uri.encodeComponent(roomNumber)}/hvac',
      parse: (json) => HvacData.fromJson(json),
    );
  }

  Future<ApiResult<HvacData>> setRoomHvac(
    String roomNumber,
    Map<String, dynamic> updates,
  ) {
    return _putJson(
      path: '$_roomBase/${Uri.encodeComponent(roomNumber)}/hvac',
      payload: updates,
      parse: (json) => HvacData.fromJson(json),
    );
  }

  Future<ApiResult<T>> _getJson<T>({
    required String path,
    required T Function(Map<String, dynamic>) parse,
  }) async {
    final response = await _safeGet(Uri.parse(path));
    if (response.error != null) {
      return ApiResult.failure(response.error!);
    }
    return _handleJsonResponse(response.response!, parse);
  }

  Future<ApiResult<T>> _putJson<T>({
    required String path,
    required Map<String, dynamic> payload,
    required T Function(Map<String, dynamic>) parse,
  }) async {
    final response = await _safePut(
      Uri.parse(path),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.error != null) {
      return ApiResult.failure(response.error!);
    }

    return _handleJsonResponse(response.response!, parse);
  }

  ApiResult<T> _handleJsonResponse<T>(
    http.Response response,
    T Function(Map<String, dynamic>) parse,
  ) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return ApiResult.failure(
        BackendError.fromHttp(statusCode: response.statusCode, body: response.body),
      );
    }

    final dynamic json;
    try {
      json = jsonDecode(response.body);
    } on FormatException catch (error) {
      return ApiResult.failure(
        BackendError(
          message: 'Invalid JSON response: $error',
          statusCode: response.statusCode,
          retryable: false,
        ),
      );
    }

    if (json is! Map<String, dynamic>) {
      return ApiResult.failure(
        BackendError(
          message: 'Expected JSON object response but received ${json.runtimeType}',
          statusCode: response.statusCode,
          retryable: false,
        ),
      );
    }

    return ApiResult.success(parse(json));
  }

  ApiResult<void> _handleEmptyResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return const ApiResult.success(null);
    }

    return ApiResult.failure(
      BackendError.fromHttp(statusCode: response.statusCode, body: response.body),
    );
  }

  Future<_SafeResponse> _safeGet(Uri uri) async {
    try {
      return _SafeResponse(response: await _client.get(uri));
    } catch (error) {
      return _SafeResponse(error: BackendError.network(error));
    }
  }

  Future<_SafeResponse> _safePost(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    try {
      return _SafeResponse(
        response: await _client.post(uri, headers: headers, body: body),
      );
    } catch (error) {
      return _SafeResponse(error: BackendError.network(error));
    }
  }

  Future<_SafeResponse> _safePut(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    try {
      return _SafeResponse(
        response: await _client.put(uri, headers: headers, body: body),
      );
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
