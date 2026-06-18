import 'dart:typed_data';

import 'artnet_constants.dart';
import 'artnet_opcodes.dart';

/// TalkToMe flag: ask nodes to send an ArtPollReply whenever their state
/// changes (not just in response to a poll). We leave it off by default for a
/// simple one-shot discovery.
const int kArtPollFlagReplyOnChange = 0x02;

/// Builds a 14-byte ArtPoll packet.
///
/// Layout (offsets):
///   [0..7]  ID  "Art-Net\0"
///   [8..9]  OpCode 0x2000, LITTLE-ENDIAN  -> 0x00, 0x20
///   [10]    ProtVerHi = 0
///   [11]    ProtVerLo = 14
///   [12]    Flags (TalkToMe)
///   [13]    Priority (lowest diagnostics priority to send; 0 = all)
///
/// Send this to the broadcast address (or a unicast target) on UDP 6454 and
/// listen for ArtPollReply packets.
Uint8List buildArtPoll({int flags = 0x00, int priority = 0x00}) {
  final packet = Uint8List(14);
  packet.setRange(0, 8, kArtNetId);
  packet[8] = ArtNetOpCode.poll & 0xFF; // OpCode low byte (LE)
  packet[9] = (ArtNetOpCode.poll >> 8) & 0xFF; // OpCode high byte
  packet[10] = 0; // ProtVerHi
  packet[11] = kArtNetProtocolVersion; // ProtVerLo (14)
  packet[12] = flags & 0xFF; // TalkToMe
  packet[13] = priority & 0xFF; // Priority
  return packet;
}
