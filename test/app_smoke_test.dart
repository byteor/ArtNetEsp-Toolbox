import 'package:artnet_app/app.dart';
import 'package:artnet_app/core/network/network_change_providers.dart';
import 'package:artnet_app/core/network/network_info.dart';
import 'package:artnet_app/core/network/network_providers.dart';
import 'package:artnet_app/core/settings/app_settings.dart';
import 'package:artnet_app/core/settings/settings_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('app builds with the five navigation destinations',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          initialSettingsProvider.overrideWithValue(const AppSettings()),
          // Avoid hitting the network_info_plus plugin in the test harness.
          localNetworkStatusProvider.overrideWith(
            (ref) async =>
                const LocalNetworkStatus(ipAddress: '192.168.1.10'),
          ),
          // Stub the network-change detector so its poll timer isn't left
          // pending when the widget tree is torn down.
          networkChangeDetectorProvider
              .overrideWith((ref) => const Stream<LocalNetworkStatus>.empty()),
        ],
        child: const ArtNetApp(),
      ),
    );

    // One frame is enough; do not pumpAndSettle (the loading spinner animates).
    await tester.pump();

    expect(find.text('Info'), findsWidgets);
    expect(find.text('Monitor'), findsWidgets);
    expect(find.text('Transmit'), findsWidgets);
    expect(find.text('ArtNet Scan'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
  });
}
