import 'dart:typed_data';

import 'package:wearcam/domain/image_annotation.dart';

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
    this.annotations,
  });

  final String id;
  final TranscriptRole role;
  final String text;
  final TranscriptStatus status;
  final DateTime createdAt;
  final Uint8List? imageBytes;
  final List<ImageAnnotation>? annotations;

  TranscriptTurn copyWith({
    String? text,
    TranscriptStatus? status,
    Uint8List? imageBytes,
    List<ImageAnnotation>? annotations,
  }) =>
      TranscriptTurn(
        id: id,
        role: role,
        text: text ?? this.text,
        status: status ?? this.status,
        createdAt: createdAt,
        imageBytes: imageBytes ?? this.imageBytes,
        annotations: annotations ?? this.annotations,
      );
}
