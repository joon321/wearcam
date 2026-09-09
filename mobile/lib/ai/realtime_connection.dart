import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

abstract interface class RealtimeConnection {
  Future<void> acquireMicrophone({required bool muted});
  Future<void> createPeerConnection();
  Future<String> createLocalOffer();
  Future<void> applyRemoteDescription(String answerSdp);
  Future<void> waitUntilConnected();
  void send(Map<String, Object?> event);
  Future<void> setMicrophoneMuted(bool muted);
  Future<void> stop();
}

final class WebRtcRealtimeConnection implements RealtimeConnection {
  WebRtcRealtimeConnection({required this.onMessage});

  final void Function(String message) onMessage;
  RTCPeerConnection? _peer;
  RTCDataChannel? _events;
  MediaStream? _localStream;
  final Completer<void> _connected = Completer<void>();

  @override
  Future<void> acquireMicrophone({required bool muted}) async {
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': {'echoCancellation': true, 'noiseSuppression': true},
      'video': false,
    });
    _localStream = stream;
    for (final track in stream.getAudioTracks()) {
      track.enabled = !muted;
    }
  }

  @override
  Future<void> createPeerConnection() async {
    final peer = await _createNativePeerConnection({'iceServers': <Object>[]});
    _peer = peer;
    peer.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected &&
          !_connected.isCompleted) {
        _connected.complete();
      }
      if ((state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
              state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) &&
          !_connected.isCompleted) {
        _connected.completeError(StateError('WebRTC connection failed.'));
      }
    };
    final stream = _localStream;
    if (stream == null) throw StateError('Microphone stream is unavailable.');
    for (final track in stream.getAudioTracks()) {
      await peer.addTrack(track, stream);
    }
    final channel = await peer.createDataChannel(
      'oai-events',
      RTCDataChannelInit(),
    );
    _events = channel;
    channel.onMessage = (message) {
      if (!message.isBinary) onMessage(message.text);
    };
  }

  @override
  Future<String> createLocalOffer() async {
    final peer = _peer;
    if (peer == null) throw StateError('Peer connection is unavailable.');
    final offer = await peer.createOffer();
    await peer.setLocalDescription(offer);
    final sdp = offer.sdp;
    if (sdp == null || sdp.isEmpty) throw StateError('Local offer was empty.');
    return sdp;
  }

  @override
  Future<void> applyRemoteDescription(String answerSdp) async {
    final peer = _peer;
    if (peer == null) throw StateError('Peer connection is unavailable.');
    await peer.setRemoteDescription(RTCSessionDescription(answerSdp, 'answer'));
  }

  @override
  Future<void> waitUntilConnected() => _connected.future;

  @override
  void send(Map<String, Object?> event) {
    final channel = _events;
    if (channel == null ||
        channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw StateError('Realtime data channel is not open.');
    }
    channel.send(RTCDataChannelMessage(jsonEncode(event)));
  }

  @override
  Future<void> setMicrophoneMuted(bool muted) async {
    for (final track
        in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
  }

  @override
  Future<void> stop() async {
    final localStream = _localStream;
    final events = _events;
    final peer = _peer;
    _localStream = null;
    _events = null;
    _peer = null;
    await runRealtimeCleanup([
      for (final track in localStream?.getTracks() ?? <MediaStreamTrack>[])
        track.stop,
      if (localStream != null) localStream.dispose,
      if (events != null) events.close,
      if (peer != null) peer.close,
    ]);
  }
}

@visibleForTesting
Future<void> runRealtimeCleanup(
  Iterable<Future<void> Function()> operations,
) async {
  Object? firstError;
  StackTrace? firstStackTrace;
  for (final operation in operations) {
    try {
      await operation();
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
  }
  final error = firstError;
  if (error != null) {
    Error.throwWithStackTrace(error, firstStackTrace!);
  }
}

Future<RTCPeerConnection> _createNativePeerConnection(
  Map<String, dynamic> configuration,
) => createPeerConnection(configuration);
