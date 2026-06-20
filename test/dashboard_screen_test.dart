import 'dart:async';

import 'package:artnet_app/core/app_info/app_info_providers.dart';
import 'package:artnet_app/core/logging/app_logger.dart';
import 'package:artnet_app/core/logging/logging_providers.dart';
import 'package:artnet_app/core/network/network_info.dart';
import 'package:artnet_app/core/network/network_providers.dart';
import 'package:artnet_app/features/dashboard/presentation/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Info screen shows the app version', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appVersionProvider.overrideWith((ref) async => '1.0.1+2'),
          // No plugins in widget tests: keep the network card loading and use a
          // plain in-memory logger (bypasses settingsProvider/SharedPreferences).
          localNetworkStatusProvider
              .overrideWith((ref) => Completer<LocalNetworkStatus>().future),
          appLoggerProvider.overrideWithValue(AppLogger()),
        ],
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );
    await tester.pump(); // resolve the appVersion future
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('App version 1.0.1+2'), findsOneWidget);

    await tester.pumpWidget(const SizedBox()); // dispose
  });
}
