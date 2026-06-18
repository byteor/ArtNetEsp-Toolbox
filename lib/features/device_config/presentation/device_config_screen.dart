import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/device_config_providers.dart';
import '../data/device_credentials_store.dart';
import '../domain/device_config_model.dart';

/// Opens the full-screen device-configuration modal for [host]:[port].
Future<void> showDeviceConfigScreen(
  BuildContext context, {
  required String host,
  required int port,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => DeviceConfigScreen(target: (host: host, port: port)),
    ),
  );
}

/// Mirrors the firmware config SPA (`docs/API_UX_DESIGN.md` §7): a 3-tab editor
/// (General · Devices · System) over the device REST API. WiFi is out of scope
/// per the contract. See docs/DEVICE_CONFIG_PARITY.md.
class DeviceConfigScreen extends ConsumerWidget {
  const DeviceConfigScreen({super.key, required this.target});

  final DeviceTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = deviceConfigControllerProvider(target);
    final state = ref.watch(provider);

    // Surface controller toasts once each.
    ref.listen(provider.select((s) => s.toastSeq), (_, _) {
      final msg = ref.read(provider).toastMessage;
      if (msg.isEmpty) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));
    });

    final title = state.draft?.host.isNotEmpty == true
        ? state.draft!.host
        : 'Configure device';

    Widget body;
    if (state.loading) {
      body = const Center(child: Text('Loading…'));
    } else if (!state.hasData) {
      body = _LoadError(
        message: state.loadError ?? 'Unknown error',
        onRetry: () => ref.read(provider.notifier).load(),
      );
    } else {
      body = _Loaded(target: target);
    }

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(child: body),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Couldn't load configuration:\n$message",
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Loaded extends ConsumerWidget {
  const _Loaded({required this.target});
  final DeviceTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = deviceConfigControllerProvider(target);
    final state = ref.watch(provider);
    final ctrl = ref.read(provider.notifier);
    final draft = state.draft!;
    final info = draft.info;

    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.needReboot)
            _RebootBanner(busy: state.busy, onReboot: ctrl.reboot),
          if (state.needsAuth) _AuthBanner(target: target),
          _Header(host: draft.host, info: info),
          TabBar(
            tabs: [
              _DirtyTab('General', state.isDirty(ConfigSection.general)),
              _DirtyTab('Devices', state.isDirty(ConfigSection.devices)),
              _DirtyTab('System', state.isDirty(ConfigSection.system)),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _GeneralSection(target: target),
                _DevicesSection(target: target),
                _SystemSection(target: target),
              ],
            ),
          ),
          _Footer(info: info),
        ],
      ),
    );
  }
}

class _DirtyTab extends StatelessWidget {
  const _DirtyTab(this.label, this.dirty);
  final String label;
  final bool dirty;

  @override
  Widget build(BuildContext context) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (dirty) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.circle,
              size: 8,
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ],
      ),
    );
  }
}

class _RebootBanner extends StatelessWidget {
  const _RebootBanner({required this.busy, required this.onReboot});
  final bool busy;
  final VoidCallback onReboot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Changes need a reboot to take effect.',
                style: TextStyle(color: scheme.onTertiaryContainer),
              ),
            ),
            TextButton(
              onPressed: busy ? null : onReboot,
              child: const Text('Reboot now'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Inline credentials prompt shown after a 401 (§5.2).
class _AuthBanner extends ConsumerStatefulWidget {
  const _AuthBanner({required this.target});
  final DeviceTarget target;
  @override
  ConsumerState<_AuthBanner> createState() => _AuthBannerState();
}

class _AuthBannerState extends ConsumerState<_AuthBanner> {
  late final TextEditingController _user;
  late final TextEditingController _pass;

  @override
  void initState() {
    super.initState();
    // Seed with the app-wide default so the user only tweaks what's wrong
    // (usually the password) instead of retyping both.
    final d = ref.read(deviceCredentialStoreProvider).defaultCredentials;
    _user = TextEditingController(text: d?.user ?? '');
    _pass = TextEditingController(text: d?.pass ?? '');
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _submit() => ref
      .read(deviceConfigControllerProvider(widget.target).notifier)
      .setCredentials(_user.text, _pass.text);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasDefault =
        ref.read(deviceCredentialStoreProvider).defaultCredentials != null;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasDefault
                  ? 'The default credentials were rejected. Enter this '
                      'device\'s username and password.'
                  : 'This device requires HTTP authentication.',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _user,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _pass,
                    obscureText: true,
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _submit,
                  child: const Text('Use'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.host, required this.info});
  final String host;
  final DeviceRuntimeInfo info;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final parts = <String>[
      'Up ${_uptime(info.uptime)}',
      '${(info.freeHeap / 1024).round()} KB free',
      if (info.rssi != 0) '${info.rssi} dBm',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: scheme.primaryContainer,
            child: Icon(Icons.lightbulb, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ArtNet Node',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  host.isEmpty ? '—' : '$host.local',
                  style: TextStyle(color: scheme.primary),
                ),
                Text(
                  parts.join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _uptime(int ms) {
    final s = ms ~/ 1000;
    final d = s ~/ 86400, h = (s % 86400) ~/ 3600, m = (s % 3600) ~/ 60;
    if (d > 0) return '${d}d ${h}h';
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s % 60}s';
    return '${s}s';
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.info});
  final DeviceRuntimeInfo info;

  @override
  Widget build(BuildContext context) {
    Widget tile(String value, String label) => Expanded(
      child: Column(
        children: [
          Text(
            value.isEmpty ? '—' : value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          tile('${info.id} · ${info.chip}', 'Device'),
          tile(info.ssid, 'Network'),
          tile(info.version, 'Firmware'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// General
// ---------------------------------------------------------------------------

class _GeneralSection extends ConsumerWidget {
  const _GeneralSection({required this.target});
  final DeviceTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = deviceConfigControllerProvider(target);
    final state = ref.watch(provider);
    final ctrl = ref.read(provider.notifier);
    final d = state.draft!;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _StrField(
          label: 'Hostname',
          helper: d.host.isEmpty
              ? 'Give the device a name'
              : 'Reachable as ${d.host}.local',
          value: d.host,
          maxLength: 31,
          onChanged: ctrl.setHost,
        ),
        const SizedBox(height: 16),
        _IntField(
          label: 'Art-Net universe',
          helper: 'The universe this node listens on (≥ 0).',
          value: d.universe,
          min: 0,
          onChanged: ctrl.setUniverse,
        ),
        const SizedBox(height: 20),
        _SaveButton(
          dirty: state.isDirty(ConfigSection.general),
          busy: state.busy,
          onSave: () => ctrl.saveSection(ConfigSection.general),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Devices
// ---------------------------------------------------------------------------

class _DevicesSection extends ConsumerWidget {
  const _DevicesSection({required this.target});
  final DeviceTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = deviceConfigControllerProvider(target);
    final state = ref.watch(provider);
    final ctrl = ref.read(provider.notifier);
    final d = state.draft!;
    final atMax = d.dmx.length >= d.info.maxDmxDevices;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Up to ${d.info.maxDmxDevices} device(s). Saving replaces the whole list.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (d.dmx.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'At least one device is required — add one or set a device to '
              'Disabled instead of removing the last.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 8),
        for (var i = 0; i < d.dmx.length; i++)
          _DeviceCard(
            key: ValueKey('dmx-$i'),
            index: i,
            device: d.dmx[i],
            onChanged: (dev) => ctrl.setDevice(i, dev),
            onRemove: () => ctrl.removeDevice(i),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: atMax ? null : ctrl.addDevice,
          icon: const Icon(Icons.add),
          label: Text(atMax ? 'Maximum reached' : 'Add device'),
        ),
        const SizedBox(height: 16),
        _SaveButton(
          label: 'Save devices',
          dirty: state.isDirty(ConfigSection.devices) && d.dmx.isNotEmpty,
          busy: state.busy,
          onSave: () => ctrl.saveSection(ConfigSection.devices),
        ),
      ],
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    super.key,
    required this.index,
    required this.device,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final DmxDevice device;
  final ValueChanged<DmxDevice> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = device.type;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Device ${index + 1}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onRemove,
                ),
              ],
            ),
            DropdownButtonFormField<DmxType>(
              initialValue: t,
              decoration: const InputDecoration(
                labelText: 'Type',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: DmxType.binary,
                  child: Text('Relay (BINARY)'),
                ),
                DropdownMenuItem(value: DmxType.dimmer, child: Text('Dimmer')),
                DropdownMenuItem(value: DmxType.servo, child: Text('Servo')),
                DropdownMenuItem(
                  value: DmxType.repeater,
                  child: Text('Repeater (DMX out)'),
                ),
                DropdownMenuItem(
                  value: DmxType.disabled,
                  child: Text('Disabled'),
                ),
              ],
              onChanged: (v) =>
                  onChanged(device.copyWith(type: v ?? device.type)),
            ),
            const SizedBox(height: 12),
            _IntField(
              label: 'Start channel (1–512)',
              value: device.channel,
              min: 1,
              max: 512,
              onChanged: (v) => onChanged(device.copyWith(channel: v)),
            ),
            if (t.showsPin) ...[
              const SizedBox(height: 12),
              _IntField(
                label: 'GPIO pin',
                value: device.pin,
                min: 0,
                onChanged: (v) => onChanged(device.copyWith(pin: v)),
              ),
            ],
            if (t.showsLevel) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: device.level,
                decoration: const InputDecoration(
                  labelText: 'Active level',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'HIGH', child: Text('HIGH')),
                  DropdownMenuItem(value: 'LOW', child: Text('LOW')),
                ],
                onChanged: (v) =>
                    onChanged(device.copyWith(level: v ?? device.level)),
              ),
            ],
            if (t.showsThreshold) ...[
              const SizedBox(height: 12),
              _IntField(
                label: 'On/off threshold (0–255)',
                value: device.threshold,
                min: 0,
                max: 255,
                onChanged: (v) => onChanged(device.copyWith(threshold: v)),
              ),
            ],
            if (t.showsPulse) ...[
              const SizedBox(height: 12),
              _IntField(
                label: 'Strobe pulse',
                value: device.pulse,
                min: 0,
                onChanged: (v) => onChanged(device.copyWith(pulse: v)),
              ),
            ],
            if (t.showsMultiplier) ...[
              const SizedBox(height: 12),
              _IntField(
                label: 'Strobe multiplier',
                value: device.multiplier,
                min: 1,
                onChanged: (v) => onChanged(device.copyWith(multiplier: v)),
              ),
            ],
            if (t.showsBlackout)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Blackout on DMX signal loss'),
                value: device.blackout,
                onChanged: (v) =>
                    onChanged(device.copyWith(blackout: v ?? device.blackout)),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// System
// ---------------------------------------------------------------------------

class _SystemSection extends ConsumerWidget {
  const _SystemSection({required this.target});
  final DeviceTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = deviceConfigControllerProvider(target);
    final state = ref.watch(provider);
    final ctrl = ref.read(provider.notifier);
    final d = state.draft!;
    final hw = d.hw;
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (d.info.ota)
          Builder(
            builder: (context) {
              final otaUrl = 'http://${d.host}.local/update';
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.system_update),
                  title: const Text('Firmware updater'),
                  subtitle: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'Open '),
                        TextSpan(
                          text: otaUrl,
                          style: TextStyle(
                            color: scheme.primary,
                            decoration: TextDecoration.underline,
                            decorationColor: scheme.primary,
                          ),
                        ),
                        const TextSpan(text: ' in a browser.'),
                      ],
                    ),
                  ),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _openOta(context, Uri.parse(otaUrl)),
                ),
              );
            },
          ),
        ExpansionTile(
          title: const Text('Advanced'),
          childrenPadding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Text(
              'Changing pins, PWM frequency or the button can stop the device '
              'working or lock you out. Only change these if you know your '
              "board's wiring.",
              style: TextStyle(color: scheme.error),
            ),
            const SizedBox(height: 12),
            _IntField(
              label: 'PWM frequency (Hz)',
              value: hw.freq,
              min: 100,
              onChanged: (v) => ctrl.setHardware(hw.copyWith(freq: v)),
            ),
            const SizedBox(height: 12),
            _IntField(
              label: 'Button long-press (ms)',
              helper: 'Holding the button this long resets WiFi.',
              value: hw.longPressDelay,
              min: 500,
              onChanged: (v) =>
                  ctrl.setHardware(hw.copyWith(longPressDelay: v)),
            ),
            const SizedBox(height: 12),
            _IntField(
              label: 'Status LED pin',
              value: hw.ledPin,
              min: 0,
              onChanged: (v) => ctrl.setHardware(hw.copyWith(ledPin: v)),
            ),
            const SizedBox(height: 12),
            _IntField(
              label: 'Button pin',
              value: hw.buttonPin,
              min: 0,
              onChanged: (v) => ctrl.setHardware(hw.copyWith(buttonPin: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('WiFi power saving (higher latency)'),
              subtitle: const Text(
                'Off = lowest Art-Net latency; on = lower power.',
              ),
              value: hw.wifiPowerSave,
              onChanged: (v) => ctrl.setHardware(hw.copyWith(wifiPowerSave: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Require HTTP authentication for changes'),
              value: hw.authEnabled,
              onChanged: (v) => ctrl.setHardware(hw.copyWith(authEnabled: v)),
            ),
            if (hw.authEnabled) ...[
              _StrField(
                label: 'Username',
                value: hw.authUser,
                onChanged: (v) => ctrl.setHardware(hw.copyWith(authUser: v)),
              ),
              const SizedBox(height: 12),
              _StrField(
                label: 'Password',
                value: hw.authPass,
                obscure: true,
                onChanged: (v) => ctrl.setHardware(hw.copyWith(authPass: v)),
              ),
              const SizedBox(height: 4),
              Text(
                'After enabling auth and saving, the device will ask for these '
                'credentials on the next change/reboot/reset.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            _SaveButton(
              label: 'Save advanced',
              dirty: state.isDirty(ConfigSection.system),
              busy: state.busy,
              onSave: () => ctrl.saveSection(ConfigSection.system),
            ),
          ],
        ),
        const Divider(height: 32),
        Text('Power & WiFi', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: state.busy
              ? null
              : () async {
                  if (await _confirm(
                    context,
                    'Reboot device?',
                    'The device will restart and be briefly unreachable.',
                  )) {
                    ctrl.reboot();
                  }
                },
          icon: const Icon(Icons.restart_alt),
          label: const Text('Reboot'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
          onPressed: state.busy
              ? null
              : () async {
                  if (await _confirm(
                    context,
                    'Reset WiFi?',
                    'The device will forget its WiFi and reboot into its '
                        'setup portal. You will lose access from this app '
                        'until it is reconnected.',
                    danger: true,
                  )) {
                    ctrl.resetWifi();
                  }
                },
          icon: const Icon(Icons.wifi_off),
          label: const Text('Reset WiFi'),
        ),
      ],
    );
  }

  Future<void> _openOta(BuildContext context, Uri uri) async {
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

Future<bool> _confirm(
  BuildContext context,
  String title,
  String message, {
  bool danger = false,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(backgroundColor: scheme.error)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

// ---------------------------------------------------------------------------
// Shared form widgets
// ---------------------------------------------------------------------------

class _SaveButton extends StatelessWidget {
  const _SaveButton({
    this.label = 'Save',
    required this.dirty,
    required this.busy,
    required this.onSave,
  });

  final String label;
  final bool dirty;
  final bool busy;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: (dirty && !busy) ? onSave : null,
      child: Text(busy ? 'Saving…' : (dirty ? label : 'Saved')),
    );
  }
}

/// Integer field whose controller only re-syncs from the model while unfocused,
/// so reactive rebuilds never fight the cursor.
class _IntField extends StatefulWidget {
  const _IntField({
    required this.label,
    this.helper,
    required this.value,
    this.min,
    this.max,
    required this.onChanged,
  });

  final String label;
  final String? helper;
  final int value;
  final int? min;
  final int? max;
  final ValueChanged<int> onChanged;

  @override
  State<_IntField> createState() => _IntFieldState();
}

class _IntFieldState extends State<_IntField> {
  late final TextEditingController _c = TextEditingController(
    text: '${widget.value}',
  );
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(covariant _IntField old) {
    super.didUpdateWidget(old);
    final s = '${widget.value}';
    if (!_focus.hasFocus && _c.text != s) _c.text = s;
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      focusNode: _focus,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (t) {
        final n = int.tryParse(t);
        if (n == null) return;
        var v = n;
        if (widget.min != null && v < widget.min!) v = widget.min!;
        if (widget.max != null && v > widget.max!) v = widget.max!;
        widget.onChanged(v);
      },
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helper,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}

/// String field with the same focus-aware re-sync behavior as [_IntField].
class _StrField extends StatefulWidget {
  const _StrField({
    required this.label,
    this.helper,
    required this.value,
    this.maxLength,
    this.obscure = false,
    required this.onChanged,
  });

  final String label;
  final String? helper;
  final String value;
  final int? maxLength;
  final bool obscure;
  final ValueChanged<String> onChanged;

  @override
  State<_StrField> createState() => _StrFieldState();
}

class _StrFieldState extends State<_StrField> {
  late final TextEditingController _c = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(covariant _StrField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _c.text != widget.value) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      focusNode: _focus,
      obscureText: widget.obscure,
      maxLength: widget.maxLength,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helper,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}
