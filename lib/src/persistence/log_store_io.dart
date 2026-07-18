/// Native session persistence via `dart:io`.
///
/// Deliberately uses the system temp directory rather than adding a
/// `path_provider` dependency: this is disposable diagnostic data that the OS
/// is welcome to reclaim, and `dio` staying the package's only dependency is a
/// property worth protecting.
library;

import 'dart:io';

Directory _dir() {
  final d = Directory('${Directory.systemTemp.path}/debug_deck');
  if (!d.existsSync()) d.createSync(recursive: true);
  return d;
}

File _file(String name) => File('${_dir().path}/$name');

Future<String?> readSessionFile(String name) async {
  try {
    final f = _file(name);
    if (!await f.exists()) return null;
    return await f.readAsString();
  } catch (_) {
    // A debug tool must never take the app down. An unreadable or corrupt
    // session file means "no previous session", not a crash.
    return null;
  }
}

Future<void> writeSessionFile(String name, String contents) async {
  try {
    // Write to a sibling then rename: a kill mid-write would otherwise leave a
    // truncated file that reads back as corrupt on next launch. Rename is
    // atomic on the platforms this runs on.
    final tmp = _file('$name.tmp');
    await tmp.writeAsString(contents, flush: true);
    await tmp.rename(_file(name).path);
  } catch (_) {
    // Persistence is best-effort; losing it is strictly better than throwing
    // from a background save.
  }
}

Future<void> deleteSessionFile(String name) async {
  try {
    final f = _file(name);
    if (await f.exists()) await f.delete();
  } catch (_) {
    // Ignore.
  }
}

bool get sessionStorageSupported => true;
