import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/artnet/data/artnet_providers.dart';
import '../logging/logging_providers.dart';
import 'network_info.dart';
import 'network_providers.dart';

/// How often the device's network identity is polled while the app is in the
/// foreground. A switch is reflected within roughly this interval.
const Duration kNetworkPollInterval = Duration(seconds: 4);

/// A stable key identifying the active network. A change in this key means the
/// device moved to a different network (new Wi-Fi, dropped connection, etc.).
String networkIdentityKey(LocalNetworkStatus status) =>
    '${status.ipAddress}|${status.subnetMask}|${status.gateway}';

/// Emits the new [LocalNetworkStatus] whenever the active network changes.
///
/// We poll `network_info_plus` (already a dependency) rather than add a
/// connectivity plugin: it needs no extra package and, unlike connectivity-type
/// events, it also catches switching between two Wi-Fi networks of the same
/// type. The first reading is swallowed so app startup is not treated as a
/// change. Foreground-only; the timer is cancelled when the provider is
/// disposed.
final networkChangeDetectorProvider = StreamProvider<LocalNetworkStatus>((ref) {
  final service = ref.watch(networkInfoServiceProvider);
  final controller = StreamController<LocalNetworkStatus>();
  String? lastKey;
  Timer? timer;

  Future<void> poll() async {
    final status = await service.read();
    final key = networkIdentityKey(status);
    if (lastKey == null) {
      lastKey = key; // ignore the first reading (startup is not a "change")
      return;
    }
    if (key != lastKey) {
      lastKey = key;
      if (!controller.isClosed) controller.add(status);
    }
  }

  timer = Timer.periodic(kNetworkPollInterval, (_) => poll());
  poll(); // prime immediately so the first real change is caught fast

  ref.onDispose(() {
    timer?.cancel();
    controller.close();
  });
  return controller.stream;
});

/// Reacts to a network change with the data-side effects: refresh the Info
/// page's network status, recompute Art-Net broadcast targets for the new
/// subnet, and recycle the shared UDP socket so the first scan after the switch
/// works. Activate it by watching from the widget tree; the user-facing
/// "Network changed" SnackBar is shown separately by the UI ([RootShell]).
final networkChangeReactorProvider = Provider<void>((ref) {
  ref.listen(networkChangeDetectorProvider, (previous, next) {
    if (!next.hasValue) return; // ignore loading/error states
    final status = next.requireValue;
    final where = status.hasWifi ? (status.ipAddress ?? '?') : 'no Wi-Fi';
    ref.read(appLoggerProvider).info(
          'network',
          'Network changed — now $where; refreshed info, recycled Art-Net socket',
        );
    ref.invalidate(localNetworkStatusProvider);
    ref.invalidate(artnetBroadcastTargetsProvider);
    ref.read(artnetServiceProvider).recycle();
  });
});
