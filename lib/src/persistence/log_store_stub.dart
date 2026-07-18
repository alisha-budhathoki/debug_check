/// Web/WASM fallback for session persistence.
///
/// `dart:io` has no file access on the web, and reaching for `localStorage`
/// would mean a `package:web` dependency plus a quota nobody asked for. The
/// deck degrades to in-memory-only there rather than growing a dependency —
/// the feature exists for "the app crashed, what happened", which is a native
/// concern in practice.
library;

Future<String?> readSessionFile(String name) async => null;

Future<void> writeSessionFile(String name, String contents) async {}

Future<void> deleteSessionFile(String name) async {}

/// Whether persistence does anything on this platform. The UI reads it so it
/// can say "not available here" rather than offering a switch that silently
/// does nothing.
bool get sessionStorageSupported => false;
