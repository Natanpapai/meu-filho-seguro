import 'package:flutter/material.dart';
import '../app_deps.dart';
import '../theme.dart';
import 'guardian_auth_screen.dart';
import 'pairing_screen.dart';

/// Tela inicial: quem está usando o app?
class WelcomeScreen extends StatelessWidget {
  final AppDeps deps;
  const WelcomeScreen({super.key, required this.deps});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(32),
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  size: 60,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Meu Filho Seguro',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Acompanhe a ida e a volta do seu filho à escola, com tranquilidade.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: AppTheme.textMuted),
              ),
              const Spacer(),
              _RoleButton(
                icon: Icons.family_restroom,
                title: 'Sou responsável',
                subtitle: 'Pai, mãe ou responsável',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GuardianAuthScreen(deps: deps),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _RoleButton(
                icon: Icons.backpack,
                title: 'Sou filho(a)',
                subtitle: 'Tenho um código de vinculação',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PairingScreen(deps: deps, mode: 'child'),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Nada aqui é rastreado em segredo: tudo funciona com permissão explícita.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _RoleButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppTheme.primary, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textDark,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                size: 18, color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }
}
