# Flutter Grems App

A Flutter Web frontend for the GRMS (Guest Room Management System) migrated from React.

## Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (latest stable)
- Java 11+ (for running the TestComm backend)

### Development
1. Get dependencies:
   ```bash
   flutter pub get
   ```
2. Run locally (web):
   ```bash
   flutter run -d chrome
   ```

### API Configuration
`flutter_grems_app` resolves the TestComm base URL in this order:

1. `--dart-define=TESTCOMM_BASE_URL=<absolute_url>` (highest priority)
2. Browser same-origin (`Uri.base.origin`) when running over `http/https`
3. Local fallback `http://localhost:8082` **only** when deployment mode is `local`
4. Runtime API base URL (`GREMS_API_BASE_URL`, then runtime fallback)

Deployment mode is controlled by `--dart-define=GREMS_DEPLOYMENT_MODE=<value>`.

Supported values:
- `local` → enables localhost fallback for local development.
- `deployed` → disables localhost fallback; prefer same-origin/deployed settings.

If omitted, mode is inferred from build type (`debug/profile` => `local`, `release` => `deployed`).

Examples:
```bash
# Local development (default behavior)
flutter run -d chrome --dart-define=GREMS_DEPLOYMENT_MODE=local

# Deployed profile/release behind the same host as backend
flutter build web --release --dart-define=GREMS_DEPLOYMENT_MODE=deployed

# Explicit backend override (works in any mode)
flutter run -d chrome --dart-define=TESTCOMM_BASE_URL=https://api.example.com
```

Recommended release value:
```bash
--dart-define=GREMS_DEPLOYMENT_MODE=deployed
```

### Build for Production
Build the static web assets:
```bash
flutter build web --base-href /
```
The output will be in `build/web`.

When building for Serenity Studio (app served at `http://localhost:4810/grms`), use base href `/grms/` so asset URLs resolve under `/grms/`.

#### Supported deployment modes

1. **Direct backend URL mode (recommended when proxy forwarding is not guaranteed)**
   - No dependency on WebRuntimeServer proxy rewrites.
   - Set an explicit absolute TestComm backend URL (example: `http://127.0.0.1:8081`).
   ```bash
   flutter build web --base-href /grms/ --dart-define=GREMS_API_BASE_URL=http://127.0.0.1:8081 --dart-define=TESTCOMM_BASE_URL=http://127.0.0.1:8081
   ```

2. **Same-origin proxy mode (requires `/testcomm/*` forwarding in WebRuntimeServer)**
   - Uses same-origin URLs (`/`) and depends on Serenity Studio runtime proxy rules.
   - WebRuntimeServer must forward `http://localhost:4810/testcomm/*` to the backend service.
   ```bash
   flutter build web --base-href /grms/ --dart-define=GREMS_API_BASE_URL=/ --dart-define=TESTCOMM_BASE_URL=/
   ```

#### Troubleshooting

- Console shows `ws://testcomm/... failed`
  - The app resolved a non-routable host/path for TestComm.
  - Use direct backend URL mode with an absolute URL such as `http://127.0.0.1:8081`.
- Console shows `localhost:4810/testcomm/... 404`
  - Same-origin proxy mode is active, but `/testcomm/*` forwarding is missing or misconfigured.
  - Add/fix the WebRuntimeServer proxy rule or switch to direct backend URL mode.

### Integration with TestComm
To serve this app using the TestComm Java service:
```bash
java -jar TestComm.jar --web-root ./build/web
```
Access the application at `http://localhost:8082`.
