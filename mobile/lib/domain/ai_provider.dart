import 'dart:async';

import 'package:wearcam/domain/prepared_frame.dart';
import 'package:wearcam/domain/transcript_turn.dart';

enum AIConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  failed,
}

final class ToolCall {
  const ToolCall({
    required this.name,
    required this.callId,
    required this.arguments,
  });
  final String name;
  final String callId;
  final Map<String, Object?> arguments;
}

abstract interface class AIProvider {
  Stream<AIConnectionState> get connectionStates;
  Stream<TranscriptTurn> get transcript;
  Stream<ToolCall> get toolCalls;
  Future<void> startSession();
  Future<void> sendText(String text);
  Future<void> sendImage(PreparedFrame frame, String context);
  Future<void> completeToolCall(String callId, Map<String, Object?> output);
  Future<void> setMicrophoneMuted(bool muted);
  Future<void> interrupt();
  Future<void> stopSession();
}
