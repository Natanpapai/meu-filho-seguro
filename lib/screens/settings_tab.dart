import 'package:flutter/material.dart';
import '../app_deps.dart';
import '../models/models.dart';
import '../theme.dart';
import 'alarm_sound_screen.dart';
import 'places_screen.dart';
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
          icon: Icons.home_work_outlined,
          title: 'Locais: Casa e Escola',
          subtitle: 'Defina os endereços e o raio de cada local',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => PlacesScreen(deps: deps)),
          ),
        ),
        const SizedBox(height: 12),
        _MenuTile(
          icon: Icons.alarm,
          title: 'Som do alarme SOS',
          subtitle: 'Escolha o som que toca na emergência',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => const AlarmSoundScreen()),
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

class _MenuTile extends StatelessWidget {
  final IconData icon;
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
