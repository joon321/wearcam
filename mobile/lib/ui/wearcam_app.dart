import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wearcam/ai/connection_diagnostics.dart';
import 'package:wearcam/camera/phone_camera_source.dart';
import 'package:wearcam/conversation/conversation_controller.dart';
import 'package:wearcam/domain/ai_provider.dart';
import 'package:wearcam/domain/camera_source.dart';
import 'package:wearcam/domain/capture_mode.dart';
import 'package:wearcam/domain/transcript_turn.dart';
import 'package:wearcam/domain/vision_mode.dart';

final class WearCamApp extends StatelessWidget {
  const WearCamApp({
    required this.camera,
    required this.controller,
    required this.diagnostics,
    required this.onChangeBackend,
    super.key,
  });
  final PhoneCameraSource camera;
  final ConversationController controller;
  final ConnectionDiagnostics diagnostics;
  final Future<void> Function() onChangeBackend;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'WearCam',
    theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
    home: WearCamHome(
      camera: camera,
      controller: controller,
      diagnostics: diagnostics,
      onChangeBackend: onChangeBackend,
    ),
  );
}

final class WearCamHome extends StatefulWidget {
  const WearCamHome({
    required this.camera,
    required this.controller,
    required this.diagnostics,
    required this.onChangeBackend,
    super.key,
  });
  final PhoneCameraSource camera;
  final ConversationController controller;
  final ConnectionDiagnostics diagnostics;
  final Future<void> Function() onChangeBackend;

  @override
  State<WearCamHome> createState() => _WearCamHomeState();
}

final class _WearCamHomeState extends State<WearCamHome> {
  int index = 0;
  CaptureState _lastCaptureState = CaptureState.idle;
  int _lastTranscriptCount = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    final current = widget.controller.captureState;
    if (current == CaptureState.previewing &&
        _lastCaptureState == CaptureState.idle) {
      setState(() => index = 1);
    } else if (current == CaptureState.idle &&
        _lastCaptureState == CaptureState.previewing) {
      setState(() => index = 2);
    }
    _lastCaptureState = current;

    final transcriptCount = widget.controller.transcriptTurns.length;
    if (transcriptCount > _lastTranscriptCount && index == 0) {
      setState(() => index = 2);
    }
    _lastTranscriptCount = transcriptCount;
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _Home(controller: widget.controller),
      _Camera(camera: widget.camera, controller: widget.controller),
      _Conversation(controller: widget.controller),
      _Settings(
        onChangeBackend: widget.onChangeBackend,
        diagnostics: widget.diagnostics,
        controller: widget.controller,
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('WearCam Bridge')),
      body: SafeArea(child: pages[index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.camera_alt_outlined),
            label: 'Camera',
          ),
          NavigationDestination(
            icon: Icon(Icons.mic_outlined),
            label: 'Conversation',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

final class _Home extends StatelessWidget {
  const _Home({required this.controller});
  final ConversationController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          title: const Text('AI provider'),
          subtitle: Text(controller.connectionState.name),
        ),
        ListTile(
          title: const Text('Visual access'),
          subtitle: Text(controller.visionStatus),
        ),
        FilledButton.icon(
          onPressed:
              controller.connectionState == AIConnectionState.disconnected &&
                  !controller.isStarting
              ? controller.start
              : null,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start visual conversation'),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: controller.connectionState != AIConnectionState.connected
              ? null
              : controller.visionModes.mode == VisionMode.off
              ? controller.resumeLooking
              : controller.stopLooking,
          icon: Icon(
            controller.visionModes.mode == VisionMode.off
                ? Icons.visibility
                : Icons.visibility_off,
          ),
          label: Text(
            controller.visionModes.mode == VisionMode.off
                ? 'Resume Looking'
                : 'Stop Looking',
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: controller.stopEverything,
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('Stop Everything'),
        ),
        if (controller.error != null) ...[
          Text(controller.error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.tonal(
                key: const Key('retry-connection'),
                onPressed: controller.isStarting ? null : controller.start,
                child: const Text('Retry'),
              ),
              OutlinedButton(
                key: const Key('copy-diagnostics'),
                onPressed: () => Clipboard.setData(
                  ClipboardData(text: controller.diagnostics.copyText),
                ),
                child: const Text('Copy diagnostics'),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

final class _Camera extends StatefulWidget {
  const _Camera({required this.camera, required this.controller});
  final PhoneCameraSource camera;
  final ConversationController controller;

  @override
  State<_Camera> createState() => _CameraState();
}

final class _CameraState extends State<_Camera> {
  StreamSubscription<CameraStatus>? _statusSubscription;

  @override
  void initState() {
    super.initState();
    _statusSubscription = widget.camera.status.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cameraController = widget.camera.controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return const Center(
        child: Text('Start a conversation to connect the phone camera.'),
      );
    }
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final currentController = widget.camera.controller;
        if (currentController == null ||
            !currentController.value.isInitialized) {
          return const Center(child: CircularProgressIndicator());
        }
        final isFront =
            widget.camera.preferredLens == CameraLensDirection.front;
        return Column(
          children: [
            ListTile(
              title: const Text('Camera source'),
              subtitle: Text(
                'Phone camera (${isFront ? 'front' : 'rear'}) · '
                'External/wearable camera — Coming later',
              ),
              trailing: IconButton(
                tooltip: isFront
                    ? 'Switch to rear camera'
                    : 'Switch to front camera',
                icon: const Icon(Icons.cameraswitch),
                onPressed: () async {
                  try {
                    await widget.camera.selectLens(
                      isFront
                          ? CameraLensDirection.back
                          : CameraLensDirection.front,
                    );
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Could not switch camera lens.'),
                        ),
                      );
                    }
                  }
                },
              ),
            ),
            const MaterialBanner(
              content: Text(
                'Local preview only — preview video is never uploaded.',
              ),
              actions: [SizedBox.shrink()],
            ),
            Expanded(
              child: CameraPreview(currentController),
            ),
            if (widget.controller.captureState == CaptureState.previewing &&
                widget.controller.captureMode == CaptureMode.manual)
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  key: const Key('manual-capture-button'),
                  onPressed: widget.controller.triggerCapture,
                  icon: const Icon(Icons.camera),
                  label: const Text('Capture'),
                ),
              ),
            if (widget.controller.captureState == CaptureState.previewing &&
                widget.controller.captureMode == CaptureMode.auto)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Capturing automatically…'),
              ),
          ],
        );
      },
    );
  }
}

final class _Conversation extends StatefulWidget {
  const _Conversation({required this.controller});
  final ConversationController controller;

  @override
  State<_Conversation> createState() => _ConversationState();
}

final class _ConversationState extends State<_Conversation> {
  final ScrollController _scrollController = ScrollController();
  String? _latestTurnSignature;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToLatest(List<TranscriptTurn> turns) {
    final latest = turns.lastOrNull;
    final signature = latest == null
        ? null
        : '${latest.id}:${latest.text.length}:${latest.status.name}';
    if (signature == _latestTurnSignature) return;
    _latestTurnSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final visionMode = controller.visionModes.mode;
      final frame = controller.lastTransmittedFrame;
      final turns = controller.transcriptTurns;
      _scrollToLatest(turns);
      return ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          if (visionMode != VisionMode.off)
            Card(
              child: ListTile(
                leading: const Icon(Icons.visibility, color: Colors.green),
                title: Text(controller.visionStatusFor(visionMode)),
              ),
            ),
          Text('Transcript', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (turns.isEmpty)
            const Text('Waiting for speech…')
          else
            for (final turn in turns) _TranscriptBubble(turn: turn),
          const SizedBox(height: 16),
          Text(
            'Last image transmitted',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (frame == null)
            const Text('No image transmitted in this session.')
          else ...[
            Image.memory(frame.jpegBytes, gaplessPlayback: true),
            Text(
              frame.capturedAt.toLocal().toIso8601String(),
              key: const Key('transmitted-timestamp'),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: controller.toggleMute,
            icon: Icon(controller.microphoneMuted ? Icons.mic_off : Icons.mic),
            label: Text(
              controller.microphoneMuted
                  ? 'Unmute microphone'
                  : 'Mute microphone',
            ),
          ),
        ],
      );
    },
  );
}

final class _TranscriptBubble extends StatelessWidget {
  const _TranscriptBubble({required this.turn});

  final TranscriptTurn turn;

  @override
  Widget build(BuildContext context) {
    final isUser = turn.role == TranscriptRole.user;
    final colors = Theme.of(context).colorScheme;
    return Align(
      key: ValueKey('transcript-turn-${turn.id}'),
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? colors.primaryContainer : colors.secondaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isUser ? 'You' : 'WearCam',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            if (turn.imageBytes != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    turn.imageBytes!,
                    gaplessPlayback: true,
                    width: 200,
                  ),
                ),
              ),
            if (turn.text.isNotEmpty) SelectableText(turn.text),
            if (turn.status == TranscriptStatus.streaming)
              const Text('Speaking…', key: Key('streaming-turn-status')),
            if (turn.status == TranscriptStatus.interrupted)
              const Text('Interrupted', key: Key('interrupted-turn-status')),
          ],
        ),
      ),
    );
  }
}

final class _Settings extends StatelessWidget {
  const _Settings({
    required this.onChangeBackend,
    required this.diagnostics,
    required this.controller,
  });
  final Future<void> Function() onChangeBackend;
  final ConnectionDiagnostics diagnostics;
  final ConversationController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => ListView(
      children: [
        const ListTile(
          title: Text('Provider'),
          subtitle: Text('OpenAI Realtime'),
        ),
        ListTile(
          key: const Key('change-backend-action'),
          leading: const Icon(Icons.settings_ethernet),
          title: const Text('Change backend'),
          subtitle: const Text('Update the saved WearCam backend URL'),
          onTap: () => handleChangeBackend(onChangeBackend, diagnostics),
        ),
        ListTile(
          key: const Key('capture-mode-setting'),
          leading: const Icon(Icons.camera_alt),
          title: const Text('Capture mode'),
          subtitle: Text(
            controller.captureMode == CaptureMode.auto
                ? 'Auto — captures after a short delay'
                : 'Manual — tap to capture',
          ),
          trailing: Switch(
            value: controller.captureMode == CaptureMode.manual,
            onChanged: (manual) {
              controller.captureMode =
                  manual ? CaptureMode.manual : CaptureMode.auto;
            },
          ),
        ),
        if (kDebugMode)
          ListTile(
            key: const Key('connection-diagnostics-action'),
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Connection diagnostics'),
            subtitle: const Text('Debug-only sanitized connection timeline'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => _DiagnosticsScreen(diagnostics: diagnostics),
              ),
            ),
          ),
        const ListTile(title: Text('JPEG quality'), subtitle: Text('82%')),
        const ListTile(
          title: Text('Long edge'),
          subtitle: Text('1280 px maximum'),
        ),
        const ListTile(
          title: Text('Retention'),
          subtitle: Text('In memory until session stop'),
        ),
        const ListTile(
          title: Text('Guidance'),
          subtitle: Text('Planned for Milestone 3'),
        ),
      ],
    ),
  );
}

@visibleForTesting
Future<void> handleChangeBackend(
  Future<void> Function() onChangeBackend,
  ConnectionDiagnostics diagnostics,
) async {
  try {
    await onChangeBackend();
  } catch (error) {
    diagnostics.record(
      ConnectionStage.readBackendConfiguration,
      'previous_session_cleanup_failed',
      message:
          'Backend setup opened after cleanup failed (${error.runtimeType}).',
    );
  }
}

final class _DiagnosticsScreen extends StatelessWidget {
  const _DiagnosticsScreen({required this.diagnostics});
  final ConnectionDiagnostics diagnostics;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Connection diagnostics'),
      actions: [
        IconButton(
          tooltip: 'Copy diagnostics',
          onPressed: () =>
              Clipboard.setData(ClipboardData(text: diagnostics.copyText)),
          icon: const Icon(Icons.copy),
        ),
      ],
    ),
    body: AnimatedBuilder(
      animation: diagnostics,
      builder: (context, _) => ListView.builder(
        itemCount: diagnostics.entries.length,
        itemBuilder: (context, index) => ListTile(
          title: Text(diagnostics.entries[index].stage.wireName),
          subtitle: Text(diagnostics.entries[index].summary),
        ),
      ),
    ),
  );
}
