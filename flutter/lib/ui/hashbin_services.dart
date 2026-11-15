/// Platform pieces of Native Save: the system auth session
/// (flutter_web_auth_2) and token storage in the Keychain or Keystore
/// (flutter_secure_storage). Tokens go nowhere else.
library;

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../core/core.dart';

/// Stores the tokens under `hashbin.tokens` in the Keychain
/// (`AfterFirstUnlockThisDeviceOnly`) or the Android Keystore.
class SecureTokenStore implements TokenStore {
  /// Creates the store.
  const SecureTokenStore();

  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  @override
  Future<String?> read() => _storage.read(key: HashbinClient.tokensKey);

  @override
  Future<void> write(String? value) => value == null
      ? _storage.delete(key: HashbinClient.tokensKey)
      : _storage.write(key: HashbinClient.tokensKey, value: value);
}

/// Opens [url] in `ASWebAuthenticationSession` (iOS) or an Auth Tab / Custom
/// Tab (Android) and returns the `<ownScheme>://oauth?…` callback URL.
Future<String> systemAuthenticate(Uri url, String callbackScheme) async {
  try {
    return await FlutterWebAuth2.authenticate(url: url.toString(), callbackUrlScheme: callbackScheme);
  } on PlatformException catch (e) {
    if (e.code == 'CANCELED') throw const BinfireException(ErrorCodes.cancelled);
    throw BinfireException(ErrorCodes.failed, e.code);
  }
}
