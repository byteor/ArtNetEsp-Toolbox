import '../domain/mdns_service_record.dart';

/// Abstraction over mDNS/Bonjour browsing.
///
/// Backed by [NsdMdnsDiscovery] (native NSD/Bonjour). Keeping this interface
/// lets us swap the backend (or fake it in tests) without touching the UI.
abstract interface class MdnsDiscovery {
  /// Browses all [serviceTypes] concurrently. Emits the accumulated list of
  /// currently-visible records whenever a service is found or lost. Cancel the
  /// subscription to stop browsing and release native resources.
  Stream<List<MdnsServiceRecord>> browse(List<String> serviceTypes);
}
