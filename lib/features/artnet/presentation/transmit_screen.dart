import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/artnet_providers.dart';

/// Art-Net transmit/test tab: send a single ArtDmx frame with one channel set.
/// Carries a prominent warning because this can drive real lighting hardware.
class TransmitScreen extends ConsumerStatefulWidget {
  const TransmitScreen({super.key});

  @override
  ConsumerState<TransmitScreen> createState() => _TransmitScreenState();
}

class _TransmitScreenState extends ConsumerState<TransmitScreen> {
  late final TextEditingController _target;
  final TextEditingController _universe = TextEditingController(text: '0');
  final TextEditingController _channel = TextEditingController(text: '1');

  @override
  void initState() {
    super.initState();
    // Default the target to the configured broadcast address (e.g. 255.255.255.255).
    _target = TextEditingController(
      text: ref.read(transmitControllerProvider).target,
    );
  }

  @override
  void dispose() {
    _target.dispose();
    _universe.dispose();
    _channel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(transmitControllerProvider);
    final controller = ref.read(transmitControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Art-Net Transmit')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _WarningBanner(),
            const SizedBox(height: 16),
            TextField(
              controller: _target,
              onChanged: controller.setTarget,
              decoration: const InputDecoration(
                labelText: 'Target IP',
                hintText: 'e.g. 192.168.1.50 or a broadcast address',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _universe,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) =>
                        controller.setUniverse(int.tryParse(v) ?? 0),
                    decoration: const InputDecoration(
                      labelText: 'Universe',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _channel,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) =>
                        controller.setChannel(int.tryParse(v) ?? 1),
                    decoration: const InputDecoration(
                      labelText: 'Channel (1–512)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Value: ${state.value}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Slider(
              value: state.value.toDouble(),
              min: 0,
              max: 255,
              divisions: 255,
              label: '${state.value}',
              onChanged: (v) => controller.setValue(v.round()),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: state.sending ? null : controller.send,
              icon: state.sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: Text(state.sending ? 'Sending…' : 'Send ArtDmx'),
            ),
            if (state.status.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                state.status,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'Sends a full 512-channel ArtDmx frame with the selected channel set '
              'and all others at 0. Sequence increments each send.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'This transmits real Art-Net DMX and may control live lighting '
              'equipment. Make sure you are on the correct network.',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
