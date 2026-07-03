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
    await tester.tap(find.text('Info'));
    await tester.pumpAndSettle();
    await shot(tester, '05-app-info');
  });
}
