import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wearcam/ai/openai_realtime_protocol.dart';
import 'package:wearcam/domain/prepared_frame.dart';
import 'package:wearcam/domain/transcript_turn.dart';

void main() {
  const protocol = OpenAIRealtimeProtocol();

  test('serializes text and response events', () {
    expect(protocol.textMessage('hello'), {
      'type': 'conversation.item.create',
      'item': {
        'type': 'message',
        'role': 'user',
        'content': [
          {'type': 'input_text', 'text': 'hello'},
        ],
      },
    });
    expect(OpenAIRealtimeProtocol.responseCreate, {'type': 'response.create'});
  });

  test('serializes an image as a JPEG data URL', () {
    final frame = PreparedFrame(
      jpegBytes: Uint8List.fromList([0xff, 0xd8, 0xff]),
      capturedAt: DateTime.utc(2026, 9, 8, 12, 30),
      width: 640,
      height: 480,
      sourceId: 'phone-rear',
      sharpnessScore: 42,
    );
    final event = protocol.imageMessage(frame, 'Fresh view.');
    final item = event['item']! as Map<String, Object?>;
    final content = item['content']! as List<Map<String, Object?>>;
    expect(content, [
      {
        'type': 'input_text',
        'text':
            'Fresh view. Captured 2026-09-08T12:30:00.000Z '
            'from phone-rear.',
      },
      {'type': 'input_image', 'image_url': 'data:image/jpeg;base64,/9j/'},
    ]);
  });

  test('serializes function output and immediate audio interruption', () {
    expect(protocol.functionOutput('call_1', {'captured': true}), {
      'type': 'conversation.item.create',
      'item': {
        'type': 'function_call_output',
        'call_id': 'call_1',
        'output': '{"captured":true}',
      },
    });
    expect(OpenAIRealtimeProtocol.responseCancel, {'type': 'response.cancel'});
    expect(OpenAIRealtimeProtocol.clearOutputAudio, {
      'type': 'output_audio_buffer.clear',
    });
  });

  test('parses completed tool calls and rejects malformed arguments', () {
    final call = protocol.toolCall({
      'type': 'response.function_call_arguments.done',
      'name': 'get_current_view',
      'call_id': 'call_1',
      'arguments': '{}',
    });
    expect(call?.name, 'get_current_view');
    expect(call?.callId, 'call_1');
    expect(call?.arguments, isEmpty);
    expect(
      protocol.toolCall({
        'type': 'response.function_call_arguments.done',
        'name': 'get_current_view',
        'call_id': 'call_2',
        'arguments': '[1]',
      }),
      isNull,
    );
  });

  test('rejects malformed and non-object server events', () {
    expect(protocol.decodeEvent('{'), isNull);
    expect(protocol.decodeEvent('[]'), isNull);
    expect(protocol.decodeEvent('{"type":"session.created"}'), {
      'type': 'session.created',
    });
  });

  test('maps input and output audio transcript lifecycle events', () {
    final userDelta = protocol.transcriptEvents({
      'type': 'conversation.item.input_audio_transcription.delta',
      'item_id': 'user-1',
      'delta': 'hello',
    }).single;
    expect(userDelta.turnId, 'user-1');
    expect(userDelta.role, TranscriptRole.user);
    expect(userDelta.delta, 'hello');
    expect(userDelta.status, TranscriptStatus.streaming);

    final assistantDone = protocol.transcriptEvents({
      'type': 'response.output_audio_transcript.done',
      'item_id': 'assistant-1',
      'transcript': 'Hello there.',
    }).single;
    expect(assistantDone.turnId, 'assistant-1');
    expect(assistantDone.role, TranscriptRole.assistant);
    expect(assistantDone.completedText, 'Hello there.');
    expect(assistantDone.status, TranscriptStatus.completed);

    expect(
      protocol.transcriptEvents({
        'type': 'response.text.delta',
        'item_id': 'ignored',
        'delta': 'x',
      }),
      isEmpty,
    );
  });

  test('maps new items and truncation to distinct transcript turns', () {
    final first = protocol.transcriptEvents({
      'type': 'response.output_item.added',
      'item': {'id': 'assistant-1', 'role': 'assistant'},
    }).single;
    final second = protocol.transcriptEvents({
      'type': 'response.output_item.added',
      'item': {'id': 'assistant-2', 'role': 'assistant'},
    }).single;
    final interrupted = protocol.transcriptEvents({
      'type': 'conversation.item.truncated',
      'item_id': 'assistant-2',
    }).single;

    expect([first.turnId, second.turnId], ['assistant-1', 'assistant-2']);
    expect(interrupted.status, TranscriptStatus.interrupted);
  });

  test('marks output items from a cancelled response as interrupted', () {
    final events = protocol.transcriptEvents({
      'type': 'response.done',
      'response': {
        'status': 'cancelled',
        'output': [
          {'id': 'assistant-1', 'role': 'assistant'},
        ],
      },
    });

    expect(events.single.turnId, 'assistant-1');
    expect(events.single.status, TranscriptStatus.interrupted);
  });
}
