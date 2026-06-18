import 'dart:convert';
import 'dart:typed_data';

/// A normalized mDNS/Bonjour service record, decoupled from the `nsd` package
/// types so the discovery backend can be swapped behind [MdnsDiscovery].
class MdnsServiceRecord {
  const MdnsServiceRecord({
    required this.name,
    required this.type,
    required this.host,
    required this.port,
    required this.addresses,
    required this.txt,
  });

  final String name;
  final String type;
  final String host;
  final int? port;
  final List<String> addresses;
  final Map<String, String> txt;

  /// Stable identity for de-duplication: a service is identified by its type +
  /// instance name.
  String get key => '$type|$name';

  String get displayName => name.isNotEmpty ? name : (host.isNotEmpty ? host : type);

  /// Decodes a TXT value (opaque bytes) to a readable string, tolerating
  /// non-UTF8 data rather than throwing.
  static String decodeTxtValue(Uint8List? value) {
    if (value == null || value.isEmpty) return '';
    try {
      return utf8.decode(value);
    } catch (_) {
      return value
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
    }
  }
}
