import 'package:flutter/material.dart';
import '../app_deps.dart';
import '../theme.dart';
import 'day_history_screen.dart';

/// Aba Histórico: registro de chegadas, saídas e SOS.
class HistoryTab extends StatelessWidget {
  final AppDeps deps;
  const HistoryTab({super.key, required this.deps});

  IconData _iconFor(String type) {
    switch (type) {
      case 'chegou_escola':
        return Icons.school;
      case 'saiu_escola':
        return Icons.directions_walk;
      case 'chegou_casa':
        return Icons.home;
      case 'saiu_casa':
        return Icons.logout;
      case 'sos':
        return Icons.sos;
      default:
        return Icons.location_on;
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'sos':
        return AppTheme.danger;
      case 'chegou_escola':
      case 'chegou_casa':
        return Colors.green;
      default:
        return AppTheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = deps.storage.getEvents();
    if (events.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.history,
                  size: 56, color: AppTheme.textMuted),
              const SizedBox(height: 12),
              const Text(
                'Nenhum evento ainda',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                'Chegadas, saídas e alertas SOS aparecem aqui com data e hora.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 13, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.route_outlined),
                label: const Text('Ver trajeto do dia'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) =>
                            DayHistoryScreen(deps: deps)),
                  );
                },
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: events.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        if (i == 0) {
          // Atalho para o trajeto do dia (pontos amostrados no mapa).
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
                child: const Icon(Icons.route_outlined,
                    color: AppTheme.primary),
              ),
              title: const Text(
                'Trajeto do dia',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Por onde seu filho passou hoje, com horários e mapa.',
                style:
                    TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
              trailing: const Icon(Icons.arrow_forward_ios,
                  size: 16, color: AppTheme.textMuted),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) =>
                          DayHistoryScreen(deps: deps)),
                );
              },
            ),
          );
        }
        final e = events[i - 1];
        final color = _colorFor(e.type);
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_iconFor(e.type), color: color),
            ),
            title: Text(
              e.description,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: e.type == 'sos' ? AppTheme.danger : AppTheme.textDark,
              ),
            ),
            subtitle: Text(
              '${e.childName} • ${AppTheme.formatTime(e.timestamp)}',
              style:
                  const TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ),
        );
      },
    );
  }
}
