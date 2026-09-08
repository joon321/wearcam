import 'dart:async';
import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:wearcam/ai/openai_realtime_protocol.dart';
import 'package:wearcam/domain/ai_provider.dart';
import 'package:wearcam/domain/prepared_frame.dart';

final class OpenAIRealtimeProvider implements AIProvider {
  OpenAIRealtimeProvider({
    required this.backendBaseUri,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final Uri backendBaseUri;
  final http.Client _http;
  final _states = StreamController<AIConnectionState>.broadcast();
  final _transcript = StreamController<String>.broadcast();
  final _toolCalls = StreamController<ToolCall>.broadcast();
  RTCPeerConnection? _peer;
  RTCDataChannel? _events;
  MediaStream? _localStream;
  bool _microphoneMuted = false;
  Future<void>? _stopInProgress;
  static const _protocol = OpenAIRealtimeProtocol();

  @override
  Stream<AIConnectionState> get connectionStates => _states.stream;
  @override
  Stream<String> get transcript => _transcript.stream;
  @override
  Stream<ToolCall> get toolCalls => _toolCalls.stream;

  @override
  Future<void> startSession() async {
    _states.add(AIConnectionState.connecting);
    try {
      final credentialResponse = await _http.post(
        backendBaseUri.resolve('/v1/realtime/client-secret'),
        headers: const {'content-type': 'application/json'},
      );
      if (credentialResponse.statusCode != 201) {
        throw StateError('Credential service failed');
      }
      final credentialJson =
          jsonDecode(credentialResponse.body) as Map<String, dynamic>;
      final temporaryCredential = credentialJson['value'];
      if (temporaryCredential is! String || temporaryCredential.isEmpty) {
        throw StateError('Credential service returned no temporary value');
      }

      final peer = await createPeerConnection({'iceServers': <Object>[]});
      _peer = peer;
      final localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {'echoCancellation': true, 'noiseSuppression': true},
        'video': false,
      });
      _localStream = localStream;
      for (final track in localStream.getAudioTracks()) {
        track.enabled = !_microphoneMuted;
        await peer.addTrack(track, localStream);
      }
      final channel = await peer.createDataChannel(
        'oai-events',
        RTCDataChannelInit(),
      );
      _events = channel;
      channel.onMessage = (message) {
        if (!message.isBinary) _handleEvent(message.text);
      };
      final offer = await peer.createOffer();
      await peer.setLocalDescription(offer);
      final sdpResponse = await _http.post(
        Uri.parse('https://api.openai.com/v1/realtime/calls'),
        headers: {
          'authorization': 'Bearer $temporaryCredential',
          'content-type': 'application/sdp',
        },
        body: offer.sdp,
      );
      if (sdpResponse.statusCode < 200 || sdpResponse.statusCode >= 300) {
        throw StateError('Realtime WebRTC negotiation failed');
      }
      await peer.setRemoteDescription(
        RTCSessionDescription(sdpResponse.body, 'answer'),
      );
      _states.add(AIConnectionState.connected);
    } catch (_) {
      _states.add(AIConnectionState.failed);
      await stopSession();
      rethrow;
    }
  }

  void _handleEvent(String wire) {
    final event = _protocol.decodeEvent(wire);
    if (event == null) return;
    final delta = _protocol.transcriptDelta(event);
    if (delta != null) _transcript.add(delta);
    final toolCall = _protocol.toolCall(event);
    if (toolCall != null) _toolCalls.add(toolCall);
  }

  void _send(Map<String, Object?> event) {
    final channel = _events;
    if (channel == null ||
        channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw StateError('Realtime data channel is not open');
    }
    channel.send(RTCDataChannelMessage(jsonEncode(event)));
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
    for (final track
        in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
  }

  @override
  Future<void> interrupt() async {
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
    final localStream = _localStream;
    final events = _events;
    final peer = _peer;
    _localStream = null;
    _events = null;
    _peer = null;

    for (final track in localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      await track.stop();
    }
    await localStream?.dispose();
    await events?.close();
    await peer?.close();
    _states.add(AIConnectionState.disconnected);
  }
}
