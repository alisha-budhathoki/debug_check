import 'package:debug_deck/debug_deck.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Seeds one fully-populated API call — query, both header maps, and both
/// bodies — so every copyable section on every tab has real content.
void _seedCall() {
  DebugLogger.instance.completeApiSuccess(
    id: null,
    method: 'GET',
    url: 'https://api.example.com/v1/orders?status=open&limit=20',
    statusCode: 200,
    duration: const Duration(milliseconds: 128),
    queryParameters: const {'status': 'open', 'limit': '20'},
    requestHeaders: const {
      'Authorization': 'Bearer tok_123',
      'Accept': 'application/json',
    },
    responseHeaders: const {
      'content-type': 'application/json',
      'x-request-id': 'req_abc',
    },
    requestBody: '{"filter":"open"}',
    responseBody: '{"orders":[]}',
    responseBytes: 512,
  );
}

Future<void> _openDetail(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: Stack(children: [DebugOverlay()]))),
  );
  await tester.pump();
  await tester.tap(find.byIcon(Icons.bug_report_rounded), warnIfMissed: false);
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('orders', findRichText: true).first);
  await tester.pumpAndSettle();
}

/// Taps a copy button inside the named section and returns what landed on the
/// clipboard. Scoping to the section matters — several sections render a
/// button labelled 'Copy'.
Future<String?> _copyFromSection(
  WidgetTester tester,
  String sectionTitle,
  String buttonLabel,
) async {
  String? captured;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        captured = (call.arguments as Map)['text'] as String?;
      }
      return null;
    },
  );
  final section = find.ancestor(
    of: find.textContaining(sectionTitle.toUpperCase()),
    matching: find.byType(Column),
  );
  await tester.tap(
    find.descendant(of: section.first, matching: find.text(buttonLabel)).first,
  );
  await tester.pumpAndSettle();
  return captured;
}

void main() {
  setUp(() {
    DebugTools.setEnabled(true);
    DebugLogger.instance.clear();
    _seedCall();
  });

  testWidgets(
    'Request tab copies query params as lines and as a query string',
    (tester) async {
      await _openDetail(tester);
      await tester.tap(find.text('Request'));
      await tester.pumpAndSettle();

      expect(
        await _copyFromSection(tester, 'Query parameters', 'Copy'),
        'status: open\nlimit: 20',
      );
      expect(
        await _copyFromSection(tester, 'Query parameters', 'Query'),
        'status=open&limit=20',
      );
    },
  );

  testWidgets('Request tab copies the request body', (tester) async {
    await _openDetail(tester);
    await tester.tap(find.text('Request'));
    await tester.pumpAndSettle();

    expect(
      await _copyFromSection(tester, 'Request body', 'Copy'),
      '{"filter":"open"}',
    );
  });

  testWidgets('Headers tab copies each block in wire format', (tester) async {
    await _openDetail(tester);
    await tester.tap(find.text('Headers'));
    await tester.pumpAndSettle();

    expect(
      await _copyFromSection(tester, 'Request headers', 'Copy'),
      'Authorization: Bearer tok_123\nAccept: application/json',
    );
    expect(
      await _copyFromSection(tester, 'Response headers', 'Copy'),
      'content-type: application/json\nx-request-id: req_abc',
    );
  });

  testWidgets('Headers tab copies both blocks together', (tester) async {
    await _openDetail(tester);
    await tester.tap(find.text('Headers'));
    await tester.pumpAndSettle();

    expect(
      await _copyFromSection(tester, 'Request headers', 'All'),
      '# Request headers\n'
      'Authorization: Bearer tok_123\nAccept: application/json\n\n'
      '# Response headers\n'
      'content-type: application/json\nx-request-id: req_abc',
    );
  });

  testWidgets('Response tab copies status summary and body', (tester) async {
    await _openDetail(tester);
    await tester.tap(find.text('Response'));
    await tester.pumpAndSettle();

    expect(
      await _copyFromSection(tester, 'Status', 'Copy'),
      'Status: 200 OK\nDuration: 128 ms\nSize: 512B',
    );
    expect(
      await _copyFromSection(tester, 'Response body', 'Copy'),
      '{"orders":[]}',
    );
  });
}
