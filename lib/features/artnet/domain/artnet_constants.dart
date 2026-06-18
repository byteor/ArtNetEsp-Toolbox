// Core Art-Net protocol constants and tiny byte helpers.
//
// This file is PURE DART — it must never import Flutter. All packet
// building/parsing lives in the `domain/` layer so it can be unit-tested
// without a widget tree or a real socket. See `docs/ARTNET_NOTES.md`.
import 'dart:typed_data';

/// Default Art-Net UDP port. Fixed by the specification — do not change.
const int kArtNetPort = 6454;

/// The 8-byte Art-Net packet identifier: the ASCII string `Art-Net` followed
/// by a NUL terminator: 'A','r','t','-','N','e','t','\0'.
///
/// Every Art-Net packet (ArtPoll, ArtPollReply, ArtDmx, …) begins with these
/// bytes. We validate them before trusting any other field.
const List<int> kArtNetId = <int>[
  0x41, 0x72, 0x74, 0x2D, 0x4E, 0x65, 0x74, 0x00,
];

/// Art-Net protocol version this app speaks (Art-Net 4 == 14).
/// Encoded as two bytes (Hi=0, Lo=14) in outgoing packets.
const int kArtNetProtocolVersion = 14;

/// Returns true if [data] starts with the Art-Net ID (`Art-Net\0`).
///
/// Safe on short buffers: returns false rather than throwing.
bool hasArtNetId(List<int> data) {
  if (data.length < kArtNetId.length) return false;
  for (var i = 0; i < kArtNetId.length; i++) {
    if (data[i] != kArtNetId[i]) return false;
  }
  return true;
}

/// Reads the 16-bit OpCode (bytes 8..9) which Art-Net transmits LITTLE-ENDIAN.
/// Returns null if the buffer is too short.
int? readOpCode(List<int> data) {
  if (data.length < 10) return null;
  return data[8] | (data[9] << 8);
}

/// Compact hex preview of a packet for diagnostic display/logging.
String hexPreview(List<int> data, [int max = 32]) {
  final count = data.length < max ? data.length : max;
  final sb = StringBuffer();
  for (var i = 0; i < count; i++) {
    if (i > 0) sb.write(' ');
    sb.write(data[i].toRadixString(16).padLeft(2, '0'));
  }
  if (data.length > count) sb.write(' … (${data.length} bytes)');
  return sb.toString();
}

/// Decodes a fixed-width, NUL-terminated ASCII field, keeping only printable
/// characters. Never throws on a short/garbage buffer (clamps to [data] end).
String readAsciiField(Uint8List data, int offset, int maxLen) {
  if (offset >= data.length) return '';
  final end = (offset + maxLen) <= data.length ? offset + maxLen : data.length;
  final sb = StringBuffer();
  for (var i = offset; i < end; i++) {
    final c = data[i];
    if (c == 0) break; // NUL terminates the string
    if (c >= 0x20 && c < 0x7F) sb.writeCharCode(c); // printable ASCII only
  }
  return sb.toString().trim();
}
