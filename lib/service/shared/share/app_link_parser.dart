import 'dart:convert';

import 'package:onexray/core/model/geo_data_type.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/service/shared/share/app_link_model.dart';
import 'package:onexray/service/servers/subscription/model.dart';

abstract final class OneXrayAppLinkParser {
  static const scheme = 'onexray';
  static const host = 'onexray.com';

  static const configPath = '/config/add';
  static const subscriptionPath = '/sub/add';
  static const geoDataPath = '/dat/add';

  static OneXrayAppLink? parse(Uri uri) {
    if (uri.scheme.toLowerCase() != scheme ||
        uri.host.toLowerCase() != host ||
        uri.hasPort ||
        uri.userInfo.isNotEmpty) {
      return null;
    }

    return switch (uri.path) {
      configPath => _parseConfig(uri),
      subscriptionPath => _parseSubscription(uri),
      geoDataPath => _parseGeoData(uri),
      _ => null,
    };
  }

  static OneXrayConfigLink? _parseConfig(Uri uri) {
    if (!_hasOnlyQueryKeys(uri, const {'type', 'data'})) {
      return null;
    }
    final typeText = _singleQueryValue(uri, 'type');
    final data = _singleQueryValue(uri, 'data');
    if (typeText == null || data == null) {
      return null;
    }
    final type = switch (typeText) {
      'outbound' => OneXrayConfigLinkType.outbound,
      'raw' => OneXrayConfigLinkType.raw,
      'custom' => OneXrayConfigLinkType.custom,
      'custom-advanced' => OneXrayConfigLinkType.customAdvanced,
      _ => null,
    };
    if (type == null) {
      return null;
    }

    try {
      final xrayJson = utf8.decode(base64Decode(data));
      if (xrayJson.trim().isEmpty) {
        return null;
      }
      return OneXrayConfigLink(
        name: _fragmentName(uri),
        type: type,
        xrayJson: xrayJson,
      );
    } catch (_) {
      return null;
    }
  }

  static OneXraySubscriptionLink? _parseSubscription(Uri uri) {
    if (!_hasOnlyQueryKeys(uri, const {'url', 'age', 'panel', 'mode'})) {
      return null;
    }
    final urlText = _singleQueryValue(uri, 'url');
    if (urlText == null) {
      return null;
    }
    final url = _httpsUrl(SubscriptionUrl.normalize(urlText));
    if (url == null) {
      return null;
    }

    final ageText = _optionalSingleQueryValue(uri, 'age');
    if (uri.queryParametersAll.containsKey('age') && ageText == null) {
      return null;
    }
    AgeKeyType? ageKeyType;
    if (ageText != null) {
      ageKeyType = switch (ageText) {
        'x25519' => AgeKeyType.x25519,
        'hybrid' => AgeKeyType.hybrid,
        _ => null,
      };
      if (ageKeyType == null) {
        return null;
      }
    }

    final panelText = _optionalSingleQueryValue(uri, 'panel');
    final modeText = _optionalSingleQueryValue(uri, 'mode');
    final panel = panelText == null
        ? SubscriptionPanel.generic
        : SubscriptionPanel.fromString(panelText);
    final mode = modeText == null
        ? null
        : SubscriptionMode.fromString(modeText);
    if (panel == null ||
        (uri.queryParametersAll.containsKey('panel') && panelText == null) ||
        (uri.queryParametersAll.containsKey('mode') &&
            (modeText == null || mode == null))) {
      return null;
    }
    return OneXraySubscriptionLink(
      name: _fragmentName(uri),
      url: url,
      ageKeyType: ageKeyType,
      panel: panel,
      mode: mode,
    );
  }

  static OneXrayGeoDataLink? _parseGeoData(Uri uri) {
    if (!_hasOnlyQueryKeys(uri, const {'type', 'url'})) {
      return null;
    }
    final typeText = _singleQueryValue(uri, 'type');
    final urlText = _singleQueryValue(uri, 'url');
    if (typeText == null || urlText == null) {
      return null;
    }
    final type = GeoDataType.fromString(typeText);
    final url = _httpsUrl(urlText);
    if (type == null || url == null) {
      return null;
    }
    return OneXrayGeoDataLink(name: _fragmentName(uri), type: type, url: url);
  }

  static String? _httpsUrl(String text) {
    final uri = Uri.tryParse(text);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty) {
      return null;
    }
    return uri.toString();
  }

  static bool _hasOnlyQueryKeys(Uri uri, Set<String> allowed) {
    return uri.queryParametersAll.keys.every(allowed.contains);
  }

  static String? _singleQueryValue(Uri uri, String key) {
    final values = uri.queryParametersAll[key];
    if (values == null || values.length != 1) {
      return null;
    }
    final value = values.single.trim();
    return value.isEmpty ? null : value;
  }

  static String? _optionalSingleQueryValue(Uri uri, String key) {
    if (!uri.queryParametersAll.containsKey(key)) {
      return null;
    }
    return _singleQueryValue(uri, key);
  }

  static String _fragmentName(Uri uri) {
    if (uri.fragment.isEmpty) {
      return '';
    }
    try {
      return Uri.decodeComponent(uri.fragment).trim();
    } catch (_) {
      return '';
    }
  }
}
