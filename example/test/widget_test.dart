import 'package:debug_deck/debug_deck.dart';
import 'package:debug_deck_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Autopsy tab renders a graded diagnosis from seeded traffic', (
    tester,
  ) async {
    DebugTools.init(
      enabled: true,
      appInfo: const DebugAppInfo(
        version: 'test',
        environmentName: 'test',
        baseUrl: 'https://api.example.com',
        isNativeCall: false,
      ),
    );
    DebugLogger.instance.clear();
    seedDemoData();

    await tester.pumpWidget(const DemoApp());
    await tester.pumpAndSettle();

    // Open the floating debug overlay (the bug chip sits top-left). The chip
    // handles taps via a raw Listener, so the icon itself isn't the hit target.
    await tester.tap(
      find.byIcon(Icons.bug_report_rounded).first,
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    // Switch to the Autopsy tab.
    await tester.tap(find.text('Autopsy'));
    await tester.pumpAndSettle();

    // The report is present: findings header + the three subsystem scores.
    expect(find.text('FINDINGS'), findsOneWidget);
    expect(find.text('NETWORK'), findsOneWidget);
    expect(find.text('RENDERING'), findsOneWidget);
    expect(find.text('STABILITY'), findsOneWidget);

    // Seeded traffic includes a 500 + a platform error, so at least one
    // critical finding must surface.
    expect(find.byIcon(Icons.error_outline), findsWidgets);

    // Findings prescribe rather than restate metrics: the seeded 500 is
    // diagnosed as a server-side failure, not echoed as a "500" count.
    expect(
      find.text('Failures are server-side, not in the app'),
      findsOneWidget,
    );
  });
}
