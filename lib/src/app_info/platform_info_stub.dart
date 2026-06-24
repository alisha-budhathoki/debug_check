/// Web/WASM fallback for platform facts that `dart:io` would provide on native.
/// `dart:io` isn't available on the web, so these report neutral placeholders;
/// the rest of the snapshot (display, a11y, locale) still works everywhere.
String platformOperatingSystem() => 'web';
String platformOperatingSystemVersion() => '-';
String platformDartVersion() => '-';
int platformNumberOfProcessors() => 0;
