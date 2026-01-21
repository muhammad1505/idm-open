import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:idm_open_ui/main.dart' as app;

final IntegrationTestWidgetsFlutterBinding _binding =
    IntegrationTestWidgetsFlutterBinding.ensureInitialized();

Future<void> _pumpFor(
  WidgetTester tester,
  Duration total, {
  Duration step = const Duration(milliseconds: 200),
}) async {
  final end = DateTime.now().add(total);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(step);
  }
}

Future<void> _waitForFinder(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  expect(finder, findsOneWidget);
}

Future<void> _waitForGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isEmpty) {
      return;
    }
  }
  expect(finder, findsNothing);
}

void main() {
  _binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('Full App E2E Test', (tester) async {
    app.main();
    await tester.pump(const Duration(milliseconds: 200));

    // 1. Tunggu core ONLINE.
    await _waitForFinder(
      tester,
      find.textContaining('STATUS: ONLINE'),
      timeout: const Duration(seconds: 30),
    );

    // 2. Cek tombol refresh.
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump(const Duration(milliseconds: 200));

    // 3. Buka log dialog, cek judul, lalu tutup.
    await tester.tap(find.byIcon(Icons.bug_report));
    await _waitForFinder(tester, find.text('SYSTEM LOG'));
    expect(find.text('FACTORY RESET (FIX DB)'), findsOneWidget);
    final logDialog =
        find.ancestor(of: find.text('SYSTEM LOG'), matching: find.byType(Dialog));
    final logClose = find.descendant(
      of: logDialog,
      matching: find.byIcon(Icons.close),
    );
    await tester.tap(logClose.first);
    await _waitForGone(tester, find.text('SYSTEM LOG'));

    // 4. Buka dialog tambah task lalu ABORT.
    final addButton = find.text('New Download');
    expect(addButton, findsOneWidget);
    await tester.tap(addButton);
    await _waitForFinder(tester, find.text('NEW DOWNLOAD'));
    await tester.tap(find.text('CANCEL'));
    await _waitForGone(tester, find.text('NEW DOWNLOAD'));

    // 5. Tambah task.
    await tester.tap(addButton);
    await _waitForFinder(tester, find.text('NEW DOWNLOAD'));
    final url = 'https://example.com/test.zip';
    final urlField = find.widgetWithText(TextField, 'DOWNLOAD LINK');
    await tester.enterText(urlField, url);
    await tester.tap(find.text('ADD'));
    await _waitForFinder(tester, find.text(url), timeout: const Duration(seconds: 20));

    // 6. Buka detail task lalu tutup.
    await tester.tap(find.text(url));
    await _waitForFinder(tester, find.text('DATA LOG'));
    expect(find.textContaining('URL:'), findsOneWidget);
    expect(find.textContaining('DEST:'), findsOneWidget);
    await tester.tap(find.text('CLOSE'));
    await _waitForGone(tester, find.text('DATA LOG'));

    // 7. Cek tombol enqueue dan start.
    await tester.tap(find.text('Queue all'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Start next'));
    await tester.pump(const Duration(milliseconds: 200));

    // 8. Cek aksi task (pause/resume jika ada, stop, lalu delete).
    final taskCard =
        find.ancestor(of: find.text(url), matching: find.byType(GestureDetector));
    final pauseBtn =
        find.descendant(of: taskCard, matching: find.byIcon(Icons.pause));
    if (pauseBtn.evaluate().isNotEmpty) {
      await tester.tap(pauseBtn.first);
      await tester.pump(const Duration(milliseconds: 400));
    }
    final resumeBtn = find.descendant(
      of: taskCard,
      matching: find.byIcon(Icons.play_arrow),
    );
    if (resumeBtn.evaluate().isNotEmpty) {
      await tester.tap(resumeBtn.first);
      await tester.pump(const Duration(milliseconds: 400));
    }
    final stopBtn =
        find.descendant(of: taskCard, matching: find.byIcon(Icons.stop));
    expect(stopBtn, findsOneWidget);
    await tester.tap(stopBtn.first);
    await tester.pump(const Duration(milliseconds: 400));
    final deleteBtn = find.descendant(
      of: taskCard,
      matching: find.byIcon(Icons.delete_outline),
    );
    await tester.tap(deleteBtn.first);
    await _waitForGone(tester, find.text(url), timeout: const Duration(seconds: 20));

    // 9. Settings tab toggles.
    await tester.tap(find.text('Settings'));
    await _waitForFinder(tester, find.text('Smart download'));
    await tester.tap(find.text('Smart download'));
    await tester.pump(const Duration(milliseconds: 200));

    // 10. Browser tab basic presence.
    await tester.tap(find.text('Browser'));
    await _waitForFinder(tester, find.text('Search or paste download link'));

    // 11. Back to downloads.
    await tester.tap(find.text('Downloads'));
    await _waitForFinder(tester, find.textContaining('STATUS:'));

    // 9. Uji factory reset dari log dialog.
    await tester.tap(find.byIcon(Icons.bug_report));
    await _waitForFinder(tester, find.text('SYSTEM LOG'));
    await tester.tap(find.text('FACTORY RESET (FIX DB)'));
    await _pumpFor(tester, const Duration(seconds: 2));
    await _waitForFinder(
      tester,
      find.textContaining('STATUS: ONLINE'),
      timeout: const Duration(seconds: 30),
    );

    // Clean up focus to avoid post-test FocusManager disposal assertions.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 200));
  });
}
