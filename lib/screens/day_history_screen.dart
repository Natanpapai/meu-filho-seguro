import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../app_deps.dart';
import '../models/models.dart';
import '../models/safety_models.dart';
import '../services/firebase_service.dart';
import '../services/history_service.dart';
import '../theme.dart';

/// Trajeto do dia: por onde o filho passou, com horários.
///
/// Usa os pontos amostrados a cada ~2 min em `history/{childId}/points`.
/// Sem Firebase/rede, mostra os eventos locais do dia como alternativa.
class DayHistoryScreen extends StatefulWidget {
  final AppDeps deps;
  const DayHistoryScreen({super.key, required this.deps});

  @override
  State<DayHistoryScreen> createState() => _DayHistoryScreenState();
}

class _DayHistoryScreenState extends State<DayHistoryScreen> {
  Child? _child;
  DateTime _date = DateTime.now();
  List<HistoryPoint>? _points;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final children = widget.deps.storage.getChildren();
    if (children.isNotEmpty) _child = children.first;
    _load();
  }

  Future<void> _load() async {
    if (_child == null) return;
    setState(() {
      _loading = true;
      _points = null;
    });
    final pts =
        await HistoryService.pointsOfDay(_child!.id, _date);
    if (mounted) {
      setState(() {
        _points = pts;
        _loading = false;
      });
    }
  }

  bool get _isToday {
    final n = DateTime.now();
    return _date.year == n.year &&
        _date.month == n.month &&
        _date.day == n.day;
  }

  String _dateLabel() {
    if (_isToday) return 'Hoje';
    final y = _date.subtract(const Duration(days: 1));
    if (_date.year == y.year &&
        _date.month == y.month &&
        _date.day == y.day) {
      return 'Ontem';
    }
    return '${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final children = widget.deps.storage.getChildren();
    return Scaffold(
      appBar: AppBar(title: const Text('Trajeto do dia')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: children.isEmpty
                      ? const Text('Nenhum filho cadastrado.')
                      : DropdownButtonFormField<Child>(
                          initialValue: _child,
                          decoration: const InputDecoration(
                            labelText: 'Filho(a)',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                          ),
                          items: children
                              .map((c) => DropdownMenuItem(
                                    value: c,
                                    child: Text(c.nickname.isNotEmpty
                                        ? c.nickname
                                        : c.name),
                                  ))
                              .toList(),
                          onChanged: (c) {
                            setState(() => _child = c);
                            _load();
                          },
                        ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Dia anterior',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {
                    setState(() => _date =
                        _date.subtract(const Duration(days: 1)));
                    _load();
                  },
                ),
                Text(_dateLabel(),
                    style: const TextStyle(
                        fontWeight: FontWeight.w600)),
                IconButton(
                  tooltip: 'Próximo dia',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _isToday
                      ? null
                      : () {
                          setState(() => _date =
                              _date.add(const Duration(days: 1)));
                          _load();
                        },
                ),
              ],
            ),
          ),
          if (_loading)
            const Expanded(
                child:
                    Center(child: CircularProgressIndicator()))
          else if (_points == null || _points!.isEmpty)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.route_outlined,
                          size: 56, color: AppTheme.textMuted),
                      const SizedBox(height: 12),
                      const Text(
                        'Sem pontos neste dia',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        FirebaseService.available
                            ? 'Os pontos aparecem aqui quando o app do seu filho compartilha a localização.'
                            : 'Sem conexão — o trajeto precisa de internet.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else ...[
            SizedBox(
              height: 220,
              child: Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(
                          _points!.last.lat, _points!.last.lng),
                      initialZoom: 14,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName:
                            'com.meufilhoseguro.app',
                      ),
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _points!
                                .map((p) =>
                                    LatLng(p.lat, p.lng))
                                .toList(),
                            color: AppTheme.primary,
                            strokeWidth: 4,
                          ),
                        ],
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(_points!.first.lat,
                                _points!.first.lng),
                            width: 30,
                            height: 30,
                            child: const Icon(
                                Icons.play_circle_filled,
                                color: Colors.green,
                                size: 28),
                          ),
                          Marker(
                            point: LatLng(_points!.last.lat,
                                _points!.last.lng),
                            width: 30,
                            height: 30,
                            child: const Icon(
                                Icons.location_on,
                                color: AppTheme.danger,
                                size: 30),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 16, color: AppTheme.textMuted),
                  const SizedBox(width: 6),
                  Text(
                    '${_points!.length} pontos registrados',
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding:
                    const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: _points!.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final p = _points![i];
                  final t = p.timestamp;
                  final timeStr = t == null
                      ? '--:--'
                      : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                  return Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      dense: true,
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.primary
                              .withValues(alpha: 0.12),
                          borderRadius:
                              BorderRadius.circular(10),
                        ),
                        child: const Icon(
                            Icons.location_on,
                            color: AppTheme.primary,
                            size: 20),
                      ),
                      title: Text(
                        timeStr,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${p.lat.toStringAsFixed(5)}, ${p.lng.toStringAsFixed(5)}'
                        '${p.battery != null ? ' • Bateria ${p.battery}%' : ''}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
