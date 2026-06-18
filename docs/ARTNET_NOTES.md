# Art-Net implementation notes

Reference for the packet formats this app builds/parses. Implementation lives in
`lib/features/artnet/domain/` (pure Dart, unit-tested in `test/`).

Art-Net runs over **UDP port 6454**. Every packet begins with the 8-byte ID
`Art-Net\0` (`41 72 74 2D 4E 65 74 00`).

## Endianness — the two traps

- **OpCodes are little-endian.** OpPoll `0x2000` is sent as `00 20`; OpPollReply
  `0x2100` as `00 21`; OpDmx `0x5000` as `00 50`.
- **The ArtDmx data length is BIG-endian** (`LengthHi` then `LengthLo`) — the
  opposite of the opcode. This is the single most common Art-Net bug.

Helpers: `readOpCode()` and `hasArtNetId()` in `artnet_constants.dart`.

## ArtPoll (built — 14 bytes)

`buildArtPoll()` in `art_poll.dart`.

| Offset | Field | Value |
|---|---|---|
| 0..7 | ID | `Art-Net\0` |
| 8..9 | OpCode | `0x2000` little-endian (`00 20`) |
| 10 | ProtVerHi | 0 |
| 11 | ProtVerLo | 14 (Art-Net 4) |
| 12 | Flags (TalkToMe) | 0 |
| 13 | Priority | 0 |

Send to a broadcast address (or a unicast target) on 6454; nodes reply with
ArtPollReply (which they typically broadcast).

## ArtPollReply (parsed)

`parseArtPollReply()` in `art_poll_reply.dart`. Validates ID + OpCode `0x2100`
first, then bounds-checks every field. Returns a partial `ArtNetNode` (null
fields) on short buffers and `null` on non-replies — never throws.

| Offset | Field | Notes |
|---|---|---|
| 10..13 | IP address | `a.b.c.d` |
| 14..15 | Port | little-endian, usually 6454 |
| 16..17 | VersInfo | big-endian firmware version |
| 20..21 | Oem (Hi, Lo) | OEM = `(b20<<8) \| b21` |
| 23 | Status1 | |
| 24..25 | EstaMan | **little-endian**: `(b25<<8) \| b24` |
| 26..43 | ShortName | 18 bytes, NUL-terminated ASCII |
| 44..107 | LongName | 64 bytes, NUL-terminated ASCII |
| 108..171 | NodeReport | 64 bytes (not parsed) |
| 172..173 | NumPorts | big-endian, 0..4 |
| 174..193 | PortTypes/GoodInput/GoodOutput/SwIn/SwOut | 4 bytes each (not parsed) |
| 200 | Style | (not parsed) |
| 201..206 | MAC | (not parsed) |

Real nodes vary in total length and in which trailing fields they populate —
hence the bounds checks.

## ArtDmx (built and parsed)

`buildArtDmx()` / `parseArtDmx()` in `art_dmx.dart`.

| Offset | Field | Notes |
|---|---|---|
| 0..7 | ID | `Art-Net\0` |
| 8..9 | OpCode | `0x5000` little-endian (`00 50`) |
| 10 | ProtVerHi | 0 |
| 11 | ProtVerLo | 14 |
| 12 | Sequence | 0 = disabled, else rolling 1..255 |
| 13 | Physical | informational |
| 14 | SubUni | low byte of the 15-bit Port-Address |
| 15 | Net | high 7 bits of the Port-Address |
| 16 | LengthHi | **big-endian** data length |
| 17 | LengthLo | (even, 2..512) |
| 18.. | Data | channel values |

**Universe addressing.** The 15-bit Port-Address is `(Net << 8) | SubUni`. The
app exposes a single "universe" number 0..32767 and splits it:
`SubUni = universe & 0xFF`, `Net = (universe >> 8) & 0x7F`.

**Parser safety.** `parseArtDmx` clamps the declared length to the bytes actually
present (`buffer.length - 18`) so a malformed/truncated packet can never cause an
out-of-bounds read.

## Addressing / broadcast

- **Manual unicast** to a node's IP is the most reliable for a known device.
- **Subnet-directed broadcast** (e.g. `192.168.1.255`) is preferred for
  discovery; the app computes it from the device IP + mask
  (`NetworkInfoService.computeBroadcast`) and Android can supply it directly via
  `getWifiBroadcast()`.
- **Limited broadcast** `255.255.255.255` is the fallback but is unreliable on
  iOS and some routers.

## Not implemented (future)

ArtPoll diagnostics, ArtSync/ArtTimecode, RDM (ArtTodRequest/…), sACN/E1.31
(which is multicast and would need the iOS multicast entitlement), and the full
ArtPollReply field set (Bind index, Status2, etc.).
