import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../app_deps.dart';
import '../models/models.dart';
import '../services/firebase_service.dart';
import '../services/sync_service.dart';
import '../theme.dart';

/// Posição remota vinda do Firestore (celular do filho).
class _RemoteLoc {
  final double lat;
  final double lng;
  final DateTime? updatedAt;
  final double? speed;
  final double? heading;
  _RemoteLoc(this.lat, this.lng, this.updatedAt, {this.speed, this.heading});
}

/// Interpolação linear entre dois pontos geográficos.
class _LatLngTween extends Tween<LatLng> {
  _LatLngTween({required super.begin, required super.end});

  @override
  LatLng lerp(double t) {
    final b = begin as LatLng;
    final e = end as LatLng;
    return LatLng(
      b.latitude + (e.latitude - b.latitude) * t,
      b.longitude + (e.longitude - b.longitude) * t,
    );
  }
}

/// Dados de posição resolvidos para um filho.
class _Positioned {
  final Child child;
  final double lat;
  final double lng;
  final DateTime? updatedAt;
  final double? speed;
  final double? heading;
  _Positioned({
    required this.child,
    required this.lat,
    required this.lng,
    this.updatedAt,
    this.speed,
    this.heading,
  });
}

/// Aba Mapa: mostra filhos e locais seguros no mapa.
/// Mapa via OpenStreetMap (sem necessidade de chave de API).
///
/// A posição dos filhos é mesclada em tempo real: os dados locais
/// são combinados com a localização enviada pelo celular do filho
/// via Firestore (a mais recente prevalece). O marcador desliza
/// suavemente até a nova posição (estilo Uber) e o trajeto recente
/// aparece como linha no mapa.
class MapTab extends StatefulWidget {
  final AppDeps deps;
  const MapTab({super.key, required this.deps});

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> with TickerProviderStateMixin {
  /// Trajeto recente de cada filho (últimos pontos recebidos).
  final Map<String, List<LatLng>> _trails = {};

  /// Animação de deslizamento do marcador de cada filho.
  final Map<String, AnimationController> _ctrls = {};
  final Map<String, Animation<LatLng>> _anims = {};

  /// Listenable mesclado (cache): recriar o merge a cada snapshot
  /// fazia o AnimatedBuilder recancelar e reassinar — churn desnecessário.
  Listenable? _merged;
  int _mergedSize = -1;

  Listenable _mergedAnimation() {
    if (_merged == null || _mergedSize != _ctrls.length) {
      _merged = Listenable.merge(_ctrls.values.toList());
      _mergedSize = _ctrls.length;
    }
    return _merged!;
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _appendTrail(String childId, LatLng p) {
    final trail = _trails.putIfAbsent(childId, () => []);
    if (trail.isNotEmpty) {
      final last = trail.last;
      // Ignora pontos praticamente idênticos (menos de ~5 metros).
      const dist = Distance();
      if (dist(last, p) < 5) return;
    }
    trail.add(p);
    // Mantém só os últimos 60 pontos do trajeto.
    if (trail.length > 60) trail.removeAt(0);
  }

  /// Move suavemente o marcador do filho até o novo ponto.
  ///
  /// OTIMIZAÇÃO: só reinicia a animação se o alvo mudou mais de 5 metros.
  /// Sem isso, o jitter do GPS (pequenas variações a cada update de 5s)
  /// reiniciava a animação de 1,2s sem parar, reconstruindo o mapa
  /// inteiro a 60fps — principal causa da lentidão percebida.
  void _retarget(String childId, LatLng target) {
    final ctrl = _ctrls.putIfAbsent(
      childId,
      () => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 800),
      ),
    );
    final from = _anims[childId]?.value ?? target;
    if (from == target) return;
    // Ignora micro-movimentos (jitter do GPS).
    const dist = Distance();
    if (dist(from, target) < 5) return;
    _anims[childId] = _LatLngTween(begin: from, end: target).animate(
      CurvedAnimation(parent: ctrl, curve: Curves.easeInOut),
    );
    ctrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final children = widget.deps.storage.getChildren();
    final ids = children.map((c) => c.id).toList();
    if (!FirebaseService.available || ids.isEmpty) {
      return _buildMap(children, const {});
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: RemoteSync.locationsStream(ids),
      builder: (context, snap) {
        final remote = <String, _RemoteLoc>{};
        for (final d in snap.data?.docs ?? const []) {
          final m = d.data();
          final lat = (m['lat'] as num?)?.toDouble();
          final lng = (m['lng'] as num?)?.toDouble();
          if (lat == null || lng == null) continue;
          final ts = m['updatedAt'];
          remote[d.id] = _RemoteLoc(
            lat,
            lng,
            ts is Timestamp ? ts.toDate() : null,
            speed: (m['speed'] as num?)?.toDouble(),
            heading: (m['heading'] as num?)?.toDouble(),
          );
          _appendTrail(d.id, LatLng(lat, lng));
        }
        final positioned = _resolveAll(children, remote);
        for (final p in positioned) {
          _retarget(p.child.id, LatLng(p.lat, p.lng));
        }
        // Reconstrói os marcadores a cada frame da animação de deslizamento.
        return AnimatedBuilder(
          animation: _mergedAnimation(),
          builder: (context, _) => _buildMap(children, remote, positioned),
        );
      },
    );
  }

  /// Resolve a melhor posição conhecida de cada filho:
  /// a remota (Firestore) prevalece quando é mais recente que a local.
  List<_Positioned> _resolveAll(
      List<Child> children, Map<String, _RemoteLoc> remote) {
    final out = <_Positioned>[];
    for (final c in children) {
      final r = remote[c.id];
      if (r != null &&
          (c.lastLat == null ||
              (r.updatedAt != null &&
                  (c.lastUpdate == null ||
                      r.updatedAt!.isAfter(c.lastUpdate!))))) {
        out.add(_Positioned(
          child: c,
          lat: r.lat,
          lng: r.lng,
          updatedAt: r.updatedAt,
          speed: r.speed,
          heading: r.heading,
        ));
        continue;
      }
      if (c.lastLat != null && c.lastLng != null) {
        out.add(_Positioned(
          child: c,
          lat: c.lastLat!,
          lng: c.lastLng!,
          updatedAt: c.lastUpdate,
        ));
      }
    }
    return out;
  }

  Widget _buildMap(List<Child> children, Map<String, _RemoteLoc> remote,
      [List<_Positioned>? positionedOverride]) {
    final places = widget.deps.storage.getPlaces();

    final positioned = positionedOverride ?? _resolveAll(children, remote);

    LatLng center = const LatLng(-22.9068, -43.1729); // Rio de Janeiro
    if (positioned.isNotEmpty) {
      center = LatLng(positioned.first.lat, positioned.first.lng);
    } else if (places.isNotEmpty) {
      center = LatLng(places.first.lat, places.first.lng);
    }

    final markers = <Marker>[];
    for (final p in positioned) {
      final name =
          p.child.nickname.isNotEmpty ? p.child.nickname : p.child.name;
      // Velocidade acima de ~2 km/h = em movimento.
      final moving = (p.speed ?? 0) > 0.6;
      // Posição animada (desliza suavemente); cai para a posição atual
      // se ainda não há animação para este filho.
      final point = _anims[p.child.id]?.value ?? LatLng(p.lat, p.lng);
      markers.add(
        Marker(
          point: point,
          width: 130,
          height: 84,
          child: Column(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: moving ? Colors.green.shade700 : AppTheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                    Text(
                      AppTheme.timeAgo(p.updatedAt),
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 9),
                    ),
                  ],
                ),
              ),
              // Bonequinho/a no lugar da seta: mantém a rotação pela
              // direção do movimento e fica verde quando em movimento.
              Builder(
                builder: (_) {
                  final icon = p.child.gender == 'girl'
                      ? Icons.girl
                      : Icons.boy;
                  final color =
                      moving ? Colors.green.shade700 : AppTheme.danger;
                  final marker =
                      Icon(icon, color: color, size: 36);
                  if (p.heading != null && moving) {
                    return Transform.rotate(
                      angle: p.heading! * pi / 180,
                      child: marker,
                    );
                  }
                  return marker;
                },
              ),
            ],
          ),
        ),
      );
    }
    for (final pl in places) {
      markers.add(
        Marker(
          point: LatLng(pl.lat, pl.lng),
          width: 40,
          height: 40,
          child: Icon(
            pl.type == 'casa' ? Icons.home : Icons.school,
            color: AppTheme.primaryDark,
            size: 30,
          ),
        ),
      );
    }

    // Linhas do trajeto recente de cada filho.
    final polylines = <Polyline>[];
    for (final entry in _trails.entries) {
      if (entry.value.length < 2) continue;
      polylines.add(
        Polyline(
          points: List.of(entry.value),
          color: AppTheme.primary.withValues(alpha: 0.7),
          strokeWidth: 4,
        ),
      );
    }

    final circles = places
        .map(
          (pl) => CircleMarker(
            point: LatLng(pl.lat, pl.lng),
            radius: pl.radiusMeters,
            useRadiusInMeter: true,
            color: (pl.type == 'casa' ? Colors.green : Colors.blue)
                .withValues(alpha: 0.15),
            borderColor: pl.type == 'casa' ? Colors.green : Colors.blue,
            borderStrokeWidth: 2,
          ),
        )
        .toList();

    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: center,
            initialZoom: 15,
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.meufilhoseguro.app',
            ),
            CircleLayer(circles: circles),
            if (polylines.isNotEmpty)
              PolylineLayer(polylines: polylines),
            MarkerLayer(markers: markers),
          ],
        ),
        if (positioned.isEmpty && places.isEmpty)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  places.isEmpty
                      ? 'Cadastre os locais Casa e Escola em Ajustes para vê-los no mapa.'
                      : 'Ainda não há localização dos filhos. A localização aparece aqui quando o app do filho compartilhar.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.textMuted),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
