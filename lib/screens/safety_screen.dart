import 'package:flutter/material.dart';
import '../app_deps.dart';
import '../models/models.dart';
import '../services/route_service.dart';
import '../theme.dart';
import 'route_screen.dart';
import 'school_mode_screen.dart';

/// Central de segurança: rota segura e modo escola por filho.
///
/// (Tela separada dos Ajustes para não conflitar com outras edições.)
class SafetyScreen extends StatefulWidget {
  final AppDeps deps;
  const SafetyScreen({super.key, required this.deps});

  @override
  State<SafetyScreen> createState() => _SafetyScreenState();
}

class _SafetyScreenState extends State<SafetyScreen> {
  @override
  Widget build(BuildContext context) {
    final children = widget.deps.storage.getChildren();
    final school = widget.deps.storage.getSchoolMode();
    return Scaffold(
      appBar: AppBar(title: const Text('Segurança')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Rota segura',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Desenhe o caminho esperado (casa → escola). Se seu filho sair da rota, você recebe um alerta.',
            style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 12),
          if (children.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Cadastre um filho primeiro para definir a rota.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            ...children.map((c) => _RouteTile(
                  deps: widget.deps,
                  child: c,
                  onChanged: () => setState(() {}),
                )),
          const SizedBox(height: 24),
          const Text(
            'Modo escola',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  school.enabled ? Icons.school : Icons.school_outlined,
                  color: AppTheme.primary,
                ),
              ),
              title: const Text('Modo escola',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                school.enabled
                    ? 'Ativo: ${school.scheduleLabel}'
                        '${school.isActiveNow() ? ' • EM AULA AGORA' : ''}'
                    : 'Desativado — toque para configurar',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: Switch(
                value: school.enabled,
                onChanged: (v) async {
                  await widget.deps.storage.setSchoolMode(
                      school.copyWith(enabled: v));
                  setState(() {});
                },
              ),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) =>
                          SchoolModeScreen(deps: widget.deps)),
                );
                setState(() {});
              },
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Pânico silencioso',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.volume_off_outlined,
                      color: AppTheme.textMuted),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No celular do seu filho há um botão discreto "Pedir ajuda sem chamar atenção": envia o SOS sem som nem confirmação no aparelho dele. Você recebe o alarme normalmente.',
                      style: TextStyle(fontSize: 13),
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

class _RouteTile extends StatefulWidget {
  final AppDeps deps;
  final Child child;
  final VoidCallback onChanged;
  const _RouteTile(
      {required this.deps, required this.child, required this.onChanged});

  @override
  State<_RouteTile> createState() => _RouteTileState();
}

class _RouteTileState extends State<_RouteTile> {
  int? _pointCount;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r =
        await RouteService.getRoute(widget.deps, widget.child.id);
    if (mounted) {
      setState(() {
        _pointCount = r?.points.length;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.child.nickname.isNotEmpty
        ? widget.child.nickname
        : widget.child.name;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: (_pointCount != null && _pointCount! >= 2
                    ? Colors.green
                    : AppTheme.textMuted)
                .withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.route_outlined,
            color: (_pointCount != null && _pointCount! >= 2)
                ? Colors.green.shade700
                : AppTheme.textMuted,
          ),
        ),
        title: Text(name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: _loading
            ? const Text('Carregando...',
                style: TextStyle(fontSize: 12))
            : Text(
                (_pointCount != null && _pointCount! >= 2)
                    ? 'Rota definida • $_pointCount pontos'
                    : 'Sem rota — toque para desenhar',
                style: const TextStyle(fontSize: 12),
              ),
        trailing: const Icon(Icons.arrow_forward_ios,
            size: 16, color: AppTheme.textMuted),
        onTap: () async {
          final changed = await Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => RouteScreen(
                    deps: widget.deps, child: widget.child)),
          );
          if (changed == true) {
            _load();
            widget.onChanged();
          }
        },
      ),
    );
  }
}
