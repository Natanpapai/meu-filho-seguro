import 'package:flutter/material.dart';
import '../app_deps.dart';
import '../screens/trial_lock_screen.dart';
import '../screens/trial_pending_screen.dart';
import '../screens/trial_request_screen.dart';
import '../services/trial_service.dart';

/// Portão do trial (v17): fica no `builder` do MaterialApp, acima do
/// Navigator — cobre TODAS as telas.
///
/// Conforme o estado do trial, sobrepõe:
/// - [TrialStatus.noRequest] → tela de solicitação do teste
/// - [TrialStatus.pendingApproval] → tela de espera
/// - [TrialStatus.expired]/[TrialStatus.blocked] → tela de bloqueio
/// - [TrialStatus.active]/[TrialStatus.checking] → app normal
///
/// A área do dono (PIN) é aberta por gesto oculto nas telas do trial e
/// navega POR CIMA do overlay (usa o Navigator raiz).
class TrialGate extends StatefulWidget {
  final AppDeps deps;
  final Widget child;
  const TrialGate({super.key, required this.deps, required this.child});

  @override
  State<TrialGate> createState() => _TrialGateState();
}

class _TrialGateState extends State<TrialGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Voltou para o app: recalcula (ex.: dono liberou com o app aberto,
    // ou os 7 dias viraram com o app em 2º plano).
    if (state == AppLifecycleState.resumed) {
      TrialService.instance.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TrialStatus>(
      valueListenable: TrialService.instance.status,
      builder: (context, st, _) {
        Widget? overlay;
        switch (st) {
          case TrialStatus.noRequest:
            overlay = const TrialRequestScreen();
            break;
          case TrialStatus.pendingApproval:
            overlay = const TrialPendingScreen();
            break;
          case TrialStatus.expired:
          case TrialStatus.blocked:
            overlay = const TrialLockScreen();
            break;
          case TrialStatus.checking:
          case TrialStatus.active:
            overlay = null;
            break;
        }
        if (overlay == null) return widget.child;
        // Overlay opaco por cima do app: bloqueia toda interação.
        return Stack(
          children: [
            widget.child,
            Positioned.fill(child: overlay),
          ],
        );
      },
    );
  }
}
