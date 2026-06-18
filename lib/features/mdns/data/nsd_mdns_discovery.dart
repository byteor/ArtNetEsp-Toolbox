import 'dart:async';

import 'package:nsd/nsd.dart';

import '../../../core/logging/app_logger.dart';
import '../domain/mdns_service_record.dart';
import 'mdns_discovery.dart';

const String _kTag = 'mdns';

/// [MdnsDiscovery] backed by the `nsd` package, which uses the OS-level service
/// discovery stack (Android NSD, Apple Bonjour/NetService).
///
/// Using the system resolver — rather than raw multicast in Dart — means we do
/// NOT need the iOS `com.apple.developer.networking.multicast` entitlement. We
/// do still need the Local Network permission and an `NSBonjourServices`
/// declaration for every browsed type. See docs/IOS_LOCAL_NETWORK.md.
class NsdMdnsDiscovery implements MdnsDiscovery {
  NsdMdnsDiscovery(this._logger);

  final AppLogger _logger;

  @override
  Stream<List<MdnsServiceRecord>> browse(List<String> serviceTypes) {
    final records = <String, MdnsServiceRecord>{};
    final discoveries = <Discovery>[];
    late final StreamController<List<MdnsServiceRecord>> controller;

    Future<void> startAll() async {
      for (final type in serviceTypes) {
        if (type.trim().isEmpty) continue;
        try {
          final discovery = await startDiscovery(
            type.trim(),
            autoResolve: true,
            ipLookupType: IpLookupType.v4,
          );
          discovery.addServiceListener((service, status) {
            final record = _toRecord(service);
            if (status == ServiceStatus.found) {
              records[record.key] = record;
            } else {
              records.remove(record.key);
            }
            if (!controller.isClosed) {
              controller.add(records.values.toList(growable: false));
            }
          });
          discoveries.add(discovery);
          _logger.info(_kTag, 'Browsing $type');
        } catch (e) {
          _logger.error(_kTag, 'Failed to browse $type', e);
        }
      }
    }

    Future<void> stopAll() async {
      for (final discovery in discoveries) {
        try {
          await stopDiscovery(discovery);
        } catch (_) {
          // best-effort teardown
        }
      }
      discoveries.clear();
      _logger.info(_kTag, 'Stopped mDNS browsing');
    }

    controller = StreamController<List<MdnsServiceRecord>>(
      onListen: startAll,
      onCancel: stopAll,
    );
    return controller.stream;
  }

  MdnsServiceRecord _toRecord(Service service) {
    final addresses =
        (service.addresses ?? const []).map((a) => a.address).toList();
    final txt = <String, String>{};
    service.txt?.forEach((k, v) {
      txt[k] = MdnsServiceRecord.decodeTxtValue(v);
    });
    return MdnsServiceRecord(
      name: service.name ?? '',
      type: service.type ?? '',
      host: service.host ?? '',
      port: service.port,
      addresses: addresses,
      txt: txt,
    );
  }
}
