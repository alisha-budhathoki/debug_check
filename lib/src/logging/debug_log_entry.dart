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

  /// The route that was on top when this call started, captured from
  /// [CurrentScreenObserver] at request time (not completion time — a call may
  /// resolve after the user has navigated away). Null when no screen observer
  /// is wired or the route is unknown; duplicate detection then falls back to
  /// grouping across the whole session.
  ///
  /// This is what makes "duplicate API call" a *bug* signal rather than noise:
  /// the same request firing twice on the same screen is a double-tap or a
  /// rebuild loop; the same request firing on two different screens is normal
  /// navigation.
  final String? screen;

  /// Kept out of the ring buffer's eviction. The 200-entry cap means the call
  /// you are investigating scrolls out of existence while you read it; pinning
  /// is the escape hatch.
  final bool pinned;

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
    this.screen,
    this.pinned = false,
  });

  DebugLogEntry copyWith({bool? pinned}) => DebugLogEntry(
    id: id,
    timestamp: timestamp,
    kind: kind,
    title: title,
    subtitle: subtitle,
    method: method,
    url: url,
    statusCode: statusCode,
    duration: duration,
    queryParameters: queryParameters,
    requestHeaders: requestHeaders,
    responseHeaders: responseHeaders,
    requestBody: requestBody,
    responseBody: responseBody,
    responseBytes: responseBytes,
    errorMessage: errorMessage,
    stackTrace: stackTrace,
    screen: screen,
    pinned: pinned ?? this.pinned,
  );

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
