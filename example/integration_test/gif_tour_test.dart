import 'package:debug_deck/debug_deck.dart';
import 'package:debug_deck_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Drives the demo app through a paced tour meant to be screen-recorded into
/// the README's hero GIF. Unlike `screenshot_test.dart`, this one deliberately
/// spends real wall-clock time on each beat so the recording has frames to
/// show — `pumpAndSettle` alone would blink through the whole tour.
///
///   xcrun simctl io booted recordVideo --codec h264 tour.mov &
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/gif_tour_test.dart -d `simulator-id`
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Render every frame the scheduler asks for, not just the ones a test needs.
  // Without this the live binding coalesces frames and animations record as
  // jump cuts.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('hero tour', (tester) async {
    /// Holds the current screen for [ms] of real time, pumping frames so
    /// animations actually play out on the device being recorded.
    Future<void> beat([int ms = 1000]) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    /// A human-paced scroll — a single fling lands too fast to read.
    Future<void> drag(Finder target, double dy, {int steps = 30}) async {
      final gesture = await tester.startGesture(tester.getCenter(target));
      for (var i = 0; i < steps; i++) {
        await gesture.moveBy(Offset(0, dy / steps));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 16));
    }

    Future<void> tap(Finder f) async {
      await tester.tap(f.first);
      await tester.pump(const Duration(milliseconds: 16));
    }

    DebugTools.init(
      enabled: true,
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
    await beat(1200);

    // Fling the demo list first: gives the Perf tab real frame timings to
    // report later, and shows the overlay riding above a normal app.
    await drag(find.byType(ListView).first, -600, steps: 24);
    await beat(700);

    // 1. The floating bug chip opens the viewer.
    await tap(find.byIcon(Icons.bug_report_rounded));
    await beat(2000);

    // 2. The log list — badges, latency colours, the red Errors count.
    await drag(find.byType(ListView).first, -260, steps: 26);
    await beat(1600);

    // 3. A failing call in detail: insight chips (SERVER 500, SLOW).
    await tap(find.textContaining('orders/history', findRichText: true));
    await beat(2400);

    // 4. Its response body, then back to the list.
    await tap(find.text('Response'));
    await beat(1800);
    await tap(find.byIcon(Icons.arrow_back));
    await beat(1200);

    // 5. Search inside a response — every match highlighted, jump to next.
    await tap(find.textContaining('portfolio/holdings', findRichText: true));
    await beat(1200);
    await tap(find.text('Response'));
    await beat(800);
    final field = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Search response…',
    );
    await tester.enterText(field, 'symbol');
    await beat(1600);
    await tap(find.byTooltip('Next match'));
    await beat(1400);
    await tap(find.byIcon(Icons.arrow_back));
    await beat(1000);

    // 6. The headline feature: a graded verdict on the whole app.
    await tap(find.text('Autopsy'));
    await beat(2600);
    await drag(find.byType(ListView).first, -320, steps: 30);
    await beat(2200);

    // 7. Live performance, labelled with the screen it was measured on.
    await tap(find.text('Perf'));
    await beat(2600);

    // 8. The copyable app-info snapshot.
    await tap(find.text('App'));
    await beat(2200);
  });
}
