import 'package:flutter/material.dart';
import '../app_deps.dart';
import '../theme.dart';

/// Tela "Meus Dados": ver e editar os dados do perfil.
///
/// - Responsável: edita nome e telefone (o e-mail é somente leitura,
///   pois é a credencial de login). Salva localmente e sincroniza com
///   o Firestore (`guardians/{uid}`) quando houver login Firebase.
/// - Filho: edita nome e apelido (salvo localmente no aparelho).
class ProfileScreen extends StatefulWidget {
  final AppDeps deps;
  const ProfileScreen({super.key, required this.deps});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _nicknameController;
  bool _saving = false;
  String? _error;
  String? _success;

  bool get _isGuardian => widget.deps.storage.getRole() != 'child';

  @override
  void initState() {
    super.initState();
    if (_isGuardian) {
      final g = widget.deps.storage.getGuardian();
      _nameController = TextEditingController(text: g?.name ?? '');
      _phoneController = TextEditingController(text: g?.phone ?? '');
      _nicknameController = TextEditingController();
    } else {
      final children = widget.deps.storage.getChildren();
      final child = children.isNotEmpty ? children.first : null;
      _nameController = TextEditingController(text: child?.name ?? '');
      _phoneController = TextEditingController();
      _nicknameController =
          TextEditingController(text: child?.nickname ?? '');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    try {
      if (_isGuardian) {
        final result = await widget.deps.auth.updateGuardianProfile(
          name: _nameController.text,
          phone: _phoneController.text,
        );
        if (!mounted) return;
        if (result.$1) {
          setState(() => _success = 'Dados atualizados com sucesso!');
        } else {
          setState(() => _error = result.$2 ?? 'Não foi possível salvar.');
        }
      } else {
        final children = widget.deps.storage.getChildren();
        if (children.isEmpty) {
          setState(() => _error = 'Perfil não encontrado.');
          return;
        }
        final child = children.first;
        final updated = child.copyWith(
          name: _nameController.text.trim(),
          nickname: _nicknameController.text.trim(),
        );
        await widget.deps.storage.upsertChild(updated);
        if (!mounted) return;
        setState(() => _success = 'Dados atualizados com sucesso!');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Erro ao salvar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final guardian = _isGuardian ? widget.deps.storage.getGuardian() : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Meus Dados')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: AppTheme.primary,
                  child: Icon(
                    _isGuardian ? Icons.person : Icons.child_care,
                    color: Colors.white,
                    size: 44,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  _isGuardian ? 'Responsável' : 'Filho(a)',
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.textMuted),
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nome',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Informe o nome.' : null,
              ),
              const SizedBox(height: 16),
              if (_isGuardian) ...[
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Telefone',
                    prefixIcon: Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  initialValue: guardian?.email ?? '',
                  decoration: const InputDecoration(
                    labelText: 'E-mail (login)',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                  readOnly: true,
                  enabled: false,
                ),
                const SizedBox(height: 8),
                const Text(
                  'O e-mail não pode ser alterado porque é usado no login.',
                  style:
                      TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ] else ...[
                TextFormField(
                  controller: _nicknameController,
                  decoration: const InputDecoration(
                    labelText: 'Apelido',
                    prefixIcon: Icon(Icons.tag_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (_error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_error!,
                      style: const TextStyle(color: AppTheme.danger)),
                ),
              if (_success != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_success!,
                      style: const TextStyle(color: Colors.green)),
                ),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Salvar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
