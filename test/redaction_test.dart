import 'dart:convert';

import 'package:debug_deck/debug_deck.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// The logger coalesces publishes through `scheduleMicrotask`, so a read taken
/// in the same synchronous turn as the write still sees the previous list.
Future<List<DebugLogEntry>> _flushed() async {
  await Future<void>.delayed(Duration.zero);
  return DebugLogger.instance.entries.value;
}

void main() {
  setUp(() {
    DebugTools.redaction = DebugRedaction.standard();
    DebugTools.setEnabled(true);
    DebugLogger.instance.clear();
  });

  group('DebugRedaction.mask', () {
    const r = DebugRedaction(keys: {'authorization'});

    test('keeps the auth scheme so Basic-vs-Bearer bugs stay visible', () {
      expect(r.mask('Bearer abcdefghijklmnop'), 'Bearer ••••mnop');
      expect(r.mask('Basic dXNlcjpwYXNzd29yZA=='), 'Basic ••••ZA==');
    });

    test('keeps a 4-char tail so two tokens can be told apart', () {
      expect(r.mask('abcdefghijklmnop'), '••••mnop');
      expect(r.mask('abcdefghijklZZZZ'), '••••ZZZZ');
    });

    test('reveals nothing from a short secret', () {
      // 4 of 8 characters would be a meaningful fraction of the secret.
      expect(r.mask('short123'), '••••');
      expect(r.mask('a'), '••••');
    });

    test('leaves empty values alone', () => expect(r.mask(''), ''));
  });

  group('DebugRedaction.apply', () {
    test('masks known keys case-insensitively, leaves others intact', () {
      final out = DebugRedaction.standard().apply({
        'AUTHORIZATION': 'Bearer abcdefghijklmnop',
        'Cookie': 'session=abcdefghijklmnop',
        'Accept': 'application/json',
      });
      expect(out!['AUTHORIZATION'], 'Bearer ••••mnop');
      expect(out['Cookie'], '••••mnop');
      expect(out['Accept'], 'application/json', reason: 'not sensitive');
    });

    test('returns the same instance when nothing matched', () {
      const input = {'Accept': 'application/json'};
      expect(identical(DebugRedaction.standard().apply(input), input), isTrue);
    });

    test('also/except adjust the default policy', () {
      final also = DebugRedaction.standard(also: {'x-tenant-sig'});
      expect(
        also.apply({'x-tenant-sig': 'abcdefghijklmnop'})!['x-tenant-sig'],
        '••••mnop',
      );

      final except = DebugRedaction.standard(except: {'authorization'});
      expect(
        except.apply({
          'authorization': 'Bearer abcdefghijklmnop',
        })!['authorization'],
        'Bearer abcdefghijklmnop',
      );
    });

    test('disabled masks nothing', () {
      const secret = {'authorization': 'Bearer abcdefghijklmnop'};
      expect(DebugRedaction.disabled.apply(secret), secret);
    });
  });

  group('capture-time masking', () {
    test('secrets never enter the buffer at all', () async {
      DebugLogger.instance.completeApiSuccess(
        id: null,
        method: 'GET',
        url: 'https://api.example.com/me',
        statusCode: 200,
        duration: const Duration(milliseconds: 10),
        requestHeaders: const {
          'Authorization': 'Bearer supersecrettoken123',
          'Accept': 'application/json',
        },
        responseHeaders: const {'set-cookie': 'sid=supersecrettoken123'},
        queryParameters: const {'api_key': 'supersecrettoken123'},
      );

      final e = (await _flushed()).single;
      // The strong guarantee: not merely hidden at export — absent from memory,
      // so no future export surface, screenshot or shoulder can leak it.
      expect(e.requestHeaders!['Authorization'], 'Bearer ••••n123');
      expect(e.responseHeaders!['set-cookie'], '••••n123');
      expect(e.requestHeaders!['Accept'], 'application/json');
      expect(
        e.toString().contains('supersecrettoken123'),
        isFalse,
        reason: 'no field anywhere on the entry should hold the raw secret',
      );
    });

    test('query-param secrets are masked too', () async {
      DebugLogger.instance.completeApiSuccess(
        id: null,
        method: 'GET',
        url: 'https://api.example.com/search',
        statusCode: 200,
        duration: const Duration(milliseconds: 5),
        queryParameters: const {
          'access_token': 'supersecrettoken123',
          'q': 'shoes',
        },
      );
      final e = (await _flushed()).single;
      expect(e.queryParameters!['access_token'], '••••n123');
      expect(e.queryParameters!['q'], 'shoes');
    });

    test('opting out preserves raw values', () async {
      DebugTools.redaction = DebugRedaction.disabled;
      DebugLogger.instance.completeApiSuccess(
        id: null,
        method: 'GET',
        url: 'https://api.example.com/me',
        statusCode: 200,
        duration: const Duration(milliseconds: 10),
        requestHeaders: const {'Authorization': 'Bearer supersecrettoken123'},
      );
      expect(
        (await _flushed()).single.requestHeaders!['Authorization'],
        'Bearer supersecrettoken123',
      );
    });
  });

  group('DebugDioInterceptor reports true payload size', () {
    late DebugDioInterceptor interceptor;
    RequestOptions opts() =>
        RequestOptions(path: '/x', method: 'GET', baseUrl: 'https://e.com');

    setUp(() => interceptor = DebugDioInterceptor());

    Future<DebugLogEntry> capture(dynamic data, {Headers? headers}) async {
      final o = opts();
      interceptor.onRequest(o, RequestInterceptorHandler());
      interceptor.onResponse(
        Response<dynamic>(
          requestOptions: o,
          statusCode: 200,
          data: data,
          headers: headers ?? Headers(),
        ),
        ResponseInterceptorHandler(),
      );
      return (await _flushed()).last;
    }

    test(
      'a binary body reports its real length, not the placeholder text',
      () async {
        final e = await capture(List<int>.filled(4096, 0));
        // The old code measured '<binary 4096 bytes>'.length == 19.
        expect(e.responseBytes, 4096);
      },
    );

    test('a JSON body is measured compact, not pretty-printed', () async {
      final body = {'a': 1, 'b': 2, 'c': 3};
      final e = await capture(body);
      final compact = jsonEncode(body).length; // 19
      final indented = const JsonEncoder.withIndent('  ').convert(body).length;
      expect(indented, greaterThan(compact), reason: 'guards the premise');
      expect(e.responseBytes, compact);
      expect(
        e.responseBytes,
        isNot(indented),
        reason: 'indentation is a display concern, not payload size',
      );
    });

    test('content-length wins when the server declares it', () async {
      final h = Headers()..set('content-length', '98765');
      final e = await capture({'a': 1}, headers: h);
      expect(e.responseBytes, 98765);
    });

    test('reports nothing rather than a fabricated size', () async {
      final e = await capture(null);
      expect(e.responseBytes, isNull);
    });
  });

  group('reveal preference (RedactionMode.hide)', () {
    setUp(() {
      DebugTools.redaction = DebugRedaction.standard(mode: RedactionMode.hide);
      DebugTools.revealSecrets.value = false;
      DebugLogger.instance.clear();
    });

    tearDown(() {
      DebugTools.redaction = DebugRedaction.standard();
      DebugTools.revealSecrets.value = false;
    });

    Future<DebugLogEntry> seed() async {
      DebugLogger.instance.completeApiSuccess(
        id: null,
        method: 'GET',
        url: 'https://api.example.com/me',
        statusCode: 200,
        duration: const Duration(milliseconds: 10),
        requestHeaders: const {'Authorization': 'Bearer supersecrettoken123'},
      );
      return (await _flushed()).single;
    }

    test('hide retains the raw value so it CAN be revealed', () async {
      final e = await seed();
      // Contrast with drop mode, where the buffer holds only the mask.
      expect(e.requestHeaders!['Authorization'], 'Bearer supersecrettoken123');
    });

    test('masked by default, real once the user opts in', () async {
      final e = await seed();
      expect(
        DebugTools.visible(e.requestHeaders)!['Authorization'],
        'Bearer ••••n123',
      );

      DebugTools.revealSecrets.value = true;
      expect(
        DebugTools.visible(e.requestHeaders)!['Authorization'],
        'Bearer supersecrettoken123',
      );

      DebugTools.revealSecrets.value = false;
      expect(
        DebugTools.visible(e.requestHeaders)!['Authorization'],
        'Bearer ••••n123',
      );
    });

    test('drop mode ignores the toggle — nothing survives to reveal', () async {
      DebugTools.redaction = DebugRedaction.standard();
      final e = await seed();
      DebugTools.revealSecrets.value = true;
      expect(
        DebugTools.visible(e.requestHeaders)!['Authorization'],
        'Bearer ••••n123',
        reason: 'the raw value was discarded at capture',
      );
    });

    test('reveal defaults to off so it is always a deliberate act', () {
      expect(DebugTools.revealSecrets.value, isFalse);
      expect(DebugRedaction.standard().mode, RedactionMode.drop);
      expect(DebugRedaction.standard().canReveal, isFalse);
    });
  });
}
