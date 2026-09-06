import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wearcam/conversation/conversation_controller.dart';
import 'package:wearcam/domain/ai_provider.dart';
import 'package:wearcam/domain/camera_source.dart';
import 'package:wearcam/domain/prepared_frame.dart';

void main() {
  test(
    'get_current_view captures a genuinely new frame and sends exact bytes',
    () async {
      final camera = FakeCamera();
      final provider = FakeProvider();
      final controller = ConversationController(
        camera: camera,
        provider: provider,
      );
      await controller.start();

      provider.issueToolCall('call-1');
      await provider.completed.first;
      expect(camera.captureCount, 1);
      expect(provider.images, hasLength(1));
      expect(
        identical(controller.lastTransmittedFrame, provider.images.single),
        isTrue,
      );

      provider.issueToolCall('call-2');
      await provider.completed.where((id) => id == 'call-2').first;
      expect(camera.captureCount, 2);
      expect(provider.images, hasLength(2));
      expect(
        provider.images[1].capturedAt.isAfter(
          provider.images[0].capturedAt,
        ),
        isTrue,
      );
      controller.dispose();
    },
  );

  test('vision mode off prevents image upload', () async {
    final camera = FakeCamera();
    final provider = FakeProvider();
    final controller = ConversationController(
      camera: camera,
      provider: provider,
    );
    await controller.start();
    await controller.stopLooking();
    provider.issueToolCall('disabled');
    await provider.completed.where((id) => id == 'disabled').first;
    expect(camera.captureCount, 0);
    expect(provider.images, isEmpty);
    controller.dispose();
  });

  test('Stop looking during capture prevents pending transmission', () async {
    final gate = Completer<void>();
    final camera = FakeCamera(captureGate: gate.future);
    final provider = FakeProvider();
    final controller = ConversationController(
      camera: camera,
      provider: provider,
    );
    await controller.start();
    provider.issueToolCall('pending');
    await Future<void>.delayed(Duration.zero);
    await controller.stopLooking();
    gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(provider.images, isEmpty);
    expect(controller.lastTransmittedFrame, isNull);
    controller.dispose();
  });
}

final class FakeCamera implements CameraSource {
  FakeCamera({this.captureGate});
  final Future<void>? captureGate;
  final _status = StreamController<CameraStatus>.broadcast();
  int captureCount = 0;
  @override
  Stream<CameraStatus> get status => _status.stream;
  @override
  Future<void> connect() async => _status.add(CameraStatus.connected);
  @override
  Future<void> disconnect() async => _status.add(CameraStatus.disconnected);
  @override
  Future<CameraFrame> capture() async {
    await captureGate;
    captureCount += 1;
    final image = img.Image(width: 20, height: 20)
      ..setPixelRgb(10, 10, captureCount * 20, 0, 0);
    return CameraFrame(
      jpegBytes: Uint8List.fromList(img.encodeJpg(image)),
      capturedAt: DateTime.now()
          .toUtc()
          .add(Duration(milliseconds: captureCount)),
      width: 20,
      height: 20,
      sourceId: 'fake-$captureCount',
      orientation: FrameOrientation.portraitUp,
      sharpnessScore: 1,
    );
  }
}

final class FakeProvider implements AIProvider {
  final _states = StreamController<AIConnectionState>.broadcast();
  final _transcript = StreamController<String>.broadcast();
  final _tools = StreamController<ToolCall>.broadcast();
  final _completed = StreamController<String>.broadcast();
  final images = <PreparedFrame>[];
  Stream<String> get completed => _completed.stream;
  void issueToolCall(String id) => _tools.add(
    ToolCall(name: 'get_current_view', callId: id, arguments: const {}),
  );
  @override
  Stream<AIConnectionState> get connectionStates => _states.stream;
  @override
  Stream<String> get transcript => _transcript.stream;
  @override
  Stream<ToolCall> get toolCalls => _tools.stream;
  @override
  Future<void> startSession() async => _states.add(AIConnectionState.connected);
  @override
  Future<void> stopSession() async =>
      _states.add(AIConnectionState.disconnected);
  @override
  Future<void> sendImage(PreparedFrame frame, String context) async =>
      images.add(frame);
  @override
  Future<void> completeToolCall(
    String callId,
    Map<String, Object?> output,
  ) async => _completed.add(callId);
  @override
  Future<void> interrupt() async {}
  @override
  Future<void> sendText(String text) async {}
  @override
  Future<void> setMicrophoneMuted(bool muted) async {}
}
