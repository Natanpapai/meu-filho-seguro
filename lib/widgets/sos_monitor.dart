import 'package:flutter/material.dart';
import '../app_deps.dart';
import '../app_navigator.dart';
import '../models/models.dart';
import '../models/safety_models.dart';
import '../services/firebase_service.dart';
import '../services/sos_alarm_service.dart';
import '../services/sync_service.dart';

/// Monitor global de alertas SOS.
///
/// Fica acima de todas as telas do responsável: ouve o Firestore e, ao
/// chegar um SOS novo, dispara o alarme sonoro e mostra um popup em
/// qualquer tela do app (mapa, histórico, ajustes — não só na aba de
/// filhos).
///
/// Detalhes importantes:
/// - Reage ao login feito DURANTE a sessão (via `authTick`): o `builder`
///   do MaterialApp não é reconstruído sozinho quando o responsável
///   entra, então sem isso o monitor nunca assinava o stream.
/// - O popup usa a chave global do Navigator ([appNavigatorKey]): o
///   contexto do `builder` fica ACIMA do Navigator, então
///   `Navigator.of(context)` ali falharia silenciosamente.
/// - Se o alerta for marcado como visto por outro caminho (ex.: a tela
///   de emergência nativa estilo Defesa Civil), o popup fecha sozinho.
///
/// Com o app fechado ou a tela bloqueada, o serviço nativo de vigilância
/// (SosWatchService) assume o alarme e a tela de emergência.
class SosMonitor extends StatefulWidget {
  final AppDeps deps;
  final Widget child;
  const SosMonitor({super.key, required this.deps, required this.child});

  @override
  State<SosMonitor> createState() => _SosMonitorState();
}

class _SosMonitorState extends State<SosMonitor> {
  final Set<String> _dialogShown = {};
  final Map<String, BuildContext> _dialogContexts = {};

  @override
  void initState() {
    super.initState();
    // v15 — reforço: garante a vigilância nativa (SosWatchService) ligada
    // se o responsável estiver logado. O serviço precisa estar vivo para
    // o alerta chegar com o app fechado ou a tela bloqueada. O
    // startWatch nativo é idempotente (não duplica listeners).
    final gid = widget.deps.storage.getGuardian()?.id;
    if (gid != null && gid.isNotEmpty) {
      SosAlarmService.startWatch(gid);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!FirebaseService.available) return widget.child;
    // Reconstrói (e assina o stream) quando a sessão muda — cobre o
    // login feito com o app já aberto.
    return ValueListenableBuilder<int>(
      valueListenable: widget.deps.storage.authTick,
      builder: (context, tick, child) {
        final gid = widget.deps.storage.getGuardian()?.id;
        if (gid == null || gid.isEmpty) {
          _dismissAllDialogs();
          return widget.child;
        }
        return StreamBuilder<List<SosAlertInfo>>(
          stream: RemoteSync.sosAlertsInfoStream(gid),
          builder: (context, snap) {
            final alerts = (snap.data ?? const <SosAlertInfo>[])
                .where((a) => !a.ack)
                .where((a) =>
                    a.timestamp == null ||
                    DateTime.now().difference(a.timestamp!).inHours < 24)
                .toList();

            final unackedIds = alerts.map((a) => a.id).toSet();
            // Fecha popups de alertas que foram vistos por outro caminho
            // (ex.: botão "MARCAR COMO VISTO" da tela de emergência nativa).
            for (final id in _dialogContexts.keys.toList()) {
              if (!unackedIds.contains(id)) _dismissDialog(id);
            }

            for (final a in alerts) {
              // Dispara o som (idempotente por alerta).
              SosAlarmService.triggerAlarm(SosAlert(
                id: a.id,
                childId: a.childId,
                childName: a.childName,
                guardianId: gid,
                lat: a.lat,
                lng: a.lng,
                timestamp: a.timestamp,
                ack: a.ack,
              ));
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
      },
    );
  }

  void _showSosDialog(SosAlertInfo alert) {
    // Pela chave global: funciona de qualquer tela, pois o contexto do
    // builder do MaterialApp não tem um Navigator acima dele.
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    showDialog(
      context: nav.context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        _dialogContexts[alert.id] = dialogCtx;
        return AlertDialog(
          backgroundColor: const Color(0xFFB71C1C),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Colors.white, size: 30),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('SOS ACIONADO!',
                    style: TextStyle(color: Colors.white)),
              ),
              // v15: selo de teste — o alerta veio do botão "Testar nos
              // DOIS aparelhos", não é emergência real.
              if (alert.test) _testChip(),
            ],
          ),
          content: Text(
            alert.test
                ? 'Alerta de TESTE para ${alert.childName}. '
                    'Está tudo bem — é só para validar que o alerta '
                    'chega nos dois aparelhos.'
                : '${alert.childName} precisa de ajuda agora!',
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
                _dismissDialog(alert.id);
              },
              child: const Text('Marcar como visto',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  /// Selo "TESTE" para alertas vindos do botão de teste.
  Widget _testChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: const Text(
        'TESTE',
        style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1),
      ),
    );
  }

  void _dismissDialog(String id) {
    _dialogShown.remove(id);
    final ctx = _dialogContexts.remove(id);
    if (ctx == null) return;
    try {
      if (ctx.mounted) Navigator.of(ctx).pop();
    } catch (_) {}
  }

  void _dismissAllDialogs() {
    for (final id in _dialogContexts.keys.toList()) {
      _dismissDialog(id);
    }
  }
}
