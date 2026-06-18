import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'network_info.dart';

final networkInfoServiceProvider =
    Provider<NetworkInfoService>((ref) => NetworkInfoService());

/// Current Wi-Fi/local-network status (IP, gateway, broadcast, mask).
/// Re-read by invalidating this provider (the dashboard exposes a refresh).
final localNetworkStatusProvider = FutureProvider<LocalNetworkStatus>((ref) {
  return ref.watch(networkInfoServiceProvider).read();
});
