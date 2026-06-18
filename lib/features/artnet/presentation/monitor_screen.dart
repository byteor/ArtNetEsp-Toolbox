import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/artnet_providers.dart';
import '../domain/art_dmx.dart';

/// Art-Net universe monitor tab.
///
/// The universe + listen controls stay pinned at the top; the monitored data is
/// split into two compact secondary sub-tabs:
///  - Channels: the 512-channel fader grid.
///  - Packets:  live stats (count / sequence / source) + the rolling log.
class MonitorScreen extends ConsumerStatefulWidget {
  const MonitorScreen({super.key});

  @override
  ConsumerState<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends ConsumerState<MonitorScreen> {
  final TextEditingController _universe = TextEditingController(text: '0');

  @override
  void dispose() {
    _universe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(monitorControllerProvider);
    final controller = ref.read(monitorControllerProvider.notifier);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: const Text('Art-Net Monitor')),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _universe,
                      enabled: !state.listening,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (v) =>
                          controller.setUniverse(int.tryParse(v) ?? 0),
                      decoration: const InputDecoration(
                        labelText: 'Universe (0–32767)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  state.listening
                      ? FilledButton.tonalIcon(
                          onPressed: controller.stop,
                          icon: const Icon(Icons.stop),
                          label: const Text('Stop'),
                        )
                      : FilledButton.icon(
                          onPressed: controller.start,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Listen'),
                        ),
                ],
              ),
              if (state.error.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Error: ${state.error}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 6),
              TabBar.secondary(
                tabs: const [
                  Tab(height: 34, text: 'Channels'),
                  Tab(height: 34, text: 'Packets'),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TabBarView(
                  children: [
                    _ChannelsTab(channels: state.channels),
                    _PacketsTab(state: state),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Channels sub-tab: active count + legend + the 512-cell fader grid.
class _ChannelsTab extends StatelessWidget {
  const _ChannelsTab({required this.channels});
  final List<int> channels;

  @override
  Widget build(BuildContext context) {
    final activeCount = channels.where((v) => v > 0).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '$activeCount active / $kDmxChannels',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Spacer(),
            const _Legend(),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(child: _ChannelGrid(values: channels)),
      ],
    );
  }
}

/// Packets sub-tab: live stats + the rolling recent-packets log.
class _PacketsTab extends StatelessWidget {
  const _PacketsTab({required this.state});
  final MonitorState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatsBar(state: state),
        const SizedBox(height: 10),
        Text('Recent packets', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: state.log.isEmpty
                ? const Center(child: Text('No packets yet.'))
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(8),
                    itemCount: state.log.length,
                    itemBuilder: (context, i) => Text(
                      state.log[state.log.length - 1 - i],
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Compact horizontal bar of the key monitor stats.
class _StatsBar extends StatelessWidget {
  const _StatsBar({required this.state});
  final MonitorState state;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        _chip(context, 'Universe', '${state.universe}'),
        _chip(context, 'Packets', '${state.packetCount}'),
        _chip(
          context,
          'Seq',
          state.lastSequence < 0 ? '—' : '${state.lastSequence}',
        ),
        _chip(
          context,
          'Source',
          state.lastSourceIp.isEmpty ? '—' : state.lastSourceIp,
        ),
      ],
    );
  }

  Widget _chip(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget swatch(Color c) => Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(2),
      ),
    );
    final style = TextStyle(fontSize: 11, color: scheme.onSurfaceVariant);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        swatch(scheme.primary),
        const SizedBox(width: 4),
        Text('value', style: style),
        const SizedBox(width: 10),
        swatch(scheme.surfaceContainerHighest),
        const SizedBox(width: 4),
        Text('0', style: style),
      ],
    );
  }
}

/// A scrollable grid of all [kDmxChannels] channels. Each cell is a vertical
/// fader; value-0 channels are dimmed and show only the channel number.
class _ChannelGrid extends StatelessWidget {
  const _ChannelGrid({required this.values});
  final List<int> values;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 25,
        mainAxisExtent: 31,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: kDmxChannels,
      itemBuilder: (context, index) {
        final value = index < values.length ? values[index] : 0;
        return _ChannelCell(channel: index + 1, value: value);
      },
    );
  }
}

/// One channel rendered as a vertical fader: the cell background is the bar
/// (fill rises from the bottom by value/255), with the channel number and value
/// overlaid on top. Dimmed with just the channel number when the value is 0.
class _ChannelCell extends StatelessWidget {
  const _ChannelCell({required this.channel, required this.value});

  final int channel; // 1-based
  final int value; // 0..255

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = value > 0;
    final fraction = (value / 255).clamp(0.0, 1.0);

    // White glyphs with a dark outline stay readable over both the light track
    // and the saturated fill — a single text colour can't contrast with both.
    const outline = <Shadow>[
      Shadow(offset: Offset(-0.6, -0.6), color: Colors.black87),
      Shadow(offset: Offset(0.6, -0.6), color: Colors.black87),
      Shadow(offset: Offset(0.6, 0.6), color: Colors.black87),
      Shadow(offset: Offset(-0.6, 0.6), color: Colors.black87),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: scheme.surfaceContainerHighest), // track
          Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: fraction,
              widthFactor: 1,
              child: ColoredBox(color: scheme.primary), // fill
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$channel',
                  style: active
                      ? const TextStyle(
                          fontSize: 6,
                          height: 1,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          shadows: outline,
                        )
                      : TextStyle(
                          fontSize: 6,
                          height: 1,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                ),
                if (active)
                  Text(
                    '$value',
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 8,
                      height: 1,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: outline,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
