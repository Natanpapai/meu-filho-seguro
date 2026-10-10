import 'package:flutter/material.dart';
import '../app_deps.dart';
import '../models/models.dart';
import '../services/firebase_service.dart';
import '../services/sos_alarm_service.dart';
import '../services/sync_service.dart';

/// Monitor global de alertas SOS.
///
/// Fica acima de todas as telas do responsável: ouve o Firestore e, ao
/// chegar um SOS novo, dispara o alarme sonoro e mostra um popup em
/// qualquer tela do app (não só na aba de filhos).
///
/// Com o app fechado ou a tela bloqueada, o serviço nativo de vigilância
/// (SosWatchService) assume o alarme.
class SosMonitor extends StatefulWidget {
  final AppDeps deps;
  final Widget child;
  const SosMonitor({super.key, required this.deps, required this.child});

  @override
  State<SosMonitor> createState() => _SosMonitorState();
}

class _SosMonitorState extends State<SosMonitor> {
  final Set<String> _dialogShown = {};

  @override
  Widget build(BuildContext context) {
    if (!FirebaseService.available) return widget.child;
    final gid = widget.deps.storage.getGuardian()?.id;
    if (gid == null || gid.isEmpty) return widget.child;

    return StreamBuilder<List<SosAlert>>(
      stream: RemoteSync.sosAlertsStream(gid),
      builder: (context, snap) {
        final alerts = (snap.data ?? const <SosAlert>[])
            .where((a) => !a.ack)
            .where((a) =>
                a.timestamp == null ||
                DateTime.now().difference(a.timestamp!).inHours < 24)
            .toList();

        for (final a in alerts) {
          // Dispara o som (idempotente por alerta).
          SosAlarmService.triggerAlarm(a);
          // Popup em qualquer tela (uma vez por alerta).
          if (_dialogShown.add(a.id)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _showSosDialog(a);
            });
          }
        }
        return widget.child;
      },
    );
  }

  void _showSosDialog(SosAlert alert) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFFB71C1C),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: Colors.white, size: 30),
            SizedBox(width: 10),
            Text('SOS ACIONADO!',
                style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          '${alert.childName} precisa de ajuda agora!',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFFB71C1C),
            ),
            onPressed: () async {
              await RemoteSync.ackSosAlert(alert.id);
              await SosAlarmService.stopAlarm(alert.id);
              if (mounted) Navigator.of(context).pop();
            },
            child: const Text('Marcar como visto',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
