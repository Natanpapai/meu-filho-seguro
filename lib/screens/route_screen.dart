import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../app_deps.dart';
import '../models/models.dart';
import '../models/safety_models.dart';
import '../services/route_service.dart';
import '../theme.dart';

/// Tela para o responsável definir a rota segura do filho
/// (ex.: caminho casa -> escola).
///
/// Toca no mapa para adicionar pontos de passagem. Se o filho se
/// afastar mais de 200m da linha, o responsável recebe um alerta.
class RouteScreen extends StatefulWidget {
  final AppDeps deps;
  final Child child;
  const RouteScreen({super.key, required this.deps, required this.child});

  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> {
  final List<LatLng> _points = [];
  bool _loading = true;
  bool _saving = false;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final route =
        await RouteService.getRoute(widget.deps, widget.child.id);
    if (mounted) {
      setState(() {
        if (route != null) {
          _points.addAll(
              route.points.map((p) => LatLng(p.lat, p.lng)));
        }
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_points.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Toque no mapa para marcar pelo menos 2 pontos da rota.')),
      );
      return;
    }
    setState(() => _saving = true);
    final route = SafeRoute(
      childId: widget.child.id,
      label:
          'Rota de ${widget.child.nickname.isNotEmpty ? widget.child.nickname : widget.child.name}',
      points:
          _points.map((p) => RoutePoint(p.latitude, p.longitude)).toList(),
      updatedAt: DateTime.now(),
    );
    await RouteService.saveRoute(widget.deps, route);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text(
              'Rota salva! Você será avisado se seu filho sair dela.')),
    );
    Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Apagar rota?'),
        content: const Text(
            'O monitoramento de desvio de rota será desativado.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apagar',
                style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await RouteService.deleteRoute(widget.deps, widget.child.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.child.nickname.isNotEmpty
        ? widget.child.nickname
        : widget.child.name;
    LatLng center = const LatLng(-22.9068, -43.1729);
    if (_points.isNotEmpty) {
      center = _points.first;
    } else if (widget.child.lastLat != null &&
        widget.child.lastLng != null) {
      center = LatLng(widget.child.lastLat!, widget.child.lastLng!);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('Rota segura — $name'),
        actions: [
          if (_points.isNotEmpty)
            IconButton(
              tooltip: 'Apagar rota',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: 14,
                    onTap: (_, p) =>
                        setState(() => _points.add(p)),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName:
                          'com.meufilhoseguro.app',
                    ),
                    if (_points.length >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _points,
                            color: AppTheme.primary,
                            strokeWidth: 5,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        for (int i = 0; i < _points.length; i++)
                          Marker(
                            point: _points[i],
                            width: 36,
                            height: 36,
                            child: Container(
                              decoration: BoxDecoration(
                                color: i == 0
                                    ? Colors.green
                                    : (i == _points.length - 1
                                        ? AppTheme.danger
                                        : AppTheme.primary),
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.white, width: 2),
                              ),
                              child: Center(
                                child: Text(
                                  '${i + 1}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  top: 12,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _points.isEmpty
                            ? 'Toque no mapa para marcar os pontos do caminho (casa → escola).'
                            : '${_points.length} pontos marcados. Toque para adicionar mais.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_points.isNotEmpty)
                        Padding(
                          padding:
                              const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => setState(
                                      () => _points.removeLast()),
                                  icon: const Icon(Icons.undo),
                                  label:
                                      const Text('Desfazer'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      setState(() => _points.clear()),
                                  icon: const Icon(Icons.clear_all),
                                  label: const Text('Limpar'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ElevatedButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white))
                            : const Icon(Icons.check),
                        label: const Text('Salvar rota'),
                        style: ElevatedButton.styleFrom(
                          minimumSize:
                              const Size(double.infinity, 52),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
