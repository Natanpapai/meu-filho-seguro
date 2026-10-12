import 'package:flutter/material.dart';
import '../app_deps.dart';
import '../models/models.dart';
import '../services/sos_alarm_service.dart';
import '../services/system_permissions.dart';
import '../theme.dart';
import 'alarm_sound_screen.dart';
import 'alert_permissions_screen.dart';
import 'places_screen.dart';
import 'profile_screen.dart';
import 'welcome_screen.dart';

/// Aba Ajustes: perfil, locais, som do alarme e saída.
class SettingsTab extends StatelessWidget {
  final AppDeps deps;
  final Guardian? guardian;
  const SettingsTab({super.key, required this.deps, required this.guardian});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 28,
                  backgroundColor: AppTheme.primary,
                  child:
                      Icon(Icons.person, color: Colors.white, size: 32),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        guardian?.name ?? 'Responsável',
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        guardian?.email ?? '',
                        style: const TextStyle(
                            fontSize: 13, color: AppTheme.textMuted),
                      ),
                      if ((guardian?.phone ?? '').isNotEmpty)
                        Text(
                          guardian!.phone,
                          style: const TextStyle(
                              fontSize: 13, color: AppTheme.textMuted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _MenuTile(
          icon: Icons.person_outline,
          title: 'Meus Dados',
          subtitle: 'Ver e editar nome e telefone',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => ProfileScreen(deps: deps)),
          ),
        ),
        const SizedBox(height: 12),
        _MenuTile(
          icon: Icons.home_work_outlined,
          title: 'Locais: Casa e Escola',
          subtitle: 'Defina os endereços e o raio de cada local',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => PlacesScreen(deps: deps)),
          ),
        ),
        const SizedBox(height: 12),
        // v15 — Central de permissões do alerta: as 3 liberações que fazem
        // o SOS aparecer em tela cheia com o celular bloqueado (bateria,
        // tela cheia e overlay). Mostra quantas estão liberadas.
        _AlertPermissionsTile(deps: deps),
        const SizedBox(height: 12),
        _MenuTile(
          icon: Icons.alarm,
          title: 'Som do alarme SOS',
          subtitle: 'Escolha o som que toca na emergência',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => AlarmSoundScreen(deps: deps)),
          ),
        ),
        const SizedBox(height: 12),
        // NOTA (versão de teste do proprietário): todas as funções estão
        // 100% liberadas nesta versão — nenhum bloqueio ou paywall.
        // O card do Premium só aparece na versão comercial futura.
        _MenuTile(
          icon: Icons.privacy_tip_outlined,
          title: 'Privacidade',
          subtitle: 'Como seus dados são tratados',
          onTap: () => showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Privacidade'),
              content: const Text(
                '• A localização do seu filho só é compartilhada com você, '
                'e apenas com permissão explícita no celular dele.\n\n'
                '• Nada é rastreado em segredo.\n\n'
                '• Nesta versão inicial, os dados ficam salvos apenas '
                'neste aparelho. Com o servidor conectado, os dados trafegam '
                'de forma criptografada e nunca são vendidos.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Entendi'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: () async {
            await deps.auth.logout();
            if (!context.mounted) return;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                  builder: (_) => WelcomeScreen(deps: deps)),
              (_) => false,
            );
          },
          icon: const Icon(Icons.logout, color: AppTheme.danger),
          label: const Text('Sair da conta',
              style: TextStyle(color: AppTheme.danger)),
        ),
        const SizedBox(height: 8),
        const Center(
          child: Text(
            'Meu Filho Seguro • versão 0.1.0 (protótipo)',
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
        ),
      ],
    );
  }
}

class _MenuTile extends StatelessWidget {  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppTheme.primary),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style:
                const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
        trailing: const Icon(Icons.arrow_forward_ios,
            size: 16, color: AppTheme.textMuted),
        onTap: onTap,
      ),
    );
  }
}

/// Atalho para a Central de permissões do alerta (v15), com resumo ao
/// vivo de quantas das 3 liberações estão ativas neste aparelho.
/// Ao voltar da Central, re-verifica os status.
class _AlertPermissionsTile extends StatefulWidget {
  final AppDeps deps;
  const _AlertPermissionsTile({required this.deps});

  @override
  State<_AlertPermissionsTile> createState() => _AlertPermissionsTileState();
}

class _AlertPermissionsTileState extends State<_AlertPermissionsTile> {
  int? _okCount;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final results = await Future.wait([
      SystemPermissions.isIgnoringBatteryOptimizations(),
      SosAlarmService.canUseFullScreenIntent(),
      SystemPermissions.canDrawOverlays(),
    ]);
    if (mounted) {
      setState(() => _okCount = results.where((ok) => ok).length);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _okCount;
    final allOk = count == 3;
    return _MenuTile(
      icon: allOk ? Icons.verified_user_outlined : Icons.security_outlined,
      title: 'Permissões do alerta SOS',
      subtitle: count == null
          ? 'Verificando liberações...'
          : (allOk
              ? 'Tudo liberado neste aparelho ✅'
              : '$count de 3 liberações ativas — toque para corrigir'),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => const AlertPermissionsScreen()),
        );
        // Re-verifica ao voltar da Central.
        _check();
      },
    );
  }
}
