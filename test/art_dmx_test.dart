import 'dart:typed_data';

import 'package:artnet_app/features/artnet/domain/art_dmx.dart';
import 'package:artnet_app/features/artnet/domain/artnet_constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildArtDmx', () {
    test('512 channels -> 18 + 512 byte packet with correct header', () {
      final p = buildArtDmx(universe: 0, channels: List<int>.filled(512, 0));
      expect(p.length, 18 + 512);
      expect(hasArtNetId(p), isTrue);
      expect(p[8], 0x00); // OpDmx 0x5000 little-endian
      expect(p[9], 0x50);
      expect(readOpCode(p), 0x5000);
      expect(p[10], 0); // ProtVerHi
      expect(p[11], 14); // ProtVerLo
      expect(p[16], 0x02); // LengthHi (512 = 0x0200) BIG-ENDIAN
      expect(p[17], 0x00); // LengthLo
    });

    test('splits universe into SubUni (low) and Net (high)', () {
      final p = buildArtDmx(universe: 0x1234, channels: List<int>.filled(512, 0));
      expect(p[14], 0x34); // SubUni
      expect(p[15], 0x12); // Net
    });

    test('odd channel counts are padded to an even length', () {
      final p = buildArtDmx(universe: 0, channels: [1, 2, 3]);
      final length = (p[16] << 8) | p[17];
      expect(length, 4);
      expect(p.length, 18 + 4);
    });

    test('lengths below 2 are bumped to 2', () {
      final p = buildArtDmx(universe: 0, channels: [5]);
      final length = (p[16] << 8) | p[17];
      expect(length, 2);
      expect(p[18], 5);
      expect(p[19], 0);
    });

    test('lengths above 512 are clamped', () {
      final p = buildArtDmx(universe: 0, channels: List<int>.filled(600, 7));
      final length = (p[16] << 8) | p[17];
      expect(length, 512);
      expect(p.length, 18 + 512);
    });
  });

  group('buildArtDmxSingleChannel', () {
    test('sets channel 1', () {
      final p = buildArtDmxSingleChannel(universe: 0, channel: 1, value: 255);
      expect(p[18], 255);
    });

    test('sets channel 512', () {
      final p = buildArtDmxSingleChannel(universe: 0, channel: 512, value: 10);
      expect(p[18 + 511], 10);
    });

    test('clamps out-of-range channel without throwing', () {
      expect(
        () => buildArtDmxSingleChannel(universe: 0, channel: 9999, value: 1),
        returnsNormally,
      );
    });
  });

  group('parseArtDmx', () {
    test('round-trips universe, sequence and channel data', () {
      final p = buildArtDmx(
        universe: 0x1234,
        channels: [10, 20, 30, 40, ...List<int>.filled(508, 0)],
        sequence: 7,
      );
      final parsed = parseArtDmx(p);
      expect(parsed, isNotNull);
      expect(parsed!.universe, 0x1234);
      expect(parsed.sequence, 7);
      expect(parsed.length, 512);
      expect(parsed.firstChannels(4), [10, 20, 30, 40]);
    });

    test('returns null for wrong ID', () {
      final p = buildArtDmx(universe: 0, channels: [1, 2]);
      p[0] = 0;
      expect(parseArtDmx(p), isNull);
    });

    test('returns null for wrong opcode', () {
      final p = buildArtDmx(universe: 0, channels: [1, 2]);
      p[8] = 0x00;
      p[9] = 0x21; // poll reply opcode
      expect(parseArtDmx(p), isNull);
    });

    test('returns null when shorter than the 18-byte header', () {
      final b = Uint8List(10)..setRange(0, 8, kArtNetId);
      expect(parseArtDmx(b), isNull);
    });

    test('clamps a declared length that exceeds the buffer (no throw)', () {
      // Full frame declares length 512 but we truncate to 24 bytes total.
      final full = buildArtDmx(universe: 1, channels: List<int>.filled(512, 9));
      final truncated = Uint8List.sublistView(full, 0, 24);
      final parsed = parseArtDmx(truncated);
      expect(parsed, isNotNull);
      expect(parsed!.length, 24 - 18); // clamped to available bytes
      expect(parsed.channels.length, 6);
    });
  });
}
