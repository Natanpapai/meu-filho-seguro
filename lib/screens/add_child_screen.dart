import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../app_deps.dart';
import '../models/models.dart';
import '../theme.dart';

/// Cadastro do filho(a): nome, nascimento, apelido e foto opcional.
class AddChildScreen extends StatefulWidget {
  final AppDeps deps;
  const AddChildScreen({super.key, required this.deps});

  @override
  State<AddChildScreen> createState() => _AddChildScreenState();
}

class _AddChildScreenState extends State<AddChildScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _nickname = TextEditingController();
  DateTime? _birthDate;
  String? _photoPath;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      imageQuality: 80,
    );
    if (picked != null) {
      setState(() => _photoPath = picked.path);
    }
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 8, now.month, now.day),
      firstDate: DateTime(now.year - 18),
      lastDate: now,
      helpText: 'Data de nascimento',
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_birthDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe a data de nascimento')),
      );
      return;
    }
    setState(() => _saving = true);
    final child = Child.create(
      name: _name.text.trim(),
      nickname: _nickname.text.trim().isEmpty
          ? _name.text.trim().split(' ').first
          : _nickname.text.trim(),
      birthDate: _birthDate!,
      photoPath: _photoPath,
    );
    await widget.deps.storage.upsertChild(child);
    setState(() => _saving = false);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cadastrar filho(a)')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: GestureDetector(
                  onTap: _pickPhoto,
                  child: CircleAvatar(
                    radius: 52,
                    backgroundColor:
                        AppTheme.primary.withValues(alpha: 0.12),
                    backgroundImage: _photoPath != null
                        ? FileImage(File(_photoPath!))
                        : null,
                    child: _photoPath == null
                        ? const Icon(Icons.add_a_photo,
                            size: 32, color: AppTheme.primary)
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Center(
                child: Text(
                  'Foto (opcional) — toque para escolher',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Nome completo',
                  prefixIcon: Icon(Icons.child_care),
                ),
                validator: (v) => (v == null || v.trim().length < 2)
                    ? 'Informe o nome'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _nickname,
                decoration: const InputDecoration(
                  labelText: 'Apelido (opcional)',
                  prefixIcon: Icon(Icons.tag),
                ),
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: _pickBirthDate,
                borderRadius: BorderRadius.circular(14),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Data de nascimento',
                    prefixIcon: Icon(Icons.cake_outlined),
                  ),
                  child: Text(
                    _birthDate == null
                        ? 'Toque para escolher'
                        : '${_birthDate!.day.toString().padLeft(2, '0')}/'
                            '${_birthDate!.month.toString().padLeft(2, '0')}/'
                            '${_birthDate!.year}',
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
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
