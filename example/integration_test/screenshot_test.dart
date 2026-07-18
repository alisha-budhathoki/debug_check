import 'package:debug_deck/debug_deck.dart';
import 'package:debug_deck_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Drives the demo app and captures one clean screenshot per debug_deck feature.
/// Run with:
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/screenshot_test.dart -d emulator-5554
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> boot(WidgetTester tester) async {
    DebugTools.init(
      enabled: true,
      // Same config as the demo's main(), so the redaction shots show what a
      // reader running `flutter run` will actually see.
      redaction: DebugRedaction.standard(mode: RedactionMode.hide),
      appInfo: const DebugAppInfo(
        version: '1.0.0 (42)',
        environmentName: 'staging',
        baseUrl: 'https://api.tradingapp.dev',
        isNativeCall: false,
      ),
    );
    DebugLogger.instance.clear();
    seedDemoData();
    await tester.pumpWidget(const DemoApp());
    await tester.pumpAndSettle();
  }

  Future<void> openViewer(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.bug_report_rounded).first);
    await tester.pumpAndSettle();
  }

  /// Settles by fixed frames instead of pumpAndSettle.
  ///
  /// The sheet openers await showModalBottomSheet, and the Errors tab runs a
  /// repeating pulse, so under the live binding pumpAndSettle spins past the
  /// end of the test instead of returning.
  Future<void> settleFrames(WidgetTester tester, [int frames = 30]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> shotRaw(WidgetTester tester, String name) async {
    try {
      await binding.convertFlutterSurfaceToImage();
    } catch (_) {
      // Already converted for this surface — fine.
    }
    await settleFrames(tester, 10);
    await binding.takeScreenshot(name);
  }

  Future<void> shot(WidgetTester tester, String name) async {
    try {
      await binding.convertFlutterSurfaceToImage();
    } catch (_) {
      // Already converted for this surface — fine.
    }
    await tester.pumpAndSettle();
    await binding.takeScreenshot(name);
  }

  testWidgets('01 log list', (tester) async {
    await boot(tester);
    await openViewer(tester);
    await shot(tester, '01-log-list');
  });

  testWidgets('02 api detail + insight chips', (tester) async {
    await boot(tester);
    await openViewer(tester);
    await tester.tap(
      find.textContaining('orders/history', findRichText: true).first,
    );
    await tester.pumpAndSettle();
    await shot(tester, '02-api-detail');
  });

  testWidgets('03 search inside response', (tester) async {
    await boot(tester);
    await openViewer(tester);
    await tester.tap(
      find.textContaining('portfolio/holdings', findRichText: true).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Response'));
    await tester.pumpAndSettle();
    final field = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Search response…',
    );
    await tester.enterText(field, 'symbol');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next match'));
    await tester.pumpAndSettle();
    await shot(tester, '03-search-response');
  });

  testWidgets('04 performance', (tester) async {
    await boot(tester);
    // Generate some frames so the perf panel has data.
    for (var i = 0; i < 3; i++) {
      await tester.fling(
        find.byType(ListView).first,
        const Offset(0, -500),
        1200,
      );
      await tester.pumpAndSettle();
    }
    await openViewer(tester);
    await tester.tap(find.text('Perf'));
    await tester.pumpAndSettle();
    await shot(tester, '04-performance');
  });

  testWidgets('05 app info', (tester) async {
    await boot(tester);
    await openViewer(tester);
    // Renamed from 'Info': DebugLogKind.info is what breadcrumbs are, and the
    // panel owning that id is why breadcrumbs had no filter of their own.
    await tester.tap(find.text('App'));
    await tester.pumpAndSettle();
    await shot(tester, '05-app-info');
  });

  testWidgets('06 secrets masked, revealable', (tester) async {
    await boot(tester);
    await openViewer(tester);
    await tester.tap(
      find.textContaining('quotes/UNKNOWN', findRichText: true).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Headers'));
    await tester.pumpAndSettle();
    await shot(tester, '06-secrets-masked');

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();
    await shot(tester, '07-secrets-revealed');
  });

  // NOTE: the filter and session-export sheets are not captured here.
  // Their openers await showModalBottomSheet, and under the live integration
  // binding that pending future keeps pumping after the test body ends
  // ("inTest is not true"), which then corrupts the following test. They are
  // covered by widget tests instead; capture them by hand if needed.

  testWidgets('10 pinned row survives eviction', (tester) async {
    await boot(tester);
    await openViewer(tester);
    await tester.longPress(
      find.textContaining('quotes/UNKNOWN', findRichText: true).first,
    );
    await tester.pumpAndSettle();
    await shot(tester, '10-pinned');
  });
}
