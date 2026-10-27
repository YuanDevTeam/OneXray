import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onexray/service/shared/share/service.dart';

void main() {
  late StreamController<Uri> links;
  late ShareService service;
  final first = Uri.parse(
    'onexray://onexray.com/sub/add?url=https://a.example',
  );
  final second = Uri.parse(
    'onexray://onexray.com/sub/add?url=https://b.example',
  );

  setUp(() {
    links = StreamController<Uri>.broadcast(sync: true);
    service = ShareService.forTesting(
      appLinks: links.stream,
      receiveWidgetUri: (uri) => uri.host == 'widget',
    );
    service.startAppLinks();
  });
  tearDown(() async {
    service.dispose();
    await links.close();
  });

  test('initialization completes with an unconsumed cold link', () async {
    links.add(first);
    await service.init();
    final event = service.claimNextAppLink()!;
    expect(event.uri, first);
    expect(service.claimNextAppLink(), isNull);
  });

  test('broadcast and proactive read share one FIFO claim', () async {
    links.add(first);
    final claimed = <IncomingAppLink>[];
    final subscription = service.pendingAppLinksChanged.listen((_) {
      final event = service.claimNextAppLink();
      if (event != null) claimed.add(event);
    });
    addTearDown(subscription.cancel);
    claimed.add(service.claimNextAppLink()!);
    links.add(second);
    await pumpEventQueue();
    expect(claimed.map((event) => event.uri), [first]);
    service.finishAppLink(claimed.single);
    await pumpEventQueue();
    expect(claimed.map((event) => event.uri), [first, second]);
  });

  test('coalesces queued and active duplicates but permits a later reopen', () {
    links.add(first);
    links.add(first);
    links.add(second);
    final event = service.claimNextAppLink()!;
    links.add(first);
    service.finishAppLink(event);
    final next = service.claimNextAppLink()!;
    expect(next.uri, second);
    service.finishAppLink(next);
    expect(service.claimNextAppLink(), isNull);
    links.add(first);
    expect(service.claimNextAppLink()!.uri, first);
  });

  test('widget URIs do not enter the import queue', () {
    links.add(Uri.parse('onexray://widget/connect'));
    expect(service.claimNextAppLink(), isNull);
  });

  test('old completion after teardown cannot finish a newer event', () async {
    links.add(first);
    final old = service.claimNextAppLink()!;
    service.dispose();
    await service.init();
    links.add(first);
    final current = service.claimNextAppLink()!;
    service.finishAppLink(old);
    expect(service.claimNextAppLink(), isNull);
    links.add(second);
    service.finishAppLink(current);
    expect(service.claimNextAppLink()!.uri, second);
  });
}
