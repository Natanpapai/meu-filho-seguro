import 'package:flutter/material.dart';
import '../services/sos_alarm_service.dart';
import '../services/system_permissions.dart';
import '../theme.dart';

/// Central de permissões do alerta (v15).
///
/// Para o alerta de emergência aparecer em TELA CHEIA mesmo com o
/// celular BLOQUEADO, estes 3 pontos precisam estar liberados NESTE
/// aparelho — e também no aparelho do OUTRO responsável. Cada cartão
/// mostra o status atual (LIBERADO verde / PENDENTE laranja), explica
/// em linguagem simples o porquê e abre direto a configuração do
/// sistema correspondente.
///
/// Os status são atualizados ao voltar das configurações
/// ([didChangeAppLifecycleState]).
class AlertPermissionsScreen extends StatefulWidget {
  const AlertPermissionsScreen({super.key});

  @override
  State<AlertPermissionsScreen> createState() =>
      _AlertPermissionsScreenState();
}

class _AlertPermissionsScreenState extends State<AlertPermissionsScreen>
    with WidgetsBindingObserver {
  bool? _batteryOk;
  bool? _fullScreenOk;
  bool? _overlayOk;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Atualiza os status quando o usuário volta das configurações do
  /// sistema (é lá que ele libera cada permissão).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkAll();
  }

  Future<void> _checkAll() async {
    final results = await Future.wait([
      SystemPermissions.isIgnoringBatteryOptimizations(),
      SosAlarmService.canUseFullScreenIntent(),
      SystemPermissions.canDrawOverlays(),
    ]);
    if (!mounted) return;
    setState(() {
      _batteryOk = results[0];
      _fullScreenOk = results[1];
      _overlayOk = results[2];
      _checking = false;
    });
  }

  /// Abre a configuração do sistema e re-verifica ao voltar.
  Future<void> _openAndRecheck(
      Future<bool> Function() openSettings) async {
    await openSettings();
    // Pequena pausa para o sistema aplicar a mudança antes de reler.
    await Future.delayed(const Duration(seconds: 1));
    _checkAll();
  }

  /// Quantas permissões estão liberadas (para o resumo no topo).
  int get _okCount =>
      [_batteryOk, _fullScreenOk, _overlayOk].where((ok) => ok == true).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Permissões do alerta SOS')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _checking
                          ? Icons.hourglass_empty
                          : (_okCount == 3
                              ? Icons.verified_user_outlined
                              : Icons.warning_amber_rounded),
                      color: _checking
                          ? AppTheme.textMuted
                          : (_okCount == 3
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFFEF6C00)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _checking
                            ? 'Verificando permissões...'
                            : (_okCount == 3
                                ? 'Tudo liberado neste aparelho ✅'
                                : '$_okCount de 3 permissões liberadas'),
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'O alerta de emergência precisa destas 3 liberações para '
                  'aparecer em tela cheia mesmo com o celular bloqueado. '
                  'Faça o mesmo no celular do OUTRO responsável — cada '
                  'aparelho tem suas próprias permissões.',
                  style:
                      TextStyle(fontSize: 13, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _PermissionCard(
            icon: Icons.battery_saver_outlined,
            title: 'Ignorar otimização de bateria',
            why: 'Se o celular economizar a bateria do app, ele pode '
                'DESLIGAR o monitoramento em 2º plano — aí os passinhos do '
                'trajeto ficam com buracos e o alerta SOS pode nem chegar.',
            ok: _batteryOk,
            onOpen: () => _openAndRecheck(
                SystemPermissions.openBatteryOptimizationSettings),
          ),
          const SizedBox(height: 12),
          _PermissionCard(
            icon: Icons.fullscreen,
            title: 'Alertas em tela cheia',
            why: 'Sem isso (obrigatório no Android 14+), com a tela '
                'bloqueada o SOS toca SÓ o som — a tela vermelha de '
                'emergência não aparece por cima do bloqueio.',
            ok: _fullScreenOk,
            onOpen: () => _openAndRecheck(
                () async {
                  await SosAlarmService.openFullScreenIntentSettings();
                  return true;
                }),
          ),
          const SizedBox(height: 12),
          _PermissionCard(
            icon: Icons.layers_outlined,
            title: 'Aparecer por cima de outros apps',
            why: 'Camada extra de segurança: se a tela cheia falhar no seu '
                'aparelho, o alerta mostra um painel vermelho por cima de '
                'tudo mesmo assim.',
            ok: _overlayOk,
            onOpen: () => _openAndRecheck(
                SystemPermissions.openOverlaySettings),
          ),
          const SizedBox(height: 16),
          const Text(
            'Dica: depois de liberar, use o botão "Testar nos DOIS '
            'aparelhos" na tela "Som do alarme SOS" para confirmar que o '
            'alerta aparece com a tela bloqueada nos dois celulares.',
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Cartão de uma permissão: status (LIBERADO / PENDENTE), explicação
/// simples do porquê e botão que abre a configuração do sistema.
class _PermissionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String why;
  final bool? ok;
  final VoidCallback onOpen;

  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.why,
    required this.ok,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final granted = ok ?? false;
    final checking = ok == null;
    final statusColor =
        granted ? const Color(0xFF2E7D32) : const Color(0xFFEF6C00);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: checking ? Colors.grey.shade300 : statusColor,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: statusColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: (checking
                            ? Colors.grey
                            : statusColor)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        checking
                            ? Icons.hourglass_empty
                            : (granted
                                ? Icons.check_circle
                                : Icons.warning_amber_rounded),
                        size: 15,
                        color:
                            checking ? Colors.grey : statusColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        checking
                            ? '...'
                            : (granted ? 'LIBERADO' : 'PENDENTE'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                          color:
                              checking ? Colors.grey : statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              why,
              style:
                  const TextStyle(fontSize: 13, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: Text(granted
                    ? 'Revisar nas configurações'
                    : 'Liberar nas configurações'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: statusColor,
                  side: BorderSide(color: statusColor),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
