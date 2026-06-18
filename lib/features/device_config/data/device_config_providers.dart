import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/device_config_model.dart';
import 'device_config_client.dart';
import 'device_credentials_store.dart';

/// Identifies the device whose config is being edited (HTTP host + port).
typedef DeviceTarget = ({String host, int port});

/// The REST client. Overridable in tests.
final deviceConfigClientProvider =
    Provider<DeviceConfigClient>((ref) => DeviceConfigClient());

/// Mirrors the firmware SPA's state model (§7.2): a [draft] working copy vs the
/// last-persisted [saved] baseline, with per-section dirty tracking.
class DeviceConfigState {
  const DeviceConfigState({
    this.loading = true,
    this.loadError,
    this.needsAuth = false,
    this.saved,
    this.draft,
    this.busy = false,
    this.creds,
    this.toastSeq = 0,
    this.toastMessage = '',
  });

  final bool loading;
  final String? loadError;
  final bool needsAuth; // a 401 occurred; prompt for credentials
  final DeviceFullConfig? saved;
  final DeviceFullConfig? draft;
  final bool busy; // a save/reboot/reset is in flight
  final DeviceCredentials? creds;
  final int toastSeq; // bumped each toast so the UI shows it once
  final String toastMessage;

  bool get hasData => saved != null && draft != null;
  bool get needReboot => saved?.needReboot ?? false;

  bool isDirty(ConfigSection section) {
    final d = draft, s = saved;
    if (d == null || s == null) return false;
    switch (section) {
      case ConfigSection.general:
        return jsonEncode(d.generalPayload()) != jsonEncode(s.generalPayload());
      case ConfigSection.devices:
        return jsonEncode(d.devicesPayload()) != jsonEncode(s.devicesPayload());
      case ConfigSection.system:
        return jsonEncode(d.hwPayload()) != jsonEncode(s.hwPayload());
    }
  }

  static const Object _keep = Object();

  DeviceConfigState copyWith({
    bool? loading,
    Object? loadError = _keep,
    bool? needsAuth,
    DeviceFullConfig? saved,
    DeviceFullConfig? draft,
    bool? busy,
    Object? creds = _keep,
    int? toastSeq,
    String? toastMessage,
  }) =>
      DeviceConfigState(
        loading: loading ?? this.loading,
        loadError:
            loadError == _keep ? this.loadError : loadError as String?,
        needsAuth: needsAuth ?? this.needsAuth,
        saved: saved ?? this.saved,
        draft: draft ?? this.draft,
        busy: busy ?? this.busy,
        creds: creds == _keep ? this.creds : creds as DeviceCredentials?,
        toastSeq: toastSeq ?? this.toastSeq,
        toastMessage: toastMessage ?? this.toastMessage,
      );
}

/// Loads, edits and saves one device's config over the REST API, mirroring the
/// firmware SPA's behavior (§7). Auto-disposes (cancelling the status poll) when
/// the config screen closes.
class DeviceConfigController extends Notifier<DeviceConfigState> {
  DeviceConfigController(this.target);

  final DeviceTarget target;
  late final DeviceConfigClient _client;
  Timer? _poll;

  @override
  DeviceConfigState build() {
    _client = ref.read(deviceConfigClientProvider);
    ref.onDispose(() => _poll?.cancel());
    scheduleMicrotask(load);
    return const DeviceConfigState();
  }

  /// `GET /config` and start the 5 s status poll (§7). GET is unauthenticated,
  /// but seed any credentials remembered for this host so the first mutating
  /// call is pre-authenticated.
  Future<void> load() async {
    final remembered =
        ref.read(deviceCredentialStoreProvider).rememberedFor(target.host);
    state = remembered != null && state.creds == null
        ? state.copyWith(loading: true, loadError: null, creds: remembered)
        : state.copyWith(loading: true, loadError: null);
    try {
      final cfg =
          await _client.getConfig(target.host, target.port, creds: state.creds);
      state = state.copyWith(
          loading: false, saved: cfg, draft: cfg, loadError: null);
      _startPolling();
    } catch (e) {
      state = state.copyWith(loading: false, loadError: e.toString());
    }
  }

  void setCredentials(String user, String pass) => state =
      state.copyWith(creds: DeviceCredentials(user, pass), needsAuth: false);

  // ---- editing (draft only) ----
  void setHost(String v) => _patch((d) => d.copyWith(host: v));
  void setUniverse(int v) => _patch((d) => d.copyWith(universe: v));
  void setHardware(HardwareConfig hw) => _patch((d) => d.copyWith(hw: hw));

  void setDevice(int index, DmxDevice device) => _patch((d) {
        if (index < 0 || index >= d.dmx.length) return d;
        final list = [...d.dmx]..[index] = device;
        return d.copyWith(dmx: list);
      });

  void addDevice() => _patch((d) => d.dmx.length >= d.info.maxDmxDevices
      ? d
      : d.copyWith(dmx: [...d.dmx, DmxDevice.freshDefault]));

  void removeDevice(int index) => _patch((d) {
        if (index < 0 || index >= d.dmx.length) return d;
        final list = [...d.dmx]..removeAt(index);
        return d.copyWith(dmx: list);
      });

  void _patch(DeviceFullConfig Function(DeviceFullConfig) f) {
    final d = state.draft;
    if (d != null) state = state.copyWith(draft: f(d));
  }

  // ---- saving / lifecycle ----

  /// POST only [section]'s keys, confirm via re-GET, then refresh the baseline
  /// (§7.2). The just-saved section adopts the device's confirmed values so it
  /// reads clean; edits in other sections are preserved.
  Future<void> saveSection(ConfigSection section) async {
    final draft = state.draft;
    if (draft == null || state.busy) return;
    final payload = switch (section) {
      ConfigSection.general => draft.generalPayload(),
      ConfigSection.devices => draft.devicesPayload(),
      ConfigSection.system => draft.hwPayload(),
    };
    state = state.copyWith(busy: true);
    try {
      final fresh = await _attemptWithAuth((creds) => _client
          .postConfigSection(target.host, target.port, payload, creds: creds));
      final mergedDraft = draft.copyWith(
        host: section == ConfigSection.general ? fresh.host : draft.host,
        universe:
            section == ConfigSection.general ? fresh.universe : draft.universe,
        dmx: section == ConfigSection.devices ? fresh.dmx : draft.dmx,
        hw: section == ConfigSection.system ? fresh.hw : draft.hw,
        needReboot: fresh.needReboot,
        info: fresh.info,
        configVersion: fresh.configVersion,
      );
      state = state.copyWith(
        busy: false,
        saved: fresh,
        draft: mergedDraft,
        toastSeq: state.toastSeq + 1,
        toastMessage: fresh.needReboot ? 'Saved — reboot required' : 'Saved',
      );
    } on DeviceAuthException {
      _failAuth();
    } catch (e) {
      _failToast('Save failed: $e');
    }
  }

  Future<void> reboot() => _lifecycle(
      (creds) => _client.reboot(target.host, target.port, creds: creds),
      'Rebooting…');

  Future<void> resetWifi() => _lifecycle(
      (creds) => _client.resetWifi(target.host, target.port, creds: creds),
      'Resetting WiFi…');

  Future<void> _lifecycle(
      Future<void> Function(DeviceCredentials?) action, String okToast) async {
    if (state.busy) return;
    state = state.copyWith(busy: true);
    try {
      await _attemptWithAuth(action);
      state = state.copyWith(
          busy: false,
          toastSeq: state.toastSeq + 1,
          toastMessage: okToast);
    } on DeviceAuthException {
      _failAuth();
    } catch (e) {
      _failToast('Failed: $e');
    }
  }

  /// Runs a mutating [action], retrying with each available credential when the
  /// device answers `401`: the current creds, then those remembered for this
  /// host, then the app-wide default (§5.2). On the first success the working
  /// creds are adopted and remembered. If every candidate is rejected the
  /// [DeviceAuthException] propagates so the caller can prompt the user.
  Future<T> _attemptWithAuth<T>(
      Future<T> Function(DeviceCredentials?) action) async {
    final store = ref.read(deviceCredentialStoreProvider);
    final candidates = <DeviceCredentials?>[
      state.creds,
      store.rememberedFor(target.host),
      store.defaultCredentials,
    ];
    final tried = <String>{};
    DeviceAuthException lastAuth = const DeviceAuthException();
    for (final creds in candidates) {
      if (!tried.add(_credsKey(creds))) continue; // skip duplicates (incl. null)
      try {
        final result = await action(creds);
        if (creds != null) {
          if (!_sameCreds(creds, state.creds)) {
            state = state.copyWith(creds: creds);
          }
          store.remember(target.host, creds);
        }
        return result;
      } on DeviceAuthException catch (e) {
        lastAuth = e;
      }
    }
    throw lastAuth;
  }

  static String _credsKey(DeviceCredentials? c) =>
      c == null ? ' none' : '${c.user} ${c.pass}';

  static bool _sameCreds(DeviceCredentials? a, DeviceCredentials? b) =>
      _credsKey(a) == _credsKey(b);

  void _failAuth() => state = state.copyWith(
        busy: false,
        needsAuth: true,
        toastSeq: state.toastSeq + 1,
        toastMessage: 'Unauthorized — enter device credentials',
      );

  void _failToast(String msg) => state = state.copyWith(
      busy: false, toastSeq: state.toastSeq + 1, toastMessage: msg);

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _pollStatus());
  }

  Future<void> _pollStatus() async {
    final saved = state.saved;
    if (saved == null) return;
    try {
      final st = await _client.getStatus(target.host, target.port,
          creds: state.creds);
      state = state.copyWith(
        saved: saved.copyWith(needReboot: st.needReboot, info: st.info),
        draft: state.draft?.copyWith(needReboot: st.needReboot, info: st.info),
      );
    } catch (_) {
      // Transient (e.g. mid-reboot); ignore and keep polling.
    }
  }
}

final deviceConfigControllerProvider = NotifierProvider.autoDispose
    .family<DeviceConfigController, DeviceConfigState, DeviceTarget>(
  DeviceConfigController.new,
);
