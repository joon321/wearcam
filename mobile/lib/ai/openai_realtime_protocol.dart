import 'dart:convert';

import 'package:wearcam/domain/ai_provider.dart';
import 'package:wearcam/domain/prepared_frame.dart';

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

  Map<String, Object?> imageMessage(PreparedFrame frame, String context) => {
        'type': 'conversation.item.create',
        'item': {
          'type': 'message',
          'role': 'user',
          'content': [
            {
              'type': 'input_text',
              'text': '$context Captured ${frame.capturedAt.toIso8601String()} '
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
  ) =>
      {
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

  String? transcriptDelta(Map<String, dynamic> event) {
    const transcriptEvents = {
      'response.output_audio_transcript.delta',
      'conversation.item.input_audio_transcription.delta',
    };
    return transcriptEvents.contains(event['type']) && event['delta'] is String
        ? event['delta'] as String
        : null;
  }

  static const responseCreate = <String, Object?>{'type': 'response.create'};
  static const responseCancel = <String, Object?>{'type': 'response.cancel'};
  static const clearOutputAudio = <String, Object?>{
    'type': 'output_audio_buffer.clear',
  };
}
