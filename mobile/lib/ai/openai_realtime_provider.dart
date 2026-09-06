import 'dart:async';
import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
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
    final event = jsonDecode(wire);
    if (event is! Map<String, dynamic>) return;
    final type = event['type'];
    if (type == 'response.output_audio_transcript.delta' ||
        type == 'conversation.item.input_audio_transcription.delta') {
      final delta = event['delta'];
      if (delta is String) _transcript.add(delta);
    }
    if (type == 'response.function_call_arguments.done' &&
        event['name'] is String) {
      final arguments = jsonDecode((event['arguments'] as String?) ?? '{}');
      _toolCalls.add(
        ToolCall(
          name: event['name'] as String,
          callId: event['call_id'] as String,
          arguments: arguments is Map<String, dynamic> ? arguments : const {},
        ),
      );
    }
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
    _send({
      'type': 'conversation.item.create',
      'item': {
        'type': 'message',
        'role': 'user',
        'content': [
          {'type': 'input_text', 'text': text},
        ],
      },
    });
    _send({'type': 'response.create'});
  }

  @override
  Future<void> sendImage(PreparedFrame frame, String context) async {
    final base64Image = base64Encode(frame.jpegBytes);
    _send({
      'type': 'conversation.item.create',
      'item': {
        'type': 'message',
        'role': 'user',
        'content': [
          {
            'type': 'input_text',
            'text':
                '$context Captured ${frame.capturedAt.toIso8601String()} '
                'from ${frame.sourceId}.',
          },
          {
            'type': 'input_image',
            'image_url': 'data:image/jpeg;base64,$base64Image',
          },
        ],
      },
    });
  }

  @override
  Future<void> completeToolCall(
    String callId,
    Map<String, Object?> output,
  ) async {
    _send({
      'type': 'conversation.item.create',
      'item': {
        'type': 'function_call_output',
        'call_id': callId,
        'output': jsonEncode(output),
      },
    });
    _send({'type': 'response.create'});
  }

  @override
  Future<void> setMicrophoneMuted(bool muted) async {
    for (final track
        in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
  }

  @override
  Future<void> interrupt() async => _send({'type': 'response.cancel'});

  @override
  Future<void> stopSession() async {
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      track.stop();
    }
    await _localStream?.dispose();
    _localStream = null;
    await _events?.close();
    _events = null;
    await _peer?.close();
    _peer = null;
    _states.add(AIConnectionState.disconnected);
  }
}
