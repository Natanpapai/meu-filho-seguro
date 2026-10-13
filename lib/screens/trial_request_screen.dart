import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/trial_service.dart';
import '../theme.dart';
import 'owner_pin_screen.dart';

/// Primeira tela do testador (v17): solicita os 7 dias de teste.
///
/// O testador informa nome + WhatsApp; o app gera o número sequencial
/// do teste (#001, #002...) e grava o pedido no Firestore. Depois é só
/// tocar em "Enviar pedido pelo WhatsApp".
///
/// Gesto oculto: 5 toques no escudo abrem a área do dono (PIN).
class TrialRequestScreen extends StatefulWidget {
  const TrialRequestScreen({super.key});

  @override
  State<TrialRequestScreen> createState() => _TrialRequestScreenState();
}

class _TrialRequestScreenState extends State<TrialRequestScreen> {
  final _nameCtrl = TextEditingController();
  final _zapCtrl = TextEditingController();
  bool _sending = false;
  String? _error;
  int? _number; // pedido criado
  int _shieldTaps = 0;
  DateTime? _firstTap;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _zapCtrl.dispose();
    super.dispose();
  }

  /// Gesto oculto da área do dono: 5 toques no escudo em até 3 segundos.
  void _onShieldTap() {
    final now = DateTime.now();
    if (_firstTap == null ||
        now.difference(_firstTap!).inSeconds > 3) {
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

  Future<void> _request() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final number = await TrialService.instance.requestTrial(
        name: _nameCtrl.text,
        whatsapp: _zapCtrl.text,
      );
      if (!mounted) return;
      setState(() {
        _sending = false;
        _number = number;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e is ArgumentError
            ? e.message as String
            : 'Não foi possível enviar o pedido. '
                'Confira a internet e tente de novo.';
      });
    }
  }

  Future<void> _openWhatsapp() async {
    final number = _number;
    if (number == null) return;
    final uri = Uri.parse(TrialService.whatsappRequestUrl(
      name: _nameCtrl.text.trim(),
      number: number,
    ));
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _number == null ? _buildForm() : _buildSent(),
        ),
      ),
    );
  }

  Widget _buildShield() {
    return GestureDetector(
      onTap: _onShieldTap,
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(28),
        ),
        child: const Icon(Icons.shield_outlined,
            size: 52, color: Colors.white),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        Center(child: _buildShield()),
        const SizedBox(height: 20),
        const Text(
          'Teste grátis por 7 dias',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark),
        ),
        const SizedBox(height: 8),
        const Text(
          'O Meu Filho Seguro mostra onde seu filho está em tempo real, '
          'com alerta de emergência e muito mais.\n\n'
          'Preencha para solicitar seu teste:',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _nameCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Seu nome',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _zapCtrl,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d\s()+-]')),
          ],
          decoration: const InputDecoration(
            labelText: 'Seu WhatsApp com DDD',
            hintText: '(21) 99999-9999',
            prefixIcon: Icon(Icons.chat_outlined),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: AppTheme.danger, fontSize: 13)),
        ],
        const Spacer(),
        ElevatedButton(
          onPressed: _sending ? null : _request,
          child: _sending
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white),
                )
              : const Text('SOLICITAR 7 DIAS DE TESTE'),
        ),
      ],
    );
  }

  Widget _buildSent() {
    final number = _number!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        Center(child: _buildShield()),
        const SizedBox(height: 20),
        Text(
          'Pedido ${TrialService.displayNumber(number)} criado!',
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark),
        ),
        const SizedBox(height: 8),
        const Text(
          'Agora envie o pedido pelo WhatsApp para liberarmos '
          'seu teste. Assim que liberado, o app avisa sozinho.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
        ),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: _openWhatsapp,
          icon: const Icon(Icons.chat),
          label: const Text('ENVIAR PEDIDO PELO WHATSAPP'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF25D366),
            foregroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Sem o envio, não conseguimos liberar.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
        ),
      ],
    );
  }
}
