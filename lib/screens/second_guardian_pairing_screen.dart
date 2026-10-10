import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_deps.dart';
import '../theme.dart';
import 'guardian_home_screen.dart';

/// Tela do 2º responsável (pai/mãe).
///
/// O outro responsável instala o app, toca em "Sou responsável", cria a
/// conta dele e chega aqui para digitar o código gerado pelo 1º
/// responsável. Ao vincular, os dois acompanham o MESMO filho e recebem
/// os alertas SOS.
class SecondGuardianPairingScreen extends StatefulWidget {
  final AppDeps deps;
  const SecondGuardianPairingScreen({super.key, required this.deps});

  @override
  State<SecondGuardianPairingScreen> createState() =>
      _SecondGuardianPairingScreenState();
}

class _SecondGuardianPairingScreenState
    extends State<SecondGuardianPairingScreen> {
  final _codeController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'O código tem 6 dígitos.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.deps.auth.pairGuardianWithCode(code);
    setState(() => _busy = false);
    if (result.$1) {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
            builder: (_) => GuardianHomeScreen(deps: widget.deps)),
        (_) => false,
      );
    } else {
      setState(() => _error = result.$2);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vincular como 2º responsável')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            Container(
              width: 90,
              height: 90,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.family_restroom,
                  size: 44, color: AppTheme.primary),
            ),
            const SizedBox(height: 20),
            const Text(
              'Digite o código do 1º responsável',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark),
            ),
            const SizedBox(height: 8),
            const Text(
              'Peça para o outro responsável gerar um código de 6 dígitos '
              'no celular dele (em "Vincular celular") e digite aqui. '
              'Você vai acompanhar o mesmo filho e receber os alertas SOS.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 10),
              decoration: const InputDecoration(
                hintText: '••••••',
                counterText: '',
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: AppTheme.danger, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Vincular'),
            ),
          ],
        ),
      ),
    );
  }
}
