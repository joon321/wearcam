import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wearcam/ai/connection_diagnostics.dart';
import 'package:wearcam/ai/openai_realtime_provider.dart';
import 'package:wearcam/ai/realtime_connection.dart';
import 'package:wearcam/domain/ai_provider.dart';
import 'package:wearcam/domain/transcript_turn.dart';

void main() {
  test('credential request uses the saved runtime backend endpoint', () async {
    final requests = <Uri>[];
    final provider = _provider(
      MockClient((request) async {
        requests.add(request.url);
        if (requests.length == 1) {
          return http.Response('{"value":"temporary"}', 201);
        }
        return http.Response('answer', 200);
      }),
    );

    await provider.startSession();

    expect(
      requests.first,
      Uri.parse('https://saved.example.test/v1/realtime/client-secret'),
    );
    expect(
      requests,
      isNot(contains(Uri.parse('https://obsolete.example.test'))),
    );
  });

  test('unreachable backend reports its stage and disconnects', () async {
    final provider = _provider(
      MockClient(
        (_) async => throw const SocketException('secret host detail'),
      ),
    );
    final states = <AIConnectionState>[];
    provider.connectionStates.listen(states.add);

    await expectLater(
      provider.startSession(),
      throwsA(
        isA<ProviderConnectionException>().having(
          (error) => error.stage,
          'stage',
          ConnectionStage.requestTemporaryCredentials,
        ),
      ),
    );

    await Future<void>.delayed(Duration.zero);
    expect(states.last, AIConnectionState.disconnected);
  });

  test('credential request times out', () async {
    final provider = _provider(
      MockClient((_) => Completer<http.Response>().future),
      credentialTimeout: const Duration(milliseconds: 5),
    );

    await expectLater(
      provider.startSession(),
      throwsA(
        isA<ProviderConnectionException>()
            .having(
              (error) => error.stage,
              'stage',
              ConnectionStage.requestTemporaryCredentials,
            )
            .having((error) => error.message, 'message', contains('5 ms')),
      ),
    );
  });

  test(
    'non-2xx backend response includes safe status and request ID',
    () async {
      final provider = _provider(
        MockClient(
          (_) async => http.Response(
            '{"error":{"code":"denied","requestId":"backend-123"}}',
            503,
          ),
        ),
      );

      await expectLater(
        provider.startSession(),
        throwsA(
          isA<ProviderConnectionException>()
              .having((error) => error.httpStatus, 'status', 503)
              .having((error) => error.requestId, 'request ID', 'backend-123'),
        ),
      );
    },
  );

  test('malformed credential response is rejected', () async {
    final provider = _provider(
      MockClient((_) async => http.Response('{"not_value":"secret"}', 200)),
    );

    await expectLater(
      provider.startSession(),
      throwsA(
        isA<ProviderConnectionException>().having(
          (error) => error.message,
          'message',
          contains('malformed'),
        ),
      ),
    );
  });

  test('SDP exchange times out and returns to disconnected', () async {
    var requestCount = 0;
    final provider = _provider(
      MockClient((_) {
        requestCount += 1;
        if (requestCount == 1) {
          return Future.value(http.Response('{"value":"temporary"}', 201));
        }
        return Completer<http.Response>().future;
      }),
      sdpTimeout: const Duration(milliseconds: 5),
    );
    final states = <AIConnectionState>[];
    provider.connectionStates.listen(states.add);

    await expectLater(
      provider.startSession(),
      throwsA(
        isA<ProviderConnectionException>()
            .having(
              (error) => error.stage,
              'stage',
              ConnectionStage.exchangeSdp,
            )
            .having((error) => error.message, 'message', contains('5 ms')),
      ),
    );

    await Future<void>.delayed(Duration.zero);
    expect(states.last, AIConnectionState.disconnected);
  });

  test('overall timeout identifies wait_for_connected_state', () async {
    final connection = _FakeConnection(wait: Completer<void>().future);
    var requestCount = 0;
    final provider = OpenAIRealtimeProvider(
      backendBaseUri: Uri.parse('https://saved.example.test'),
      httpClient: MockClient((_) async {
        requestCount += 1;
        return requestCount == 1
            ? http.Response('{"value":"temporary"}', 201)
            : http.Response('answer', 200);
      }),
      connectionFactory: (_) => connection,
      overallTimeout: const Duration(milliseconds: 5),
    );

    await expectLater(
      provider.startSession(),
      throwsA(
        isA<ProviderConnectionException>()
            .having(
              (error) => error.stage,
              'stage',
              ConnectionStage.waitForConnectedState,
            )
            .having((error) => error.message, 'message', contains('5 ms')),
      ),
    );
  });

  test('diagnostics remove secret-like content', () {
    final diagnostics = ConnectionDiagnostics(backendHost: 'safe.example');
    diagnostics.record(
      ConnectionStage.exchangeSdp,
      'failed',
      message: 'Authorization: Bearer secret-token\nv=0 complete SDP',
      requestId: 'bad request id with spaces',
    );

    expect(diagnostics.copyText, contains('Sensitive error details removed.'));
    expect(diagnostics.copyText, isNot(contains('secret-token')));
    expect(diagnostics.copyText, isNot(contains('v=0')));
    expect(diagnostics.copyText, isNot(contains('bad request')));
  });

  test('streams, completes, and interrupts only the matching turn', () async {
    late _FakeConnection connection;
    var requestCount = 0;
    final provider = OpenAIRealtimeProvider(
      backendBaseUri: Uri.parse('https://saved.example.test'),
      httpClient: MockClient((_) async {
        requestCount += 1;
        return requestCount == 1
            ? http.Response('{"value":"temporary"}', 201)
            : http.Response('answer', 200);
      }),
      connectionFactory: (onMessage) =>
          connection = _FakeConnection(onMessage: onMessage),
    );
    final turns = <TranscriptTurn>[];
    provider.transcript.listen(turns.add);
    await provider.startSession();

    connection.receive({
      'type': 'conversation.item.input_audio_transcription.delta',
      'item_id': 'user-1',
      'delta': 'What is ',
    });
    connection.receive({
      'type': 'conversation.item.input_audio_transcription.delta',
      'item_id': 'user-1',
      'delta': 'this?',
    });
    connection.receive({
      'type': 'conversation.item.input_audio_transcription.completed',
      'item_id': 'user-1',
      'transcript': 'What is this?',
    });
    connection.receive({
      'type': 'response.output_audio_transcript.delta',
      'item_id': 'assistant-1',
      'delta': 'It is a screen.',
    });
    await Future<void>.delayed(Duration.zero);
    await provider.interrupt();
    connection.receive({
      'type': 'response.output_audio_transcript.delta',
      'item_id': 'assistant-2',
      'delta': 'You asked another question.',
    });
    await Future<void>.delayed(Duration.zero);

    final latestById = <String, TranscriptTurn>{
      for (final turn in turns) turn.id: turn,
    };
    expect(latestById['user-1']!.text, 'What is this?');
    expect(latestById['user-1']!.status, TranscriptStatus.completed);
    expect(latestById['assistant-1']!.text, 'It is a screen.');
    expect(latestById['assistant-1']!.status, TranscriptStatus.interrupted);
    expect(latestById['assistant-2']!.text, 'You asked another question.');
  });

  test('realtime cleanup continues after an early operation fails', () async {
    final completed = <String>[];

    await expectLater(
      runRealtimeCleanup([
        () async {
          completed.add('track.stop');
          throw StateError('track stop failed');
        },
        () async => completed.add('stream.dispose'),
        () async => completed.add('events.close'),
        () async => completed.add('peer.close'),
      ]),
      throwsStateError,
    );

    expect(completed, [
      'track.stop',
      'stream.dispose',
      'events.close',
      'peer.close',
    ]);
  });

  test(
    'cleanup failure still returns provider state to disconnected',
    () async {
      final connection = _FakeConnection(
        stop: () async => throw StateError('cleanup failed'),
      );
      var requestCount = 0;
      final provider = OpenAIRealtimeProvider(
        backendBaseUri: Uri.parse('https://saved.example.test'),
        httpClient: MockClient((_) async {
          requestCount += 1;
          return requestCount == 1
              ? http.Response('{"value":"temporary"}', 201)
              : http.Response('answer', 200);
        }),
        connectionFactory: (_) => connection,
      );
      final states = <AIConnectionState>[];
      provider.connectionStates.listen(states.add);
      await provider.startSession();

      await expectLater(provider.stopSession(), throwsStateError);
      await Future<void>.delayed(Duration.zero);

      expect(states.last, AIConnectionState.disconnected);
    },
  );
}

OpenAIRealtimeProvider _provider(
  http.Client client, {
  Duration credentialTimeout = const Duration(seconds: 10),
  Duration sdpTimeout = const Duration(seconds: 15),
}) => OpenAIRealtimeProvider(
  backendBaseUri: Uri.parse('https://saved.example.test'),
  httpClient: client,
  connectionFactory: (_) => _FakeConnection(),
  credentialTimeout: credentialTimeout,
  sdpTimeout: sdpTimeout,
);

final class _FakeConnection implements RealtimeConnection {
  _FakeConnection({
    Future<void>? wait,
    Future<void> Function()? stop,
    this.onMessage,
  }) : wait = wait ?? Future.value(),
       _stop = stop;
  final Future<void> wait;
  final Future<void> Function()? _stop;
  final void Function(String)? onMessage;

  void receive(Map<String, Object?> event) {
    onMessage?.call(jsonEncode(event));
  }

  @override
  Future<void> acquireMicrophone({required bool muted}) async {}
  @override
  Future<void> applyRemoteDescription(String answerSdp) async {}
  @override
  Future<void> createPeerConnection() async {}
  @override
  Future<String> createLocalOffer() async => 'offer';
  @override
  void send(Map<String, Object?> event) {}
  @override
  Future<void> setMicrophoneMuted(bool muted) async {}
  @override
  Future<void> stop() async {
    await _stop?.call();
  }

  @override
  Future<void> waitUntilConnected() => wait;
}
