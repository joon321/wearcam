import 'dart:typed_data';

enum CameraStatus { disconnected, connecting, connected, failed }

final class CameraCapabilities {
  const CameraCapabilities({
    required this.supportsPreview,
    required this.supportsLensSwitching,
    required this.isHeadMounted,
    required this.supportsContinuousPreview,
  });
  final bool supportsPreview;
  final bool supportsLensSwitching;
  final bool isHeadMounted;
  final bool supportsContinuousPreview;
}

enum FrameOrientation {
  portraitUp,
  portraitDown,
  landscapeLeft,
  landscapeRight,
}

final class CameraFrame {
  const CameraFrame({
    required this.jpegBytes,
    required this.capturedAt,
    required this.width,
    required this.height,
    required this.sourceId,
    required this.orientation,
    required this.sharpnessScore,
  });

  final Uint8List jpegBytes;
  final DateTime capturedAt;
  final int width;
  final int height;
  final String sourceId;
  final FrameOrientation orientation;
  final double sharpnessScore;
}

abstract interface class CameraSource {
  String get id;
  String get displayName;
  CameraCapabilities get capabilities;
  CameraStatus get connectionState;
  Future<void> connect();
  Future<CameraFrame> capture();
  Stream<CameraStatus> get status;
  Future<void> disconnect();
}

final class CameraSourceManager {
  CameraSourceManager({required List<CameraSource> sources, String? selectedId})
    : _sources = List.unmodifiable(sources),
      _selectedId = selectedId ?? sources.first.id {
    if (sources.isEmpty) throw ArgumentError.value(sources, 'sources');
  }
  final List<CameraSource> _sources;
  String _selectedId;
  List<CameraSource> get availableSources => _sources;
  CameraSource get selectedSource =>
      _sources.firstWhere((source) => source.id == _selectedId);
  void select(String id) {
    if (!_sources.any((source) => source.id == id)) {
      throw ArgumentError.value(id, 'id', 'Unknown camera source');
    }
    _selectedId = id;
  }
}
