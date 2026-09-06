import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile source contains no permanent OpenAI credential configuration', () {
    final files = Directory('lib').listSync(recursive: true).whereType<File>();
    final source = files.map((file) => file.readAsStringSync()).join('\n');
    expect(source, isNot(contains('OPENAI_API_KEY')));
    expect(RegExp(r'sk-[A-Za-z0-9_-]{12,}').hasMatch(source), false);
  });
}
