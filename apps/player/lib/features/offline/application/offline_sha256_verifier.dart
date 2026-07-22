import 'package:crypto/crypto.dart';

import '../data/offline_file_system.dart';

abstract interface class OfflineSha256Verifier {
  Future<String> digestFile(OfflineFileSystem fileSystem, String path);
}

class CryptoOfflineSha256Verifier implements OfflineSha256Verifier {
  const CryptoOfflineSha256Verifier();

  @override
  Future<String> digestFile(OfflineFileSystem fileSystem, String path) async {
    final digest = await sha256.bind(fileSystem.openRead(path)).first;
    return digest.toString();
  }
}
