import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:wearcam/camera/phone_camera_source.dart';
import 'package:wearcam/conversation/conversation_controller.dart';
import 'package:wearcam/domain/ai_provider.dart';
import 'package:wearcam/domain/vision_mode.dart';

final class WearCamApp extends StatelessWidget {
  const WearCamApp({
    required this.camera,
    required this.controller,
    super.key,
  });
  final PhoneCameraSource camera;
  final ConversationController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'WearCam',
    theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
    home: WearCamHome(camera: camera, controller: controller),
  );
}

final class WearCamHome extends StatefulWidget {
  const WearCamHome({
    required this.camera,
    required this.controller,
    super.key,
  });
  final PhoneCameraSource camera;
  final ConversationController controller;

  @override
  State<WearCamHome> createState() => _WearCamHomeState();
}

final class _WearCamHomeState extends State<WearCamHome> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      _Home(controller: widget.controller),
      _Camera(camera: widget.camera),
      _Conversation(controller: widget.controller),
      const _Settings(),
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
          title: const Text('Vision mode'),
          subtitle: Text(controller.visionModes.mode.name),
        ),
        FilledButton.icon(
          onPressed:
              controller.connectionState == AIConnectionState.disconnected
                  ? controller.start
                  : null,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start visual conversation'),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: controller.visionModes.mode == VisionMode.off
              ? null
              : controller.stopLooking,
          icon: const Icon(Icons.visibility_off),
          label: const Text('Stop looking'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: controller.stopEverything,
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('Stop everything'),
        ),
        if (controller.error != null)
          Text(
            controller.error!,
            style: const TextStyle(color: Colors.red),
          ),
      ],
    ),
  );
}

final class _Camera extends StatelessWidget {
  const _Camera({required this.camera});
  final PhoneCameraSource camera;
  @override
  Widget build(BuildContext context) {
    final controller = camera.controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: Text('Start a conversation to connect the rear camera.'),
      );
    }
    return Column(
      children: [
        const MaterialBanner(
          content: Text(
            'Local preview only — preview video is never uploaded.',
          ),
          actions: [SizedBox.shrink()],
        ),
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: CameraPreview(controller),
            ),
          ),
        ),
      ],
    );
  }
}

final class _Conversation extends StatelessWidget {
  const _Conversation({required this.controller});
  final ConversationController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final frame = controller.lastTransmittedFrame;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (controller.visionModes.mode != VisionMode.off)
            const Card(
              child: ListTile(
                leading: Icon(Icons.visibility, color: Colors.green),
                title: Text('Visual mode active'),
              ),
            ),
          Text('Transcript', style: Theme.of(context).textTheme.titleLarge),
          SelectableText(
            controller.transcript.isEmpty
                ? 'Waiting for speech…'
                : controller.transcript,
          ),
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
            icon: Icon(
              controller.microphoneMuted ? Icons.mic_off : Icons.mic,
            ),
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

final class _Settings extends StatelessWidget {
  const _Settings();
  @override
  Widget build(BuildContext context) => ListView(
    children: const [
      ListTile(title: Text('Provider'), subtitle: Text('OpenAI Realtime')),
      ListTile(title: Text('JPEG quality'), subtitle: Text('82%')),
      ListTile(title: Text('Long edge'), subtitle: Text('1280 px maximum')),
      ListTile(
        title: Text('Retention'),
        subtitle: Text('In memory until session stop'),
      ),
      ListTile(
        title: Text('Guidance'),
        subtitle: Text('Planned for Milestone 3'),
      ),
    ],
  );
}
