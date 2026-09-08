import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wearcam/ai/openai_realtime_provider.dart';
import 'package:wearcam/camera/phone_camera_source.dart';
import 'package:wearcam/config/backend_configuration.dart';
import 'package:wearcam/config/backend_url_store.dart';
import 'package:wearcam/conversation/conversation_controller.dart';
import 'package:wearcam/ui/wearcam_app.dart';

typedef WearCamConfiguredBuilder =
    Widget Function(
      BuildContext context,
      Uri backendBaseUri,
      Future<void> Function() changeBackend,
    );

final class WearCamBootstrap extends StatefulWidget {
  const WearCamBootstrap({
    required this.store,
    this.fallbackUrl = '',
    this.allowInsecureHttp = kDebugMode,
    this.configuredBuilder,
    super.key,
  });

  final BackendUrlStore store;
  final String fallbackUrl;
  final bool allowInsecureHttp;
  final WearCamConfiguredBuilder? configuredBuilder;

  @override
  State<WearCamBootstrap> createState() => _WearCamBootstrapState();
}

final class _WearCamBootstrapState extends State<WearCamBootstrap> {
  Uri? _backendBaseUri;
  String _setupValue = '';
  String? _loadError;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadConfiguration());
  }

  Future<void> _loadConfiguration() async {
    try {
      final savedUrl = await widget.store.read();
      if (!mounted) return;
      final selectedUrl = savedUrl?.trim().isNotEmpty ?? false
          ? savedUrl!
          : widget.fallbackUrl;
      final configuration = BackendConfiguration.fromUrl(
        selectedUrl,
        allowInsecureHttp: widget.allowInsecureHttp,
      );
      setState(() {
        _backendBaseUri = configuration.uri;
        _setupValue = selectedUrl;
        _loadError = configuration.isValid ? null : configuration.error;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'The saved backend URL could not be loaded.';
        _loading = false;
      });
    }
  }

  Future<String?> _save(String value) async {
    final configuration = BackendConfiguration.fromUrl(
      value,
      allowInsecureHttp: widget.allowInsecureHttp,
    );
    if (!configuration.isValid) return configuration.error;
    try {
      final normalizedUrl = configuration.uri.toString();
      await widget.store.write(normalizedUrl);
      if (!mounted) return null;
      setState(() {
        _backendBaseUri = configuration.uri;
        _setupValue = normalizedUrl;
        _loadError = null;
      });
      return null;
    } catch (_) {
      return 'The backend URL could not be saved on this device.';
    }
  }

  Future<void> _changeBackend() async {
    setState(() => _backendBaseUri = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    final backendBaseUri = _backendBaseUri;
    if (backendBaseUri == null) {
      return BackendSetupApp(
        initialValue: _setupValue,
        initialError: _loadError,
        onSave: _save,
      );
    }
    return (widget.configuredBuilder ?? _buildConfiguredApp)(
      context,
      backendBaseUri,
      _changeBackend,
    );
  }

  Widget _buildConfiguredApp(
    BuildContext context,
    Uri backendBaseUri,
    Future<void> Function() changeBackend,
  ) => _WearCamRuntime(
    key: ValueKey(backendBaseUri),
    backendBaseUri: backendBaseUri,
    changeBackend: changeBackend,
  );
}

final class BackendSetupApp extends StatelessWidget {
  const BackendSetupApp({
    required this.initialValue,
    required this.onSave,
    this.initialError,
    super.key,
  });

  final String initialValue;
  final String? initialError;
  final Future<String?> Function(String value) onSave;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'WearCam setup',
    theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
    home: _BackendSetupScreen(
      initialValue: initialValue,
      initialError: initialError,
      onSave: onSave,
    ),
  );
}

final class _BackendSetupScreen extends StatefulWidget {
  const _BackendSetupScreen({
    required this.initialValue,
    required this.onSave,
    this.initialError,
  });

  final String initialValue;
  final String? initialError;
  final Future<String?> Function(String value) onSave;

  @override
  State<_BackendSetupScreen> createState() => _BackendSetupScreenState();
}

final class _BackendSetupScreenState extends State<_BackendSetupScreen> {
  late final TextEditingController _controller;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _error = widget.initialError;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.onSave(_controller.text);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('WearCam backend setup')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.settings_ethernet, size: 48),
        const SizedBox(height: 16),
        Text(
          'Connect to your WearCam backend',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Enter only the backend base URL. WearCam stores it on this device '
          'and uses the backend to request temporary Realtime credentials.',
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('backend-url-field'),
          controller: _controller,
          enabled: !_saving,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: 'Backend base URL',
            hintText: 'https://wearcam.example.com',
            errorText: _error,
          ),
          onSubmitted: _saving ? null : (_) => _submit(),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('save-backend-button'),
          onPressed: _saving ? null : _submit,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: const Text('Save and continue'),
        ),
        const SizedBox(height: 16),
        const Text(
          'Do not enter a provider API key. Permanent provider credentials '
          'belong only in the backend environment and are never stored by '
          'the mobile app.',
        ),
      ],
    ),
  );
}

final class _WearCamRuntime extends StatefulWidget {
  const _WearCamRuntime({
    required this.backendBaseUri,
    required this.changeBackend,
    super.key,
  });

  final Uri backendBaseUri;
  final Future<void> Function() changeBackend;

  @override
  State<_WearCamRuntime> createState() => _WearCamRuntimeState();
}

final class _WearCamRuntimeState extends State<_WearCamRuntime> {
  late final PhoneCameraSource _camera;
  late final ConversationController _controller;

  @override
  void initState() {
    super.initState();
    _camera = PhoneCameraSource();
    _controller = ConversationController(
      camera: _camera,
      provider: OpenAIRealtimeProvider(backendBaseUri: widget.backendBaseUri),
    );
  }

  Future<void> _changeBackend() async {
    await _controller.stopEverything();
    await widget.changeBackend();
  }

  @override
  void dispose() {
    unawaited(_controller.stopEverything());
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WearCamApp(
    camera: _camera,
    controller: _controller,
    onChangeBackend: _changeBackend,
  );
}
