import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../device_config/presentation/device_config_screen.dart';
import '../data/scan_providers.dart';
import '../domain/scanned_device.dart';

/// Combined-scan screen: discovers Art-Net + mDNS devices, probes each over HTTP
/// (`/status`, then `/config`), and lists the merged result.
class ScanScreen extends ConsumerWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(scanControllerProvider);
    final controller = ref.read(scanControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('ArtNet Scan')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: state.scanning ? null : controller.scan,
              icon: state.scanning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.radar),
              label: Text(state.scanning ? 'Scanning…' : 'Scan'),
            ),
            if (state.scanning && state.phase.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const SizedBox(width: 4),
                  Text(
                    state.phase,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const LinearProgressIndicator(),
            ],
            if (state.error.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Error: ${state.error}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '${state.devices.length} device(s) · ${state.goodCount} active',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                if (state.lastScan != null)
                  Text(
                    'last scan ${_clock(state.lastScan!)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
            if (state.devices.isEmpty && !state.scanning) ...[
              const SizedBox(height: 4),
              Text(
                "Tap 'Scan' button to discover ArtNet devices",
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: state.devices.isEmpty
                  ? const _ScanIntro()
                  : ListView.separated(
                      itemCount: state.devices.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) =>
                          _DeviceTile(device: state.devices[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _clock(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device});
  final ScannedDevice device;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final info = device.info;
    final artnet = device.artnet;
    final good = device.good;

    final subtitle = good
        ? '${device.ip} · ${info!.chip} · v${info.version}'
        : device.ip;

    final tile = Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        leading: Icon(
          good ? Icons.check_circle : Icons.lightbulb_outline,
          color: good ? scheme.primary : scheme.onSurfaceVariant,
        ),
        title: Text(device.title),
        subtitle: Text(subtitle),
        trailing: Wrap(
          spacing: 4,
          children: [
            for (final s in device.sources) _SourceChip(label: s),
            const Icon(Icons.expand_more),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ipRow(context),
          if (good) ...[
            _row('ID', info!.id),
            _row('Chip', info.chip),
            _row('Version', info.version),
            _row('Built', info.builtLabel),
            if (info.host != null) _row('Host', info.host!),
          ],
          if (artnet != null) ...[
            // Supported devices show both names; for unsupported Art-Net nodes
            // the short name is already the tile title, so show the long name only.
            if (good)
              _row(
                'Short name',
                artnet.shortName.isEmpty ? '—' : artnet.shortName,
              ),
            _row('Long name', artnet.longName.isEmpty ? '—' : artnet.longName),
          ],
          if (good) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: () => showDeviceConfigScreen(
                  context,
                  host: device.ip,
                  port: device.mdns?.port ?? 80,
                ),
                icon: const Icon(Icons.tune),
                label: const Text('Configure'),
              ),
            ),
          ],
        ],
      ),
    );

    // Dim the whole tile for inactive (non-responding) devices.
    return good ? tile : Opacity(opacity: 0.6, child: tile);
  }

  Widget _row(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 96, child: Text(k)),
        Expanded(
          child: Text(v, style: const TextStyle(fontFamily: 'monospace')),
        ),
      ],
    ),
  );

  /// IP row whose value is a hyperlink opening the device's web page.
  Widget _ipRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 96, child: Text('IP')),
          Expanded(
            child: InkWell(
              onTap: () => _openInBrowser(context),
              child: Text(
                device.ip,
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: scheme.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: scheme.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openInBrowser(BuildContext context) async {
    final port = device.mdns?.port ?? 80;
    final uri = Uri(
      scheme: 'http',
      host: device.ip,
      port: port == 80 ? null : port,
    );
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        messenger.showSnackBar(SnackBar(content: Text('Could not open $uri')));
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open browser: $e')),
      );
    }
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: scheme.onSecondaryContainer),
      ),
    );
  }
}

/// Empty-state body for the Scan screen: renders editable Markdown loaded from
/// `assets/docs/scan_intro.md`. Links open externally in a browser.
class _ScanIntro extends StatefulWidget {
  const _ScanIntro();

  @override
  State<_ScanIntro> createState() => _ScanIntroState();
}

class _ScanIntroState extends State<_ScanIntro> {
  // Loaded once so frequent parent rebuilds (e.g. scan progress) don't reflow.
  static const _assetPath = 'assets/docs/scan_intro.md';
  late final Future<String> _doc = rootBundle.loadString(_assetPath);

  Future<void> _openLink(String? href) async {
    final uri = href == null ? null : Uri.tryParse(href);
    if (uri == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        messenger.showSnackBar(SnackBar(content: Text('Could not open $uri')));
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open link: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _doc,
      builder: (context, snap) {
        if (snap.hasError) {
          return _IntroFallback(error: snap.error.toString());
        }
        if (!snap.hasData) return const SizedBox.shrink();
        return Markdown(
          data: snap.data!,
          padding: const EdgeInsets.symmetric(vertical: 8),
          onTapLink: (text, href, title) => _openLink(href),
        );
      },
    );
  }
}

/// Shown only if the Markdown asset can't be read (e.g. not bundled).
class _IntroFallback extends StatelessWidget {
  const _IntroFallback({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          "No devices yet. Tap 'Scan' to discover ArtNet devices.\n($error)",
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
