import 'package:flutter/material.dart';
import '../services/sos_alarm_service.dart';
import '../theme.dart';

/// Tela de configuração do som do alarme SOS.
///
/// Lista os sons de alarme do sistema, permite ouvir cada um
/// (pré-visualização) e salvar o escolhido. O som salvo é usado
/// quando um SOS chega — mesmo com o celular no silencioso ou
/// em "Não perturbe", pois usa o canal de ALARME do Android.
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Som do alarme salvo!')),
    );
    Navigator.of(context).pop();
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
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Escolha o som que vai tocar quando seu filho acionar o SOS. '
                    'Toque no alto-falante para ouvir.',
                    style:
                        TextStyle(fontSize: 13, color: AppTheme.textMuted),
                  ),
                ),
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
                      final previewKey = uri.isEmpty ? '__default__' : uri;
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
                                    setState(() => _previewingUri = null);
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
