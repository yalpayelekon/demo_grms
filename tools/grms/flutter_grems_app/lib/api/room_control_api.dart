import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/api_result.dart';
import '../models/backend_error.dart';
import '../models/room_models.dart';
import '../models/lighting_device.dart';
import '../models/rcu_models.dart';

class RoomControlApi {
  final String baseUrl;
  final http.Client _client;
  final Future<String?> Function()? roleProvider;
  final String Function(String roomNumber)? roomNumberResolver;

  RoomControlApi({
    required this.baseUrl,
    this.roleProvider,
    this.roomNumberResolver,
    http.Client? client,
  }) : _client = client ?? http.Client();

  String get _roomsBase => '$baseUrl/testcomm/rooms';

  String _resolveRoomNumber(String roomNumber) {
    return roomNumberResolver?.call(roomNumber) ?? roomNumber;
  }

  Future<ApiResult<RoomData>> getRoomSnapshot(String roomNumber) async {
    final effectiveRoomNumber = _resolveRoomNumber(roomNumber);
    return _requestJson(
      method: 'GET',
      path: '$_roomsBase/${Uri.encodeComponent(effectiveRoomNumber)}',
      parse: (json) => RoomData.fromJson(json),
    );
  }

  Future<ApiResult<void>> setLightingLevel(
    String roomNumber,
    int address,
    int level, {
    LightingDeviceType type = LightingDeviceType.onboard,
  }) async {
    final effectiveRoomNumber = _resolveRoomNumber(roomNumber);
    return _requestNoContent(
      method: 'POST',
      path:
          '$_roomsBase/${Uri.encodeComponent(effectiveRoomNumber)}/lighting/level',
      payload: {'address': address, 'level': level, 'type': type.name},
      includeRoleHeader: true,
    );
  }

  Future<ApiResult<LightingDevicesResponse>> getLightingDevices(
    String roomNumber,
  ) async {
    final effectiveRoomNumber = _resolveRoomNumber(roomNumber);
    return _requestJson(
      method: 'GET',
      path:
          '$_roomsBase/${Uri.encodeComponent(effectiveRoomNumber)}/lighting/devices',
      parse: (json) => LightingDevicesResponse.fromJson(json),
    );
  }

  Future<ApiResult<LightingSceneTriggerResponse>> triggerLightingScene(
    String roomNumber,
    int scene,
    {
    String? clientRequestId,
    int? clientTappedAtMs,
    }
  ) async {
    final effectiveRoomNumber = _resolveRoomNumber(roomNumber);
    final payload = <String, dynamic>{'scene': scene};
    if (clientRequestId != null && clientRequestId.isNotEmpty) {
      payload['clientRequestId'] = clientRequestId;
    }
    if (clientTappedAtMs != null) {
      payload['clientTappedAtMs'] = clientTappedAtMs;
    }
    return _requestJson(
      method: 'POST',
      path:
          '$_roomsBase/${Uri.encodeComponent(effectiveRoomNumber)}/lighting/scene',
      payload: payload,
      parse: (json) => LightingSceneTriggerResponse.fromJson(json),
      includeRoleHeader: true,
    );
  }

  Future<ApiResult<Map<String, dynamic>>> sendRawCommand(
    String roomNumber,
    String hexCommand, {
    String? clientRequestId,
  }) async {
    final effectiveRoomNumber = _resolveRoomNumber(roomNumber);
    final payload = <String, dynamic>{'hex': hexCommand};
    if (clientRequestId != null && clientRequestId.isNotEmpty) {
      payload['clientRequestId'] = clientRequestId;
    }
    return _requestJson(
      method: 'POST',
      path:
          '$_roomsBase/${Uri.encodeComponent(effectiveRoomNumber)}/raw-command',
      payload: payload,
      parse: (json) => json,
      includeRoleHeader: true,
    );
  }

  Future<ApiResult<RcuMenuResponse>> fetchRcuMenu(
    RcuMenuRequest request,
  ) async {
    final effectiveRoomNumber = _resolveRoomNumber(request.roomNumber);
    final path = '$_roomsBase/${Uri.encodeComponent(effectiveRoomNumber)}/menu';
    if (request.choice == null) {
      return _requestJson(
        method: 'GET',
        path: path,
        parse: (json) => RcuMenuResponse.fromJson(json),
      );
    } else {
      return _requestJson(
        method: 'POST',
        path: path,
        payload: request.toJson(),
        parse: (json) => RcuMenuResponse.fromJson(json),
      );
    }
  }

  Future<ApiResult<HvacDetail>> updateHvac(
    String roomNumber,
    Map<String, dynamic> updates,
  ) async {
    final effectiveRoomNumber = _resolveRoomNumber(roomNumber);
    return _requestJson(
      method: 'PUT',
      path: '$_roomsBase/${Uri.encodeComponent(effectiveRoomNumber)}/hvac',
      payload: updates,
      parse: (json) => HvacDetail.fromJson(json),
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
        case 'POST':
          return _SafeResponse(
            response: await _client.post(
              uri,
              headers: headers,
              body: payload == null ? null : jsonEncode(payload),
            ),
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
  final http.Response? response;
  final BackendError? error;

  const _SafeResponse({this.response, this.error});
}
