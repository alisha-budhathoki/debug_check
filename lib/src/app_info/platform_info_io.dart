import 'dart:io' show Platform;

/// Native (dart:io) platform facts. Selected via a conditional import so the
/// package stays Web/WASM-compatible (the web build uses `platform_info_stub`).
String platformOperatingSystem() => Platform.operatingSystem;
String platformOperatingSystemVersion() => Platform.operatingSystemVersion;
String platformDartVersion() => Platform.version;
int platformNumberOfProcessors() => Platform.numberOfProcessors;
