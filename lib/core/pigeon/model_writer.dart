import 'dart:io';
import 'dart:convert';

import 'package:onexray/core/pigeon/constants.dart';
import 'package:onexray/core/pigeon/model.dart';
import 'package:onexray/core/tools/json.dart';
import 'package:onexray/core/tools/atomic_file.dart';

extension StartVpnRequestWriter on StartVpnRequest {
  Future<void> writeToStartFile() async {
    final filePath = switch (captureMode) {
      'tun' => VpnConstants.startPath,
      'proxy' => VpnConstants.proxyStartPath,
      _ => throw const FormatException('Invalid capture mode'),
    };
    final data = JsonTool.encoder.convert(toJson());
    await Directory(File(filePath).parent.path).create(recursive: true);
    await writeBytesAtomically(File(filePath), utf8.encode(data));
  }
}
