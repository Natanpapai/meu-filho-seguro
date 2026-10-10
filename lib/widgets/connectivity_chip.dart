import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

/// Indicador de conexão na barra do app do responsável.
/// Mostra se o celular tem internet (WiFi ou dados móveis) ou está offline.
/// Ajuda a diagnosticar: se estiver offline, os dados do filho não atualizam.
///
/// OTIMIZAÇÃO: StatefulWidget com UMA única instância de Connectivity.
/// Antes era StatelessWidget criando `Connectivity()` novo a cada build
/// da AppBar — churn de streams a cada rebuild da tela.
class ConnectivityChip extends StatefulWidget {
  const ConnectivityChip({super.key});

  @override
  State<ConnectivityChip> createState() => _ConnectivityChipState();
}

class _ConnectivityChipState extends State<ConnectivityChip> {
  final Connectivity _connectivity = Connectivity();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ConnectivityResult>>(
      stream: _connectivity.onConnectivityChanged,
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
