import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wearcam/ai/connection_diagnostics.dart';
import 'package:wearcam/camera/phone_camera_source.dart';
import 'package:wearcam/conversation/conversation_controller.dart';
import 'package:wearcam/domain/ai_provider.dart';
import 'package:wearcam/domain/camera_source.dart';
import 'package:wearcam/domain/prepared_frame.dart';
import 'package:wearcam/domain/transcript_turn.dart';
import 'package:wearcam/domain/vision_mode.dart';
import 'package:wearcam/ui/wearcam_app.dart';

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
      controller.startVisualSession();

      provider.issueToolCall('call-1');
      await provider.completed.first;
      await controller.activeToolCallCompleted;
      expect(camera.captureCount, 1);
      expect(provider.images, hasLength(1));
      expect(
        identical(controller.lastTransmittedFrame, provider.images.single),
        isTrue,
      );

      await Future<void>.delayed(const Duration(seconds: 2));
      provider.issueToolCall('call-2');
      await provider.completed.where((id) => id == 'call-2').first;
      await controller.activeToolCallCompleted;
      expect(camera.captureCount, 2);
      expect(provider.images, hasLength(2));
      expect(
        provider.images[1].capturedAt.isAfter(provider.images[0].capturedAt),
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
    provider.issueToolCall('disabled');
    await provider.completed.where((id) => id == 'disabled').first;
    expect(camera.captureCount, 0);
    expect(provider.images, isEmpty);
    expect(provider.outputs['disabled'], {
      'ok': false,
      'error': {
        'code': 'vision_permission_required',
        'message':
            'Explicit user authorization is required before capturing a view.',
        'allowedActions': ['request_one_look', 'request_visual_session'],
      },
    });
    controller.dispose();
  });

  test(
    'direct visual transcript authorizes exactly one selected-source capture',
    () async {
      final camera = FakeCamera();
      final provider = FakeProvider();
      final controller = ConversationController(
        camera: camera,
        provider: provider,
      );
      await controller.start();
      provider.emitTranscript(
        _completedTurn('user-look', TranscriptRole.user, 'Can you see this?'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.visionModes.mode, VisionMode.oneLook);

      provider.issueToolCall('authorized');
      await provider.completed.where((id) => id == 'authorized').first;
      provider.issueToolCall('not-reusable');
      await provider.completed.where((id) => id == 'not-reusable').first;

      expect(camera.captureCount, 1);
      expect(provider.images, hasLength(1));
      expect(controller.visionModes.mode, VisionMode.off);
      controller.dispose();
    },
  );

  test(
    'assistant recommendations do not authorize and contextual approval does',
    () async {
      final provider = FakeProvider();
      final controller = ConversationController(
        camera: FakeCamera(),
        provider: provider,
      );
      provider.emitTranscript(
        _completedTurn(
          'assistant-request',
          TranscriptRole.assistant,
          'I need one clear view. Point the phone at the valve and say ready.',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.visionModes.mode, VisionMode.off);
      expect(controller.visionModes.pendingScope, VisualRecommendation.oneLook);

      provider.emitTranscript(
        _completedTurn('user-ready', TranscriptRole.user, 'Ready.'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.visionModes.mode, VisionMode.oneLook);
      // Replayed transcript IDs cannot grant fresh authorization.
      controller.visionModes.revoke(VisionEndReason.completed);
      provider.emitTranscript(
        _completedTurn('user-ready', TranscriptRole.user, 'Ready.'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.visionModes.mode, VisionMode.off);
      controller.dispose();
    },
  );

  test(
    'isolated approval and assistant speech cannot authorize vision',
    () async {
      final provider = FakeProvider();
      final controller = ConversationController(
        camera: FakeCamera(),
        provider: provider,
      );
      provider.emitTranscript(
        _completedTurn('assistant-yes', TranscriptRole.assistant, 'Yes.'),
      );
      provider.emitTranscript(
        _completedTurn('user-yes', TranscriptRole.user, 'Okay.'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.visionModes.mode, VisionMode.off);
      controller.dispose();
    },
  );

  test(
    'direct ongoing-observation request starts a user-authorized session',
    () async {
      final provider = FakeProvider();
      final controller = ConversationController(
        camera: FakeCamera(),
        provider: provider,
      );
      provider.emitTranscript(
        _completedTurn(
          'user-session',
          TranscriptRole.user,
          'Keep checking my progress while I do this.',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.visionModes.mode, VisionMode.visualSession);
      controller.dispose();
    },
  );

  test('disconnects camera when provider startup fails', () async {
    final camera = FakeCamera();
    final provider = FakeProvider(failStart: true);
    final controller = ConversationController(
      camera: camera,
      provider: provider,
    );

    await controller.start();

    expect(camera.disconnectCount, 1);
    expect(controller.visionModes.mode, VisionMode.off);
    expect(controller.connectionState, AIConnectionState.disconnected);
    expect(controller.error, contains('connection failed'));
    controller.dispose();
  });

  test('preserves generic startup failure when camera cleanup fails', () async {
    final controller = ConversationController(
      camera: FakeCamera(failDisconnect: true),
      provider: FakeProvider(failStart: true),
    );
    var notifications = 0;
    controller.addListener(() => notifications += 1);

    await controller.start();

    expect(controller.connectionState, AIConnectionState.disconnected);
    expect(controller.error, 'connection failed (StateError)');
    expect(controller.isStarting, isFalse);
    expect(notifications, greaterThan(0));
    controller.dispose();
  });

  test('preserves provider failure when camera cleanup also fails', () async {
    final diagnostics = ConnectionDiagnostics(backendHost: 'safe.example');
    final controller = ConversationController(
      camera: FakeCamera(failDisconnect: true),
      provider: FakeProvider(failWithProviderException: true),
      diagnostics: diagnostics,
    );

    await controller.start();

    expect(controller.error, contains('request_temporary_credentials'));
    expect(controller.connectionState, AIConnectionState.disconnected);
    expect(diagnostics.entries.single.status, 'camera_cleanup_failed');
    controller.dispose();
  });

  test('concurrent starts share one camera and provider startup', () async {
    final connectGate = Completer<void>();
    final camera = FakeCamera(connectGate: connectGate.future);
    final provider = FakeProvider();
    final controller = ConversationController(
      camera: camera,
      provider: provider,
    );

    final first = controller.start();
    final second = controller.start();

    expect(identical(first, second), isTrue);
    expect(controller.isStarting, isTrue);
    expect(camera.connectCount, 1);
    expect(provider.startCount, 0);
    connectGate.complete();
    await Future.wait([first, second]);

    expect(provider.startCount, 1);
    expect(controller.isStarting, isFalse);
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
    controller.authorizeOneLook();
    provider.issueToolCall('pending');
    await camera.captureStarted.future;
    await controller.stopLooking();
    gate.complete();
    await controller.activeToolCallCompleted;
    expect(provider.images, isEmpty);
    expect(controller.lastTransmittedFrame, isNull);
    expect(provider.outputs['pending'], {
      'ok': false,
      'reason': 'visual transmission cancelled',
    });
    controller.dispose();
  });

  test('disposal during capture prevents notifications and upload', () async {
    final gate = Completer<void>();
    final camera = FakeCamera(captureGate: gate.future);
    final provider = FakeProvider();
    final controller = ConversationController(
      camera: camera,
      provider: provider,
    );
    await controller.start();
    controller.authorizeOneLook();
    var notifications = 0;
    controller.addListener(() => notifications += 1);

    provider.issueToolCall('disposed');
    await camera.captureStarted.future;
    final completed = controller.activeToolCallCompleted;
    final notificationsBeforeDispose = notifications;
    controller.dispose();
    gate.complete();
    await completed;

    expect(provider.images, isEmpty);
    expect(provider.outputs['disposed'], {
      'ok': false,
      'reason': 'visual transmission cancelled',
    });
    expect(notifications, notificationsBeforeDispose);
  });

  test('concurrent stop requests tear down provider and camera once', () async {
    final stopGate = Completer<void>();
    final camera = FakeCamera();
    final provider = FakeProvider(stopGate: stopGate.future);
    final controller = ConversationController(
      camera: camera,
      provider: provider,
    );
    await controller.start();

    final firstStop = controller.stopEverything();
    final secondStop = controller.stopEverything();
    expect(provider.stopCount, 1);
    stopGate.complete();
    await Future.wait([firstStop, secondStop]);

    expect(provider.stopCount, 1);
    expect(camera.disconnectCount, 1);
    expect(controller.visionModes.mode, VisionMode.off);
    controller.dispose();
  });

  test(
    'keeps streamed speaker and response turns separate and ordered',
    () async {
      final provider = FakeProvider();
      final controller = ConversationController(
        camera: FakeCamera(),
        provider: provider,
      );
      final created = DateTime.utc(2026);

      provider.emitTranscript(
        TranscriptTurn(
          id: 'user-1',
          role: TranscriptRole.user,
          text: 'screen.',
          status: TranscriptStatus.completed,
          createdAt: created,
        ),
      );
      provider.emitTranscript(
        TranscriptTurn(
          id: 'assistant-1',
          role: TranscriptRole.assistant,
          text: 'You can continue.',
          status: TranscriptStatus.streaming,
          createdAt: created.add(const Duration(seconds: 1)),
        ),
      );
      provider.emitTranscript(
        TranscriptTurn(
          id: 'assistant-1',
          role: TranscriptRole.assistant,
          text: 'You can continue safely.',
          status: TranscriptStatus.completed,
          createdAt: created.add(const Duration(seconds: 1)),
        ),
      );
      provider.emitTranscript(
        TranscriptTurn(
          id: 'assistant-2',
          role: TranscriptRole.assistant,
          text: 'No worries.',
          status: TranscriptStatus.completed,
          createdAt: created.add(const Duration(seconds: 2)),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.transcriptTurns.map((turn) => turn.id), [
        'user-1',
        'assistant-1',
        'assistant-2',
      ]);
      expect(controller.transcriptTurns[1].text, 'You can continue safely.');
      expect(controller.transcriptTurns[1].status, TranscriptStatus.completed);
      expect(controller.transcriptTurns[2].text, 'No worries.');
      expect(
        controller.transcriptTurns.map((turn) => turn.text).join('|'),
        'screen.|You can continue safely.|No worries.',
      );
      controller.dispose();
    },
  );

  test(
    'retains interrupted assistant text and clears turns on new session',
    () async {
      final provider = FakeProvider();
      final controller = ConversationController(
        camera: FakeCamera(),
        provider: provider,
      );
      final created = DateTime.utc(2026);
      provider.emitTranscript(
        TranscriptTurn(
          id: 'assistant-1',
          role: TranscriptRole.assistant,
          text: 'The part already spoken',
          status: TranscriptStatus.interrupted,
          createdAt: created,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.transcriptTurns.single.text, 'The part already spoken');
      expect(
        controller.transcriptTurns.single.status,
        TranscriptStatus.interrupted,
      );

      await controller.start();
      expect(controller.transcriptTurns, isEmpty);
      controller.dispose();
    },
  );

  test('bounds transcript history to the newest 100 turns', () async {
    final provider = FakeProvider();
    final controller = ConversationController(
      camera: FakeCamera(),
      provider: provider,
    );
    for (var index = 0; index < 101; index += 1) {
      provider.emitTranscript(
        TranscriptTurn(
          id: 'turn-$index',
          role: TranscriptRole.assistant,
          text: '$index',
          status: TranscriptStatus.completed,
          createdAt: DateTime.utc(2026).add(Duration(seconds: index)),
        ),
      );
    }
    await Future<void>.delayed(Duration.zero);

    expect(controller.transcriptTurns, hasLength(100));
    expect(controller.transcriptTurns.first.id, 'turn-1');
    expect(controller.transcriptTurns.last.id, 'turn-100');
    controller.dispose();
  });

  testWidgets('renders transcript turns chronologically with speaker labels', (
    tester,
  ) async {
    final provider = FakeProvider();
    final diagnostics = ConnectionDiagnostics(backendHost: 'safe.example');
    final controller = ConversationController(
      camera: FakeCamera(),
      provider: provider,
      diagnostics: diagnostics,
    );
    await tester.pumpWidget(
      WearCamApp(
        camera: PhoneCameraSource(),
        controller: controller,
        diagnostics: diagnostics,
        onChangeBackend: () async {},
      ),
    );
    await tester.tap(find.text('Conversation'));
    await tester.pumpAndSettle();
    final created = DateTime.utc(2026);
    provider.emitTranscript(
      TranscriptTurn(
        id: 'assistant-2',
        role: TranscriptRole.assistant,
        text: 'Third',
        status: TranscriptStatus.streaming,
        createdAt: created.add(const Duration(seconds: 2)),
      ),
    );
    provider.emitTranscript(
      TranscriptTurn(
        id: 'user-1',
        role: TranscriptRole.user,
        text: 'First',
        status: TranscriptStatus.completed,
        createdAt: created,
      ),
    );
    provider.emitTranscript(
      TranscriptTurn(
        id: 'assistant-1',
        role: TranscriptRole.assistant,
        text: 'Second',
        status: TranscriptStatus.completed,
        createdAt: created.add(const Duration(seconds: 1)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('You'), findsOneWidget);
    expect(find.text('WearCam'), findsNWidgets(2));
    final first = find.byKey(const ValueKey('transcript-turn-user-1'));
    final second = find.byKey(const ValueKey('transcript-turn-assistant-1'));
    final third = find.byKey(const ValueKey('transcript-turn-assistant-2'));
    expect(tester.getTopLeft(first).dy, lessThan(tester.getTopLeft(second).dy));
    expect(tester.getTopLeft(second).dy, lessThan(tester.getTopLeft(third).dy));
    expect(find.byKey(const Key('streaming-turn-status')), findsOneWidget);
    controller.dispose();
  });

  testWidgets('disables Retry while a retry is pending', (tester) async {
    final provider = FakeProvider(failStart: true);
    final diagnostics = ConnectionDiagnostics(backendHost: 'safe.example');
    final controller = ConversationController(
      camera: FakeCamera(),
      provider: provider,
      diagnostics: diagnostics,
    );
    await controller.start();
    await tester.pumpWidget(
      WearCamApp(
        camera: PhoneCameraSource(),
        controller: controller,
        diagnostics: diagnostics,
        onChangeBackend: () async {},
      ),
    );
    final retryGate = Completer<void>();
    provider.failStart = false;
    provider.startGate = retryGate.future;

    await tester.tap(find.byKey(const Key('retry-connection')));
    await tester.pump();

    final retry = tester.widget<FilledButton>(
      find.byKey(const Key('retry-connection')),
    );
    expect(retry.onPressed, isNull);
    retryGate.complete();
    await tester.pumpAndSettle();
    controller.dispose();
  });
}

TranscriptTurn _completedTurn(String id, TranscriptRole role, String text) =>
    TranscriptTurn(
      id: id,
      role: role,
      text: text,
      status: TranscriptStatus.completed,
      createdAt: DateTime.utc(2026),
    );

final class FakeCamera implements CameraSource {
  FakeCamera({this.captureGate, this.connectGate, this.failDisconnect = false});
  final Future<void>? captureGate;
  final Future<void>? connectGate;
  final bool failDisconnect;
  final _status = StreamController<CameraStatus>.broadcast();
  CameraStatus _connectionState = CameraStatus.disconnected;
  @override
  String get id => 'fake-camera';
  @override
  String get displayName => 'Fake camera';
  @override
  CameraCapabilities get capabilities => const CameraCapabilities(
    supportsPreview: true,
    supportsLensSwitching: false,
    isHeadMounted: false,
    supportsContinuousPreview: true,
  );
  @override
  CameraStatus get connectionState => _connectionState;
  int captureCount = 0;
  int connectCount = 0;
  int disconnectCount = 0;
  final captureStarted = Completer<void>();
  @override
  Stream<CameraStatus> get status => _status.stream;
  @override
  Future<void> connect() async {
    connectCount += 1;
    await connectGate;
    _connectionState = CameraStatus.connected;
    _status.add(_connectionState);
  }

  @override
  Future<void> disconnect() async {
    disconnectCount += 1;
    if (failDisconnect) throw StateError('camera disconnect failed');
    _connectionState = CameraStatus.disconnected;
    _status.add(_connectionState);
  }

  @override
  Future<CameraFrame> capture() async {
    if (!captureStarted.isCompleted) captureStarted.complete();
    await captureGate;
    captureCount += 1;
    final image = img.Image(width: 20, height: 20)
      ..setPixelRgb(10, 10, captureCount * 20, 0, 0);
    return CameraFrame(
      jpegBytes: Uint8List.fromList(img.encodeJpg(image)),
      capturedAt: DateTime.now().toUtc().add(
        Duration(milliseconds: captureCount),
      ),
      width: 20,
      height: 20,
      sourceId: 'fake-$captureCount',
      orientation: FrameOrientation.portraitUp,
      sharpnessScore: 1,
    );
  }
}

final class FakeProvider implements AIProvider {
  FakeProvider({
    this.failStart = false,
    this.failWithProviderException = false,
    this.stopGate,
  });

  bool failStart;
  final bool failWithProviderException;
  final Future<void>? stopGate;
  Future<void>? startGate;
  final _states = StreamController<AIConnectionState>.broadcast();
  final _transcript = StreamController<TranscriptTurn>.broadcast();
  final _tools = StreamController<ToolCall>.broadcast();
  final _completed = StreamController<String>.broadcast();
  final images = <PreparedFrame>[];
  final outputs = <String, Map<String, Object?>>{};
  int stopCount = 0;
  int startCount = 0;
  Stream<String> get completed => _completed.stream;
  void issueToolCall(String id) => _tools.add(
    ToolCall(name: 'get_current_view', callId: id, arguments: const {}),
  );
  @override
  Stream<AIConnectionState> get connectionStates => _states.stream;
  @override
  Stream<TranscriptTurn> get transcript => _transcript.stream;
  void emitTranscript(TranscriptTurn turn) => _transcript.add(turn);
  @override
  Stream<ToolCall> get toolCalls => _tools.stream;
  @override
  Future<void> startSession() async {
    startCount += 1;
    await startGate;
    if (failWithProviderException) {
      throw const ProviderConnectionException(
        stage: ConnectionStage.requestTemporaryCredentials,
        message: 'Backend rejected the credential request.',
      );
    }
    if (failStart) throw StateError('provider startup failed');
    _states.add(AIConnectionState.connected);
  }

  @override
  Future<void> stopSession() async {
    stopCount += 1;
    await stopGate;
    _states.add(AIConnectionState.disconnected);
  }

  @override
  Future<void> sendImage(PreparedFrame frame, String context) async =>
      images.add(frame);
  @override
  Future<void> completeToolCall(
    String callId,
    Map<String, Object?> output,
  ) async {
    outputs[callId] = output;
    _completed.add(callId);
  }

  @override
  Future<void> interrupt() async {}
  @override
  Future<void> sendText(String text) async {}
  @override
  Future<void> setMicrophoneMuted(bool muted) async {}
}
