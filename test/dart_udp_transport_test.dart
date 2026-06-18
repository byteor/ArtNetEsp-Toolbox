import 'dart:io';
import 'dart:typed_data';

import 'package:artnet_app/core/network/dart_udp_transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lets the socket's close event propagate to the transport's listener.
Future<void> _pump() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  group('DartUdpTransport recovers from a closed socket (Wi-Fi switch)', () {
    // Records every socket the transport binds so a test can (a) close one to
    // mimic the OS tearing it down on a network change and (b) assert a genuinely
    // fresh socket is created on rebind.
    late List<RawDatagramSocket> bound;
    late DartUdpTransport transport;

    setUp(() {
      bound = <RawDatagramSocket>[];
      transport = DartUdpTransport(bindSocket: (port) async {
        final socket = await RawDatagramSocket.bind(
            InternetAddress.anyIPv4, port, reuseAddress: true);
        bound.add(socket);
        return socket;
      });
    });

    tearDown(() => transport.close());

    test('marks itself unbound when the OS closes the socket', () async {
      await transport.bind(0);
      expect(transport.isBound, isTrue);

      // The OS closes the socket when Wi-Fi changes.
      bound.last.close();
      await _pump();

      expect(transport.isBound, isFalse,
          reason: 'a dead socket must leave the transport unbound so the next '
              'scan rebinds instead of reusing a closed socket');
    });

    test('rebinds a fresh socket after the old one was closed', () async {
      await transport.bind(0);
      bound.last.close();
      await _pump();

      // The next bind() must create a new working socket, not no-op on the dead
      // one (the pre-fix bug: bind() returned early forever once _socket was set).
      await transport.bind(0);

      expect(transport.isBound, isTrue);
      expect(bound, hasLength(2));
      expect(identical(bound[0], bound[1]), isFalse,
          reason: 'recovery must create a genuinely new socket');
    });

    test('send on a dead socket fails gracefully instead of throwing', () async {
      await transport.bind(0);
      bound.last.close();

      // Pre-fix this surfaced `SocketException: socket has been closed` to the
      // UI. It must now degrade to a failed send (and leave us rebindable).
      expect(
        () => transport.send(Uint8List.fromList(const [1, 2, 3]), '127.0.0.1',
            6454),
        returnsNormally,
      );
      await _pump();
      expect(transport.isBound, isFalse);
    });

    test('recycle() proactively drops the socket and allows a fresh rebind',
        () async {
      await transport.bind(0);
      expect(transport.isBound, isTrue);

      // Proactive recovery on a detected network change (no close event needed).
      transport.recycle();
      expect(transport.isBound, isFalse);

      await transport.bind(0);
      expect(transport.isBound, isTrue);
      expect(bound, hasLength(2));
      expect(identical(bound[0], bound[1]), isFalse);
    });

    test('recycle() is a no-op when not bound', () {
      expect(transport.recycle, returnsNormally);
      expect(transport.isBound, isFalse);
    });
  });
}
