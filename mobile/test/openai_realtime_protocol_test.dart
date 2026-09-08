import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wearcam/ai/openai_realtime_protocol.dart';
import 'package:wearcam/domain/prepared_frame.dart';

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

  test('parses only documented transcript delta events', () {
    expect(
      protocol.transcriptDelta({
        'type': 'response.output_audio_transcript.delta',
        'delta': 'hello',
      }),
      'hello',
    );
    expect(
      protocol.transcriptDelta({'type': 'response.text.delta', 'delta': 'x'}),
      isNull,
    );
  });
}
