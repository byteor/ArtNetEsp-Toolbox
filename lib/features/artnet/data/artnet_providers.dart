import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/logging_providers.dart';
import '../../../core/network/dart_udp_transport.dart';
import '../../../core/network/multicast_lock.dart';
import '../../../core/network/network_providers.dart';
import '../../../core/settings/settings_providers.dart';
import '../domain/artnet_node.dart';
import 'artnet_service.dart';

// ---------------------------------------------------------------------------
// Service wiring
// ---------------------------------------------------------------------------

final multicastLockProvider =
    Provider<MulticastLock>((ref) => createMulticastLock());

/// The Art-Net service. Rebuilt (and the old socket disposed) if the configured
/// UDP port changes. Owns its [DartUdpTransport]; inject a fake in tests by
/// constructing [ArtnetService] directly.
final artnetServiceProvider = Provider<ArtnetService>((ref) {
  final port = ref.watch(settingsProvider.select((s) => s.artNetPort));
  final service = ArtnetService(
    transport: DartUdpTransport(),
    multicastLock: ref.watch(multicastLockProvider),
    logger: ref.watch(appLoggerProvider),
    port: port,
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Broadcast addresses to poll when no manual unicast target is given:
/// computed subnet broadcast first (if preferred & available), then the
/// configured broadcast address (limited broadcast by default).
final artnetBroadcastTargetsProvider = FutureProvider<List<String>>((ref) async {
  final settings = ref.watch(settingsProvider);
  final targets = <String>[];
  try {
    final status = await ref.watch(localNetworkStatusProvider.future);
    if (settings.preferComputedBroadcast &&
        status.broadcast != null &&
        status.broadcast!.isNotEmpty) {
      targets.add(status.broadcast!);
    }
  } catch (_) {
    // network info unavailable — fall back to configured broadcast only
  }
  if (settings.broadcastAddress.isNotEmpty &&
      !targets.contains(settings.broadcastAddress)) {
    targets.add(settings.broadcastAddress);
  }
  return targets;
});

// ---------------------------------------------------------------------------
// Discovery
// ---------------------------------------------------------------------------

class DiscoveryState {
  const DiscoveryState({
    this.scanning = false,
    this.nodes = const [],
    this.error = '',
    this.lastScan,
    this.manualTarget = '',
  });

  final bool scanning;
  final List<ArtNetNode> nodes;
  final String error;
  final DateTime? lastScan;
  final String manualTarget;

  DiscoveryState copyWith({
    bool? scanning,
    List<ArtNetNode>? nodes,
    String? error,
    DateTime? lastScan,
    String? manualTarget,
  }) {
    return DiscoveryState(
      scanning: scanning ?? this.scanning,
      nodes: nodes ?? this.nodes,
      error: error ?? this.error,
      lastScan: lastScan ?? this.lastScan,
      manualTarget: manualTarget ?? this.manualTarget,
    );
  }
}

class DiscoveryController extends Notifier<DiscoveryState> {
  @override
  DiscoveryState build() => const DiscoveryState();

  void setManualTarget(String target) =>
      state = state.copyWith(manualTarget: target);

  Future<void> scan() async {
    if (state.scanning) return;
    state = state.copyWith(scanning: true, error: '');
    final service = ref.read(artnetServiceProvider);
    final settings = ref.read(settingsProvider);
    try {
      List<String> broadcastTargets;
      try {
        broadcastTargets = await ref.read(artnetBroadcastTargetsProvider.future);
      } catch (_) {
        broadcastTargets = [settings.broadcastAddress];
      }
      final manual = state.manualTarget.trim();
      final nodes = await service.discover(
        target: manual.isEmpty ? null : manual,
        broadcastTargets: broadcastTargets,
        timeout: settings.listenTimeout,
      );
      state = state.copyWith(
        nodes: nodes,
        scanning: false,
        lastScan: DateTime.now(),
      );
    } catch (e) {
      state = state.copyWith(
        scanning: false,
        error: e.toString(),
        lastScan: DateTime.now(),
      );
    }
  }
}

final discoveryControllerProvider =
    NotifierProvider<DiscoveryController, DiscoveryState>(
  DiscoveryController.new,
);

// ---------------------------------------------------------------------------
// Universe monitor
// ---------------------------------------------------------------------------

class MonitorState {
  const MonitorState({
    this.listening = false,
    this.universe = 0,
    this.packetCount = 0,
    this.lastSequence = -1,
    this.lastSourceIp = '',
    this.channels = const [],
    this.log = const [],
    this.error = '',
  });

  final bool listening;
  final int universe;
  final int packetCount;
  final int lastSequence; // -1 when none yet
  final String lastSourceIp; // '' when none yet
  final List<int> channels; // first up-to-16
  final List<String> log; // rolling, newest last
  final String error;

  MonitorState copyWith({
    bool? listening,
    int? universe,
    int? packetCount,
    int? lastSequence,
    String? lastSourceIp,
    List<int>? channels,
    List<String>? log,
    String? error,
  }) {
    return MonitorState(
      listening: listening ?? this.listening,
      universe: universe ?? this.universe,
      packetCount: packetCount ?? this.packetCount,
      lastSequence: lastSequence ?? this.lastSequence,
      lastSourceIp: lastSourceIp ?? this.lastSourceIp,
      channels: channels ?? this.channels,
      log: log ?? this.log,
      error: error ?? this.error,
    );
  }
}

/// Monitors one universe at a time. Network packets can arrive at up to ~44 Hz
/// per universe; to keep the UI smooth, incoming packets update private
/// accumulators and a periodic ticker pushes a fresh [MonitorState] at ~2.5 Hz
/// (slow enough to render the full 512-channel grid without jank).
class MonitorController extends Notifier<MonitorState> {
  StreamSubscription<ArtDmxMonitorEvent>? _sub;
  Timer? _ticker;

  int _count = 0;
  int _lastSeq = -1;
  String _lastIp = '';
  List<int> _channels = const [];
  final List<String> _log = [];
  bool _dirty = false;

  @override
  MonitorState build() {
    ref.onDispose(_teardown);
    return const MonitorState();
  }

  void setUniverse(int universe) {
    if (state.listening) return; // change universe only while stopped
    state = state.copyWith(universe: universe);
  }

  void start() {
    if (state.listening) return;
    _count = 0;
    _lastSeq = -1;
    _lastIp = '';
    _channels = const [];
    _log.clear();
    _dirty = true;
    state = MonitorState(listening: true, universe: state.universe);

    final service = ref.read(artnetServiceProvider);
    _sub = service.monitorUniverse(state.universe).listen(
      (event) {
        _count++;
        _lastSeq = event.packet.sequence;
        _lastIp = event.sourceIp;
        _channels = event.packet.channels; // full frame (up to 512 channels)
        _log.add(
          '${_two(event.time.minute)}:${_two(event.time.second)}  '
          '${event.sourceIp}  seq=${event.packet.sequence} len=${event.packet.length}',
        );
        final limit = ref.read(settingsProvider).packetDisplayLimit;
        while (_log.length > limit) {
          _log.removeAt(0);
        }
        _dirty = true;
      },
      onError: (Object e) {
        state = state.copyWith(listening: false, error: e.toString());
        _teardown();
      },
    );

    _ticker = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!_dirty) return;
      _dirty = false;
      state = state.copyWith(
        packetCount: _count,
        lastSequence: _lastSeq,
        lastSourceIp: _lastIp,
        channels: List<int>.of(_channels),
        log: List<String>.of(_log),
      );
    });
  }

  Future<void> stop() async {
    await _teardown();
    state = state.copyWith(listening: false);
  }

  Future<void> _teardown() async {
    _ticker?.cancel();
    _ticker = null;
    await _sub?.cancel();
    _sub = null;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}

final monitorControllerProvider =
    NotifierProvider<MonitorController, MonitorState>(MonitorController.new);

// ---------------------------------------------------------------------------
// Transmit / test
// ---------------------------------------------------------------------------

class TransmitState {
  const TransmitState({
    this.target = '',
    this.universe = 0,
    this.channel = 1,
    this.value = 255,
    this.sending = false,
    this.status = '',
    this.sequence = 0,
  });

  final String target;
  final int universe;
  final int channel; // 1..512
  final int value; // 0..255
  final bool sending;
  final String status;
  final int sequence;

  TransmitState copyWith({
    String? target,
    int? universe,
    int? channel,
    int? value,
    bool? sending,
    String? status,
    int? sequence,
  }) {
    return TransmitState(
      target: target ?? this.target,
      universe: universe ?? this.universe,
      channel: channel ?? this.channel,
      value: value ?? this.value,
      sending: sending ?? this.sending,
      status: status ?? this.status,
      sequence: sequence ?? this.sequence,
    );
  }
}

class TransmitController extends Notifier<TransmitState> {
  @override
  TransmitState build() =>
      TransmitState(target: ref.read(settingsProvider).broadcastAddress);

  void setTarget(String v) => state = state.copyWith(target: v);
  void setUniverse(int v) => state = state.copyWith(universe: v);
  void setChannel(int v) => state = state.copyWith(channel: v.clamp(1, 512));
  void setValue(int v) => state = state.copyWith(value: v.clamp(0, 255));

  Future<void> send() async {
    final target = state.target.trim();
    if (target.isEmpty) {
      state = state.copyWith(status: 'Enter a target IP first');
      return;
    }
    state = state.copyWith(sending: true, status: '');
    final service = ref.read(artnetServiceProvider);
    final seq = (state.sequence % 255) + 1;
    final channels = List<int>.filled(512, 0);
    channels[(state.channel - 1).clamp(0, 511)] = state.value & 0xFF;
    try {
      final sent = await service.sendDmx(
        target: target,
        universe: state.universe,
        channels: channels,
        sequence: seq,
      );
      state = state.copyWith(
        sending: false,
        sequence: seq,
        status: sent < 0
            ? 'Send failed — check the target IP'
            : 'Sent ArtDmx ($sent bytes) ch${state.channel}=${state.value} to $target',
      );
    } catch (e) {
      state = state.copyWith(sending: false, status: 'Error: $e');
    }
  }
}

final transmitControllerProvider =
    NotifierProvider<TransmitController, TransmitState>(TransmitController.new);
