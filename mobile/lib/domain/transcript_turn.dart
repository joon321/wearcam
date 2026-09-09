enum TranscriptRole { user, assistant }

enum TranscriptStatus { streaming, completed, interrupted }

final class TranscriptTurn {
  const TranscriptTurn({
    required this.id,
    required this.role,
    required this.text,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final TranscriptRole role;
  final String text;
  final TranscriptStatus status;
  final DateTime createdAt;

  TranscriptTurn copyWith({String? text, TranscriptStatus? status}) =>
      TranscriptTurn(
        id: id,
        role: role,
        text: text ?? this.text,
        status: status ?? this.status,
        createdAt: createdAt,
      );
}
