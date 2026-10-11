import 'package:onexray/core/errors/json_diagnostic.dart';

/// Templates supply preferences; App supplies selectors, fallback and subjects.
void checkSelectionDocument(Map<String, dynamic> json) {
  final routing = json['routing'];
  if (routing is Map && routing.containsKey('balancers')) {
    final balancers = routing['balancers'];
    const path = ['routing', 'balancers'];
    if (balancers is! List ||
        balancers.length != 1 ||
        balancers.single is! Map) {
      throw const JsonDiagnostic(
        'Exactly one proxy balancer preference is supported',
        path: path,
      );
    }
    final balancer = balancers.single as Map;
    _keys(balancer, {'tag', 'strategy'}, [...path, 0]);
    if (balancer['tag'] != 'proxy') {
      throw const JsonDiagnostic(
        'Use proxy',
        path: ['routing', 'balancers', 0, 'tag'],
      );
    }
    final strategy = balancer['strategy'];
    if (strategy is! Map) {
      throw const JsonDiagnostic(
        'strategy must be an object',
        path: ['routing', 'balancers', 0, 'strategy'],
      );
    }
    _keys(strategy, {'type'}, [...path, 0, 'strategy']);
    if (!{'roundRobin', 'leastPing'}.contains(strategy['type'])) {
      throw const JsonDiagnostic(
        'Use roundRobin or leastPing',
        path: ['routing', 'balancers', 0, 'strategy', 'type'],
      );
    }
  }
  if (json.containsKey('observatory')) {
    final value = json['observatory'];
    if (value is! Map) {
      throw const JsonDiagnostic(
        'observatory must be an object',
        path: ['observatory'],
      );
    }
    _keys(
      value,
      {'probeURL', 'probeInterval', 'enableConcurrency'},
      ['observatory'],
    );
  }
}

void _keys(Map value, Set<String> allowed, List<Object> path) {
  for (final key in value.keys) {
    if (!allowed.contains(key)) {
      throw JsonDiagnostic('App manages $key', path: [...path, key as String]);
    }
  }
}
