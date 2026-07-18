import 'package:debug_deck/debug_deck.dart';
import 'package:debug_deck_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives the real demo app to the Headers tab of a seeded call.
Future<void> _openHeaders(WidgetTester tester) async {
  await tester.pumpWidget(const DemoApp());
  await tester.pumpAndSettle();

  await tester.tap(
    find.byIcon(Icons.bug_report_rounded).first,
    warnIfMissed: false, // gestures live on an ancestor Listener
  );
  // Incremental frames: the reveal animation needs real ticks, and a single
  // large pump lands mid-clip with nothing painted.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }

  // The newest rows are at the top; the oldest seeded call is off-screen.
  await tester.tap(
    find.textContaining('quotes/UNKNOWN', findRichText: true).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Headers'));
  await tester.pumpAndSettle();
}

String? _authHeaderOnScreen(WidgetTester tester) {
  for (final w in tester.widgetList<SelectableText>(
    find.byType(SelectableText),
  )) {
    final text = w.textSpan?.toPlainText() ?? w.data ?? '';
    if (text.toLowerCase().startsWith('authorization')) return text;
  }
  return null;
}

void main() {
  setUp(() {
    // Mirror main()'s configuration; DemoApp itself doesn't call init.
    DebugTools.init(
      enabled: true,
      redaction: DebugRedaction.standard(mode: RedactionMode.hide),
    );
    DebugTools.revealSecrets.value = false;
    DebugLogger.instance.clear();
    seedDemoData();
  });

  tearDown(() {
    DebugTools.revealSecrets.value = false;
    DebugTools.redaction = DebugRedaction.standard();
  });

  testWidgets('the example masks by default and reveals on tap', (
    tester,
  ) async {
    await _openHeaders(tester);

    final masked = _authHeaderOnScreen(tester);
    expect(masked, isNotNull, reason: 'Authorization row should be rendered');
    expect(masked, contains('••••'));
    expect(masked, isNot(contains('eyJhbGciOiJIUzI1Ni')));

    // The eye toggle only exists because the example opted into hide mode.
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();

    final revealed = _authHeaderOnScreen(tester);
    expect(revealed, contains('eyJhbGciOiJIUzI1Ni.demo.token'));

    // And back again — revealing is reversible, not a one-way door.
    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pumpAndSettle();
    expect(_authHeaderOnScreen(tester), contains('••••'));
  });

  testWidgets('revealing also changes what the cURL export carries', (
    tester,
  ) async {
    await _openHeaders(tester);

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );

    await tester.tap(find.byTooltip('Copy as cURL'));
    await tester.pumpAndSettle();
    expect(copied, contains('••••'));
    expect(copied, isNot(contains('eyJhbGciOiJIUzI1Ni')));

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Copy as cURL'));
    await tester.pumpAndSettle();
    // The screen and the export must never disagree about what is hidden.
    expect(copied, contains('eyJhbGciOiJIUzI1Ni.demo.token'));
  });
}
