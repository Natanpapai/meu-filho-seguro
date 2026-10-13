import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/trial_service.dart';
import '../theme.dart';
import 'owner_area_screen.dart';

/// Porta da área do dono: PIN de 4 dígitos.
///
/// O PIN está em `TrialService.ownerPin` (lib/services/trial_service.dart).
/// Para trocar: mude a constante e gere um novo APK.
class OwnerPinScreen extends StatefulWidget {
  const OwnerPinScreen({super.key});

  @override
  State<OwnerPinScreen> createState() => _OwnerPinScreenState();
}

class _OwnerPinScreenState extends State<OwnerPinScreen> {
  final _pinCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  void _tryOpen() {
    if (TrialService.instance.checkPin(_pinCtrl.text.trim())) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const OwnerAreaScreen()),
      );
    } else {
      setState(() => _error = 'PIN incorreto.');
      _pinCtrl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Área do dono')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              const Icon(Icons.admin_panel_settings_outlined,
                  size: 64, color: AppTheme.primary),
              const SizedBox(height: 16),
              const Text(
                'Digite o PIN de acesso',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _pinCtrl,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 32,
                    letterSpacing: 16,
                    fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  hintText: '••••',
                  counterText: '',
                ),
                onSubmitted: (_) => _tryOpen(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppTheme.danger, fontSize: 14)),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _tryOpen,
                child: const Text('ENTRAR'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
