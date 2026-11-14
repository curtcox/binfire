import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'core/core.dart';
import 'library/library_store.dart';
import 'ui/binfire_app.dart';
import 'ui/binfire_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = BinfireConfig.parse(await rootBundle.loadString(BinfireConfig.assetPath));
  final registry = Registry.parse(await rootBundle.loadString(Registry.assetPath));
  final store = LibraryStore(await getApplicationSupportDirectory());
  final library = await store.load();
  final controller = BinfireController(config: config, registry: registry, library: library, store: store);
  runApp(BinfireApp(controller: controller));
}
