import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// A received UDP datagram (source address/port + payload).
class UdpDatagram {
  const UdpDatagram(this.address, this.port, this.data);

  final InternetAddress address;
  final int port;
  final Uint8List data;
}

/// Abstraction over a UDP socket so the Art-Net layer never touches `dart:io`
/// directly. This is the seam to swap in a native Swift/Kotlin transport later
/// if Dart sockets prove unreliable on a given platform — only this interface
/// and its implementation would change, not the services or UI.
abstract interface class UdpTransport {
  /// Binds to `0.0.0.0:[port]` (reuseAddress) and begins receiving.
  /// Throws [SocketException] if the port is unavailable — callers should
  /// surface that to the user (e.g. another Art-Net app already owns 6454).
  Future<void> bind(int port);

  /// Whether the socket is currently bound.
  bool get isBound;

  /// Broadcast stream of all incoming datagrams. Multiple listeners
  /// (discovery, monitor) can subscribe and filter independently.
  Stream<UdpDatagram> get datagrams;

  /// Enables/disables sending to broadcast addresses.
  set broadcast(bool value);

  /// Sends [data] to [address]:[port]. [address] must be an IPv4/IPv6 literal.
  /// Returns the number of bytes sent, or -1 if not bound / address invalid.
  int send(Uint8List data, String address, int port);

  /// Releases the socket and stops receiving.
  Future<void> close();

  /// Drops the current socket (if any) so the next [bind] re-creates a fresh
  /// one — used to proactively recover after a network change. Unlike [close]
  /// it keeps the [datagrams] stream open, so existing subscribers survive the
  /// reconnect. No-op when not bound.
  void recycle();
}
