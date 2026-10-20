import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/advanced/local_api/configuration.dart';
import 'package:onexray/service/advanced/local_api/server.dart';

void main() {
  test(
    'HTTP API uses App parsing and compilation without external tools',
    () async {
      const token = 'http-integration-test-token';
      var kernelCalls = 0;
      final configuration = LocalApiConfiguration(
        withResources: (action) => action(),
        testXray: (text) async {
          kernelCalls++;
          final projected = jsonDecode(text) as Map<String, dynamic>;
          expect(projected['outbounds'].single['protocol'], 'freedom');
          expect(projected.containsKey('inbounds'), false);
          expect(projected['log']['error'], 'none');
          return '';
        },
      );
      final server = LocalApiServer(
        token: () => token,
        available: () => true,
        info: () async => {
          'appVersion': 'integration-test',
          'coreVersion': 'stub-no-native-core',
          'platform': 'macos',
          'supportedKinds': ['outbound', 'routing', 'advanced-routing', 'raw'],
        },
        validate: configuration.validate,
        compile: configuration.compile,
      );
      final client = HttpClient()..findProxy = (_) => 'DIRECT';
      addTearDown(() async {
        client.close(force: true);
        await server.close();
        await server.drained;
      });
      server.attach(await LocalApiServer.bind(0));

      Future<({int status, Map<String, dynamic> body})> request(
        String path, {
        String auth = token,
        Map<String, dynamic>? input,
      }) async {
        final req = await client.openUrl(
          input == null ? 'GET' : 'POST',
          Uri.parse('http://127.0.0.1:${server.port}$path'),
        );
        req.followRedirects = false;
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $auth');
        if (input != null) {
          req.headers.contentType = ContentType.json;
          req.add(utf8.encode(jsonEncode(input)));
        }
        final response = await req.close();
        return (
          status: response.statusCode,
          body: jsonDecode(
            await utf8.decoder.bind(response).join(),
          ) as Map<String, dynamic>,
        );
      }

      expect((await request('/api/v1/info', auth: 'wrong')).status, 401);
      final info = await request('/api/v1/info');
      expect(info.status, 200);
      expect(info.body['apiVersion'], 1);
      expect(info.body['appVersion'], 'integration-test');
      expect(jsonEncode(info.body), isNot(contains(token)));
      expect(kernelCalls, 0);

      final valid = await request(
        '/api/v1/config/validate',
        input: {
          'kind': 'outbound',
          'text': '{"tag":"HTTP node","protocol":"freedom"}',
        },
      );
      expect(valid.status, 200);
      expect(valid.body['status'], 'passed');
      expect(valid.body['stage'], 'kernel');
      expect(valid.body['validationConfig'], isNotEmpty);
      expect(kernelCalls, 1);

      final invalid = await request(
        '/api/v1/config/validate',
        input: {
          'kind': 'routing',
          'text': '{"outbounds":[{}],"routing":{"rules":[{"sourceIP":["10.0.0.1"]}]}}',
        },
      );
      expect(invalid.status, 200);
      expect(invalid.body['status'], 'failed');
      expect(invalid.body['stage'], 'input');
      final diagnostic = (invalid.body['diagnostics'] as List).single;
      expect(diagnostic['path'], ['routing', 'rules', 0, 'sourceIP']);
      expect(diagnostic['offset'], 50);
      expect(diagnostic['line'], 1);
      expect(diagnostic['column'], 51);
      expect(kernelCalls, 1);

      final compiled = await request(
        '/api/v1/config/compile',
        input: {
          'kind': 'raw',
          'text': '{"name":"HTTP preview","outbounds":[{"tag":"direct","protocol":"freedom"}]}',
          'options': {
            'platform': 'macos',
            'sessionDirectory': '/preview/no-files-created',
            'metricsPort': 19021,
            'socksPort': 19022,
            'ipv6': true,
          },
        },
      );
      expect(compiled.status, 200);
      expect(compiled.body['status'], 'passed');
      expect(compiled.body['stage'], 'compile');
      final preview = jsonDecode(
        compiled.body['compiledConfig'] as String,
      ) as Map<String, dynamic>;
      expect(preview['inbounds'].single['protocol'], 'tun');
      expect(preview['outbounds'].first, {
        'tag': 'direct',
        'protocol': 'freedom',
      });
      expect(preview['dns']['servers'], isNotEmpty);
      expect(preview['metrics']['listen'], '127.0.0.1:19021');
      expect(kernelCalls, 1);
    },
  );
}
