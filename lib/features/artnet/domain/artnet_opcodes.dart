/// Art-Net OpCodes used by this app.
///
/// OpCodes are 16-bit values transmitted LITTLE-ENDIAN on the wire (the low
/// byte is sent first). For example OpDmx (0x5000) is sent as `00 50`.
/// This is a classic trap — see `docs/ARTNET_NOTES.md`.
class ArtNetOpCode {
  ArtNetOpCode._();

  /// OpPoll — sent by a controller to discover nodes.
  static const int poll = 0x2000;

  /// OpPollReply — sent by nodes in response to an ArtPoll.
  static const int pollReply = 0x2100;

  /// OpDmx (a.k.a. OpOutput) — carries a frame of DMX512 channel data.
  static const int dmx = 0x5000;

  /// Human-readable name for diagnostics/logging.
  static String name(int opcode) {
    switch (opcode) {
      case poll:
        return 'ArtPoll';
      case pollReply:
        return 'ArtPollReply';
      case dmx:
        return 'ArtDmx';
      default:
        return '0x${opcode.toRadixString(16).padLeft(4, '0')}';
    }
  }
}
