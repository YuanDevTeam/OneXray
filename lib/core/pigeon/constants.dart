import 'package:onexray/core/pigeon/host_api.dart';
import 'package:path/path.dart' as p;

class VpnConstants {
  static const tunMtu = 1500;

  /// The only App-side Geodata directory. Installed files are always flat.
  static String get datDir => p.join(AppHostApi().tunFilesDir, "dat");
  static const systemGeoTimestamp = "timestamp.txt";

  static String get runDir => p.join(AppHostApi().tunFilesDir, "run");

  static const startFileName = 'start.json';
  static const proxyStartFileName = 'proxy-start.json';

  static String get startPath => p.join(runDir, startFileName);
  static String get proxyStartPath => p.join(runDir, proxyStartFileName);
  static const apnsPresetPendingFileName = 'apns-preset-pending';
}
