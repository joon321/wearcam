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
  Future<void> setNoiseGateEnabled(bool enabled);
  Future<void> stop();
}

final class WebRtcRealtimeConnection implements RealtimeConnection {
  WebRtcRealtimeConnection({required this.onMessage}) {
    unawaited(_connected.future.catchError((Object _) {}));
  }

  final void Function(String message) onMessage;
  RTCPeerConnection? _peer;
  RTCDataChannel? _events;
  MediaStream? _localStream;
  RTCRtpSender? _audioSender;
  MediaStreamTrack? _audioTrack;
  final Completer<void> _connected = Completer<void>();
  bool _manualMuted = false;
  bool _noiseGateEnabled = false;
  bool _noiseGateOpen = false;
  Timer? _noiseGateTimer;
  static const _noiseGatePollInterval = Duration(milliseconds: 150);
  static const _noiseGateThreshold = 0.02;
  static const _noiseGateHoldDuration = Duration(milliseconds: 600);

  @override
  Future<void> acquireMicrophone({required bool muted}) async {
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': {'echoCancellation': true, 'noiseSuppression': true},
      'video': false,
    });
    _localStream = stream;
    _manualMuted = muted;
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
      _audioTrack = track;
      _audioSender = await peer.addTrack(track, stream);
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
    _manualMuted = muted;
    _applyTrackState();
  }

  @override
  Future<void> setNoiseGateEnabled(bool enabled) async {
    _noiseGateEnabled = enabled;
    if (enabled) {
      _noiseGateOpen = false;
      _applyTrackState();
      _startNoiseGatePolling();
    } else {
      _noiseGateTimer?.cancel();
      _noiseGateTimer = null;
      _noiseGateOpen = false;
      _applyTrackState();
    }
  }

  void _applyTrackState() {
    final shouldSend = !_manualMuted && (!_noiseGateEnabled || _noiseGateOpen);
    final sender = _audioSender;
    if (sender != null) {
      unawaited(sender.replaceTrack(shouldSend ? _audioTrack : null));
    }
  }

  void _startNoiseGatePolling() {
    _noiseGateTimer?.cancel();
    _noiseGateTimer = Timer.periodic(_noiseGatePollInterval, (_) async {
      final peer = _peer;
      if (peer == null || _manualMuted) return;
      try {
        final stats = await peer.getStats(_audioTrack);
        double maxLevel = 0;
        for (final report in stats) {
          // Standard format (Chrome desktop, newer implementations)
          if (report.type == 'media-source' &&
              report.values['kind'] == 'audio') {
            final level = report.values['audioLevel'];
            if (level is num && level > maxLevel) {
              maxLevel = level.toDouble();
            }
          }
          // Legacy format (Android, older implementations): 0-32768 integer
          if (report.type == 'ssrc' &&
              report.values['mediaType'] == 'audio') {
            final level = report.values['audioInputLevel'];
            if (level is num && level > 0) {
              final normalized = (level / 32768.0).clamp(0.0, 1.0);
              if (normalized > maxLevel) maxLevel = normalized;
            }
          }
        }
        if (maxLevel >= _noiseGateThreshold) {
          _noiseGateOpen = true;
          _applyTrackState();
          _scheduleNoiseGateClose();
        }
      } catch (_) {}
    });
  }

  Timer? _noiseGateHoldTimer;
  void _scheduleNoiseGateClose() {
    _noiseGateHoldTimer?.cancel();
    _noiseGateHoldTimer = Timer(_noiseGateHoldDuration, () {
      _noiseGateOpen = false;
      _applyTrackState();
    });
  }

  @override
  Future<void> stop() async {
    _noiseGateTimer?.cancel();
    _noiseGateTimer = null;
    _noiseGateHoldTimer?.cancel();
    _noiseGateHoldTimer = null;
    final localStream = _localStream;
    final events = _events;
    final peer = _peer;
    _localStream = null;
    _audioSender = null;
    _audioTrack = null;
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
