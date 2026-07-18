/// Masking of secrets in captured network metadata.
///
/// The deck's most-used exports — cURL, JSON, HAR — are designed to be pasted
/// into a bug report, a PR comment or a Slack thread. Without masking, every
/// one of those carries a live `Authorization` header out of the device and
/// into a place it can be indexed and archived. Masking therefore happens at
/// *capture* time, not export time: a value that never enters the buffer can't
/// leak through a surface someone adds later, can't be read over a shoulder,
/// and can't show up in a screenshot of the Headers tab.
///
/// Masked values keep their shape so they stay useful for debugging. A bearer
/// token renders as `Bearer ••••4f2a` — enough to tell two tokens apart, or to
/// confirm the app is sending the one you expect, without revealing it.
library;

/// What happens to a secret once it's been recognised.
///
/// The choice is a genuine trade-off, so it's explicit rather than implied:
/// a secret you can reveal later is a secret that is still in memory.
enum RedactionMode {
  /// Never stored. The raw value is discarded at capture and cannot be
  /// recovered — not by an export, not by a toggle, not by a future surface.
  /// The safest option and the default.
  drop,

  /// Stored, but masked everywhere by default. The user can reveal it in the
  /// UI with the eye toggle when they genuinely need to read a token, and
  /// re-hide it afterwards. Exports follow whatever the toggle currently says,
  /// so revealing is a deliberate act rather than an accident.
  hide,

  /// No masking at all. Values are shown and exported verbatim.
  off,
}

/// Which keys to mask, and how.
///
/// Configure via `DebugTools.init(redaction: ...)`. The default set covers the
/// usual auth carriers; apps with bespoke header names should add them:
///
/// ```dart
/// DebugTools.init(
///   enabled: true,
///   redaction: DebugRedaction.standard(also: {'x-tenant-signature'}),
/// );
/// ```
///
/// To let whoever is holding the device decide, use [RedactionMode.hide] — the
/// Headers view then grows an eye toggle that flips between masked and real
/// values:
///
/// ```dart
/// DebugTools.init(
///   enabled: true,
///   redaction: DebugRedaction.standard(mode: RedactionMode.hide),
/// );
/// ```
class DebugRedaction {
  /// Header, query-parameter and cookie names masked unless overridden.
  /// Compared case-insensitively — HTTP header names aren't case-sensitive and
  /// query params vary by backend convention.
  static const defaultKeys = <String>{
    'authorization',
    'proxy-authorization',
    'www-authenticate',
    'cookie',
    'set-cookie',
    'x-api-key',
    'apikey',
    'api-key',
    'x-auth-token',
    'auth-token',
    'x-access-token',
    'access-token',
    'access_token',
    'refresh-token',
    'refresh_token',
    'x-csrf-token',
    'x-xsrf-token',
    'x-session-token',
    'session-token',
    'password',
    'secret',
    'client-secret',
    'client_secret',
    'signature',
    'sig',
    'token',
  };

  /// Auth schemes preserved in front of a masked credential. Seeing `Basic`
  /// where you expected `Bearer` is often the whole bug.
  static const _schemes = <String>{'bearer', 'basic', 'digest', 'token', 'mac'};

  final Set<String> keys;

  /// What to do with a recognised secret. See [RedactionMode].
  final RedactionMode mode;

  const DebugRedaction({required this.keys, this.mode = RedactionMode.drop});

  /// Whether any masking happens at all.
  bool get enabled => mode != RedactionMode.off;

  /// Whether the raw value survives capture, and so can be revealed on demand.
  /// Only true for [RedactionMode.hide] — under [RedactionMode.drop] there is
  /// nothing left to reveal, which is the entire point of that mode.
  bool get canReveal => mode == RedactionMode.hide;

  /// The default policy, optionally adjusted. [also] adds names, [except]
  /// removes them — use [except] when a "secret-looking" name is actually inert
  /// in your API and you need to read it.
  factory DebugRedaction.standard({
    Set<String> also = const {},
    Set<String> except = const {},
    RedactionMode mode = RedactionMode.drop,
  }) {
    final k = {
      ...defaultKeys.map((e) => e.toLowerCase()),
      ...also.map((e) => e.toLowerCase()),
    }..removeAll(except.map((e) => e.toLowerCase()));
    return DebugRedaction(keys: k, mode: mode);
  }

  /// Masks nothing. The caller accepts that exports will carry live credentials.
  static const DebugRedaction disabled = DebugRedaction(
    keys: <String>{},
    mode: RedactionMode.off,
  );

  bool shouldMask(String key) =>
      enabled && keys.contains(key.trim().toLowerCase());

  /// Masks a single value, preserving an auth scheme prefix and a short tail.
  ///
  /// The tail is dropped for short values — revealing 4 of 8 characters is a
  /// meaningful fraction of the secret, whereas 4 of 200 is not.
  String mask(String value) {
    if (!enabled || value.isEmpty) return value;

    final space = value.indexOf(' ');
    if (space > 0 &&
        _schemes.contains(value.substring(0, space).toLowerCase())) {
      final scheme = value.substring(0, space);
      return '$scheme ${_maskToken(value.substring(space + 1).trim())}';
    }
    return _maskToken(value);
  }

  static String _maskToken(String token) {
    if (token.isEmpty) return token;
    if (token.length < 12) return '••••';
    return '••••${token.substring(token.length - 4)}';
  }

  /// Applies [mask] to every entry whose key is sensitive. Returns the same
  /// instance when nothing matched, so the common case allocates nothing.
  Map<String, String>? apply(Map<String, String>? map) {
    if (!enabled || map == null || map.isEmpty) return map;
    Map<String, String>? out;
    for (final e in map.entries) {
      if (!shouldMask(e.key)) continue;
      out ??= Map<String, String>.of(map);
      out[e.key] = mask(e.value);
    }
    return out ?? map;
  }
}
