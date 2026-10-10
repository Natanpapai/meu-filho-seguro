import 'package:flutter/material.dart';
import '../app_deps.dart';
import '../theme.dart';
import 'guardian_home_screen.dart';

/// Cadastro e login do responsável (conta local neste aparelho).
class GuardianAuthScreen extends StatefulWidget {
  final AppDeps deps;
  const GuardianAuthScreen({super.key, required this.deps});

  @override
  State<GuardianAuthScreen> createState() => _GuardianAuthScreenState();
}

class _GuardianAuthScreenState extends State<GuardianAuthScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit(bool isRegister) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = isRegister
        ? await widget.deps.auth.register(
            name: _name.text,
            email: _email.text,
            phone: _phone.text,
            password: _password.text,
          )
        : await widget.deps.auth.login(
            email: _email.text,
            password: _password.text,
          );
    setState(() => _loading = false);
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
      appBar: AppBar(
        title: const Text('Responsável'),
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [Tab(text: 'Entrar'), Tab(text: 'Cadastrar')],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildForm(isRegister: false),
          _buildForm(isRegister: true),
        ],
      ),
    );
  }

  Widget _buildForm({required bool isRegister}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            if (isRegister) ...[
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Nome completo',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) =>
                    (v == null || v.trim().length < 2) ? 'Informe seu nome' : null,
              ),
              const SizedBox(height: 14),
            ],
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'E-mail',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              validator: (v) => (v == null || !v.contains('@'))
                  ? 'Informe um e-mail válido'
                  : null,
            ),
            const SizedBox(height: 14),
            if (isRegister) ...[
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Telefone / WhatsApp',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                validator: (v) => (v == null || v.trim().length < 8)
                    ? 'Informe seu telefone'
                    : null,
              ),
              const SizedBox(height: 14),
            ],
            TextFormField(
              controller: _password,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Senha',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _obscurePassword
                      ? 'Mostrar senha'
                      : 'Ocultar senha',
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(
                      () => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (v) => (v == null || v.length < 4)
                  ? 'Senha com no mínimo 4 caracteres'
                  : null,
            ),
            const SizedBox(height: 8),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppTheme.danger, fontSize: 13),
                ),
              ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loading ? null : () => _submit(isRegister),
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(isRegister ? 'Criar conta' : 'Entrar'),
            ),
            const SizedBox(height: 16),
            const Text(
              'Versão inicial: a conta fica salva neste aparelho. '
              'Na próxima etapa, o login passa a funcionar nos dois celulares.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
