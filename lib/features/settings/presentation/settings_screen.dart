import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/settings/settings_providers.dart';
import '../../device_config/data/device_config_client.dart';
import '../../device_config/data/device_credentials_store.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _broadcast;
  late final TextEditingController _port;
  late final TextEditingController _mdns;
  late final TextEditingController _packetLimit;
  late final TextEditingController _deviceAuthUser;
  late final TextEditingController _deviceAuthPass;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _broadcast = TextEditingController(text: s.broadcastAddress);
    _port = TextEditingController(text: '${s.artNetPort}');
    _mdns = TextEditingController(text: s.mdnsServiceTypes.join(', '));
    _packetLimit = TextEditingController(text: '${s.packetDisplayLimit}');
    final creds = ref.read(deviceCredentialStoreProvider).defaultCredentials;
    _deviceAuthUser = TextEditingController(text: creds?.user ?? '');
    _deviceAuthPass = TextEditingController(text: creds?.pass ?? '');
  }

  @override
  void dispose() {
    _broadcast.dispose();
    _port.dispose();
    _mdns.dispose();
    _packetLimit.dispose();
    _deviceAuthUser.dispose();
    _deviceAuthPass.dispose();
    super.dispose();
  }

  void _saveDeviceAuth() {
    final user = _deviceAuthUser.text;
    final pass = _deviceAuthPass.text;
    ref.read(deviceCredentialStoreProvider).setDefault(
          (user.isEmpty && pass.isEmpty) ? null : DeviceCredentials(user, pass),
        );
  }

  static final Uri _gitHubUri =
      Uri.parse('https://github.com/byteor/ArtNetEsp-Toolbox');

  Future<void> _openGitHub() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok =
          await launchUrl(_gitHubUri, mode: LaunchMode.externalApplication);
      if (!ok) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not open $_gitHubUri')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open link: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: _openGitHub,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.open_in_new,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'ArtNetEsp Toolbox on GitHub',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        decoration: TextDecoration.underline,
                        decorationColor: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 24),
          Text('Art-Net', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _broadcast,
            onSubmitted: controller.setBroadcastAddress,
            decoration: const InputDecoration(
              labelText: 'Broadcast address',
              helperText:
                  'Used when no manual target is given (commit with ↵).',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Prefer computed subnet broadcast'),
            subtitle: const Text(
              'Use the auto-computed x.x.x.255 when available (more reliable).',
            ),
            value: settings.preferComputedBroadcast,
            onChanged: controller.setPreferComputedBroadcast,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _port,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (v) {
              final p = int.tryParse(v);
              if (p != null && p > 0 && p < 65536) {
                controller.setArtNetPort(p);
              }
            },
            decoration: const InputDecoration(
              labelText: 'Art-Net UDP port',
              helperText: 'Default 6454. Changing it rebinds the socket.',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Listen timeout: ${(settings.listenTimeoutMs / 1000).toStringAsFixed(1)} s',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Slider(
            value: settings.listenTimeoutMs.clamp(500, 10000).toDouble(),
            min: 500,
            max: 10000,
            divisions: 19,
            label: '${(settings.listenTimeoutMs / 1000).toStringAsFixed(1)} s',
            onChanged: (v) => controller.setListenTimeoutMs(v.round()),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _packetLimit,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (v) {
              final n = int.tryParse(v);
              if (n != null && n > 0 && n <= 100000) {
                controller.setPacketDisplayLimit(n);
              }
            },
            decoration: const InputDecoration(
              labelText: 'Monitor packet log limit',
              helperText:
                  'Max recent packets shown in the monitor (default 500).',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const Divider(height: 32),
          Text('mDNS', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _mdns,
            minLines: 1,
            maxLines: 4,
            onSubmitted: (v) => controller.setMdnsServiceTypes(
              v
                  .split(',')
                  .map((t) => t.trim())
                  .where((t) => t.isNotEmpty)
                  .toList(),
            ),
            decoration: const InputDecoration(
              labelText: 'Default service types (comma-separated)',
              helperText:
                  'iOS: each type must also be in Info.plist NSBonjourServices.',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const Divider(height: 32),
          Text(
            'Device authentication',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Tried automatically when a device requires HTTP auth (Configure). '
            'If they fail you are asked once, and working credentials are '
            'remembered per device.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _deviceAuthUser,
            autofillHints: const [AutofillHints.username],
            onSubmitted: (_) => _saveDeviceAuth(),
            decoration: const InputDecoration(
              labelText: 'Default username',
              helperText: 'Leave blank if your devices have auth disabled.',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _deviceAuthPass,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _saveDeviceAuth(),
            decoration: const InputDecoration(
              labelText: 'Default password',
              helperText: 'Encrypted in the device keystore (commit with ↵).',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const Divider(height: 32),
          Text('Diagnostics', style: Theme.of(context).textTheme.titleMedium),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Debug logging'),
            subtitle: const Text('Record verbose debug-level log entries.'),
            value: settings.debugLogging,
            onChanged: controller.setDebugLogging,
          ),
          const SizedBox(height: 24),
          Text(
            'Foreground-only diagnostic build. Settings are saved automatically.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
