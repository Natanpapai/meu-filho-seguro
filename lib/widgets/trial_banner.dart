import 'package:flutter/material.dart';
import '../services/trial_service.dart';
import '../theme.dart';

/// Faixa do trial no topo das telas principais (v17):
/// - normal: "Versão de teste — X dias restantes" (discreta)
/// - 2 dias ou menos: cor de alerta, mais insistente
class TrialBanner extends StatelessWidget {
  const TrialBanner({super.key});

  String _label(int left) {
    if (left == 1) return 'Versão de teste — resta 1 dia';
    return 'Versão de teste — $left dias restantes';
  }

  String _urgentLabel(int left) {
    if (left == 1) {
      return '⚠ Seu teste termina AMANHÃ! Fale com a gente.';
    }
    return '⚠ Seu teste termina em $left dias! Fale com a gente.';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TrialStatus>(
      valueListenable: TrialService.instance.status,
      builder: (context, st, _) {
        if (st != TrialStatus.active) return const SizedBox.shrink();
        return ValueListenableBuilder<int>(
          valueListenable: TrialService.instance.daysLeft,
          builder: (context, left, _) {
            final urgent = left <= 2;
            return Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: urgent
                  ? AppTheme.danger
                  : AppTheme.primary.withOpacity(0.14),
              child: Row(
                children: [
                  Icon(
                    urgent
                        ? Icons.warning_amber_outlined
                        : Icons.timer_outlined,
                    size: 16,
                    color: urgent ? Colors.white : AppTheme.primaryDark,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      urgent ? _urgentLabel(left) : _label(left),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight:
                            urgent ? FontWeight.bold : FontWeight.w500,
                        color:
                            urgent ? Colors.white : AppTheme.primaryDark,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
