import 'package:flutter/material.dart';
import '../services/sos_alarm_service.dart';
import '../theme.dart';

/// Tela de configuração do som do alarme SOS.
///
/// Lista os sons de alarme do sistema, permite ouvir cada um
/// (pré-visualização) e salvar o escolhido. O som salvo é usado
/// quando um SOS chega — mesmo com o celular no silencioso ou
/// em "Não perturbe", pois usa o canal de ALARME do Android.
///
/// CORREÇÕES:
/// - Mostra qual som está ativo no momento (lido de volta após salvar).
/// - Botão "Testar som atual": toca pelo caminho REAL do alarme
///   (o mesmo usado quando o SOS chega), para confirmar de ponta a ponta.
/// - Se nenhum som for encontrado no aparelho, avisa em vez de mostrar
///   lista vazia.
class AlarmSoundScreen extends StatefulWidget {
  const AlarmSoundScreen({super.key});

  @override
  State<AlarmSoundScreen> createState() => _AlarmSoundScreenState();
}

class _AlarmSoundScreenState extends State<AlarmSoundScreen> {
  List<AlarmSound> _sounds = [];
  String _selectedUri = '';
  String? _previewingUri;
  bool _loading = true;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sounds = await SosAlarmService.getAlarmSounds();
    final saved = await SosAlarmService.getSavedAlarmSound();
    if (!mounted) return;
    setState(() {
      _sounds = sounds;
      _selectedUri = saved;
      _loading = false;
    });
  }

  /// Nome do som correspondente ao URI (para mostrar o atual).
  String _nameOf(String uri) {
    if (uri.isEmpty) return 'Padrão do sistema';
    for (final s in _sounds) {
      if (s.uri == uri) return s.title;
    }
    return 'Som personalizado';
  }

  Future<void> _preview(String uri) async {
    setState(() => _previewingUri = uri.isEmpty ? '__default__' : uri);
    await SosAlarmService.previewSound(uri);
    // Para a pré-visualização após alguns segundos.
    await Future.delayed(const Duration(seconds: 4));
    if (!mounted) return;
    await SosAlarmService.stopAlarm();
    if (mounted) setState(() => _previewingUri = null);
  }

  Future<void> _save() async {
    await SosAlarmService.stopAlarm();
    await SosAlarmService.saveAlarmSound(_selectedUri);
    // Lê de volta para confirmar que persistiu.
    final saved = await SosAlarmService.getSavedAlarmSound();
    if (!mounted) return;
    setState(() => _selectedUri = saved);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Som do alarme salvo: ${_nameOf(saved)}')),
    );
    Navigator.of(context).pop();
  }

  /// Testa o som ATUALMENTE SALVO pelo caminho real do alarme.
  Future<void> _testSaved() async {
    if (_testing) return;
    setState(() => _testing = true);
    await SosAlarmService.testSavedSound(seconds: 3);
    if (mounted) setState(() => _testing = false);
  }

  @override
  void dispose() {
    SosAlarmService.stopAlarm();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Som do alarme SOS')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Escolha o som que vai tocar quando seu filho acionar o SOS. '
                        'Toque no alto-falante para ouvir.',
                        style: TextStyle(
                            fontSize: 13, color: AppTheme.textMuted),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Som atual: ${_nameOf(_selectedUri)}',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _testing ? null : _testSaved,
                            icon: _testing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.volume_up, size: 18),
                            label: Text(
                                _testing ? 'Tocando...' : 'Testar som atual'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_sounds.isEmpty)
                  const Expanded(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Nenhum som de alarme foi encontrado neste aparelho. '
                          'O alarme usará o som padrão do sistema.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 14, color: AppTheme.textMuted),
                        ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: RadioGroup<String>(
                      groupValue: _selectedUri,
                      onChanged: (v) =>
                          setState(() => _selectedUri = v ?? ''),
                      child: ListView.builder(
                        itemCount: _sounds.length + 1,
                        itemBuilder: (context, i) {
                          // Primeira opção: padrão do sistema.
                          final isDefault = i == 0;
                          final uri = isDefault ? '' : _sounds[i - 1].uri;
                          final title = isDefault
                              ? 'Padrão do sistema'
                              : _sounds[i - 1].title;
                          final previewKey =
                              uri.isEmpty ? '__default__' : uri;
                          final previewing = _previewingUri == previewKey;
                          return RadioListTile<String>(
                            value: uri,
                            title: Text(title,
                                style: const TextStyle(fontSize: 14)),
                            secondary: IconButton(
                              tooltip: 'Ouvir',
                              icon: Icon(
                                previewing
                                    ? Icons.stop_circle_outlined
                                    : Icons.play_circle_outline,
                                color: AppTheme.primary,
                              ),
                              onPressed: () => previewing
                                  ? SosAlarmService.stopAlarm().then((_) {
                                      if (mounted) {
                                        setState(
                                            () => _previewingUri = null);
                                      }
                                    })
                                  : _preview(uri),
                            ),
                            activeColor: AppTheme.primary,
                          );
                        },
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _save,
                      child: const Text('Salvar'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
