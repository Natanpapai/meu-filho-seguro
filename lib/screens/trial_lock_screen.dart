import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/trial_service.dart';
import '../theme.dart';
import 'owner_pin_screen.dart';

/// Tela cheia de bloqueio (v17): o teste de 7 dias terminou ou o acesso
/// foi bloqueado. Cobre o app inteiro — não é um popup dispensável.
///
/// Botão "QUERO COMPRAR" abre o WhatsApp do dono com mensagem pronta.
/// Gesto oculto: 5 toques no escudo abrem a área do dono (PIN).
class TrialLockScreen extends StatefulWidget {
  const TrialLockScreen({super.key});

  @override
  State<TrialLockScreen> createState() => _TrialLockScreenState();
}

class _TrialLockScreenState extends State<TrialLockScreen> {
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

  Future<void> _openWhatsapp() async {
    final uri = Uri.parse(TrialService.whatsappBuyUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final blocked =
        TrialService.instance.status.value == TrialStatus.blocked;
    return Scaffold(
      backgroundColor: AppTheme.primaryDark,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Center(
                child: GestureDetector(
                  onTap: _onShieldTap,
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: const Icon(Icons.lock_outline,
                        size: 52, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                blocked ? 'Acesso bloqueado' : 'Seu teste de 7 dias terminou',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                blocked
                    ? 'Seu acesso foi revogado. Fale com a gente para regularizar.'
                    : 'Obrigado por testar! Para continuar protegendo quem '
                        'você mais ama:',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.85)),
              ),
              const SizedBox(height: 20),
              ...const [
                _Bullet('Localização do seu filho em tempo real, no mapa'),
                _Bullet('Trajeto do dia com passinhos constantes'),
                _Bullet(
                    'Alerta de emergência em tela cheia, mesmo com o celular bloqueado'),
                _Bullet('Alerta da Defesa Civil, rota segura e modo escola'),
              ],
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _openWhatsapp,
                icon: const Icon(Icons.chat),
                label: const Text('QUERO COMPRAR'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 56),
                  textStyle: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Você fala direto com a gente no WhatsApp.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.7)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline,
              size: 20, color: AppTheme.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style:
                  TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.92)),
            ),
          ),
        ],
      ),
    );
  }
}
