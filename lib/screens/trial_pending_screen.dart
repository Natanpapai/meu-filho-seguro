import 'package:flutter/material.dart';
import '../services/trial_service.dart';
import '../theme.dart';
import 'owner_pin_screen.dart';

/// Tela de espera do testador: pedido enviado, aguardando liberação.
///
/// O app escuta o documento do pedido em tempo real — quando o dono
/// libera, esta tela some sozinha e o app libera (o TrialGate reage).
///
/// Gesto oculto: 5 toques no escudo abrem a área do dono (PIN).
class TrialPendingScreen extends StatefulWidget {
  const TrialPendingScreen({super.key});

  @override
  State<TrialPendingScreen> createState() => _TrialPendingScreenState();
}

class _TrialPendingScreenState extends State<TrialPendingScreen> {
  int _shieldTaps = 0;
  DateTime? _firstTap;

  void _onShieldTap() {
    final now = DateTime.now();
    if (_firstTap == null || now.difference(_firstTap!).inSeconds > 3) {
      _firstTap = now;
      _shieldTaps = 1;
    } else {
      _shieldTaps++;
    }
    if (_shieldTaps >= 5) {
      _shieldTaps = 0;
      _firstTap = null;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const OwnerPinScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final number = TrialService.instance.requestNumber.value;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: GestureDetector(
                  onTap: _onShieldTap,
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: const Icon(Icons.hourglass_top_outlined,
                        size: 52, color: AppTheme.primary),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                number == null
                    ? 'Pedido enviado!'
                    : 'Pedido ${TrialService.displayNumber(number)} enviado!',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark),
              ),
              const SizedBox(height: 8),
              const Text(
                'Estamos analisando seu pedido. Assim que for liberado, '
                'este app avisa sozinho e seus 7 dias de teste começam.\n\n'
                'Pode deixar o app aberto ou fechar — quando liberar, '
                'é só abrir de novo.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
              ),
              const Spacer(),
              const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Aguardando liberação…',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
