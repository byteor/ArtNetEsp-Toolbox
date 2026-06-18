import 'dart:typed_data';

import 'artnet_constants.dart';
import 'artnet_opcodes.dart';

/// Maximum DMX channels in one universe / one ArtDmx frame.
const int kDmxChannels = 512;

/// A parsed ArtDmx packet (monitor side).
class ArtDmxPacket {
  const ArtDmxPacket({
    required this.universe,
    required this.net,
    required this.subUni,
    required this.sequence,
    required this.physical,
    required this.length,
    required this.channels,
  });

  /// 15-bit Port-Address: (net << 8) | subUni.
  final int universe;

  /// High byte of the Port-Address (7 bits).
  final int net;

  /// Low byte of the Port-Address (Subnet<<4 | Universe).
  final int subUni;

  /// Sequence number (0 = sequencing disabled, else rolling 1..255).
  final int sequence;

  /// Physical input port (informational only).
  final int physical;

  /// Number of channel bytes actually present (after clamping to the buffer).
  final int length;

  /// The channel values (length == [length]).
  final List<int> channels;

  /// First [n] channel values, padded with nothing (may be shorter than n).
  List<int> firstChannels(int n) =>
      channels.length <= n ? channels : channels.sublist(0, n);
}

/// Builds an ArtDmx packet carrying [channels] for [universe].
///
/// Layout:
///   [0..7]   ID
///   [8..9]   OpCode 0x5000 (LE) -> 0x00, 0x50
///   [10]     ProtVerHi = 0
///   [11]     ProtVerLo = 14
///   [12]     Sequence
///   [13]     Physical
///   [14]     SubUni  = universe & 0xFF        (low byte of Port-Address)
///   [15]     Net     = (universe >> 8) & 0x7F (high 7 bits)
///   [16]     LengthHi  } data length, BIG-ENDIAN (the opposite of the opcode!)
///   [17]     LengthLo  }
///   [18..]   channel data (length bytes)
///
/// [universe] is the full 15-bit Port-Address (0..32767). The data length is
/// normalised to an even number in 2..512 (defaults to a full 512-channel frame
/// when [channels] has 512 entries).
Uint8List buildArtDmx({
  required int universe,
  required List<int> channels,
  int sequence = 0,
  int physical = 0,
}) {
  var length = channels.length;
  if (length < 2) length = 2;
  if (length > kDmxChannels) length = kDmxChannels;
  if (length.isOdd) length += 1; // Art-Net requires an even length

  final packet = Uint8List(18 + length);
  packet.setRange(0, 8, kArtNetId);
  packet[8] = ArtNetOpCode.dmx & 0xFF; // OpCode low byte (LE)
  packet[9] = (ArtNetOpCode.dmx >> 8) & 0xFF; // OpCode high byte
  packet[10] = 0; // ProtVerHi
  packet[11] = kArtNetProtocolVersion; // ProtVerLo (14)
  packet[12] = sequence & 0xFF;
  packet[13] = physical & 0xFF;
  packet[14] = universe & 0xFF; // SubUni (low byte)
  packet[15] = (universe >> 8) & 0x7F; // Net (high 7 bits)
  packet[16] = (length >> 8) & 0xFF; // LengthHi (BIG-ENDIAN)
  packet[17] = length & 0xFF; // LengthLo
  for (var i = 0; i < length && i < channels.length; i++) {
    packet[18 + i] = channels[i] & 0xFF;
  }
  return packet;
}

/// Convenience: build a 512-channel ArtDmx frame with a single [channel]
/// (1-based, 1..512) set to [value] (0..255), all others zero.
Uint8List buildArtDmxSingleChannel({
  required int universe,
  required int channel,
  required int value,
  int sequence = 0,
}) {
  final channels = List<int>.filled(kDmxChannels, 0);
  final index = (channel - 1).clamp(0, kDmxChannels - 1);
  channels[index] = value & 0xFF;
  return buildArtDmx(universe: universe, channels: channels, sequence: sequence);
}

/// Parses an ArtDmx packet for the monitor. Returns null if [data] is not a
/// valid ArtDmx packet. Never throws on malformed input: the declared length is
/// clamped to the bytes actually present so we can't read out of bounds.
ArtDmxPacket? parseArtDmx(Uint8List data) {
  if (!hasArtNetId(data)) return null;
  if (data.length < 18) return null; // header incomplete
  if (readOpCode(data) != ArtNetOpCode.dmx) return null;

  final subUni = data[14];
  final net = data[15] & 0x7F;
  final universe = (net << 8) | subUni;
  final sequence = data[12];
  final physical = data[13];

  var length = (data[16] << 8) | data[17]; // BIG-ENDIAN length
  final available = data.length - 18;
  if (length > available) length = available; // never read past the buffer
  if (length < 0) length = 0;

  return ArtDmxPacket(
    universe: universe,
    net: net,
    subUni: subUni,
    sequence: sequence,
    physical: physical,
    length: length,
    channels: data.sublist(18, 18 + length),
  );
}
