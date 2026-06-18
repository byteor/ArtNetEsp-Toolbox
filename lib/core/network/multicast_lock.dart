import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Controls an Android Wi-Fi multicast lock.
///
/// On Android, the Wi-Fi stack often drops inbound broadcast/multicast packets
/// to save power unless a [`WifiManager.MulticastLock`] is held. Art-Net nodes
/// broadcast their ArtPollReply, so without this lock discovery can silently
/// receive nothing on some devices. On iOS this is a no-op (the system handles
/// it; Local Network permission governs access instead).
///
/// This is the seam described in AGENTS.md: a tiny MethodChannel rather than a
/// third-party plugin, so it is easy to audit and replace.
abstract interface class MulticastLock {
  /// Acquires the lock. Returns true if the lock is held afterwards.
  /// Never throws — failures are reported as `false` so scanning can continue
  /// on networks that don't filter broadcast.
  Future<bool> acquire();

  /// Releases the lock if held. Never throws.
  Future<void> release();
}

/// No-op implementation for iOS and any non-Android platform.
class NoopMulticastLock implements MulticastLock {
  const NoopMulticastLock();

  @override
  Future<bool> acquire() async => true;

  @override
  Future<void> release() async {}
}

/// Android implementation backed by the `artnet_poc/multicast_lock`
/// MethodChannel handled in `MainActivity.kt`.
class AndroidMulticastLock implements MulticastLock {
  const AndroidMulticastLock();

  static const MethodChannel _channel =
      MethodChannel('artnet_poc/multicast_lock');

  @override
  Future<bool> acquire() async {
    try {
      final held = await _channel.invokeMethod<bool>('acquire');
      return held ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> release() async {
    try {
      await _channel.invokeMethod<void>('release');
    } on PlatformException {
      // ignore — releasing is best-effort
    } on MissingPluginException {
      // ignore
    }
  }
}

/// Returns the right [MulticastLock] for the current platform.
MulticastLock createMulticastLock() {
  if (Platform.isAndroid) return const AndroidMulticastLock();
  return const NoopMulticastLock();
}
