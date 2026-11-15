import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'core/core.dart';
import 'library/library_store.dart';
import 'ui/binfire_app.dart';
import 'ui/binfire_controller.dart';
import 'ui/hashbin_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var config = BinfireConfig.parse(await rootBundle.loadString(BinfireConfig.assetPath));
  if (kDebugMode) {
    // spec/hashbin.md, Development: point HashBin at a local mock. Release
    // builds ignore these.
    config = config.withHashbinOverrides(
      api: const String.fromEnvironment('HASHBIN_API'),
      content: const String.fromEnvironment('HASHBIN_CONTENT'),
      clientId: const String.fromEnvironment('HASHBIN_CLIENT_ID'),
    );
  }
  final hashbin = config.hashbin.clientId.isEmpty || config.redirectUri.isEmpty
      ? null
      : HashbinClient(
          api: config.hashbin.api,
          clientId: config.hashbin.clientId,
          redirectUri: config.redirectUri,
          store: const SecureTokenStore(),
        );
  final registry = Registry.parse(await rootBundle.loadString(Registry.assetPath));
  final store = LibraryStore(await getApplicationSupportDirectory());
  final library = await store.load();
  final controller = BinfireController(
    config: config,
    registry: registry,
    library: library,
    store: store,
    hashbin: hashbin,
    authenticate: hashbin == null ? null : systemAuthenticate,
  );
  hashbin?.load().then((_) => controller.hashbinChanged());
  runApp(BinfireApp(controller: controller));
}
