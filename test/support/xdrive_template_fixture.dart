// JSON/Map preservation fixture, not a live service. The VLESS encryption
// public key is from Xray-core v26.10.21 infra/conf/transport_test.go.
Map<String, dynamic> xdriveTemplateOutbound() => {
  'tag': 'Template storage',
  'protocol': 'vless',
  'settings': {
    'vnext': [
      {
        'address': 'example.test',
        'port': 443,
        'users': [
          {
            'id': '27848739-7e62-4138-9fd3-098a63964b6b',
            'encryption': 'mlkem768x25519plus.native.0rtt.XKbaq1BuzJKKKPxZbwgRpn-gYQbnhrYketgezASCL1I',
          },
        ],
      },
    ],
  },
  'mux': {'enabled': true, 'concurrency': 8},
  'streamSettings': {
    'network': 'xdrive',
    'xdriveSettings': {
      'service': 'template',
      'remoteFolder': 'fixture',
      'secrets': ['fixture-only'],
      'template': {
        'flatten': true,
        'concurrency': 2,
        'auth': {
          'type': 'static',
          'header': {'Authorization': 'Bearer {secret0}'},
          'futureAuth': {'keep': true},
        },
        for (final operation in ['put', 'get', 'delete', 'list'])
          operation: {
            'method': 'POST',
            'url': 'https://example.test/{folder}/{name}',
            'headers': {'X-User-Field': '{secret0}'},
            'body': '{data}',
            if (operation == 'list') 'namesRegex': r'"name":"([^"]+)"',
            'hrefPath': 'result.url',
            'hrefMethod': 'GET',
            'futureOperation': {'keep': true},
          },
        'retry': {
          'status': [429, 503],
          'rateReason': 'slow down',
        },
        'futureTemplate': {'keep': true},
      },
      'futureTransport': {'keep': true},
    },
  },
};
