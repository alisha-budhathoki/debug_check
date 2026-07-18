import 'package:debug_deck/debug_deck.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opens the deck by tapping the floating chip and returns just after the 420ms
/// reveal completes. Deliberately NOT pumpAndSettle: settling would fast-forward
/// through the whole error pulse, so no test could ever observe the glow.
Future<void> _openDeck(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: Stack(children: [DebugOverlay()]))),
  );
  await tester.pump();
  // warnIfMissed: the chip's gesture handling lives on an ancestor Listener,
  // so the icon's own centre isn't the hit-test target — the tap still lands.
  await tester.tap(find.byIcon(Icons.bug_report_rounded), warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 600));
}

/// The Errors segment's own AnimatedContainer — the widget carrying the tint.
Finder _errorsSegmentBox() => find.ancestor(
  of: find.text('Errors'),
  matching: find.byType(AnimatedContainer),
);

void main() {
  setUp(() {
    DebugTools.setEnabled(true);
    DebugLogger.instance.clear();
  });

  testWidgets('no errors: no badge, no red tint on the Errors tab', (
    tester,
  ) async {
    DebugLogger.instance.logInfo('hello');
    await _openDeck(tester);

    expect(find.text('Errors'), findsOneWidget);

    final box = tester.widget<AnimatedContainer>(_errorsSegmentBox().first);
    final deco = box.decoration! as BoxDecoration;
    // Unselected + no errors → transparent, exactly like every other tab.
    expect(deco.color, Colors.transparent);
    expect(deco.border, isNull);
  });

  testWidgets('errors present: tab turns light red and shows the count', (
    tester,
  ) async {
    for (var i = 0; i < 3; i++) {
      DebugLogger.instance.logPlatformError('boom $i', StackTrace.current);
    }
    DebugLogger.instance.logInfo('not an error');
    await _openDeck(tester);

    final box = tester.widget<AnimatedContainer>(_errorsSegmentBox().first);
    final deco = box.decoration! as BoxDecoration;
    expect(deco.color, const Color(0xFF2B1518));
    // Critically: an unselected alerting tab must stay flat. A border or
    // shadow here would make the control look like it has two selected tabs.
    expect(deco.border, isNull);
    expect(deco.boxShadow, isNull);

    // The badge counts errors only — the info log must not be included.
    expect(
      find.descendant(of: _errorsSegmentBox().first, matching: find.text('3')),
      findsOneWidget,
    );
  });

  testWidgets('badge caps at 99+', (tester) async {
    for (var i = 0; i < 140; i++) {
      DebugLogger.instance.logPlatformError('boom $i', StackTrace.current);
    }
    await _openDeck(tester);

    expect(
      find.descendant(
        of: _errorsSegmentBox().first,
        matching: find.text('99+'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('badge updates live as new errors arrive', (tester) async {
    DebugLogger.instance.logPlatformError('first', StackTrace.current);
    await _openDeck(tester);
    expect(
      find.descendant(of: _errorsSegmentBox().first, matching: find.text('1')),
      findsOneWidget,
    );

    DebugLogger.instance.logPlatformError('second', StackTrace.current);
    await tester.pump();
    await tester.pump();
    expect(
      find.descendant(of: _errorsSegmentBox().first, matching: find.text('2')),
      findsOneWidget,
    );
  });

  testWidgets('errors glow on open, then settle to a calm tint', (
    tester,
  ) async {
    DebugLogger.instance.logPlatformError('boom', StackTrace.current);
    await _openDeck(tester);
    // It visibly breathes during the first couple of seconds.
    expect(
      await _peakGlow(tester, const Duration(seconds: 2)),
      greaterThan(0.3),
    );

    // 4 cycles at 1150ms reversing ≈ 9.2s; well past that it must go quiet, or
    // a permanently-throbbing tab becomes noise the user learns to ignore.
    await tester.pump(const Duration(seconds: 12));
    expect(await _peakGlow(tester, const Duration(seconds: 3)), 0.0);
  });

  testWidgets('selecting the Errors tab stops the pulse immediately', (
    tester,
  ) async {
    DebugLogger.instance.logPlatformError('boom', StackTrace.current);
    await _openDeck(tester);
    expect(
      await _peakGlow(tester, const Duration(seconds: 2)),
      greaterThan(0.3),
    );

    await tester.tap(find.text('Errors'));
    await tester.pumpAndSettle();
    // Selecting the tab drops the glow wrapper entirely — not merely animates
    // it to zero — so there is nothing left that could resume pulsing.
    expect(find.byKey(const Key('debugDeck.errorTabGlow')), findsNothing);
  });
}

/// Current alpha of the pulsing glow behind the Errors segment. Keyed, because
/// AnimatedContainer builds its own DecoratedBox and a type finder hits that
/// one first.
double _glowAlpha(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find.byKey(const Key('debugDeck.errorTabGlow')),
  );
  final shadows = (box.decoration as BoxDecoration).boxShadow!;
  return shadows.single.color.a;
}

/// Peak glow across a window. Sampling a window rather than one instant keeps
/// the assertion about *whether it pulses* instead of what phase it happens to
/// be in at an arbitrary millisecond.
Future<double> _peakGlow(WidgetTester tester, Duration window) async {
  var peak = 0.0;
  const step = Duration(milliseconds: 50);
  for (var t = Duration.zero; t < window; t += step) {
    await tester.pump(step);
    peak = peak > _glowAlpha(tester) ? peak : _glowAlpha(tester);
  }
  return peak;
}
