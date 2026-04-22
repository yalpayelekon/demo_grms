import 'package:flutter/foundation.dart';

enum LightingCoordinatesSourceMode {
  assetInDebugBackendInRelease,
  backendAlways,
  assetAlways,
}

class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    this.lightingCoordinatesSourceMode =
        LightingCoordinatesSourceMode.backendAlways,
  });

  final String apiBaseUrl;
  final LightingCoordinatesSourceMode lightingCoordinatesSourceMode;
}

enum DeploymentMode { local, deployed }

DeploymentMode resolveDeploymentMode() => _resolveDeploymentMode();

String normalizeBaseUrl(String url) => url.replaceAll(RegExp(r'/+$'), '');

String resolveRuntimeApiBaseUrl({String fallback = 'http://127.0.0.1:8081'}) {
  const envValue = String.fromEnvironment(
    'GREMS_API_BASE_URL',
    defaultValue: '',
  );
  if (envValue.isNotEmpty) {
    return normalizeBaseUrl(envValue);
  }

  final origin = _resolveSameOriginBaseUrl();
  if (origin != null) {
    return origin;
  }

  return normalizeBaseUrl(fallback);
}

String resolveTestCommApiBaseUrl({String fallback = 'http://localhost:8082'}) {
  const envValue = String.fromEnvironment(
    'TESTCOMM_BASE_URL',
    defaultValue: '',
  );
  final normalizedEnv = normalizeBaseUrl(envValue);
  // Treat empty or "/" as "use same origin / deployment logic", not as literal base URL
  if (normalizedEnv.isNotEmpty) {
    return normalizedEnv;
  }

  if (_resolveDeploymentMode() == DeploymentMode.local) {
    return normalizeBaseUrl(fallback);
  }

  final origin = _resolveSameOriginBaseUrl();
  if (origin != null) {
    return origin;
  }

  return resolveRuntimeApiBaseUrl();
}

String resolveDemoRcuDefaultHost({String fallback = '192.168.1.114'}) {
  const envValue = String.fromEnvironment(
    'DEMO_RCU_DEFAULT_HOST',
    defaultValue: '',
  );
  final normalizedEnv = envValue.trim();
  if (normalizedEnv.isNotEmpty) {
    return normalizedEnv;
  }
  return fallback;
}

DeploymentMode _resolveDeploymentMode() {
  const envValue = String.fromEnvironment(
    'GREMS_DEPLOYMENT_MODE',
    defaultValue: '',
  );

  switch (envValue.toLowerCase()) {
    case 'local':
      return DeploymentMode.local;
    case 'deployed':
      return DeploymentMode.deployed;
    default:
      return kReleaseMode ? DeploymentMode.deployed : DeploymentMode.local;
  }
}

String? _resolveSameOriginBaseUrl() {
  final base = Uri.base;
  final hasOrigin =
      (base.scheme == 'http' || base.scheme == 'https') && base.host.isNotEmpty;
  if (!hasOrigin) {
    return null;
  }

  return normalizeBaseUrl(base.origin);
}

final AppConfig defaultAppConfig = AppConfig(
  apiBaseUrl: resolveTestCommApiBaseUrl(),
);
