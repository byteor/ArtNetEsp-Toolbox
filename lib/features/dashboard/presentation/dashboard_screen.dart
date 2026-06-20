import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_info/app_info_providers.dart';
import '../../../core/network/network_providers.dart';
import '../../../shared/widgets/log_view.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final netAsync = ref.watch(localNetworkStatusProvider);
    final appVersion = ref.watch(appVersionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Info'),
        actions: [
          IconButton(
            tooltip: 'Refresh network info',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(localNetworkStatusProvider),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Local network',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            netAsync.when(
              loading: () => const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('Reading network info…'),
                    ],
                  ),
                ),
              ),
              error: (e, _) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Network info unavailable: $e'),
                ),
              ),
              data: (status) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            status.hasWifi ? Icons.wifi : Icons.wifi_off,
                            color: status.hasWifi
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            status.hasWifi ? 'Connected' : 'No Wi-Fi detected',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _kv(context, 'Device IP', status.ipAddress ?? '—'),
                      _kv(context, 'Gateway', status.gateway ?? '—'),
                      _kv(context, 'Broadcast', status.broadcast ?? '—'),
                      _kv(context, 'Subnet mask', status.subnetMask ?? '—'),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Text(
                  'Activity log',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Text(
                  'foreground-only',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Expanded(child: LogView()),
            appVersion.when(
              data: (v) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'App version $v',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(k, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Expanded(
            child: Text(v, style: const TextStyle(fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }
}
