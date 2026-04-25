import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';

class VersionService {
  static Future<bool> needsForceUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('app')
          .get();

      if (!doc.exists) return false;

      final minVersion = doc.data()?['minVersionPro'] as String?;
      if (minVersion == null) return false;

      return _isVersionLower(currentVersion, minVersion);
    } catch (_) {
      return false;
    }
  }

  static bool _isVersionLower(String current, String minimum) {
    final currentParts = current.split('.').map(int.parse).toList();
    final minimumParts = minimum.split('.').map(int.parse).toList();

    for (int i = 0; i < 3; i++) {
      final c = i < currentParts.length ? currentParts[i] : 0;
      final m = i < minimumParts.length ? minimumParts[i] : 0;
      if (c < m) return true;
      if (c > m) return false;
    }
    return false;
  }
}
