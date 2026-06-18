# Testing checklist

A manual pass for the diagnostic features, plus no-hardware desk-test scripts.

## Pre-flight (no device needed)

- [ ] `flutter pub get`
- [ ] `flutter analyze` → **No issues found**
- [ ] `flutter test` → all green (Art-Net codec: build/parse + malformed inputs)

## On a real device (required for network features)

> Use a physical iPhone **and** a physical Android phone on the same Wi-Fi as
> your Art-Net/mDNS devices (or the desk-test machine below). Simulator/emulator
> do not reproduce local-network behaviour.

### First launch / permissions
- [ ] App launches to the Dashboard with bottom navigation.
- [ ] iOS: first scan/browse shows the **Local Network** permission prompt →
      accept it. (If missed: Settings › Privacy › Local Network.)

### Dashboard
- [ ] Shows device IP / gateway / broadcast / subnet mask (or "No Wi-Fi").
- [ ] Refresh icon re-reads network info.
- [ ] Art-Net and mDNS counts + last-scan times update after scans.
- [ ] Activity log shows entries.

### Art-Net › Discover
- [ ] **Scan Art-Net** finds nodes (real node or the Python responder below).
- [ ] Each node shows IP, short/long name, OEM, ESTA, ports, firmware, raw.
- [ ] Manual target IP scans that single device.
- [ ] On a blocked/guest network: scan completes with 0 nodes and the empty-state
      hint is shown (no crash).

### Art-Net › Monitor
- [ ] Enter a universe, tap **Listen**.
- [ ] Packet count climbs; source IP, last sequence, first 16 channels update.
- [ ] UI stays smooth under a fast sender (≥ 30 packets/s).
- [ ] **Stop** halts updates.

### Art-Net › Transmit
- [ ] Warning banner is visible.
- [ ] Enter target IP, universe, channel, value → **Send ArtDmx** → status shows
      bytes sent.
- [ ] A second device in Monitor (or the Python listener) sees the frame with the
      right universe and channel value.
- [ ] Empty target IP shows a friendly message (no crash).

### mDNS
- [ ] Default service types are pre-filled.
- [ ] **Browse mDNS** lists services (ESP `_http._tcp` shows host/port/TXT).
- [ ] iOS: a type NOT in `Info.plist` returns nothing (expected); Android may
      still find it.

### Settings
- [ ] Changing broadcast address / port / timeout / mDNS types persists across an
      app restart.
- [ ] Toggling **Debug logging** changes log verbosity on the Dashboard.

---

## No-hardware desk tests (Python 3)

Run these on a computer on the **same subnet** as the phone. Replace IPs to match
your network. Stop with Ctrl-C.

### 1. Fake Art-Net node (responds to the app's Scan)

```python
# fake_node.py — replies to ArtPoll so the app's Discover finds a node.
import socket
ID = b'Art-Net\x00'
PORT = 6454

def poll_reply(ip='192.168.1.77', short=b'FakeNode', long=b'Fake Art-Net Node'):
    p = bytearray(240)
    p[0:8] = ID
    p[8], p[9] = 0x00, 0x21                  # OpPollReply (LE)
    p[10:14] = bytes(int(x) for x in ip.split('.'))
    p[14], p[15] = 0x36, 0x19                # port 6454 (LE)
    p[20], p[21] = 0x00, 0x50                # OEM
    p[24], p[25] = 0x34, 0x12                # ESTA (LE)
    p[26:26+len(short)] = short
    p[44:44+len(long)] = long
    p[173] = 1                               # NumPorts lo
    return bytes(p)

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
s.bind(('', PORT))
print('Waiting for ArtPoll on 6454…')
reply = poll_reply()
while True:
    data, addr = s.recvfrom(2048)
    if data[:8] == ID and data[8] == 0x00 and data[9] == 0x20:   # ArtPoll
        print('ArtPoll from', addr)
        s.sendto(reply, (addr[0], PORT))
        s.sendto(reply, ('255.255.255.255', PORT))
```

### 2. ArtDmx sender (feeds the app's Monitor)

```python
# send_dmx.py — streams ArtDmx so the app's Monitor shows packets.
import socket, time
ID = b'Art-Net\x00'
TARGET = ('192.168.1.255', 6454)   # use the phone's IP or a broadcast
UNIVERSE = 0                       # must match the Monitor universe

def artdmx(universe, channels, seq):
    n = len(channels) + (len(channels) & 1)
    ch = channels + [0] * (n - len(channels))
    h = bytearray(18)
    h[0:8] = ID
    h[8], h[9] = 0x00, 0x50            # OpDmx (LE)
    h[11] = 14
    h[12] = seq
    h[14] = universe & 0xFF
    h[15] = (universe >> 8) & 0x7F
    h[16], h[17] = (n >> 8) & 0xFF, n & 0xFF   # length BIG-endian
    return bytes(h) + bytes(ch[:n])

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
seq = 1
while True:
    chans = [0] * 512
    chans[0] = (seq * 5) % 256        # channel 1 ramps
    s.sendto(artdmx(UNIVERSE, chans, seq), TARGET)
    seq = seq % 255 + 1
    time.sleep(0.1)                   # ~10 packets/s
```

### 3. ArtDmx listener (verifies the app's Transmit)

```python
# recv_dmx.py — prints ArtDmx frames the app sends.
import socket
ID = b'Art-Net\x00'
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('', 6454))
print('Listening for ArtDmx on 6454…')
while True:
    data, addr = s.recvfrom(2048)
    if data[:8] == ID and data[8] == 0x00 and data[9] == 0x50:
        uni = data[14] | ((data[15] & 0x7F) << 8)
        ln = (data[16] << 8) | data[17]
        ch1 = data[18] if len(data) > 18 else '-'
        print(f'ArtDmx from {addr[0]} universe={uni} len={ln} ch1={ch1}')
```

> If a script can't bind 6454 ("address already in use"), another Art-Net app
> (or a second script) already holds it — close it first. On macOS you may need
> to allow incoming connections for Python in the firewall.

## Desktop alternatives

QLC+, DMX Workshop (Windows), or `ola` (Open Lighting Architecture) can also act
as Art-Net nodes/senders/monitors for cross-checking.
