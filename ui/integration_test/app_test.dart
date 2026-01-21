import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:idm_open_ui/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Full App E2E Test', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    // 1. Wait for Core to Initialize (STATUS: ONLINE)
    // The text might initially say "STATUS: BOOTING..."
    // We poll for "STATUS: ONLINE" or "Engine ONLINE" log if visible.
    // In our UI, we have a Text widget showing 'STATUS: ...'
    
    // We'll give it up to 30 seconds to initialize
    bool isOnline = false;
    for (int i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.textContaining('STATUS: ONLINE').evaluate().isNotEmpty) {
        isOnline = true;
        break;
      }
    }
    expect(isOnline, isTrue, reason: "Core failed to initialize (Status not ONLINE)");

    // 2. Open Add Task Dialog
    final addButton = find.byIcon(Icons.add);
    expect(addButton, findsOneWidget);
    await tester.tap(addButton);
    await tester.pumpAndSettle();

    // 3. Verify Dialog Open
    expect(find.text('NEW TARGET'), findsOneWidget);

    // 4. Enter URL
    final urlField = find.widgetWithText(TextField, 'URL SOURCE');
    await tester.enterText(urlField, 'https://example.com/test.zip');
    await tester.pump();

    // 5. Tap Initiate
    final initiateBtn = find.text('INITIATE');
    await tester.tap(initiateBtn);
    // Use pump with duration instead of pumpAndSettle because Timer.periodic prevents settling
    await tester.pump(const Duration(seconds: 2));

    // 6. Verify Task Added to List
    // We look for the URL text in the list
    expect(find.text('https://example.com/test.zip'), findsOneWidget);
    
    // 7. Verify Status (Active/Queued)
    expect(find.textContaining('%'), findsOneWidget);

    // Clean up focus to avoid post-test FocusManager disposal assertions.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 200));
  });
}
