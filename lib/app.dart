import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/network/network_change_providers.dart';
import 'features/artnet/presentation/monitor_screen.dart';
import 'features/artnet/presentation/transmit_screen.dart';
import 'features/dashboard/presentation/dashboard_screen.dart';
import 'features/scan/presentation/scan_screen.dart';
import 'features/settings/presentation/settings_screen.dart';

/// Root MaterialApp (Material 3).
class ArtNetApp extends StatelessWidget {
  const ArtNetApp({super.key});

  @override
  Widget build(BuildContext context) {
    final seed = Colors.indigo;
    return MaterialApp(
      title: 'ArtNetEsp Toolbox',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
      ),
      home: const RootShell(),
    );
  }
}

/// Bottom-navigation shell. Each destination is a self-contained screen. Adding
/// a new device type or tool later means adding a destination here.
class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key});

  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell> {
  int _index = 0;

  static const List<Widget> _screens = [
    ScanScreen(),
    MonitorScreen(),
    TransmitScreen(),
    DashboardScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    // Keep the network-change reactor alive (refreshes Info + recycles the
    // Art-Net socket on a switch) and surface each change to the user.
    ref.watch(networkChangeReactorProvider);
    ref.listen(networkChangeDetectorProvider, (previous, next) {
      if (!next.hasValue) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Network changed — refreshed')),
        );
    });

    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.radar_outlined),
            selectedIcon: Icon(Icons.radar),
            label: 'ArtNet Scan',
          ),
          NavigationDestination(
            icon: Icon(Icons.graphic_eq),
            selectedIcon: Icon(Icons.graphic_eq),
            label: 'Monitor',
          ),
          NavigationDestination(
            icon: Icon(Icons.send_outlined),
            selectedIcon: Icon(Icons.send),
            label: 'Transmit',
          ),
          NavigationDestination(
            icon: Icon(Icons.info_outline),
            selectedIcon: Icon(Icons.info),
            label: 'Info',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
