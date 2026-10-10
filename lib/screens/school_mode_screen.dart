import 'package:flutter/material.dart';
import '../app_deps.dart';
import '../models/safety_models.dart';
import '../theme.dart';

/// Configuração do Modo Escola.
///
/// Durante o horário escolar, o app suprime alertas de rotina
/// (chegou/saiu de casa/escola, desvio de rota), mas o SOS continua
/// funcionando normalmente.
class SchoolModeScreen extends StatefulWidget {
  final AppDeps deps;
  const SchoolModeScreen({super.key, required this.deps});

  @override
  State<SchoolModeScreen> createState() => _SchoolModeScreenState();
}

class _SchoolModeScreenState extends State<SchoolModeScreen> {
  late SchoolModeSettings _s;

  static const _dayNames = {
    1: 'Seg',
    2: 'Ter',
    3: 'Qua',
    4: 'Qui',
    5: 'Sex',
    6: 'Sáb',
    7: 'Dom',
  };

  @override
  void initState() {
    super.initState();
    _s = widget.deps.storage.getSchoolMode();
  }

  Future<void> _save(SchoolModeSettings s) async {
    setState(() => _s = s);
    await widget.deps.storage.setSchoolMode(s);
  }

  Future<void> _pickTime(bool isStart) async {
    final initial = TimeOfDay(
      hour: isStart ? _s.startHour : _s.endHour,
      minute: isStart ? _s.startMinute : _s.endMinute,
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked == null) return;
    if (isStart) {
      await _save(_s.copyWith(
          startHour: picked.hour, startMinute: picked.minute));
    } else {
      await _save(
          _s.copyWith(endHour: picked.hour, endMinute: picked.minute));
    }
  }

  String _fmt(int h, int m) =>
      '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Modo escola')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: SwitchListTile(
              title: const Text('Modo escola',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text(
                  'Suprime alertas de rotina no horário da aula. O SOS continua ativo.'),
              value: _s.enabled,
              onChanged: (v) => _save(_s.copyWith(enabled: v)),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Horário das aulas',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _s.enabled
                              ? () => _pickTime(true)
                              : null,
                          icon: const Icon(Icons.login),
                          label: Text(
                              'Entrada: ${_fmt(_s.startHour, _s.startMinute)}'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              _s.enabled ? () => _pickTime(false) : null,
                          icon: const Icon(Icons.logout),
                          label: Text(
                              'Saída: ${_fmt(_s.endHour, _s.endMinute)}'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Dias da semana',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final d in [1, 2, 3, 4, 5, 6, 7])
                        FilterChip(
                          label: Text(_dayNames[d]!),
                          selected: _s.days.contains(d),
                          onSelected: !_s.enabled
                              ? null
                              : (sel) {
                                  final days =
                                      List<int>.from(_s.days);
                                  if (sel) {
                                    days.add(d);
                                  } else {
                                    days.remove(d);
                                  }
                                  days.sort();
                                  _save(
                                      _s.copyWith(days: days));
                                },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_s.enabled)
            Card(
              color: AppTheme.primary.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      _s.isActiveNow()
                          ? Icons.school
                          : Icons.schedule,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _s.isActiveNow()
                            ? 'Modo escola ATIVO agora — só o SOS vai te alertar.'
                            : 'Modo escola configurado (${_s.scheduleLabel}). Fora desse horário, os alertas funcionam normalmente.',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
