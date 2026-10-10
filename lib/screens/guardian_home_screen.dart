import 'dart:io';
import 'package:flutter/material.dart';
import '../app_deps.dart';
import '../models/models.dart';
import '../theme.dart';
import 'add_child_screen.dart';
import 'map_tab.dart';
import 'history_tab.dart';
import 'settings_tab.dart';
import 'pairing_screen.dart';

/// Tela principal do responsável: filhos, status, mapa, histórico e ajustes.
class GuardianHomeScreen extends StatefulWidget {
  final AppDeps deps;
  const GuardianHomeScreen({super.key, required this.deps});

  @override
  State<GuardianHomeScreen> createState() => _GuardianHomeScreenState();
}

class _GuardianHomeScreenState extends State<GuardianHomeScreen> {
  int _tab = 0;

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final guardian = widget.deps.storage.getGuardian();
    final titles = ['Meus filhos', 'Mapa', 'Histórico', 'Ajustes'];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_tab]),
        actions: [
          if (_tab == 0)
            IconButton(
              tooltip: 'Vincular celular do filho',
              icon: const Icon(Icons.qr_code),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        PairingScreen(deps: widget.deps, mode: 'guardian'),
                  ),
                );
                _refresh();
              },
            ),
        ],
      ),
      body: switch (_tab) {
        0 => _HomeTab(deps: widget.deps, onChanged: _refresh),
        1 => MapTab(deps: widget.deps),
        2 => HistoryTab(deps: widget.deps),
        _ => SettingsTab(deps: widget.deps, guardian: guardian),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.family_restroom_outlined),
              selectedIcon: Icon(Icons.family_restroom),
              label: 'Filhos'),
          NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map),
              label: 'Mapa'),
          NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history),
              label: 'Histórico'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Ajustes'),
        ],
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  final AppDeps deps;
  final VoidCallback onChanged;
  const _HomeTab({required this.deps, required this.onChanged});

  static const _statusLabel = {
    'em_casa': 'Em casa',
    'na_escola': 'Na escola',
    'a_caminho': 'A caminho',
    'desconhecido': 'Sem dados',
  };

  static const _statusColor = {
    'em_casa': Color(0xFF2E7D32),
    'na_escola': Color(0xFF1565C0),
    'a_caminho': Color(0xFFEF6C00),
    'desconhecido': Color(0xFF9E9E9E),
  };

  @override
  Widget build(BuildContext context) {
    final children = deps.storage.getChildren();
    return RefreshIndicator(
      onRefresh: () async => onChanged(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (children.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    Icon(Icons.child_care,
                        size: 56,
                        color: AppTheme.primary.withValues(alpha: 0.5)),
                    const SizedBox(height: 12),
                    const Text(
                      'Nenhum filho cadastrado ainda',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Cadastre seu filho e vincule o celular dele para começar a acompanhar.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 13, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
            )
          else
            ...children.map((c) => _ChildCard(
                  child: c,
                  onTap: () {},
                  onDelete: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Remover filho?'),
                        content: Text(
                            'Remover ${c.name} da sua conta? O histórico será mantido.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancelar'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Remover',
                                style: TextStyle(color: AppTheme.danger)),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await deps.storage.removeChild(c.id);
                      onChanged();
                    }
                  },
                )),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final added = await Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => AddChildScreen(deps: deps)),
              );
              if (added == true) onChanged();
            },
            icon: const Icon(Icons.add),
            label: const Text('Cadastrar filho(a)'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChildCard extends StatelessWidget {
  final Child child;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ChildCard(
      {required this.child, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final color = _HomeTab._statusColor[child.status] ?? Colors.grey;
    final label = _HomeTab._statusLabel[child.status] ?? child.status;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                backgroundImage: child.photoPath != null
                    ? FileImage(File(child.photoPath!))
                    : null,
                child: child.photoPath == null
                    ? Text(
                        child.nickname.isNotEmpty
                            ? child.nickname[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary),
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      child.nickname.isNotEmpty
                          ? child.nickname
                          : child.name,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${child.name} • ${child.age} anos',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                    color: color, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                label,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: color),
                              ),
                            ],
                          ),
                        ),
                        if (!child.paired) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Não vinculado',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orange),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Atualizado ${AppTheme.timeAgo(child.lastUpdate)}'
                      '${child.batteryLevel != null ? ' • Bateria ${child.batteryLevel}%' : ''}',
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.more_vert, color: AppTheme.textMuted),
                onPressed: () => showModalBottomSheet(
                  context: context,
                  builder: (_) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.delete_outline,
                              color: AppTheme.danger),
                          title: const Text('Remover filho(a)',
                              style: TextStyle(color: AppTheme.danger)),
                          onTap: () {
                            Navigator.pop(context);
                            onDelete();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
