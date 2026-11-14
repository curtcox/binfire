/// JSON-file persistence for [Library] in app-private storage.
library;

import 'dart:convert';
import 'dart:io';

import 'library.dart';

/// Loads and saves the library as `library.json` in [directory].
///
/// Writes go to a temporary file first and are renamed into place, and are
/// serialized so a slow write can't overwrite a newer one.
class LibraryStore {
  /// Creates a store in [directory].
  LibraryStore(this.directory);

  /// The app-private directory holding `library.json`.
  final Directory directory;

  File get _file => File('${directory.path}/library.json');

  Future<void> _pending = Future.value();

  /// Loads the library, or returns an empty one if the file is missing or
  /// unreadable.
  Future<Library> load() async {
    try {
      final f = _file;
      if (!await f.exists()) return Library();
      final json = jsonDecode(await f.readAsString());
      return Library.fromJson(json as Map<String, Object?>);
    } on Object {
      return Library();
    }
  }

  /// Persists [library].
  Future<void> save(Library library) {
    final text = jsonEncode(library.toJson());
    return _pending = _pending.then((_) async {
      await directory.create(recursive: true);
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(text, flush: true);
      await tmp.rename(_file.path);
    });
  }
}
