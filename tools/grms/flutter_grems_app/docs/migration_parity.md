# React → Flutter Migration Parity Matrix

> **Process rule (required):** Every phase PR **must** update this matrix (status, destination file, owner, or notes) so parity gaps are visible as early as possible.

## Status legend
- `not-started`
- `in-progress`
- `blocked`
- `done`

## Parity checklist

| Checklist | React source anchor (legacy React source tree) | Behavior summary (including edge cases) | Flutter destination file | Status | Owner |
|---|---|---|---|---|---|
| - [x] | `pages/Login.tsx#handleSubmit` + `contexts/AuthContext.tsx#login` | Login flow with localStorage session persistence; supports default credentials and role assignment. Edge case: failed credentials stay on login without session writes. | `lib/pages/login_page.dart` | done | @antigravity |
| - [x] | `contexts/AuthContext.tsx#deleteUser` | Auth/user management context (add/update/delete users, display name updates, persisted users). Edge cases: cannot delete signed-in user, cannot remove last admin, duplicate username rejection. | `lib/providers/auth_provider.dart` | done | @antigravity |
| - [x] | `components/Header.tsx#navLinks` + `pages/Home.tsx#isAdmin` | Role-based navigation visibility and route affordances. Edge case: Settings/admin-only controls hidden for `viewer`. | `lib/app_shell.dart` | done | @antigravity |
| - [x] | `pages/Home.tsx#handleZonePointerDown` / `#handleZonePointerMove` / `#finishZoneDrag` | Floor map interactions: zone click-through navigation, admin-only polygon drag repositioning, RAF-throttled updates, delayed persist. Edge cases: drag-distance threshold and click suppression window prevent accidental navigation after drag. | `lib/pages/home_page.dart` | done | @antigravity |
| - [x] | `pages/Home.tsx#zoneBadgeCounts` | Zone-level badges aggregate alarms + delayed room services mapped from room labels to block/floor metadata. Edge cases: fallback matching by numeric room fragments and normalized zone names. | `lib/pages/home_page.dart` | done | @antigravity |
| - [x] | `pages/HotelStatus.tsx#filteredRooms` + `#toggleStatusFilter` | Hotel status board filters by zone/floor, room query, occupancy state chips, and feature visibility toggles (Lighting/HVAC/Room Service). Edge cases: multi-filter combinations, empty state, fallback to demo zone. | `lib/pages/hotel_status_page.dart` | done | @antigravity |
| - [x] | `pages/HotelStatus.tsx#LightingDialog` + `#filteredMenuOptions` + `#sanitizedOutputText` | Lighting dialog with role restrictions. Viewer mode only exposes output/target-level menu options and sanitized command output; control mode sees full command menu. | `lib/pages/hotel_status/widgets/lighting_dialog.dart` | done | @antigravity |
| - [x] | `pages/HotelStatus.tsx#handleDeviceLevelSubmit` + `api/testComm.ts#setLightingLevel` | Per-device lighting level updates with active-device state and submit status badges. Edge cases: numeric target validation, saving/error/saved states, UI target-level refresh after successful write (optimistic-feeling per-device feedback). | `lib/pages/hotel_status/widgets/lighting_dialog.dart` | done | @antigravity |
| - [x] | `pages/HotelStatus.tsx#HvacDialog` + `api/testComm.ts#getRoomHvac` / `#setRoomHvac` | HVAC detail dialog with editable setpoint/mode/fan/on-off, dirty-field tracking, and save gating. Edge cases: parse/validation for nullable numeric inputs, disable controls during load/save, normalize unknown HVAC payloads. | `lib/pages/hotel_status_page.dart` | done | @antigravity |
| - [x] | `pages/Alarms.tsx#filteredAlarms` + `#paginatedAlarms` | Alarm list with severity/status/type filters plus client-side pagination. Edge cases: page index clamped when filter shrinks result set, zero-result summary counters. | `lib/pages/alarms_page.dart` | done | @antigravity |
| - [x] | `pages/Reports.tsx#filterByDateRange` | Reports tabs (alarms/services/activity/exports) with date-range filtering and preview modal. Edge cases: mixed timestamp fields (`incidentTime` vs `activationTime`) and inclusive time windows. | `lib/pages/reports_page.dart` | done | @antigravity |
| - [x] | `pages/Dashboard.tsx` | Dashboard view with aggregated stats for alarms, occupancy, HVAC distribution and room services. Includes real-time weather and energy consumption charts. | `lib/pages/dashboard_page.dart` | done | @antigravity |
| - [x] | `pages/ServiceStatus.tsx#serviceState` + `hooks/useRoomServiceData.tsx` | Service status workflows (DND/MUR/Laundry readiness and delay semantics) and derived room-level service indicators. Edge cases: delayed thresholds and merged service state from multiple feeds. | `lib/pages/service_status_page.dart` | done | @antigravity |
| - [x] | `pages/Settings.tsx` | Tabbed settings interface for Profile (user management), Zones (active toggles), Room Services (thresholds), and Preferences (localization). | `lib/pages/settings_page.dart` | done | @antigravity |
| - [x] | `contexts/ZonesContext.tsx#persistZones` + `api/coordinates.ts#saveZones` | Zones state sync and persistence to coordinates API. Edge cases: request failure toast with dedupe window, role header forwarding (`X-User-Role`) for write authorization. | `lib/providers/zones_provider.dart` | done | @antigravity |
| - [x] | `contexts/LightingDevicesContext.tsx#updateDevice` + `api/coordinates.ts#saveLightingDevices` | Lighting device coordinate/config state hydrates from coordinates payload and websocket updates; merge policy is applied for replay-safe state updates. Edge case: stale replay frames do not regress device state. | `lib/providers/lighting_devices_provider.dart` | done | @antigravity |
| - [x] | `utils/coordinatesSubscription.ts#scheduleReconnect` + `#connectWebSocket` | Realtime coordinates stream subscription shared by zones and lighting contexts with initial REST refresh and exponential backoff reconnect. Edge case: first websocket replay frame is de-duplicated when payload is unchanged. | `lib/providers/coordinates_sync_provider.dart` | done | @antigravity |

## Usage in migration PRs
- Update every touched row’s **Status**, **Flutter destination file**, and **Owner** in each phase PR.
- If a React behavior is split across multiple Flutter files, keep one matrix row and list the primary destination with brief notes in the PR.
- Add new rows immediately when React scope expands; do not defer parity tracking.

## State merge policy migration notes (zones, lighting, room service)

- Shared merge utility: `lib/providers/state_merge_policy.dart`.
- Providers wired to this policy:
  - `lib/providers/zones_provider.dart`
  - `lib/providers/lighting_devices_provider.dart`
  - `lib/providers/room_service_provider.dart`

### Precedence order

When data quality signals are tied/missing, precedence is:

1. local optimistic update
2. websocket event
3. polling snapshot

### Timestamp/version behavior

- Higher `version` wins across all sources.
- If versions are equal/missing, newer `eventTimestamp` wins.
- If event timestamps are equal/missing, newer `observedAt` wins.
- Source precedence is the final tie-breaker.

### Stale/out-of-order/replay handling

- Lower version payloads are discarded as stale.
- Older event timestamps are discarded as out-of-order.
- Older arrival timestamps are discarded when no stronger metadata exists.
- Reconnect replay websocket frames (`isReplay=true`) are treated as duplicates unless
  they carry strictly newer metadata than currently merged state.

This policy prevents flicker/revert loops where periodic snapshots or delayed replayed
events temporarily override more recent local or websocket-confirmed state.
## Backend endpoint migration checklist

| Endpoint | Wired | Validated in UI | Handles failure state |
|---|---|---|---|
| `GET /testcomm/rooms/{roomNumber}` | [x] | [x] | [x] |
| `GET /testcomm/rooms/{roomNumber}/lighting/devices` | [x] | [x] | [x] |
| `POST /testcomm/rooms/{roomNumber}/lighting/level` | [x] | [x] | [x] |
| `GET /testcomm/rooms/{roomNumber}/hvac` | [x] | [x] | [x] |
| `PUT /testcomm/rooms/{roomNumber}/hvac` | [x] | [x] | [x] |
| `GET /testcomm/coordinates` | [x] | [x] | [x] |
| `PUT /testcomm/coordinates/zones` | [x] | [x] | [x] |
| `PUT /testcomm/coordinates/lighting-devices` | [x] | [x] | [x] |
