import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'udp_transport.dart';

/// Binds the underlying UDP socket. Overridable so tests can inject a socket
/// they control (e.g. to simulate the OS closing it when Wi-Fi changes).
typedef RawDatagramSocketBinder = Future<RawDatagramSocket> Function(int port);

Future<RawDatagramSocket> _bindAnyIPv4(int port) =>
    RawDatagramSocket.bind(InternetAddress.anyIPv4, port, reuseAddress: true);

/// [UdpTransport] backed by `dart:io`'s [RawDatagramSocket].
///
/// One socket is bound to `0.0.0.0:port` and shared for both sending and
/// receiving; incoming datagrams are fanned out on a broadcast stream. This
/// avoids binding the same port twice (discovery + monitor would otherwise
/// conflict on 6454).
///
/// The socket is **self-healing**: if the OS closes it (typically when the
/// Wi-Fi network changes), the transport drops it and reports [isBound] `false`
/// so the next [bind] re-creates a fresh, working socket. Without this the
/// cached socket stays dead and every later send throws
/// `SocketException: socket has been closed` until the app restarts.
///
/// Note: socket I/O here is event-loop driven (non-blocking), so it does not
/// block the UI thread. Heavy per-packet work belongs in the service/parsing
/// layer, which stays cheap (a few hundred bytes per packet).
class DartUdpTransport implements UdpTransport {
  DartUdpTransport({RawDatagramSocketBinder? bindSocket})
      : _bindSocket = bindSocket ?? _bindAnyIPv4;

  final RawDatagramSocketBinder _bindSocket;

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;
  final StreamController<UdpDatagram> _controller =
      StreamController<UdpDatagram>.broadcast();

  @override
  bool get isBound => _socket != null;

  @override
  Stream<UdpDatagram> get datagrams => _controller.stream;

  @override
  Future<void> bind(int port) async {
    if (_socket != null) return;
    final socket = await _bindSocket(port);
    _socket = socket;
    _subscription = socket.listen(
      (event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram != null) {
            _controller.add(
              UdpDatagram(datagram.address, datagram.port, datagram.data),
            );
          }
        } else if (event == RawSocketEvent.closed) {
          // OS closed the socket (e.g. the Wi-Fi network changed).
          _dropSocket(socket);
        }
      },
      onError: (Object error) {
        if (!_controller.isClosed) _controller.addError(error);
        _dropSocket(socket);
      },
      onDone: () => _dropSocket(socket),
    );
  }

  /// Releases a dead socket so the next [bind] can create a fresh one, while
  /// keeping the broadcast [_controller] alive (its subscribers — discovery,
  /// monitor — survive a reconnect). Idempotent; the identity guard ignores a
  /// late event for a socket we've already replaced so it can't tear down a
  /// newer one.
  void _dropSocket(RawDatagramSocket socket) {
    if (!identical(_socket, socket)) return;
    _subscription?.cancel();
    _subscription = null;
    _socket?.close();
    _socket = null;
  }

  @override
  set broadcast(bool value) {
    _socket?.broadcastEnabled = value;
  }

  @override
  int send(Uint8List data, String address, int port) {
    final socket = _socket;
    if (socket == null) return -1;
    final target = InternetAddress.tryParse(address);
    if (target == null) return -1;
    try {
      return socket.send(data, target, port);
    } on SocketException {
      // The socket died without delivering a close event (can happen on a
      // network change). Drop it so the next bind() re-creates a working socket
      // and report a failed send rather than throwing an unrecoverable error.
      _dropSocket(socket);
      return -1;
    }
  }

  @override
  void recycle() {
    final socket = _socket;
    if (socket != null) _dropSocket(socket);
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    _socket?.close();
    _socket = null;
    if (!_controller.isClosed) await _controller.close();
  }
}
