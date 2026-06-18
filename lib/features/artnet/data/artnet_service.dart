import 'dart:async';

import '../../../core/logging/app_logger.dart';
import '../../../core/network/multicast_lock.dart';
import '../../../core/network/udp_transport.dart';
import '../domain/art_dmx.dart';
import '../domain/art_poll.dart';
import '../domain/art_poll_reply.dart';
import '../domain/artnet_node.dart';

const String _kTag = 'artnet';

/// One received, universe-matched ArtDmx packet plus its source.
class ArtDmxMonitorEvent {
  const ArtDmxMonitorEvent({
    required this.sourceIp,
    required this.packet,
    required this.time,
  });

  final String sourceIp;
  final ArtDmxPacket packet;
  final DateTime time;
}

/// High-level Art-Net operations over a [UdpTransport].
///
/// Owns a single socket bound to [port]; discovery, monitoring and transmit all
/// share it. Packet building/parsing is delegated to the pure `domain/` codec.
/// The service is transport-agnostic (inject a fake [UdpTransport] in tests).
class ArtnetService {
  ArtnetService({
    required UdpTransport transport,
    required MulticastLock multicastLock,
    required AppLogger logger,
    required int port,
  })  : _transport = transport,
        _multicastLock = multicastLock,
        _logger = logger,
        _port = port;

  final UdpTransport _transport;
  final MulticastLock _multicastLock;
  final AppLogger _logger;
  final int _port;

  int get port => _port;

  /// Binds the shared socket (idempotent). Rethrows [Exception] (e.g. port in
  /// use) so the caller can show a diagnostic message.
  Future<void> ensureBound() async {
    if (_transport.isBound) return;
    try {
      await _transport.bind(_port);
      _transport.broadcast = true;
      _logger.info(_kTag, 'UDP socket bound on 0.0.0.0:$_port');
    } catch (e) {
      _logger.error(_kTag, 'Failed to bind UDP port $_port', e);
      rethrow;
    }
  }

  /// Sends an ArtPoll and collects ArtPollReply packets for [timeout].
  ///
  /// If [target] is given it is polled directly (unicast); otherwise each entry
  /// in [broadcastTargets] is polled (e.g. computed subnet broadcast + limited
  /// broadcast). Results are de-duplicated by IP.
  Future<List<ArtNetNode>> discover({
    String? target,
    required List<String> broadcastTargets,
    required Duration timeout,
  }) async {
    await _multicastLock.acquire();
    final byIp = <String, ArtNetNode>{};
    StreamSubscription<UdpDatagram>? sub;
    try {
      await ensureBound();
      _transport.broadcast = true;

      sub = _transport.datagrams.listen((dg) {
        final source = dg.address.address;
        final node = parseArtPollReply(dg.data, sourceIp: source);
        if (node == null) return;
        final ip = node.ip.isNotEmpty ? node.ip : source;
        byIp[ip] = node.copyWith(ip: ip, lastSeen: DateTime.now());
        _logger.info(_kTag,
            'ArtPollReply from $ip — "${node.shortName}" / "${node.longName}"');
      });

      final poll = buildArtPoll();
      final targets = <String>[];
      if (target != null && target.trim().isNotEmpty) {
        targets.add(target.trim());
      } else {
        targets.addAll(broadcastTargets.where((t) => t.trim().isNotEmpty));
      }
      if (targets.isEmpty) {
        _logger.warning(_kTag, 'No Art-Net target/broadcast address available');
      }
      for (final t in targets) {
        final sent = _transport.send(poll, t, _port);
        if (sent < 0) {
          _logger.warning(_kTag, 'Could not send ArtPoll to $t (invalid/unbound)');
        } else {
          _logger.debug(_kTag, 'Sent ArtPoll ($sent bytes) to $t:$_port');
        }
      }

      await Future<void>.delayed(timeout);
      return byIp.values.toList(growable: false);
    } finally {
      await sub?.cancel();
      await _multicastLock.release();
    }
  }

  /// Streams ArtDmx packets for [universe]. Holds the multicast lock and the
  /// socket binding for as long as there is a listener.
  Stream<ArtDmxMonitorEvent> monitorUniverse(int universe) {
    StreamSubscription<UdpDatagram>? sub;
    late final StreamController<ArtDmxMonitorEvent> controller;
    controller = StreamController<ArtDmxMonitorEvent>(
      onListen: () async {
        await _multicastLock.acquire();
        try {
          await ensureBound();
        } catch (e) {
          if (!controller.isClosed) controller.addError(e);
          return;
        }
        _logger.info(_kTag, 'Monitoring universe $universe');
        sub = _transport.datagrams.listen((dg) {
          final packet = parseArtDmx(dg.data);
          if (packet == null || packet.universe != universe) return;
          if (!controller.isClosed) {
            controller.add(ArtDmxMonitorEvent(
              sourceIp: dg.address.address,
              packet: packet,
              time: DateTime.now(),
            ));
          }
        });
      },
      onCancel: () async {
        await sub?.cancel();
        await _multicastLock.release();
        _logger.info(_kTag, 'Stopped monitoring universe $universe');
      },
    );
    return controller.stream;
  }

  /// Sends a single ArtDmx frame (512 channels) to [target]. Returns bytes sent
  /// (or -1 on failure). WARNING: this can drive real lighting equipment.
  Future<int> sendDmx({
    required String target,
    required int universe,
    required List<int> channels,
    int sequence = 0,
  }) async {
    await ensureBound();
    final packet =
        buildArtDmx(universe: universe, channels: channels, sequence: sequence);
    final sent = _transport.send(packet, target, _port);
    if (sent < 0) {
      _logger.error(_kTag, 'Failed to send ArtDmx to $target:$_port');
    } else {
      _logger.info(_kTag,
          'Sent ArtDmx universe $universe ($sent bytes) to $target:$_port');
    }
    return sent;
  }

  /// Proactively drops the shared socket so the next bind re-creates it (e.g.
  /// after the Wi-Fi network changed). Safe to call when not bound.
  void recycle() => _transport.recycle();

  Future<void> dispose() async {
    await _transport.close();
  }
}
