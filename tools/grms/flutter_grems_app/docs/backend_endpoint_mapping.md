# Backend endpoint mapping (Legacy React app migration → Flutter)

This document tracks the backend endpoints currently used by the legacy React app and maps each endpoint to Flutter API client methods.

## Shared error/result contract (Flutter)

Flutter now wraps API calls in `ApiResult<T>`:
- `ApiResult.success(data)` for successful responses.
- `ApiResult.failure(error)` for any HTTP/network/parse failure.

All failures are normalized to `BackendError`:
- `message: String`
- `statusCode: int?`
- `code: String?` (when provided by backend JSON)
- `details: Map<String, dynamic>?` (raw backend JSON payload)
- `retryable: bool` (`true` for network failures, `408`, `429`, and `5xx`)

## Retry policy

No automatic retries are performed by current Flutter API clients. Consumers (providers/pages) should:
- Retry only when `result.error?.retryable == true`.
- Avoid retries for validation/auth failures (`4xx` except `408/429`).

---

## Endpoint inventory + mapping

### 1) `GET /testcomm/rooms/{roomNumber}`
- **React method:** `getRoomSnapshot(roomNumber)` in `src/api/testComm.ts`
- **Flutter method:** `TestCommApi.getRoomSnapshot(roomNumber)`
- **Request schema:** path param `roomNumber: string`
- **Response schema:** `RoomData` JSON object
- **Error shape:** normalized to `BackendError`
- **Auth requirements:** none
- **Retry policy:** manual retry only when `retryable`

### 2) `GET /testcomm/rooms/{roomNumber}/lighting/devices`
- **React method:** `getLightingDevices(roomNumber)`
- **Flutter method:** `TestCommApi.getLightingDevices(roomNumber)`
- **Request schema:** path param `roomNumber: string`
- **Response schema:**
  - `onboardOutputs: LightingDeviceSummary[]`
  - `daliOutputs: LightingDeviceSummary[]`
  - `404` is normalized to empty arrays (compat behavior)
- **Error shape:** normalized to `BackendError` (except explicit `404` fallback)
- **Auth requirements:** none
- **Retry policy:** manual retry only when `retryable`

### 3) `POST /testcomm/rooms/{roomNumber}/lighting/level`
- **React method:** `setLightingLevel(roomNumber, payload)`
- **Flutter method:** `TestCommApi.setLightingLevel(roomNumber, address, level, type)`
- **Request schema:**
  - `address: number`
  - `level: number`
  - `type: 'onboard' | 'dali'`
- **Response schema:** empty/no-content success (2xx)
- **Error shape:** normalized to `BackendError`
- **Auth requirements:** none
- **Retry policy:** manual retry only when `retryable`

### 4) `GET /testcomm/rooms/{roomNumber}/hvac`
- **React method:** `getRoomHvac(roomNumber)`
- **Flutter method:** `TestCommApi.getRoomHvac(roomNumber)`
- **Request schema:** path param `roomNumber: string`
- **Response schema:** `HvacData` JSON object
- **Error shape:** normalized to `BackendError`
- **Auth requirements:** none
- **Retry policy:** manual retry only when `retryable`

### 5) `PUT /testcomm/rooms/{roomNumber}/hvac`
- **React method:** `setRoomHvac(roomNumber, payload)`
- **Flutter method:** `TestCommApi.setRoomHvac(roomNumber, updates)`
- **Request schema:** partial HVAC update object (`Map<String, dynamic>`)
- **Response schema:** updated `HvacData` JSON object
- **Error shape:** normalized to `BackendError`
- **Auth requirements:** none
- **Retry policy:** manual retry only when `retryable`

### 6) `GET /testcomm/coordinates`
- **React method:** `getCoordinates()` in `src/api/coordinates.ts`
- **Flutter method:** `CoordinatesApi.getCoordinates()`
- **Request schema:** none
- **Response schema:**
  - `zones: object` with canonical `schemaVersion: 2`
  - `zones.categoryNamesBlockFloorMap: Record<string, Record<string, string[]>>`
  - `lightingDevices: LightingDeviceSummary[]`
- **Error shape:** normalized to `BackendError`
- **Auth requirements:** none
- **Retry policy:** manual retry only when `retryable`

### 7) `PUT /testcomm/coordinates/zones`
- **React method:** `saveZones(zones)`
- **Flutter method:** `CoordinatesApi.saveZones(zones)`
- **Request schema:** `zones: object` (`Map<String, dynamic>`) with canonical nested floor->rooms map
- **Response schema:** empty/no-content success (2xx)
- **Error shape:** normalized to `BackendError`; invalid zones schema returns `400`
- **Auth requirements:** optional `X-User-Role` header for write authorization
- **Retry policy:** manual retry only when `retryable`

### 8) `PUT /testcomm/coordinates/lighting-devices`
- **React method:** `saveLightingDevices(devices)`
- **Flutter method:** `CoordinatesApi.saveLightingDevices(devices)`
- **Request schema:** `devices: object[]` (`List<Map<String, dynamic>>`)
- **Response schema:** empty/no-content success (2xx)
- **Error shape:** normalized to `BackendError`
- **Auth requirements:** optional `X-User-Role` header for write authorization
- **Retry policy:** manual retry only when `retryable`

### 9) `GET /testcomm/coordinates/stream` (websocket)
- **React method:** `subscribeToCoordinatesUpdates(...)` in `src/utils/coordinatesSubscription.ts`
- **Flutter method:** `coordinatesSyncProvider` (`lib/providers/coordinates_sync_provider.dart`)
- **Message schema:** `{"event":"coordinates.updated","payload":{"zones":...,"lightingDevices":[...]}}`
- **Behavior:** initial REST refresh + websocket stream + exponential backoff reconnect
