import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wearcam/config/backend_url_store.dart';
import 'package:wearcam/ui/wearcam_bootstrap.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(
    const WearCamBootstrap(
      store: SharedPreferencesBackendUrlStore(),
      fallbackUrl: String.fromEnvironment('WEARCAM_BACKEND_URL'),
    ),
  );
}
