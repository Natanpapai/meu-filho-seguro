import 'package:flutter/material.dart';
import '../app_deps.dart';
import '../services/sos_alarm_service.dart';
import '../services/sync_service.dart';
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
  /// v15 — necessário para o teste nos DOIS aparelhos (busca o primeiro
  /// filho vinculado e os responsáveis). Pode ser nulo: nesse caso o
  /// botão de teste duplo mostra um aviso.
  final AppDeps? deps;
  const AlarmSoundScreen({super.key, this.deps});

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
                // v14 — teste de ponta a ponta: dispara o caminho COMPLETO
                // do SOS (tela de emergência + som + notificação) sem um
                // SOS real. Como testar: toque no botão e BLOQUEIE a tela
                // do celular em seguida — a tela vermelha deve aparecer por
                // cima do bloqueio, com o som tocando. Encerra com
                // "MARCAR COMO VISTO".
                // v15 — agora com 2 botões: "neste aparelho" (local) e
                // "nos DOIS aparelhos" (SOS de teste real no servidor).
                _TestAlertCard(deps: widget.deps),
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

/// Card de teste do alerta de emergência (v14 + v15).
///
/// - "Testar neste aparelho" (v14): dispara o caminho COMPLETO do SOS
///   (tela vermelha + som + notificação) só neste celular, sem precisar
///   de um SOS real. Para validar de verdade: toque e BLOQUEIE a tela —
///   a tela de emergência deve aparecer por cima do bloqueio.
/// - "Testar nos DOIS aparelhos" (v15): grava um SOS de TESTE de verdade
///   no servidor, endereçado aos DOIS responsáveis vinculados. Cada
///   aparelho dispara o caminho completo (tela vermelha com selo TESTE +
///   som + notificação). Encerra com "MARCAR COMO VISTO" (ack normal).
class _TestAlertCard extends StatefulWidget {
  final AppDeps? deps;
  const _TestAlertCard({this.deps});

  @override
  State<_TestAlertCard> createState() => _TestAlertCardState();
}

class _TestAlertCardState extends State<_TestAlertCard> {
  bool _testing = false;
  bool _testingBoth = false;

  /// Teste local (só neste aparelho), caminho nativo completo.
  Future<void> _test() async {
    setState(() => _testing = true);
    final ok = await SosAlarmService.testEmergencyAlert();
    if (!mounted) return;
    setState(() => _testing = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Não foi possível iniciar o teste. Tente com o app aberto.'),
        ),
      );
    }
    // Se iniciou, o alerta de teste aparece em segundos — o próprio
    // "MARCAR COMO VISTO" da tela de emergência encerra o teste.
  }

  /// Teste nos DOIS aparelhos: grava um SOS de TESTE real no Firestore
  /// para o primeiro filho vinculado, com guardianIds = os dois
  /// responsáveis. Cada aparelho dispara o caminho completo sozinho.
  Future<void> _testBoth() async {
    if (_testingBoth) return;
    setState(() => _testingBoth = true);
    try {
      final deps = widget.deps;
      if (deps == null) {
        _snack('Teste indisponível: abra por Ajustes > Som do alarme SOS.');
        return;
      }
      final children = deps.storage.getChildren();
      if (children.isEmpty) {
        _snack('Cadastre um filho primeiro para testar.');
        return;
      }
      final child = children.first;
      // Responsáveis vinculados a este filho (pai + mãe) + garante o
      // responsável atual na lista (cobre transição de IDs).
      final myId = deps.storage.getGuardian()?.id ?? '';
      var gids = await RemoteSync.fetchGuardianIds(child.id);
      if (myId.isNotEmpty && !gids.contains(myId)) {
        gids = [...gids, myId];
      }
      if (gids.isEmpty) {
        _snack('Nenhum responsável vinculado a este filho ainda.');
        return;
      }
      final rawName =
          child.nickname.isNotEmpty ? child.nickname : child.name;
      final ok = await RemoteSync.sendTestSosAlert(
        childId: child.id,
        childName: rawName.isNotEmpty ? rawName : 'Seu filho',
        guardianIds: gids,
      );
      if (!mounted) return;
      _snack(ok
          ? 'Alerta de TESTE enviado! Nos dois aparelhos: tela vermelha '
              'com selo TESTE + som. Encerre com "MARCAR COMO VISTO".'
          : 'Não foi possível enviar o teste. Verifique a internet.');
    } finally {
      if (mounted) setState(() => _testingBoth = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFCE4EC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFE57373),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.science_outlined,
                  color: Color(0xFFC62828), size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Testar alerta de emergência',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Dispara um alerta de TESTE (tela vermelha com selo TESTE + '
            'som). Para validar de verdade: toque no botão e BLOQUEIE a '
            'tela do celular em seguida — a tela de emergência deve '
            'aparecer por cima do bloqueio. Encerre com '
            '"MARCAR COMO VISTO".',
            style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC62828),
                foregroundColor: Colors.white,
              ),
              onPressed: _testing ? null : _test,
              icon: _testing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.smartphone, size: 18),
              label: Text(
                  _testing ? 'Iniciando...' : 'Testar neste aparelho'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFC62828),
                side: const BorderSide(color: Color(0xFFC62828)),
              ),
              onPressed: _testingBoth ? null : _testBoth,
              icon: _testingBoth
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.group, size: 18),
              label: Text(_testingBoth
                  ? 'Enviando...'
                  : 'Testar nos DOIS aparelhos'),
            ),
          ),
          const Text(
            'O teste duplo grava um SOS de TESTE no servidor para os 2 '
            'responsáveis — cada celular dispara sozinho o caminho '
            'completo.',
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }
}
