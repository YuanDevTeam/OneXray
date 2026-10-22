import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/servers/outbound/map.dart';
import 'package:onexray/service/servers/outbound/state_db.dart';

import '../../../support/xdrive_template_fixture.dart';

void main() {
  test('single outbound wrapper round-trips without shared references', () {
    final source = <String, dynamic>{
      'protocol': 'vless',
      'settings': {
        'address': 'example.com',
        'editorOnly': {'enabled': true},
      },
    };

    final decoded = decodeSingleOutbound(encodeSingleOutbound(source));
    (decoded['settings'] as Map<String, dynamic>)['address'] = 'changed';

    expect(decoded['protocol'], 'vless');
    expect(
      (source['settings'] as Map<String, dynamic>)['address'],
      'example.com',
    );
    expect((decoded['settings'] as Map<String, dynamic>)['editorOnly'], {
      'enabled': true,
    });
  });

  test('XDrive template and unknown nested fields survive node storage', () {
    final source = xdriveTemplateOutbound();
    final saved = _savedOutbound(outboundCompanion(source).data.value!);
    expect(saved, source);
    expect(decodeSingleOutbound(encodeSingleOutbound(saved)), source);
    (saved['streamSettings']['xdriveSettings']['template']['get']
            as Map<String, dynamic>)['hrefPath'] =
        'changed';
    expect(
      source['streamSettings']['xdriveSettings']['template']['get']['hrefPath'],
      'result.url',
    );
  });

  test('single outbound wrapper rejects invalid shapes', () {
    expect(() => decodeSingleOutbound('[]'), throwsFormatException);
    expect(
      () => decodeSingleOutbound('{"outbounds":[]}'),
      throwsFormatException,
    );
    expect(
      () => decodeSingleOutbound('{"outbounds":[{},{}]}'),
      throwsFormatException,
    );
    expect(
      () => decodeSingleOutbound('{"outbounds":[1]}'),
      throwsFormatException,
    );
  });

  test('runtime tag and dialer helpers preserve siblings', () {
    final outbound = <String, dynamic>{
      'tag': 'proxy',
      'protocol': 'vless',
      'editorOnly': {'keep': true},
      'streamSettings': {
        'network': 'xhttp',
        'sockopt': {'interface': 'utun9', 'dialerProxy': 'old'},
      },
    };

    setOutboundDialerProxy(outbound, 'chainProxy');
    expect(outboundDialerProxy(outbound), 'chainProxy');

    expect(outbound['tag'], 'proxy');
    expect(outbound['editorOnly'], {'keep': true});
    expect(
      ((outbound['streamSettings'] as Map<String, dynamic>)['sockopt']
          as Map<String, dynamic>)['interface'],
      'utun9',
    );
    expect(outboundDialerProxy(outbound), 'chainProxy');
  });

  test(
    'storage preserves libXray fields without a second protocol validator',
    () {
      for (final outbound in <Map<String, dynamic>>[
        {
          'protocol': 'vmess',
          'settings': {'address': 'example.com', 'port': 443},
        },
        {
          'protocol': 'vmess',
          'settings': {'security': 'none'},
        },
        {
          'protocol': 'shadowsocks',
          'settings': {'method': 'plain'},
        },
        {'protocol': 'vless'},
      ]) {
        final saved = _savedOutbound(outboundCompanion(outbound).data.value!);
        expect(saved, {...outbound, 'tag': outbound['protocol']});
      }
      final unnamed = outboundCompanion({'tag': '', 'protocol': 'freedom'});
      expect(unnamed.name.value, 'freedom');
      expect(_savedOutbound(unnamed.data.value!)['tag'], '');
    },
  );

  test('legacy name aliases tag only when tag is absent', () {
    final legacy = <String, dynamic>{
      'name': 'Legacy Name',
      'protocol': 'vless',
      'settings': {'editorOnly': true},
    };
    final normalized = copyOutboundMap(legacy);

    expect(normalized['tag'], 'Legacy Name');
    expect(normalized, isNot(contains('name')));
    expect(legacy['name'], 'Legacy Name');

    final canonical = copyOutboundMap({
      'name': 'Legacy Name',
      'tag': 'Canonical Tag',
    });
    expect(canonical['tag'], 'Canonical Tag');
    expect(canonical, isNot(contains('name')));

    final unnamed = copyOutboundMap({'protocol': 'vless'});
    expect(unnamed, isNot(contains('tag')));
  });

  test('DB save uses tag and fills a missing tag from the row name', () {
    final tagged = <String, dynamic>{
      'tag': 'Node Tag',
      'protocol': 'vless',
      'settings': {'editorOnly': true},
    };
    final taggedCompanion = outboundCompanion(
      tagged,
      databaseName: 'Legacy Row Name',
    );

    expect(taggedCompanion.name.value, 'Node Tag');
    expect(_savedOutbound(taggedCompanion.data.value!), tagged);

    final untagged = <String, dynamic>{
      'protocol': 'vless',
      'settings': {'editorOnly': true},
    };
    final fallbackCompanion = outboundCompanion(
      untagged,
      databaseName: 'Legacy Row Name',
    );

    expect(fallbackCompanion.name.value, 'Legacy Row Name');
    expect(
      _savedOutbound(fallbackCompanion.data.value!)['tag'],
      'Legacy Row Name',
    );
    expect(
      _savedOutbound(fallbackCompanion.data.value!),
      isNot(contains('name')),
    );
    expect(untagged, isNot(contains('tag')));

    final protocolCompanion = outboundCompanion({
      'protocol': 'vless',
      'settings': {'editorOnly': true},
    });
    expect(protocolCompanion.name.value, 'vless');
    expect(_savedOutbound(protocolCompanion.data.value!)['tag'], 'vless');
  });
}

Map<String, dynamic> _savedOutbound(String data) =>
    decodeSingleOutbound(utf8.decode(base64Decode(data)));
