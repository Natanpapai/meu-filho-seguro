import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Desenha um pezinho (solado + dedinhos) apontando para cima.
///
/// O [Marker] que usa este painter aplica [Transform.rotate] com o rumo
/// do trajeto, então o passinho "anda" na direção do movimento.
class _FootprintPainter extends CustomPainter {
  final Color color;
  _FootprintPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final cx = size.width / 2;

    // Solado: elipse arredondada.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx, size.height * 0.68),
          width: size.width * 0.42,
          height: size.height * 0.52,
        ),
        const Radius.circular(8),
      ),
      paint,
    );
    // Dedinhos: 4 bolinhas no topo, do maior ao menor.
    final toeSizes = [0.11, 0.095, 0.08, 0.065];
    for (var i = 0; i < toeSizes.length; i++) {
      final r = size.width * toeSizes[i];
      final x = cx + (i - 1.5) * size.width * 0.17;
      // Dedos externos um pouco mais baixos (formato de pé).
      final y = size.height * 0.16 + (i == 0 || i == 3 ? r * 0.9 : 0);
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FootprintPainter old) =>
      old.color != color;
}

/// Converte uma lista de pontos do trajeto em marcadores de passinhos.
///
/// - Um passinho a cada [spacingMeters] percorridos (padrão 25 m): visível
///   sem poluir o mapa.
/// - Cada passinho é rotacionado para o rumo do trajeto naquele ponto.
/// - Alterna o lado (esquerda/direita) para parecer passos reais.
/// - [maxCount] limita a quantidade por performance.
List<Marker> buildFootprintMarkers(
  List<LatLng> points, {
  Color color = const Color(0xFF1565C0),
  double spacingMeters = 25,
  int maxCount = 300,
}) {
  final markers = <Marker>[];
  if (points.length < 2) return markers;

  const dist = Distance();
  double acc = 0;
  LatLng? anchor; // último ponto onde um passinho foi colocado
  var side = 1.0; // alterna +1 / -1 (direita / esquerda)

  for (var i = 1; i < points.length && markers.length < maxCount; i++) {
    final prev = points[i - 1];
    final cur = points[i];
    final step = dist(prev, cur);
    if (step < 1) continue;
    acc += step;
    if (acc < spacingMeters) continue;
    acc = 0;

    // Rumo do trajeto neste ponto (0 = norte, sentido horário).
    final from = anchor ?? prev;
    final dLat = cur.latitude - from.latitude;
    final dLng = (cur.longitude - from.longitude) *
        cos(from.latitude * pi / 180);
    if (dLat == 0 && dLng == 0) continue;
    final heading = atan2(dLng, dLat);

    // Desloca o passinho ~2 m para o lado, alternando esquerda/direita.
    const double sideMeters = 2.0;
    final perpX = -sin(heading); // componente leste do perpendicular
    final perpY = cos(heading); // componente norte do perpendicular
    final lat = from.latitude;
    final dLatM = perpY * side * sideMeters;
    final dLngM = perpX * side * sideMeters;
    final footLat = lat + dLatM / 111320.0;
    final footLng =
        from.longitude + dLngM / (111320.0 * cos(lat * pi / 180));
    side = -side;
    anchor = cur;

    markers.add(
      Marker(
        point: LatLng(footLat, footLng),
        width: 26,
        height: 26,
        child: Transform.rotate(
          angle: heading,
          child: CustomPaint(
            size: const Size(26, 26),
            painter: _FootprintPainter(color),
          ),
        ),
      ),
    );
  }
  return markers;
}
