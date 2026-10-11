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
  bool? _fullScreenGranted;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sounds = await SosAlarmService.getAlarmSounds();
    final saved = await SosAlarmService.getSavedAlarmSound();
    final fullScreen = await SosAlarmService.canUseFullScreenIntent();
    if (!mounted) return;
    setState(() {
      _sounds = sounds;
      _selectedUri = saved;
      _fullScreenGranted = fullScreen;
      _loading = false;
    });
  }

  /// Re-verifica a permissão ao voltar das configurações do sistema.
  Future<void> _openFullScreenSettings() async {
    await SosAlarmService.openFullScreenIntentSettings();
    await Future.delayed(const Duration(seconds: 1));
    final fullScreen = await SosAlarmService.canUseFullScreenIntent();
    if (mounted) setState(() => _fullScreenGranted = fullScreen);
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
    await SosAlarmService.stopPreview();
    if (mounted) setState(() => _previewingUri = null);
  }

  Future<void> _save() async {
    await SosAlarmService.stopPreview();
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
    SosAlarmService.stopPreview();
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
                // Permissão de tela cheia: sem ela (Android 14+), a tela
                // de emergência estilo Defesa Civil não abre por cima da
                // tela bloqueada — o usuário precisa liberar no sistema.
                Container(
                  width: double.infinity,
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: (_fullScreenGranted ?? true)
                        ? AppTheme.primary.withValues(alpha: 0.1)
                        : const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (_fullScreenGranted ?? true)
                          ? AppTheme.primary.withValues(alpha: 0.3)
                          : const Color(0xFFFFB74D),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            (_fullScreenGranted ?? true)
                                ? Icons.check_circle_outline
                                : Icons.warning_amber_rounded,
                            color: (_fullScreenGranted ?? true)
                                ? AppTheme.primary
                                : const Color(0xFFEF6C00),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Tela cheia de emergência',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        (_fullScreenGranted ?? true)
                            ? 'Liberado: o alerta SOS abre em tela cheia mesmo com o celular bloqueado.'
                            : 'BLOQUEADO pelo sistema: o alerta SOS não vai abrir em tela cheia. Toque abaixo para liberar nas configurações do celular.',
                        style: const TextStyle(
                            fontSize: 13, color: AppTheme.textMuted),
                      ),
                      if (!(_fullScreenGranted ?? true)) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _openFullScreenSettings,
                            icon: const Icon(Icons.settings_outlined,
                                size: 18),
                            label: const Text(
                                'Liberar nas configurações'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
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
                                  ? SosAlarmService.stopPreview().then((_) {
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
