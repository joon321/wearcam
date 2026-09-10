import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:wearcam/ai/connection_diagnostics.dart';
import 'package:wearcam/ai/openai_realtime_protocol.dart';
import 'package:wearcam/ai/realtime_connection.dart';
import 'package:wearcam/domain/ai_provider.dart';
import 'package:wearcam/domain/prepared_frame.dart';
import 'package:wearcam/domain/transcript_turn.dart';

final class OpenAIRealtimeProvider implements AIProvider {
  OpenAIRealtimeProvider({
    required this.backendBaseUri,
    http.Client? httpClient,
    ConnectionDiagnostics? diagnostics,
    RealtimeConnection Function(void Function(String))? connectionFactory,
    this.credentialTimeout = const Duration(seconds: 10),
    this.sdpTimeout = const Duration(seconds: 15),
    this.overallTimeout = const Duration(seconds: 30),
  }) : _http = httpClient ?? http.Client(),
       diagnostics =
           diagnostics ??
           ConnectionDiagnostics(backendHost: backendBaseUri.host),
       _connectionFactory =
           connectionFactory ??
           ((onMessage) => WebRtcRealtimeConnection(onMessage: onMessage));

  final Uri backendBaseUri;
  final http.Client _http;
  final ConnectionDiagnostics diagnostics;
  final RealtimeConnection Function(void Function(String)) _connectionFactory;
  final Duration credentialTimeout;
  final Duration sdpTimeout;
  final Duration overallTimeout;
  final _states = StreamController<AIConnectionState>.broadcast();
  final _transcript = StreamController<TranscriptTurn>.broadcast();
  final _toolCalls = StreamController<ToolCall>.broadcast();
  RealtimeConnection? _connection;
  bool _microphoneMuted = false;
  Future<void>? _stopInProgress;
  final Map<String, TranscriptTurn> _transcriptTurns = {};
  static const _maximumTranscriptTurns = 100;
  ConnectionStage _stage = ConnectionStage.readBackendConfiguration;
  static const _protocol = OpenAIRealtimeProtocol();

  @override
  Stream<AIConnectionState> get connectionStates => _states.stream;
  @override
  Stream<TranscriptTurn> get transcript => _transcript.stream;
  @override
  Stream<ToolCall> get toolCalls => _toolCalls.stream;

  @override
  Future<void> startSession() async {
    _transcriptTurns.clear();
    _states.add(AIConnectionState.connecting);
    try {
      await _start().timeout(
        overallTimeout,
        onTimeout: () => throw ProviderConnectionException(
          stage: _stage,
          message:
              'Overall connection timed out after '
              '${overallTimeout.inMilliseconds} ms.',
        ),
      );
      _states.add(AIConnectionState.connected);
    } catch (caught) {
      final failure = caught is ProviderConnectionException
          ? caught
          : ProviderConnectionException(
              stage: _stage,
              message: _safeStageMessage(_stage, caught),
            );
      diagnostics.record(
        failure.stage,
        'failed',
        message: failure.message,
        httpStatus: failure.httpStatus,
        requestId: failure.requestId,
      );
      _states.add(AIConnectionState.disconnected);
      unawaited(
        stopSession().catchError((Object cleanupError) {
          diagnostics.record(
            failure.stage,
            'cleanup_failed',
            message: _safeStageMessage(failure.stage, cleanupError),
          );
        }),
      );
      throw failure;
    }
  }

  Future<void> _start() async {
    final temporaryCredential = await _credentials();
    final connection = _connectionFactory(_handleEvent);
    _connection = connection;
    await _runStage(
      ConnectionStage.acquireMicrophone,
      () => connection.acquireMicrophone(muted: _microphoneMuted),
    );
    await _runStage(
      ConnectionStage.createPeerConnection,
      connection.createPeerConnection,
    );
    final offer = await _runStage(
      ConnectionStage.createLocalOffer,
      connection.createLocalOffer,
    );
    final answer = await _exchangeSdp(offer, temporaryCredential);
    await _runStage(
      ConnectionStage.applyRemoteDescription,
      () => connection.applyRemoteDescription(answer),
    );
    await _runStage(
      ConnectionStage.waitForConnectedState,
      connection.waitUntilConnected,
    );
  }

  Future<String> _credentials() async {
    _stage = ConnectionStage.requestTemporaryCredentials;
    diagnostics.record(_stage, 'started');
    late final http.Response response;
    try {
      response = await _http
          .post(
            backendBaseUri.resolve('/v1/realtime/client-secret'),
            headers: const {'content-type': 'application/json'},
          )
          .timeout(credentialTimeout);
    } on TimeoutException {
      throw ProviderConnectionException(
        stage: _stage,
        message:
            'Backend credential request timed out after '
            '${credentialTimeout.inMilliseconds} ms.',
      );
    }
    final responseData = _jsonObject(response.body);
    final requestId = _requestId(response, responseData);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ProviderConnectionException(
        stage: _stage,
        message: 'Backend rejected the credential request.',
        httpStatus: response.statusCode,
        requestId: requestId,
      );
    }
    final value = responseData?['value'];
    if (value is! String || value.isEmpty) {
      throw ProviderConnectionException(
        stage: _stage,
        message: 'Backend returned a malformed credential response.',
        httpStatus: response.statusCode,
        requestId: requestId,
      );
    }
    diagnostics.record(_stage, 'succeeded', requestId: requestId);
    return value;
  }

  Future<String> _exchangeSdp(String offer, String credential) async {
    _stage = ConnectionStage.exchangeSdp;
    diagnostics.record(_stage, 'started');
    late final http.Response response;
    try {
      response = await _http
          .post(
            Uri.parse('https://api.openai.com/v1/realtime/calls'),
            headers: {
              'authorization': 'Bearer $credential',
              'content-type': 'application/sdp',
            },
            body: offer,
          )
          .timeout(sdpTimeout);
    } on TimeoutException {
      throw ProviderConnectionException(
        stage: _stage,
        message:
            'OpenAI SDP exchange timed out after '
            '${sdpTimeout.inMilliseconds} ms.',
      );
    }
    final requestId = sanitizeRequestId(response.headers['x-request-id']);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ProviderConnectionException(
        stage: _stage,
        message: 'OpenAI rejected the SDP exchange.',
        httpStatus: response.statusCode,
        requestId: requestId,
      );
    }
    if (response.body.trim().isEmpty) {
      throw ProviderConnectionException(
        stage: _stage,
        message: 'OpenAI returned an empty SDP answer.',
        httpStatus: response.statusCode,
        requestId: requestId,
      );
    }
    diagnostics.record(_stage, 'succeeded', requestId: requestId);
    return response.body;
  }

  Future<T> _runStage<T>(
    ConnectionStage stage,
    Future<T> Function() action,
  ) async {
    _stage = stage;
    diagnostics.record(stage, 'started');
    try {
      final result = await action();
      diagnostics.record(stage, 'succeeded');
      return result;
    } catch (caught) {
      throw ProviderConnectionException(
        stage: stage,
        message: _safeStageMessage(stage, caught),
      );
    }
  }

  Map<String, dynamic>? _jsonObject(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String? _requestId(http.Response response, Map<String, dynamic>? data) {
    final error = data?['error'];
    final bodyId = error is Map<String, dynamic> ? error['requestId'] : null;
    return sanitizeRequestId(
      response.headers['x-request-id'] ?? (bodyId is String ? bodyId : null),
    );
  }

  String _safeStageMessage(ConnectionStage stage, Object caught) =>
      '${stage.wireName} failed (${caught.runtimeType}).';

  void _handleEvent(String wire) {
    final event = _protocol.decodeEvent(wire);
    if (event == null) return;
    for (final transcriptEvent in _protocol.transcriptEvents(event)) {
      _handleTranscriptEvent(transcriptEvent);
    }
    final toolCall = _protocol.toolCall(event);
    if (toolCall != null) _toolCalls.add(toolCall);
  }

  void _handleTranscriptEvent(RealtimeTranscriptEvent event) {
    final existing = _transcriptTurns[event.turnId];
    if (existing != null && existing.role != event.role) return;
    if (existing == null &&
        _transcriptTurns.length >= _maximumTranscriptTurns) {
      _transcriptTurns.remove(_transcriptTurns.keys.first);
    }
    final current =
        existing ??
        TranscriptTurn(
          id: event.turnId,
          role: event.role,
          text: '',
          status: TranscriptStatus.streaming,
          createdAt: DateTime.now().toUtc(),
        );
    if (current.status != TranscriptStatus.streaming &&
        event.status == TranscriptStatus.streaming) {
      return;
    }
    final updated = current.copyWith(
      text: event.completedText ?? '${current.text}${event.delta ?? ''}',
      status: event.status,
    );
    _transcriptTurns[event.turnId] = updated;
    _transcript.add(updated);
  }

  void _interruptActiveAssistantTurns() {
    for (final turn in _transcriptTurns.values.toList(growable: false)) {
      if (turn.role == TranscriptRole.assistant &&
          turn.status == TranscriptStatus.streaming) {
        final interrupted = turn.copyWith(status: TranscriptStatus.interrupted);
        _transcriptTurns[turn.id] = interrupted;
        _transcript.add(interrupted);
      }
    }
  }

  void _send(Map<String, Object?> event) {
    final connection = _connection;
    if (connection == null) {
      throw StateError('Realtime data channel is not open');
    }
    connection.send(event);
  }

  @override
  Future<void> sendText(String text) async {
    _send(_protocol.textMessage(text));
    _send(OpenAIRealtimeProtocol.responseCreate);
  }

  @override
  Future<void> sendImage(PreparedFrame frame, String context) async {
    _send(_protocol.imageMessage(frame, context));
  }

  @override
  Future<void> completeToolCall(
    String callId,
    Map<String, Object?> output,
  ) async {
    _send(_protocol.functionOutput(callId, output));
    _send(OpenAIRealtimeProtocol.responseCreate);
  }

  @override
  Future<void> setMicrophoneMuted(bool muted) async {
    _microphoneMuted = muted;
    await _connection?.setMicrophoneMuted(muted);
  }

  @override
  Future<void> interrupt() async {
    _interruptActiveAssistantTurns();
    _send(OpenAIRealtimeProtocol.responseCancel);
    // WebRTC can already have buffered audio after cancellation. Clearing the
    // output buffer makes the user-visible interruption immediate.
    _send(OpenAIRealtimeProtocol.clearOutputAudio);
  }

  @override
  Future<void> stopSession() {
    final existing = _stopInProgress;
    if (existing != null) return existing;
    final stopping = _stopSession();
    _stopInProgress = stopping;
    return stopping.whenComplete(() {
      if (identical(_stopInProgress, stopping)) _stopInProgress = null;
    });
  }

  Future<void> _stopSession() async {
    // Detach native resources before awaiting teardown. A second stop can be
    // requested by widget disposal, startup failure, or a repeated user action;
    // it must never close the same WebRTC object twice.
    final connection = _connection;
    _connection = null;
    try {
      await connection?.stop();
    } finally {
      _states.add(AIConnectionState.disconnected);
    }
  }
}
