import '../config/app_config.dart';

String getTestCommBaseUrl() {
  final resolved = resolveTestCommApiBaseUrl();
  return normalizeBaseUrl(resolved);
}

String getTestCommBasePath() => '${getTestCommBaseUrl()}/testcomm';
