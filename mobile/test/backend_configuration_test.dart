import 'package:flutter_test/flutter_test.dart';
import 'package:wearcam/config/backend_configuration.dart';

void main() {
  test('accepts a reachable HTTPS backend URL', () {
    final configuration = BackendConfiguration.fromUrl(
      'https://wearcam.example.com',
      allowInsecureHttp: false,
    );

    expect(configuration.uri, Uri.parse('https://wearcam.example.com'));
    expect(configuration.error, isNull);
  });

  test('rejects missing and malformed backend URLs', () {
    expect(
      BackendConfiguration.fromUrl('', allowInsecureHttp: false).error,
      contains('WEARCAM_BACKEND_URL'),
    );
    expect(
      BackendConfiguration.fromUrl('not-a-url', allowInsecureHttp: false).uri,
      isNull,
    );
  });

  test('allows HTTP only when explicitly enabled for a debug build', () {
    const localUrl = 'http://192.168.1.20:8787';

    expect(
      BackendConfiguration.fromUrl(localUrl, allowInsecureHttp: false).isValid,
      isFalse,
    );
    expect(
      BackendConfiguration.fromUrl(localUrl, allowInsecureHttp: true).isValid,
      isTrue,
    );
  });
}
