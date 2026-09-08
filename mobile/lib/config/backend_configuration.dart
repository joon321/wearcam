import 'package:flutter/foundation.dart';

final class BackendConfiguration {
  const BackendConfiguration._({this.uri, this.error});

  factory BackendConfiguration.fromUrl(
    String value, {
    bool allowInsecureHttp = kDebugMode,
  }) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.host.isEmpty || !uri.hasScheme) {
      return const BackendConfiguration._(
        error: 'Build the app with --dart-define=WEARCAM_BACKEND_URL=<url>.',
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
