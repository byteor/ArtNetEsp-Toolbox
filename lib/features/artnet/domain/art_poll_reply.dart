import 'dart:typed_data';

import 'artnet_constants.dart';
import 'artnet_opcodes.dart';
import 'artnet_node.dart';

/// Parses an ArtPollReply packet into an [ArtNetNode].
///
/// SECURITY/ROBUSTNESS RULE: network input is never trusted. Every multi-byte
/// read is bounds-checked; a short or malformed buffer yields a partial node
/// (with null fields) or null — it MUST NOT throw. See `docs/ARTNET_NOTES.md`.
///
/// ArtPollReply field offsets used here:
///   [8..9]    OpCode 0x2100 (LE)
///   [10..13]  IP address (4 bytes)
///   [14..15]  Port (LE, usually 6454)
///   [16..17]  VersInfo (BE) — firmware version
///   [20..21]  Oem (BE: OemHi, OemLo)
///   [24..25]  EstaMan (LE: EstaManLo, EstaManHi)
///   [26..43]  ShortName (18 bytes, NUL-terminated ASCII)
///   [44..107] LongName  (64 bytes, NUL-terminated ASCII)
///   [172..173] NumPorts (BE)
///
/// [sourceIp] is the UDP datagram origin; it is used as the node IP when the
/// packet is too short to contain the IP field.
ArtNetNode? parseArtPollReply(Uint8List data, {String? sourceIp}) {
  if (!hasArtNetId(data)) return null;
  final opcode = readOpCode(data);
  if (opcode != ArtNetOpCode.pollReply) return null;

  int? u16be(int offset) =>
      (offset + 1) < data.length ? (data[offset] << 8) | data[offset + 1] : null;
  int? u16le(int offset) =>
      (offset + 1) < data.length ? data[offset] | (data[offset + 1] << 8) : null;

  String packetIp() {
    if (data.length < 14) return '';
    return '${data[10]}.${data[11]}.${data[12]}.${data[13]}';
  }

  final ipFromPacket = packetIp();
  final ip = ipFromPacket.isNotEmpty ? ipFromPacket : (sourceIp ?? '');

  return ArtNetNode(
    ip: ip,
    sourceIp: sourceIp,
    port: u16le(14),
    firmwareVersion: u16be(16),
    oem: u16be(20), // OEM is big-endian (OemHi first)
    esta: u16le(24), // ESTA is little-endian (EstaManLo first)
    shortName: readAsciiField(data, 26, 18),
    longName: readAsciiField(data, 44, 64),
    numPorts: u16be(172),
    rawSummary: hexPreview(data),
  );
}
