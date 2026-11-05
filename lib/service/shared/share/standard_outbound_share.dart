import 'package:onexray/core/pigeon/host_api.dart';
import 'package:onexray/core/tools/json.dart';

/// The standard-link projection must never mutate the stored outbound graph.
final class StandardOutboundShareService {
  StandardOutboundShareService({
    Future<String> Function(Map<String, dynamic>)? encoder,
  }) : _encoder = encoder ?? AppHostApi().convertXrayJsonToShareLinks;

  final Future<String> Function(Map<String, dynamic>) _encoder;

  Future<String> encode(Map<String, dynamic> outbound) async {
    final copy = JsonTool.copyMap(outbound);
    final socks = copy['protocol'] == 'socks';
    if (socks) {
      _prepareSocks(copy);
    }
    final result = await _encoder({
      'outbounds': [copy],
    });
    if (socks) {
      _validateSocksLink(result);
    }
    return result;
  }

  static void _prepareSocks(Map<String, dynamic> outbound) {
    final settings = outbound['settings'];
    if (settings is! Map<String, dynamic>) {
      throw _unsupportedSocks;
    }
    // Xray gives a non-null flat address precedence over legacy servers.
    if (settings['address'] == null) {
      final servers = settings['servers'];
      if (servers is! List || servers.length != 1) {
        throw _unsupportedSocks;
      }
      final server = servers.single;
      if (server is! Map<String, dynamic>) {
        throw _unsupportedSocks;
      }
      final users = server['users'];
      if (users != null && (users is! List || users.length > 1)) {
        throw _unsupportedSocks;
      }
      settings
        ..remove('servers')
        ..remove('user')
        ..remove('pass')
        ..['address'] = server['address']
        ..['port'] = server['port'];
      if (users is List && users.isNotEmpty) {
        final user = users.single;
        if (user is! Map<String, dynamic>) {
          throw _unsupportedSocks;
        }
        settings['user'] = user['user'] ?? '';
        settings['pass'] = user['pass'] ?? '';
      }
    }
    final address = settings['address'];
    final port = settings['port'];
    if (address is! String ||
        address.isEmpty ||
        _invalidHost.hasMatch(address) ||
        port is! int ||
        port < 1 ||
        port > 65535 ||
        (settings['user'] != null && settings['user'] is! String) ||
        (settings['pass'] != null && settings['pass'] is! String)) {
      throw _unsupportedSocks;
    }
  }

  static void _validateSocksLink(String text) {
    try {
      final uri = Uri.parse(text);
      final host = Uri.decodeComponent(uri.host);
      if (text.trim() != text ||
          text.contains(RegExp(r'[\r\n]')) ||
          uri.scheme != 'socks' ||
          !uri.hasAuthority ||
          host.isEmpty ||
          _invalidHost.hasMatch(host) ||
          !uri.hasPort ||
          uri.port < 1 ||
          uri.port > 65535) {
        throw _invalidSocksLink;
      }
    } on FormatException {
      // Do not include generated credentials or a server address in diagnostics.
      throw _invalidSocksLink;
    }
  }

  static final _invalidHost = RegExp(r'[\s<>\x00-\x1f\x7f]');
  static const _unsupportedSocks = FormatException(
    'This SOCKS configuration cannot be represented as a standard link. '
    'Use the OneXray link to preserve the configuration.',
  );
  static const _invalidSocksLink = FormatException(
    'The generated SOCKS link has no valid server address or port. '
    'Use the OneXray link instead.',
  );
}
