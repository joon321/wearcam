import 'package:flutter/foundation.dart';

final class BackendConfiguration {
  const BackendConfiguration._({this.uri, this.error});

  factory BackendConfiguration.fromUrl(
    String value, {
    bool allowInsecureHttp = kDebugMode,
  }) {
    final candidate = value.trim();
    if (candidate.toLowerCase().startsWith('sk-')) {
      return const BackendConfiguration._(
        error: 'Enter a backend URL only. Provider API keys are not accepted.',
      );
    }
    final uri = Uri.tryParse(candidate);
    if (uri == null || uri.host.isEmpty || !uri.hasScheme) {
      return const BackendConfiguration._(
        error: 'Enter the full URL of your WearCam backend.',
      );
    }
    if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      return const BackendConfiguration._(
        error:
            'Enter a backend base URL without credentials or URL parameters.',
      );
    }
    if (uri.scheme != 'https' &&
        !(kDebugMode && allowInsecureHttp && uri.scheme == 'http')) {
      return const BackendConfiguration._(
        error: 'The backend URL must use HTTPS (HTTP is debug-only).',
      );
    }
    return BackendConfiguration._(uri: uri);
  }

  final Uri? uri;
  final String? error;

  bool get isValid => uri != null;
}
