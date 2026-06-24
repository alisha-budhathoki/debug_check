part of 'debug_overlay.dart';

Color _kindColor(DebugLogKind k) {
  switch (k) {
    case DebugLogKind.flutterError:
      return const Color(0xFFE5C07B);
    case DebugLogKind.platformError:
      return const Color(0xFFE06C75);
    case DebugLogKind.info:
      return const Color(0xFF61AFEF);
    case DebugLogKind.apiInFlight:
    case DebugLogKind.apiSuccess:
    case DebugLogKind.apiError:
      return const Color(0xFFABB2BF);
  }
}

String _kindLabel(DebugLogKind k) {
  switch (k) {
    case DebugLogKind.flutterError:
      return 'FLUTTER';
    case DebugLogKind.platformError:
      return 'UNCAUGHT';
    case DebugLogKind.info:
      return 'INFO';
    default:
      return 'EVENT';
  }
}

// ─── HTTP status text ────────────────────────────────────────────────────────

String _statusText(int code) {
  switch (code) {
    case 200:
      return 'OK';
    case 201:
      return 'Created';
    case 202:
      return 'Accepted';
    case 204:
      return 'No Content';
    case 301:
      return 'Moved Permanently';
    case 302:
      return 'Found';
    case 304:
      return 'Not Modified';
    case 400:
      return 'Bad Request';
    case 401:
      return 'Unauthorized';
    case 403:
      return 'Forbidden';
    case 404:
      return 'Not Found';
    case 405:
      return 'Method Not Allowed';
    case 408:
      return 'Request Timeout';
    case 409:
      return 'Conflict';
    case 422:
      return 'Unprocessable Entity';
    case 429:
      return 'Too Many Requests';
    case 500:
      return 'Internal Server Error';
    case 502:
      return 'Bad Gateway';
    case 503:
      return 'Service Unavailable';
    case 504:
      return 'Gateway Timeout';
    default:
      return '';
  }
}

// ─── JSON pretty-print + syntax highlight ────────────────────────────────────

String _prettify(String body) {
  final trimmed = body.trim();
  if (trimmed.isEmpty) return body;
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    try {
      final decoded = jsonDecode(trimmed);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {}
  }
  return body;
}

const _jsonKeyColor = Color(0xFF7EE7E7); // cyan
const _jsonStringColor = Color(0xFFA5D6A7); // light green
const _jsonNumberColor = Color(0xFFFFB86C); // orange
const _jsonKeywordColor = Color(0xFFD19FE8); // purple
const _jsonPunctColor = Color(0xFFB0B7C3); // soft gray

List<TextSpan> _highlightJson(String text) {
  if (text.isEmpty) return const [];
  if (!_looksLikeJson(text)) {
    return [TextSpan(text: text)];
  }
  final spans = <TextSpan>[];
  int i = 0;
  while (i < text.length) {
    final code = text.codeUnitAt(i);
    // whitespace / newline run
    if (code == 0x20 || code == 0x09 || code == 0x0A || code == 0x0D) {
      final start = i;
      while (i < text.length) {
        final c = text.codeUnitAt(i);
        if (c != 0x20 && c != 0x09 && c != 0x0A && c != 0x0D) break;
        i++;
      }
      spans.add(TextSpan(text: text.substring(start, i)));
      continue;
    }
    // string
    if (code == 0x22) {
      // "
      final start = i;
      i++;
      while (i < text.length) {
        final c = text.codeUnitAt(i);
        if (c == 0x5C) {
          // \
          i += 2;
          continue;
        }
        if (c == 0x22) {
          // "
          i++;
          break;
        }
        i++;
      }
      // detect "key:" by looking ahead past whitespace for ':'
      int look = i;
      while (look < text.length) {
        final c = text.codeUnitAt(look);
        if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
          look++;
          continue;
        }
        break;
      }
      final isKey = look < text.length && text.codeUnitAt(look) == 0x3A; // :
      spans.add(
        TextSpan(
          text: text.substring(start, i),
          style: TextStyle(color: isKey ? _jsonKeyColor : _jsonStringColor),
        ),
      );
      continue;
    }
    // numbers
    if ((code >= 0x30 && code <= 0x39) || code == 0x2D) {
      // 0-9 or -
      final start = i;
      i++;
      while (i < text.length) {
        final c = text.codeUnitAt(i);
        final isDigit = c >= 0x30 && c <= 0x39;
        final isDot = c == 0x2E;
        final isExp = c == 0x65 || c == 0x45; // e E
        final isSign = c == 0x2B || c == 0x2D; // + -
        if (!(isDigit || isDot || isExp || isSign)) break;
        i++;
      }
      spans.add(
        TextSpan(
          text: text.substring(start, i),
          style: const TextStyle(color: _jsonNumberColor),
        ),
      );
      continue;
    }
    // keywords
    if (_matchAt(text, i, 'true')) {
      spans.add(
        const TextSpan(
          text: 'true',
          style: TextStyle(color: _jsonKeywordColor),
        ),
      );
      i += 4;
      continue;
    }
    if (_matchAt(text, i, 'false')) {
      spans.add(
        const TextSpan(
          text: 'false',
          style: TextStyle(color: _jsonKeywordColor),
        ),
      );
      i += 5;
      continue;
    }
    if (_matchAt(text, i, 'null')) {
      spans.add(
        const TextSpan(
          text: 'null',
          style: TextStyle(color: _jsonKeywordColor),
        ),
      );
      i += 4;
      continue;
    }
    // punctuation / other
    spans.add(
      TextSpan(text: text[i], style: const TextStyle(color: _jsonPunctColor)),
    );
    i++;
  }
  return spans;
}

bool _matchAt(String s, int i, String needle) {
  if (i + needle.length > s.length) return false;
  for (int k = 0; k < needle.length; k++) {
    if (s.codeUnitAt(i + k) != needle.codeUnitAt(k)) return false;
  }
  return true;
}

bool _looksLikeJson(String text) {
  final trimmed = text.trimLeft();
  if (trimmed.isEmpty) return false;
  final first = trimmed.codeUnitAt(0);
  return first == 0x7B || first == 0x5B; // { or [
}

// ─── API detail screen (tabbed, per-tab search) ──────────────────────────────

/// Full screen for one API call with Overview / Request / Headers / Response
/// tabs, each with its own field search. Opened from an API log row.

List<TextSpan> _hlSpans(String text, String query, TextStyle base) {
  if (query.isEmpty) return [TextSpan(text: text, style: base)];
  final lower = text.toLowerCase();
  final q = query.toLowerCase();
  final spans = <TextSpan>[];
  var i = 0;
  while (i < text.length) {
    final idx = lower.indexOf(q, i);
    if (idx < 0) {
      spans.add(TextSpan(text: text.substring(i), style: base));
      break;
    }
    if (idx > i) spans.add(TextSpan(text: text.substring(i, idx), style: base));
    spans.add(
      TextSpan(
        text: text.substring(idx, idx + query.length),
        style: const TextStyle(
          color: Colors.black,
          backgroundColor: Color(0xFFFFD54F),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    i = idx + query.length;
  }
  return spans;
}
