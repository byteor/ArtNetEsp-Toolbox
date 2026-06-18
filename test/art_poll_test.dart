import 'package:artnet_app/features/artnet/domain/art_poll.dart';
import 'package:artnet_app/features/artnet/domain/artnet_constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildArtPoll', () {
    test('produces a 14-byte packet', () {
      expect(buildArtPoll().length, 14);
    });

    test('starts with the Art-Net ID', () {
      final p = buildArtPoll();
      expect(p.sublist(0, 8), kArtNetId);
      expect(hasArtNetId(p), isTrue);
    });

    test('encodes OpPoll (0x2000) little-endian', () {
      final p = buildArtPoll();
      expect(p[8], 0x00); // low byte first
      expect(p[9], 0x20);
      expect(readOpCode(p), 0x2000);
    });

    test('sets protocol version 0/14', () {
      final p = buildArtPoll();
      expect(p[10], 0); // ProtVerHi
      expect(p[11], 14); // ProtVerLo
    });

    test('defaults flags and priority to 0', () {
      final p = buildArtPoll();
      expect(p[12], 0);
      expect(p[13], 0);
    });

    test('honors custom flags', () {
      final p = buildArtPoll(flags: kArtPollFlagReplyOnChange);
      expect(p[12], 0x02);
    });
  });
}
