import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

/// Indicador de conexão na barra do app do responsável.
/// Mostra se o celular tem internet (WiFi ou dados móveis) ou está offline.
/// Ajuda a diagnosticar: se estiver offline, os dados do filho não atualizam.
class ConnectivityChip extends StatelessWidget {
  const ConnectivityChip({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ConnectivityResult>>(
      stream: Connectivity().onConnectivityChanged,
      builder: (context, snap) {
        final results = snap.data ?? const [ConnectivityResult.none];
        final online = results.any((r) =>
            r == ConnectivityResult.wifi ||
            r == ConnectivityResult.mobile ||
            r == ConnectivityResult.ethernet);
        final isMobile = results.contains(ConnectivityResult.mobile);
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Chip(
            visualDensity: VisualDensity.compact,
            avatar: Icon(
              online
                  ? (isMobile ? Icons.signal_cellular_alt : Icons.wifi)
                  : Icons.wifi_off,
              size: 16,
              color: online ? Colors.green : Colors.red,
            ),
            label: Text(
              online ? (isMobile ? '4G/5G' : 'Online') : 'Offline',
              style: const TextStyle(fontSize: 11),
            ),
          ),
        );
      },
    );
  }
}
