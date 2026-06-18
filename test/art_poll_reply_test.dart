import 'dart:typed_data';

import 'package:artnet_app/features/artnet/domain/art_poll_reply.dart';
import 'package:artnet_app/features/artnet/domain/artnet_constants.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a synthetic, well-formed ArtPollReply with known field values so we
/// can assert the parser extracts them at the correct offsets/endianness.
Uint8List buildSyntheticReply() {
  final b = Uint8List(240);
  b.setRange(0, 8, kArtNetId);
  b[8] = 0x00; // OpCode 0x2100 little-endian
  b[9] = 0x21;
  // IP 192.168.1.50
  b[10] = 192;
  b[11] = 168;
  b[12] = 1;
  b[13] = 50;
  // Port 6454 (0x1936) little-endian
  b[14] = 0x36;
  b[15] = 0x19;
  // VersInfo (big-endian) = 0x0102 = 258
  b[16] = 0x01;
  b[17] = 0x02;
  // OEM (big-endian) = 0x0050 = 80
  b[20] = 0x00;
  b[21] = 0x50;
  // ESTA (little-endian) = 0x1234
  b[24] = 0x34;
  b[25] = 0x12;
  _writeAscii(b, 26, 'TestNode');
  _writeAscii(b, 44, 'Test Node Long Name');
  // NumPorts (big-endian) = 4
  b[172] = 0x00;
  b[173] = 0x04;
  return b;
}

void _writeAscii(Uint8List buf, int offset, String s) {
  for (var i = 0; i < s.length; i++) {
    buf[offset + i] = s.codeUnitAt(i);
  }
}

void main() {
  group('parseArtPollReply (valid)', () {
    test('extracts all fields at correct offsets/endianness', () {
      final node = parseArtPollReply(buildSyntheticReply(), sourceIp: '192.168.1.50');
      expect(node, isNotNull);
      expect(node!.ip, '192.168.1.50');
      expect(node.port, 6454);
      expect(node.firmwareVersion, 258);
      expect(node.oem, 0x0050);
      expect(node.esta, 0x1234);
      expect(node.shortName, 'TestNode');
      expect(node.longName, 'Test Node Long Name');
      expect(node.numPorts, 4);
    });
  });

  group('parseArtPollReply (rejects non-replies)', () {
    test('returns null for an empty buffer', () {
      expect(parseArtPollReply(Uint8List(0)), isNull);
    });

    test('returns null when the Art-Net ID is wrong', () {
      final b = buildSyntheticReply();
      b[0] = 0x00; // corrupt the ID
      expect(parseArtPollReply(b), isNull);
    });

    test('returns null for a different opcode (ArtPoll, not reply)', () {
      final b = buildSyntheticReply();
      b[8] = 0x00;
      b[9] = 0x20; // 0x2000 = ArtPoll
      expect(parseArtPollReply(b), isNull);
    });
  });

  group('parseArtPollReply (never throws on malformed input)', () {
    test('truncated reply returns a partial node, no throw', () {
      // Valid ID + reply opcode, but only 30 bytes.
      final b = Uint8List(30);
      b.setRange(0, 8, kArtNetId);
      b[8] = 0x00;
      b[9] = 0x21;
      b[10] = 10;
      b[11] = 0;
      b[12] = 0;
      b[13] = 5;
      final node = parseArtPollReply(b, sourceIp: '10.0.0.5');
      expect(node, isNotNull);
      expect(node!.ip, '10.0.0.5');
      expect(node.numPorts, isNull); // offset 172 not present
      expect(node.longName, ''); // offset 44 beyond buffer
    });

    test('short buffer with valid header but no IP uses sourceIp', () {
      final b = Uint8List(12)
        ..setRange(0, 8, kArtNetId)
        ..[8] = 0x00
        ..[9] = 0x21;
      final node = parseArtPollReply(b, sourceIp: '172.16.0.9');
      expect(node, isNotNull);
      expect(node!.ip, '172.16.0.9');
      expect(node.port, isNull);
    });

    test('random garbage after a valid header does not throw', () {
      final b = Uint8List.fromList([
        ...kArtNetId,
        0x00, 0x21, // reply opcode
        for (var i = 0; i < 50; i++) (i * 37) % 256,
      ]);
      expect(() => parseArtPollReply(b), returnsNormally);
    });
  });
}
