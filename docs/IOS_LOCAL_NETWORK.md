# iOS Local Network & Bonjour notes

iOS is stricter than Android about local-network access. Read this before
debugging "it finds nothing on iPhone".

## Local Network permission (iOS 14+)

Any local-network traffic (UDP broadcast/unicast to LAN peers, Bonjour) requires
the user to grant **Local Network** permission. iOS shows the prompt the first
time the app sends/browses, using the text from `Info.plist`:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>ArtNetEsp Toolbox discovers and controls Art-Net/DMX lighting and mDNS devices on your local network.</string>
```

- If the user taps **Don't Allow**, discovery silently fails forever until they
  re-enable it in **Settings › Privacy & Security › Local Network**.
- There is no API to query the permission state directly; treat "no results" as
  possibly-denied and tell the user where to check.

## Bonjour service-type allow-list

iOS only browses Bonjour service types that are declared in `Info.plist`:

```xml
<key>NSBonjourServices</key>
<array>
  <string>_http._tcp</string>
  <string>_ws._tcp</string>
  <string>_workstation._tcp</string>
</array>
```

- A service type entered at runtime in the mDNS screen that is **not** in this
  array will silently fail to resolve on iOS (it works on Android).
- To support a new type on iOS, add it here and rebuild.

## Multicast entitlement — NOT needed here

`com.apple.developer.networking.multicast` is required only for **raw multicast**
in your own code (e.g. a Dart mDNS implementation like `multicast_dns`, or
sACN/E1.31 on `239.255.x.x`). Apple gates it behind an approval request.

This app avoids it on purpose:

- Art-Net uses **broadcast/unicast** UDP, not multicast.
- mDNS goes through the **system Bonjour resolver** via the `nsd` plugin, so the
  OS does the multicast for us.

If you later add sACN or a raw mDNS stack, you must request that entitlement.

## Broadcast caveats

- **Limited broadcast `255.255.255.255` is unreliable on iOS.** Prefer
  subnet-directed broadcast (`x.x.x.255`) or a unicast target. The app defaults
  to _Prefer computed subnet broadcast_.
- `network_info_plus` may return a null broadcast/mask on iOS; the app falls back
  to computing it from IP+mask, then to the configured broadcast.

## Test on a real device

The **iOS Simulator does not reproduce** Local Network permission, broadcast
filtering, or Bonjour behaviour reliably. Always validate Art-Net/mDNS on a
physical iPhone/iPad on the same Wi-Fi as the devices. (This is rule #2 in
[../AGENTS.md](../AGENTS.md).)

## Deployment target

Minimum iOS is the Flutter default for this SDK (≈ iOS 13). The Local Network
prompt behaviour described above is an iOS 14+ feature.
