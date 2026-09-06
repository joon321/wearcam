import 'package:flutter/material.dart';
import 'package:wearcam/ai/openai_realtime_provider.dart';
import 'package:wearcam/camera/phone_camera_source.dart';
import 'package:wearcam/conversation/conversation_controller.dart';
import 'package:wearcam/ui/wearcam_app.dart';

void main() {
  const backendUrl = String.fromEnvironment(
    'WEARCAM_BACKEND_URL',
    defaultValue: 'http://127.0.0.1:8787',
  );
  final camera = PhoneCameraSource();
  runApp(
    WearCamApp(
      camera: camera,
      controller: ConversationController(
        camera: camera,
        provider: OpenAIRealtimeProvider(backendBaseUri: Uri.parse(backendUrl)),
      ),
    ),
  );
}
