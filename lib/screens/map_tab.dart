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
  _RemoteLoc(this.lat, this.lng, this.updatedAt);
}

/// Aba Mapa: mostra filhos e locais seguros no mapa.
/// Mapa via OpenStreetMap (sem necessidade de chave de API).
///
/// A posição dos filhos é mesclada em tempo real: os dados locais
/// são combinados com a localização enviada pelo celular do filho
/// via Firestore (a mais recente prevalece).
class MapTab extends StatelessWidget {
  final AppDeps deps;
  const MapTab({super.key, required this.deps});

  @override
  Widget build(BuildContext context) {
    final children = deps.storage.getChildren();
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
          remote[d.id] =
              _RemoteLoc(lat, lng, ts is Timestamp ? ts.toDate() : null);
        }
        return _buildMap(children, remote);
      },
    );
  }

  /// Resolve a melhor posição conhecida de cada filho:
  /// a remota (Firestore) prevalece quando é mais recente que a local.
  /// Retorna null quando não há posição alguma.
  ({double lat, double lng, DateTime? updatedAt})? _resolve(
      Child c, Map<String, _RemoteLoc> remote) {
    final r = remote[c.id];
    if (r != null &&
        (c.lastLat == null ||
            (r.updatedAt != null &&
                (c.lastUpdate == null ||
                    r.updatedAt!.isAfter(c.lastUpdate!))))) {
      return (lat: r.lat, lng: r.lng, updatedAt: r.updatedAt);
    }
    if (c.lastLat != null && c.lastLng != null) {
      return (lat: c.lastLat!, lng: c.lastLng!, updatedAt: c.lastUpdate);
    }
    return null;
  }

  Widget _buildMap(List<Child> children, Map<String, _RemoteLoc> remote) {
    final places = deps.storage.getPlaces();

    final positioned = <({Child child, double lat, double lng, DateTime? updatedAt})>[];
    for (final c in children) {
      final p = _resolve(c, remote);
      if (p != null) {
        positioned.add((
          child: c,
          lat: p.lat,
          lng: p.lng,
          updatedAt: p.updatedAt
        ));
      }
    }

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
      markers.add(
        Marker(
          point: LatLng(p.lat, p.lng),
          width: 130,
          height: 76,
          child: Column(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
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
              const Icon(Icons.location_on,
                  color: AppTheme.danger, size: 30),
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
