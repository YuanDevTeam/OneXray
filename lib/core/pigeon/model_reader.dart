import 'dart:io';

import 'package:onexray/core/pigeon/constants.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/tools/json.dart';

extension StartVpnRequestReader on StartVpnRequest {
  static Future<StartVpnRequest> readFromStartFile() async {
    final filePath = VpnConstants.startPath;
    final data = await File(filePath).readAsString();
    final requestMap = JsonTool.decoder.convert(data);
    final request = StartVpnRequest.fromJson(requestMap);
    if (request.captureMode != 'tun') {
      throw const FormatException('VPN startup input requires tunnel mode');
    }
    return request;
  }
}

abstract final class LibXrayInvokeResponseParser {
  static const invalidResponseError = 'invalid libXray response';

  static LibXrayInvokeResponse parse(String response) {
    try {
      final value = JsonTool.decoder.convert(response);
      if (value is! Map<String, dynamic>) {
        return _invalidResponse();
      }
      return LibXrayInvokeResponse.fromJson(value);
    } catch (_) {
      return _invalidResponse();
    }
  }

  static LibXrayInvokeResponse _invalidResponse() =>
      LibXrayInvokeResponse(false, null, invalidResponseError);
}
