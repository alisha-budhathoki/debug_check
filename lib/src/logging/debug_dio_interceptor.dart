import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:debug_deck/debug_deck.dart';

/// Dio interceptor that pushes every request/response/error into
/// [DebugLogger] with full detail (headers, query parameters, body). Only
/// attached when running in debug mode (see dio_config).
///
/// Lifecycle: `onRequest` logs an in-flight entry and stamps its id +
/// start-time into `options.extra`; `onResponse` / `onError` replace that
/// entry with the finalized success/error record.
class DebugDioInterceptor extends Interceptor {
  static const String _startKey = '_debug_started_at_us';
  static const String _idKey = '_debug_entry_id';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // No capture work at all outside a development environment.
    if (!DebugTools.enabled) {
      handler.next(options);
      return;
    }
    options.extra[_startKey] = DateTime.now().microsecondsSinceEpoch;
    final id = DebugLogger.instance.logApiInFlight(
      method: options.method,
      url: options.uri.toString(),
      queryParameters: _stringifyMap(options.queryParameters),
      requestHeaders: _stringifyMap(options.headers),
      requestBody: _bodyToString(options.data),
    );
    if (id != null) {
      options.extra[_idKey] = id;
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    if (!DebugTools.enabled) {
      handler.next(response);
      return;
    }
    final options = response.requestOptions;
    final responseBody = _bodyToString(response.data);
    DebugLogger.instance.completeApiSuccess(
      id: _idFrom(options),
      method: options.method,
      url: options.uri.toString(),
      statusCode: response.statusCode ?? 0,
      duration: _elapsed(options),
      queryParameters: _stringifyMap(options.queryParameters),
      requestHeaders: _stringifyMap(options.headers),
      responseHeaders: _stringifyHeaders(response.headers),
      requestBody: _bodyToString(options.data),
      responseBody: responseBody,
      responseBytes: _bodyBytes(response.data, response.headers),
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (!DebugTools.enabled) {
      handler.next(err);
      return;
    }
    final options = err.requestOptions;
    final responseBody = _bodyToString(err.response?.data);
    DebugLogger.instance.completeApiError(
      id: _idFrom(options),
      method: options.method,
      url: options.uri.toString(),
      statusCode: err.response?.statusCode,
      duration: _elapsed(options),
      queryParameters: _stringifyMap(options.queryParameters),
      requestHeaders: _stringifyMap(options.headers),
      responseHeaders:
          err.response != null
              ? _stringifyHeaders(err.response!.headers)
              : null,
      requestBody: _bodyToString(options.data),
      responseBody: responseBody,
      responseBytes: _bodyBytes(err.response?.data, err.response?.headers),
      errorMessage: '${err.type.name}: ${err.message ?? err.toString()}',
    );
    handler.next(err);
  }

  int? _idFrom(RequestOptions options) {
    final v = options.extra[_idKey];
    return v is int ? v : null;
  }

  Duration _elapsed(RequestOptions options) {
    final start = options.extra[_startKey];
    if (start is int) {
      final endUs = DateTime.now().microsecondsSinceEpoch;
      return Duration(microseconds: endUs - start);
    }
    return Duration.zero;
  }

  Map<String, String>? _stringifyMap(Map<String, dynamic>? source) {
    if (source == null || source.isEmpty) return null;
    return source.map((k, v) => MapEntry(k, _scalarToString(v)));
  }

  Map<String, String> _stringifyHeaders(Headers headers) {
    final result = <String, String>{};
    headers.forEach((name, values) {
      result[name] = values.join(', ');
    });
    return result;
  }

  String _scalarToString(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    if (v is List) return v.join(', ');
    return v.toString();
  }

  /// Actual payload size on the wire.
  ///
  /// Must not be derived from [_bodyToString]'s output: that string is
  /// pretty-printed with indentation (inflating a compact JSON payload well
  /// past its real size), is truncated at 20k chars, and renders a binary body
  /// as the literal text `<binary N bytes>` — which would report 19 bytes for a
  /// 4 MB download. This feeds the LARGE insight chip and the Autopsy's
  /// heavy-payload finding, so a wrong number here shows up as wrong advice.
  int? _bodyBytes(dynamic body, Headers? headers) {
    final declared = int.tryParse(headers?.value('content-length') ?? '');
    if (declared != null && declared >= 0) return declared;
    if (body == null) return null;
    if (body is List<int>) return body.length;
    try {
      if (body is String) return utf8.encode(body).length;
      if (body is Map || body is List) {
        return utf8.encode(jsonEncode(body)).length; // compact, not indented
      }
    } catch (_) {
      // Un-encodable body (cyclic, or a type jsonEncode rejects) — better to
      // report nothing than a fabricated size.
    }
    return null;
  }

  String? _bodyToString(dynamic body) {
    if (body == null) return null;
    if (body is String) return body;
    if (body is List<int>) return '<binary ${body.length} bytes>';
    if (body is FormData) {
      final fields = body.fields.map((f) => '${f.key}=${f.value}').join('&');
      final files = body.files
          .map(
            (f) =>
                '${f.key}=<file name=${f.value.filename ?? "?"} '
                'len=${f.value.length}>',
          )
          .join('&');
      return [fields, files].where((s) => s.isNotEmpty).join('&');
    }
    if (body is Map || body is List) {
      try {
        return const JsonEncoder.withIndent('  ').convert(body);
      } catch (_) {
        return body.toString();
      }
    }
    try {
      return body.toString();
    } catch (_) {
      return '<unprintable ${body.runtimeType}>';
    }
  }
}
