import 'package:shared_preferences/shared_preferences.dart';

abstract interface class BackendUrlStore {
  Future<String?> read();

  Future<void> write(String url);
}

final class SharedPreferencesBackendUrlStore implements BackendUrlStore {
  const SharedPreferencesBackendUrlStore();

  static const _key = 'wearcam.backend_base_url';

  @override
  Future<String?> read() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_key);
  }

  @override
  Future<void> write(String url) async {
    final preferences = await SharedPreferences.getInstance();
    final stored = await preferences.setString(_key, url);
    if (!stored) throw StateError('Could not save the backend URL.');
  }
}
