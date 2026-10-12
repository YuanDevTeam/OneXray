import 'package:collection/collection.dart';
import 'package:onexray/core/constants/preferences.dart';
import 'package:onexray/core/model/ping_json.dart';
import 'package:onexray/core/tools/empty.dart';

enum PingUrl {
  cloudflare("Cloudflare", "https://cp.cloudflare.com/"),
  google("Google", "https://www.google.com/generate_204"),
  custom("Custom", "");

  const PingUrl(this.name, this.url);

  final String name;
  final String url;

  @override
  String toString() => name;

  static PingUrl? fromString(String name) =>
      PingUrl.values.firstWhereOrNull((value) => value.name == name);

  static bool isValidCustomUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) {
      return false;
    }
    final scheme = uri.scheme.toLowerCase();
    return scheme == "http" || scheme == "https";
  }
}

class PingTimeout {
  static const min = 3.0;
  static const max = 8.0;
  static const defaultValue = 5.0;
}

class PingState {
  var timeout = PingTimeout.defaultValue;
  var url = PingUrl.cloudflare;
  var customUrl = "";

  String get realUrl => url == PingUrl.custom ? customUrl : url.url;

  Future<void> readFromPreferences() async {
    final jsonMap = await PreferencesKey().readPingState();
    if (!EmptyTool.checkMap(jsonMap)) {
      return;
    }
    final pingJson = PingJson.fromJson(jsonMap!);
    if (pingJson.timeout != null) {
      var timeout = pingJson.timeout!;
      if (timeout < PingTimeout.min) {
        timeout = PingTimeout.min;
      } else if (timeout > PingTimeout.max) {
        timeout = PingTimeout.max;
      }
      this.timeout = timeout;
    }
    if (EmptyTool.checkString(pingJson.url)) {
      final url = PingUrl.fromString(pingJson.url!);
      if (url != null) {
        this.url = url;
      }
    }
    if (EmptyTool.checkString(pingJson.customUrl)) {
      customUrl = pingJson.customUrl!;
    }
    if (url == PingUrl.custom && !PingUrl.isValidCustomUrl(customUrl)) {
      url = PingUrl.cloudflare;
    }
  }

  Future<void> saveToPreferences() async {
    final pingJson = PingJson(timeout, url.name, customUrl);
    await PreferencesKey().savePingState(pingJson.toJson());
  }
}
