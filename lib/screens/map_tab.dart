import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../app_deps.dart';
import '../theme.dart';

/// Aba Mapa: mostra filhos e locais seguros no mapa.
/// Mapa via OpenStreetMap (sem necessidade de chave de API).
class MapTab extends StatelessWidget {
  final AppDeps deps;
  const MapTab({super.key, required this.deps});

  @override
  Widget build(BuildContext context) {
    final children =
        deps.storage.getChildren().where((c) => c.lastLat != null).toList();
    final places = deps.storage.getPlaces();

    LatLng center = const LatLng(-22.9068, -43.1729); // Rio de Janeiro
    if (children.isNotEmpty) {
      center = LatLng(children.first.lastLat!, children.first.lastLng!);
    } else if (places.isNotEmpty) {
      center = LatLng(places.first.lat, places.first.lng);
    }

    final markers = <Marker>[];
    for (final c in children) {
      markers.add(
        Marker(
          point: LatLng(c.lastLat!, c.lastLng!),
          width: 110,
          height: 60,
          child: Column(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  c.nickname.isNotEmpty ? c.nickname : c.name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
              ),
              const Icon(Icons.location_on,
                  color: AppTheme.danger, size: 30),
            ],
          ),
        ),
      );
    }
    for (final p in places) {
      markers.add(
        Marker(
          point: LatLng(p.lat, p.lng),
          width: 40,
          height: 40,
          child: Icon(
            p.type == 'casa' ? Icons.home : Icons.school,
            color: AppTheme.primaryDark,
            size: 30,
          ),
        ),
      );
    }

    final circles = places
        .map(
          (p) => CircleMarker(
            point: LatLng(p.lat, p.lng),
            radius: p.radiusMeters,
            useRadiusInMeter: true,
            color: (p.type == 'casa' ? Colors.green : Colors.blue)
                .withValues(alpha: 0.15),
            borderColor: p.type == 'casa' ? Colors.green : Colors.blue,
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
        if (children.isEmpty && places.isEmpty)
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
