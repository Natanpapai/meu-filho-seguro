import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_deps.dart';
import '../models/models.dart';
import '../theme.dart';
import 'child_home_screen.dart';

/// Vinculação segura entre os celulares.
///
/// Modo 'guardian': o responsável escolhe o filho e gera um código
/// de 6 dígitos (válido por 10 minutos).
/// Modo 'child': o filho digita o código no celular dele.
///
/// REAL: a validação do código funciona de verdade, inclusive entre
/// 2 aparelhos diferentes (via Firestore). Sem rede, vale neste aparelho.
class PairingScreen extends StatefulWidget {
  final AppDeps deps;
  final String mode; // 'guardian' | 'child'
  const PairingScreen({super.key, required this.deps, required this.mode});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  Child? _selectedChild;
  String? _code;
  DateTime? _expiry;
  Timer? _timer;
  int _secondsLeft = 0;
  final _codeController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _timer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_expiry == null) return;
      final left = _expiry!.difference(DateTime.now()).inSeconds;
      if (left <= 0) {
        setState(() {
          _code = null;
          _expiry = null;
          _secondsLeft = 0;
        });
        _timer?.cancel();
      } else {
        setState(() => _secondsLeft = left);
      }
    });
  }

  Future<void> _generate() async {
    if (_selectedChild == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final code =
          await widget.deps.auth.generatePairCode(_selectedChild!.id);
      setState(() {
        _code = code;
        _expiry = DateTime.now().add(const Duration(minutes: 10));
        _secondsLeft = 600;
      });
      _startCountdown();
    } catch (e) {
      setState(() => _error = 'Não foi possível gerar o código.');
    }
    setState(() => _busy = false);
  }

  Future<void> _submitCode() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'O código tem 6 dígitos.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.deps.auth.pairWithCode(code);
    setState(() => _busy = false);
    if (result.$1) {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
            builder: (_) => ChildHomeScreen(deps: widget.deps)),
        (_) => false,
      );
    } else {
      setState(() => _error = result.$2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isGuardian = widget.mode == 'guardian';
    return Scaffold(
      appBar: AppBar(
          title: Text(isGuardian ? 'Vincular celular' : 'Vincular meu celular')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: isGuardian ? _buildGuardian() : _buildChild(),
      ),
    );
  }

  Widget _buildGuardian() {
    final children = widget.deps.storage.getChildren();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Escolha o filho e gere um código. Digite esse código no celular dele para vincular.',
          style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
        ),
        const SizedBox(height: 16),
        if (children.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Cadastre um filho primeiro para gerar o código de vinculação.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          DropdownButtonFormField<Child>(
            initialValue: _selectedChild,
            decoration: const InputDecoration(
              labelText: 'Filho(a)',
              prefixIcon: Icon(Icons.child_care),
            ),
            items: children
                .map((c) => DropdownMenuItem(
                      value: c,
                      child: Text(c.name),
                    ))
                .toList(),
            onChanged: (c) => setState(() {
              _selectedChild = c;
              _code = null;
            }),
          ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: (_selectedChild == null || _busy) ? null : _generate,
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Gerar código'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!,
              style: const TextStyle(color: AppTheme.danger, fontSize: 13)),
        ],
        const SizedBox(height: 24),
        if (_code != null)
          Card(
            color: AppTheme.primary.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(
                    'Código para ${_selectedChild?.nickname ?? ''}',
                    style: const TextStyle(
                        fontSize: 14, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _code!,
                    style: const TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 8,
                      color: AppTheme.primaryDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Válido por ${_secondsLeft ~/ 60}:${(_secondsLeft % 60).toString().padLeft(2, '0')}',
                    style: const TextStyle(
                        fontSize: 13, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _code!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Código copiado')),
                      );
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copiar'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildChild() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Icon(Icons.link, size: 44, color: AppTheme.primary),
        ),
        const SizedBox(height: 20),
        const Text(
          'Digite o código',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textDark),
        ),
        const SizedBox(height: 8),
        const Text(
          'Peça para o responsável gerar um código de 6 dígitos no celular dele e digite aqui.',
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
              fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 10),
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
              style: const TextStyle(color: AppTheme.danger, fontSize: 13)),
        ],
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _busy ? null : _submitCode,
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Vincular'),
        ),
      ],
    );
  }
}
