import 'dart:convert';

import 'package:wearcam/domain/ai_provider.dart';
import 'package:wearcam/domain/prepared_frame.dart';
import 'package:wearcam/domain/transcript_turn.dart';

final class RealtimeTranscriptEvent {
  const RealtimeTranscriptEvent({
    required this.turnId,
    required this.role,
    required this.status,
    this.delta,
    this.completedText,
  });

  final String turnId;
  final TranscriptRole role;
  final TranscriptStatus status;
  final String? delta;
  final String? completedText;
}

/// Serialization boundary for the documented OpenAI Realtime wire protocol.
final class OpenAIRealtimeProtocol {
  const OpenAIRealtimeProtocol();

  Map<String, dynamic>? decodeEvent(String wire) {
    try {
      final event = jsonDecode(wire);
      return event is Map<String, dynamic> ? event : null;
    } on FormatException {
      return null;
    }
  }

  Map<String, Object?> textMessage(String text) => {
    'type': 'conversation.item.create',
    'item': {
      'type': 'message',
      'role': 'user',
      'content': [
        {'type': 'input_text', 'text': text},
      ],
    },
  };

  Map<String, Object?> greetingRequest(String text) => {
    'type': 'response.create',
    'response': {'instructions': 'Say exactly: $text'},
  };

  Map<String, Object?> imageMessage(PreparedFrame frame, String context) => {
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
          'image_url':
              'data:image/jpeg;base64,${base64Encode(frame.jpegBytes)}',
        },
      ],
    },
  };

  Map<String, Object?> functionOutput(
    String callId,
    Map<String, Object?> output,
  ) => {
    'type': 'conversation.item.create',
    'item': {
      'type': 'function_call_output',
      'call_id': callId,
      'output': jsonEncode(output),
    },
  };

  ToolCall? toolCall(Map<String, dynamic> event) {
    if (event['type'] != 'response.function_call_arguments.done') return null;
    final name = event['name'];
    final callId = event['call_id'];
    final encodedArguments = event['arguments'];
    if (name is! String || callId is! String || encodedArguments is! String) {
      return null;
    }
    try {
      final arguments = jsonDecode(encodedArguments);
      if (arguments is! Map<String, dynamic>) return null;
      return ToolCall(name: name, callId: callId, arguments: arguments);
    } on FormatException {
      return null;
    }
  }

  List<RealtimeTranscriptEvent> transcriptEvents(Map<String, dynamic> event) {
    final type = event['type'];
    final itemId = event['item_id'];
    if (itemId is String && itemId.isNotEmpty) {
      if (type == 'conversation.item.input_audio_transcription.delta' &&
          event['delta'] is String) {
        return [
          RealtimeTranscriptEvent(
            turnId: itemId,
            role: TranscriptRole.user,
            status: TranscriptStatus.streaming,
            delta: event['delta'] as String,
          ),
        ];
      }
      if (type == 'conversation.item.input_audio_transcription.completed') {
        return [
          RealtimeTranscriptEvent(
            turnId: itemId,
            role: TranscriptRole.user,
            status: TranscriptStatus.completed,
            completedText: event['transcript'] is String
                ? event['transcript'] as String
                : null,
          ),
        ];
      }
      if (type == 'response.output_audio_transcript.delta' &&
          event['delta'] is String) {
        return [
          RealtimeTranscriptEvent(
            turnId: itemId,
            role: TranscriptRole.assistant,
            status: TranscriptStatus.streaming,
            delta: event['delta'] as String,
          ),
        ];
      }
      if (type == 'response.output_audio_transcript.done') {
        return [
          RealtimeTranscriptEvent(
            turnId: itemId,
            role: TranscriptRole.assistant,
            status: TranscriptStatus.completed,
            completedText: event['transcript'] is String
                ? event['transcript'] as String
                : null,
          ),
        ];
      }
      if (type == 'conversation.item.truncated') {
        return [
          RealtimeTranscriptEvent(
            turnId: itemId,
            role: TranscriptRole.assistant,
            status: TranscriptStatus.interrupted,
          ),
        ];
      }
    }
    if (type == 'conversation.item.created') {
      return _turnStarted(event['item']);
    }
    if (type == 'response.output_item.added') {
      return _turnStarted(event['item'], assistantOnly: true);
    }
    if (type == 'response.done') return _interruptedResponse(event['response']);
    return const [];
  }

  List<RealtimeTranscriptEvent> _interruptedResponse(Object? value) {
    if (value is! Map<String, dynamic> ||
        (value['status'] != 'cancelled' && value['status'] != 'incomplete') ||
        value['output'] is! List<Object?>) {
      return const [];
    }
    return [
      for (final item in value['output'] as List<Object?>)
        if (item is Map<String, dynamic> &&
            item['id'] is String &&
            item['role'] == 'assistant')
          RealtimeTranscriptEvent(
            turnId: item['id'] as String,
            role: TranscriptRole.assistant,
            status: TranscriptStatus.interrupted,
          ),
    ];
  }

  List<RealtimeTranscriptEvent> _turnStarted(
    Object? value, {
    bool assistantOnly = false,
  }) {
    if (value is! Map<String, dynamic> || value['id'] is! String) {
      return const [];
    }
    final role = switch (value['role']) {
      'user' when !assistantOnly && _containsAudio(value, 'input_audio') =>
        TranscriptRole.user,
      'assistant' => TranscriptRole.assistant,
      _ => null,
    };
    if (role == null) return const [];
    return [
      RealtimeTranscriptEvent(
        turnId: value['id'] as String,
        role: role,
        status: TranscriptStatus.streaming,
      ),
    ];
  }

  bool _containsAudio(Map<String, dynamic> item, String type) {
    final content = item['content'];
    return content is List<Object?> &&
        content.any(
          (part) => part is Map<String, dynamic> && part['type'] == type,
        );
  }

  static Map<String, Object?> sessionUpdateInstructions(
    String instructions,
  ) => {
    'type': 'session.update',
    'session': {'instructions': instructions},
  };

  static const sessionUpdateVad = <String, Object?>{
    'type': 'session.update',
    'session': {
      'turn_detection': {
        'type': 'server_vad',
        'threshold': 0.85,
        'prefix_padding_ms': 500,
        'silence_duration_ms': 1000,
        'eagerness': 'low',
      },
    },
  };

  static const responseCreate = <String, Object?>{'type': 'response.create'};
  static const responseCancel = <String, Object?>{'type': 'response.cancel'};
  static const clearOutputAudio = <String, Object?>{
    'type': 'output_audio_buffer.clear',
  };
}
