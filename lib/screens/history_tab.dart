import 'package:flutter/material.dart';
import '../app_deps.dart';
import '../theme.dart';

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
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history, size: 56, color: AppTheme.textMuted),
              SizedBox(height: 12),
              Text(
                'Nenhum evento ainda',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 6),
              Text(
                'Chegadas, saídas e alertas SOS aparecem aqui com data e hora.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: events.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final e = events[i];
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
