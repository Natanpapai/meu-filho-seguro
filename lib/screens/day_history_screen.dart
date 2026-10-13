import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../app_deps.dart';
import '../models/models.dart';
import '../models/safety_models.dart';
import '../services/firebase_service.dart';
import '../services/history_service.dart';
import '../services/trail_service.dart';
import '../theme.dart';
import '../widgets/footprints.dart';

/// Trajeto do dia: por onde o filho passou, com horários.
///
/// v14 — os passinhos ficam marcados de forma PERMANENTE:
/// - pontos do Firestore (amostrados pelo app do filho a cada ~2 min);
/// - pontos locais gravados neste aparelho pelo mapa do responsável
///   (a cada atualização de posição com movimento real).
/// Os dois são mesclados (sem duplicados) — o trajeto não some ao
/// recarregar o app, trocar de dia ou ficar sem internet.
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
  // v16: controle do mapa + ponto selecionado ao tocar num item do histórico.
  final MapController _mapController = MapController();
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    final children = widget.deps.storage.getChildren();
    if (children.isNotEmpty) _child = children.first;
    _load();
  }

  /// Coordenadas válidas para centralizar o mapa. (0,0) é o "Null Island"
  /// (meio do oceano) e indica registro sem posição real.
  bool _hasValidCoords(HistoryPoint p) {
    if (p.lat == 0 && p.lng == 0) return false;
    if (p.lat < -90 || p.lat > 90) return false;
    if (p.lng < -180 || p.lng > 180) return false;
    return true;
  }

  String _timeStr(DateTime? t) => t == null
      ? '--:--'
      : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// v16: tocar num horário centraliza o mapa naquele ponto, com marcador
  /// destacado mostrando o horário. Sem posição válida: avisa em vez de
  /// ficar mudo ou quebrar.
  void _onPointTap(int i) {
    final p = _points![i];
    if (!_hasValidCoords(p)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Este registro não tem posição salva — não dá para mostrar no mapa.'),
        ),
      );
      return;
    }
    _mapController.move(LatLng(p.lat, p.lng), 16);
    setState(() => _selectedIndex = i);
  }

  void _clearSelection() {
    setState(() => _selectedIndex = null);
  }

  /// Ponto selecionado de forma segura (nunca estoura índice).
  HistoryPoint? get _selectedPoint {
    final i = _selectedIndex;
    final pts = _points;
    if (i == null || pts == null || i < 0 || i >= pts.length) return null;
    final p = pts[i];
    return _hasValidCoords(p) ? p : null;
  }

  Future<void> _load() async {
    if (_child == null) return;
    setState(() {
      _loading = true;
      _points = null;
      _selectedIndex = null; // v16: limpa a seleção ao trocar de dia/filho
    });
    // v14: mescla os pontos do Firestore com os pontos locais gravados
    // neste aparelho (passinhos permanentes). O parse do timestamp do
    // Firestore foi corrigido (antes vinha sempre nulo e a lista ficava
    // vazia — o "histórico não marcava os passinhos").
    final remote =
        await HistoryService.pointsOfDay(_child!.id, _date);
    final local = TrailService.pointsOfDay(
        widget.deps.storage, _child!.id, _date);
    final merged = TrailService.merge(remote, local);
    if (mounted) {
      setState(() {
        _points = merged;
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
      appBar: AppBar(
        title: const Text('Trajeto do dia'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
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
                  // v16: Stack para a faixa do ponto selecionado sobre o mapa.
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
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
                          MarkerLayer(
                            markers: [
                              // Passinhos do trajeto (em vez da linha).
                              ...buildFootprintMarkers(
                                _points!
                                    .map((p) =>
                                        LatLng(p.lat, p.lng))
                                    .toList(),
                                color: AppTheme.primary,
                              ),
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
                              // v16: marcador destacado do ponto tocado no
                              // histórico, com o horário em cima.
                              if (_selectedPoint != null)
                                Marker(
                                  point: LatLng(_selectedPoint!.lat,
                                      _selectedPoint!.lng),
                                  width: 110,
                                  height: 64,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade800,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Colors.black26,
                                              blurRadius: 4,
                                              offset: Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Text(
                                          _timeStr(_selectedPoint!.timestamp),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      const Icon(
                                          Icons.location_on,
                                          color: Colors.orange,
                                          size: 34),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      // v16: faixa sobre o mapa com o horário selecionado
                      // e botão para limpar a seleção.
                      if (_selectedPoint != null)
                        Positioned(
                          top: 8,
                          left: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.72),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.push_pin,
                                    color: Colors.orange, size: 16),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Onde ele estava às ${_timeStr(_selectedPoint!.timestamp)}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: _clearSelection,
                                  child: const Icon(Icons.close,
                                      color: Colors.white70, size: 18),
                                ),
                              ],
                            ),
                          ),
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
                  Expanded(
                    child: Text(
                      '${_points!.length} pontos registrados • salvos neste aparelho',
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted),
                    ),
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
                  final timeStr = _timeStr(t);
                  // v16: cada horário é tocável — toca para ver no mapa
                  // onde o filho estava naquele momento.
                  final valid = _hasValidCoords(p);
                  final selected = _selectedIndex == i;
                  return Card(
                    margin: EdgeInsets.zero,
                    // v16: destaque visual no item selecionado.
                    shape: selected
                        ? RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(
                                color: Colors.orange, width: 2),
                          )
                        : null,
                    child: ListTile(
                      dense: true,
                      // v16: feedback visual de toque (ripple do ListTile).
                      onTap: () => _onPointTap(i),
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: (valid
                                  ? AppTheme.primary
                                  : Colors.grey)
                              .withValues(alpha: 0.12),
                          borderRadius:
                              BorderRadius.circular(10),
                        ),
                        child: Icon(
                            valid
                                ? Icons.location_on
                                : Icons.location_off_outlined,
                            color: valid
                                ? AppTheme.primary
                                : Colors.grey,
                            size: 20),
                      ),
                      title: Text(
                        timeStr,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        valid
                            ? '${p.lat.toStringAsFixed(5)}, ${p.lng.toStringAsFixed(5)}'
                                '${p.battery != null ? ' • Bateria ${p.battery}%' : ''}'
                            : 'Sem posição registrada',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: valid
                          ? const Icon(Icons.map_outlined,
                              color: AppTheme.primary, size: 20)
                          : null,
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
