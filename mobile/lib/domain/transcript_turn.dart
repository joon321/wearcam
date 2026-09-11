import 'dart:typed_data';

enum TranscriptRole { user, assistant }

enum TranscriptStatus { streaming, completed, interrupted }

final class TranscriptTurn {
  const TranscriptTurn({
    required this.id,
    required this.role,
    required this.text,
    required this.status,
    required this.createdAt,
    this.imageBytes,
  });

  final String id;
  final TranscriptRole role;
  final String text;
  final TranscriptStatus status;
  final DateTime createdAt;
  final Uint8List? imageBytes;

  TranscriptTurn copyWith({
    String? text,
    TranscriptStatus? status,
    Uint8List? imageBytes,
  }) =>
      TranscriptTurn(
        id: id,
        role: role,
        text: text ?? this.text,
        status: status ?? this.status,
        createdAt: createdAt,
        imageBytes: imageBytes ?? this.imageBytes,
      );
}
