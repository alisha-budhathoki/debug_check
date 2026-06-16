enum DebugLogKind {
  apiInFlight,
  apiSuccess,
  apiError,
  flutterError,
  platformError,
  info,
}

class DebugLogEntry {
  final int id;
  final DateTime timestamp;
  final DebugLogKind kind;
  final String title;
  final String subtitle;

  // API-specific
  final String? method;
  final String? url;
  final int? statusCode;
  final Duration? duration;
  final Map<String, String>? queryParameters;
  final Map<String, String>? requestHeaders;
  final Map<String, String>? responseHeaders;
  final String? requestBody;
  final String? responseBody;
  final int? responseBytes;

  // Error-specific
  final String? errorMessage;
  final String? stackTrace;

  const DebugLogEntry({
    required this.id,
    required this.timestamp,
    required this.kind,
    required this.title,
    required this.subtitle,
    this.method,
    this.url,
    this.statusCode,
    this.duration,
    this.queryParameters,
    this.requestHeaders,
    this.responseHeaders,
    this.requestBody,
    this.responseBody,
    this.responseBytes,
    this.errorMessage,
    this.stackTrace,
  });

  bool get isApi =>
      kind == DebugLogKind.apiInFlight ||
      kind == DebugLogKind.apiSuccess ||
      kind == DebugLogKind.apiError;

  bool get isError =>
      kind == DebugLogKind.apiError ||
      kind == DebugLogKind.flutterError ||
      kind == DebugLogKind.platformError;

  bool get isInFlight => kind == DebugLogKind.apiInFlight;
}
