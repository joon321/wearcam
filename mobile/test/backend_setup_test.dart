import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wearcam/config/backend_url_store.dart';
import 'package:wearcam/ui/wearcam_bootstrap.dart';

void main() {
  testWidgets('shows setup when saved and fallback URLs are absent', (
    tester,
  ) async {
    await tester.pumpWidget(WearCamBootstrap(store: _MemoryStore()));
    await tester.pumpAndSettle();

    expect(find.text('WearCam backend setup'), findsOneWidget);
    expect(find.byKey(const Key('backend-url-field')), findsOneWidget);
    expect(
      find.textContaining('Do not enter a provider API key'),
      findsOneWidget,
    );
  });

  testWidgets('prefers the saved URL over the dart-define fallback', (
    tester,
  ) async {
    Uri? selected;
    await tester.pumpWidget(
      WearCamBootstrap(
        store: _MemoryStore('https://saved.example.com'),
        fallbackUrl: 'https://fallback.example.com',
        configuredBuilder: (context, uri, changeBackend) {
          selected = uri;
          return const MaterialApp(home: Text('configured'));
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(selected, Uri.parse('https://saved.example.com'));
  });

  testWidgets('uses the fallback when no URL has been saved', (tester) async {
    Uri? selected;
    await tester.pumpWidget(
      WearCamBootstrap(
        store: _MemoryStore(),
        fallbackUrl: 'https://fallback.example.com',
        configuredBuilder: (context, uri, changeBackend) {
          selected = uri;
          return const MaterialApp(home: Text('configured'));
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(selected, Uri.parse('https://fallback.example.com'));
  });

  testWidgets('validates and persists an entered URL', (tester) async {
    final store = _MemoryStore();
    await tester.pumpWidget(
      WearCamBootstrap(
        store: store,
        configuredBuilder: (context, uri, changeBackend) =>
            MaterialApp(home: Text(uri.toString())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('backend-url-field')),
      '  https://wearcam.example.com  ',
    );
    await tester.tap(find.byKey(const Key('save-backend-button')));
    await tester.pumpAndSettle();

    expect(store.value, 'https://wearcam.example.com');
    expect(find.text('https://wearcam.example.com'), findsOneWidget);
  });

  testWidgets('change backend returns to setup with the saved URL', (
    tester,
  ) async {
    await tester.pumpWidget(
      WearCamBootstrap(
        store: _MemoryStore('https://wearcam.example.com'),
        configuredBuilder: (context, uri, changeBackend) => MaterialApp(
          home: TextButton(
            onPressed: changeBackend,
            child: const Text('Change backend'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change backend'));
    await tester.pumpAndSettle();

    expect(find.text('WearCam backend setup'), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(const Key('backend-url-field')),
    );
    expect(field.controller!.text, 'https://wearcam.example.com');
  });

  testWidgets('release policy rejects HTTP URLs', (tester) async {
    await tester.pumpWidget(
      WearCamBootstrap(store: _MemoryStore(), allowInsecureHttp: false),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('backend-url-field')),
      'http://192.168.1.20:8787',
    );
    await tester.tap(find.byKey(const Key('save-backend-button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('HTTP is debug-only'), findsOneWidget);
  });
}

final class _MemoryStore implements BackendUrlStore {
  _MemoryStore([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String url) async {
    value = url;
  }
}
