import 'package:flutter/foundation.dart';

enum ConnectionStage {
  readBackendConfiguration,
  requestTemporaryCredentials,
  acquireMicrophone,
  createPeerConnection,
  createLocalOffer,
  exchangeSdp,
  applyRemoteDescription,
  waitForConnectedState,
}

extension ConnectionStageName on ConnectionStage {
  String get wireName => switch (this) {
    ConnectionStage.readBackendConfiguration => 'read_backend_configuration',
    ConnectionStage.requestTemporaryCredentials =>
      'request_temporary_credentials',
    ConnectionStage.acquireMicrophone => 'acquire_microphone',
    ConnectionStage.createPeerConnection => 'create_peer_connection',
    ConnectionStage.createLocalOffer => 'create_local_offer',
    ConnectionStage.exchangeSdp => 'exchange_sdp',
    ConnectionStage.applyRemoteDescription => 'apply_remote_description',
    ConnectionStage.waitForConnectedState => 'wait_for_connected_state',
  };
}

final class ConnectionDiagnostic {
  const ConnectionDiagnostic({
    required this.timestamp,
    required this.stage,
    required this.status,
    required this.backendHost,
    this.message,
    this.httpStatus,
    this.requestId,
  });

  final DateTime timestamp;
  final ConnectionStage stage;
  final String status;
  final String backendHost;
  final String? message;
  final int? httpStatus;
  final String? requestId;

  String get summary => [
    timestamp.toUtc().toIso8601String(),
    stage.wireName,
    status,
    'backend=$backendHost',
    if (httpStatus != null) 'http=$httpStatus',
    if (requestId != null) 'request_id=$requestId',
    if (message != null) message!,
  ].join(' | ');
}

final class ConnectionDiagnostics extends ChangeNotifier {
  ConnectionDiagnostics({required this.backendHost});

  final String backendHost;
  final List<ConnectionDiagnostic> _entries = [];

  List<ConnectionDiagnostic> get entries => List.unmodifiable(_entries);
  String get copyText => _entries.map((entry) => entry.summary).join('\n');

  void record(
    ConnectionStage stage,
    String status, {
    String? message,
    int? httpStatus,
    String? requestId,
  }) {
    _entries.add(
      ConnectionDiagnostic(
        timestamp: DateTime.now().toUtc(),
        stage: stage,
        status: status,
        backendHost: backendHost,
        message: sanitizeDiagnostic(message),
        httpStatus: httpStatus,
        requestId: sanitizeRequestId(requestId),
      ),
    );
    if (_entries.length > 100) _entries.removeAt(0);
    notifyListeners();
  }
}

String? sanitizeRequestId(String? value) {
  if (value == null || value.isEmpty) return null;
  return RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(value) ? value : null;
}

String? sanitizeDiagnostic(String? value) {
  if (value == null) return null;
  final collapsed = value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
  if (collapsed.isEmpty) return null;
  if (RegExp(
    r'(authorization\s*:|bearer\s+|sk-[A-Za-z0-9_-]{6,}|(^|\s)v=0(\s|$)|a=fingerprint:)',
    caseSensitive: false,
  ).hasMatch(collapsed)) {
    return 'Sensitive error details removed.';
  }
  return collapsed.length <= 240 ? collapsed : collapsed.substring(0, 240);
}

final class ProviderConnectionException implements Exception {
  const ProviderConnectionException({
    required this.stage,
    required this.message,
    this.httpStatus,
    this.requestId,
  });

  final ConnectionStage stage;
  final String message;
  final int? httpStatus;
  final String? requestId;

  String get displayMessage => [
    '${stage.wireName}: ${sanitizeDiagnostic(message) ?? 'Connection failed.'}',
    if (httpStatus != null) 'HTTP $httpStatus',
    if (requestId != null) 'request ID $requestId',
  ].join(' · ');

  @override
  String toString() => displayMessage;
}
