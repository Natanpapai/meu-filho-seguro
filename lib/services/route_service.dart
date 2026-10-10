import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../app_deps.dart';
import '../models/safety_models.dart';
import 'firebase_service.dart';
import 'sync_service.dart';

/// Rota segura: o responsável desenha o caminho esperado (casa -> escola).
/// Se o filho se afastar mais de [_deviationMeters] da linha, o
/// responsável recebe um alerta.
///
/// - A rota fica salva localmente e no Firestore (`routes/{childId}`).
/// - A verificação de desvio roda no app do RESPONSÁVEL ([RouteMonitor]),
///   que observa o stream de localizações. Sem Firebase, a verificação
///   não acontece (fallback gracioso).
class RouteService {
  /// Distância máxima da linha da rota antes de alertar (metros).
  static const double deviationMeters = 200;

  static bool get _fb => FirebaseService.available;
  static FirebaseFirestore get _db => FirebaseService.firestore;

  // ---------------- CRUD ----------------

  /// Salva a rota localmente e no Firestore.
  static Future<void> saveRoute(AppDeps deps, SafeRoute route) async {
    final prefs = _prefs(deps);
    await prefs._setString(
        'mfs_route_${route.childId}', jsonEncode(route.toJson()));
    if (!_fb) return;
    try {
      await _db.collection('routes').doc(route.childId).set({
        ...route.toJson(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[Route] falha ao salvar rota no Firestore: $e');
    }
  }

  /// Lê a rota (local primeiro; Firestore como fallback).
  static Future<SafeRoute?> getRoute(AppDeps deps, String childId) async {
    final raw = _prefs(deps)._getString('mfs_route_$childId');
    if (raw != null) {
      try {
        return SafeRoute.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    if (!_fb) return null;
    try {
      final doc = await _db.collection('routes').doc(childId).get();
      final data = doc.data();
      if (data == null) return null;
      return SafeRoute.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      debugPrint('[Route] falha ao ler rota: $e');
      return null;
    }
  }

  /// Apaga a rota (local + Firestore).
  static Future<void> deleteRoute(AppDeps deps, String childId) async {
    await _prefs(deps)._remove('mfs_route_$childId');
    if (!_fb) return;
    try {
      await _db.collection('routes').doc(childId).delete();
    } catch (_) {}
  }

  // ---------------- Geometria ----------------

  /// Menor distância (metros) de um ponto à polilinha da rota.
  /// Usa projeção equiretangular local (precisa para distâncias curtas).
  static double distanceToRoute(
      double lat, double lng, List<RoutePoint> points) {
    if (points.isEmpty) return double.infinity;
    if (points.length == 1) {
      return _haversine(
          lat, lng, points.first.lat, points.first.lng);
    }
    // Fator de escala local (metros por grau).
    final kx = 111320 * cos(_rad(lat));
    final ky = 110574;
    double best = double.infinity;
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      final ax = (a.lng - lng) * kx;
      final ay = (a.lat - lat) * ky;
      final bx = (b.lng - lng) * kx;
      final by = (b.lat - lat) * ky;
      final d = _pointToSegment(0, 0, ax, ay, bx, by);
      if (d < best) best = d;
    }
    return best;
  }

  static double _pointToSegment(double px, double py, double ax,
      double ay, double bx, double by) {
    final dx = bx - ax;
    final dy = by - ay;
    final len2 = dx * dx + dy * dy;
    double t = len2 == 0 ? 0 : ((px - ax) * dx + (py - ay) * dy) / len2;
    t = t.clamp(0.0, 1.0);
    final cx = ax + t * dx;
    final cy = ay + t * dy;
    return sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
  }

  static double _haversine(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    return 2 * r * asin(sqrt(a));
  }

  static double _rad(double d) => d * pi / 180;
}

// Helpers de SharedPreferences via StorageService (evita importar
// shared_preferences aqui; usa as chaves cruas).
extension on Object {
  // (placeholder para manter o estilo; acesso real abaixo)
}

_SharedPrefs _prefs(AppDeps deps) => _SharedPrefs(deps);

class _SharedPrefs {
  final AppDeps _deps;
  _SharedPrefs(this._deps);

  // Acesso às preferências através do StorageService usando chaves
  // genéricas. Como o StorageService não expõe get/set genérico,
  // usamos um truque: guardamos o JSON da rota dentro do próprio
  // mapa de "places"? Não — implementamos via método dedicado abaixo.
  //
  // Na prática, adicionamos get/set genéricos no StorageService
  // (ver storage_service.dart: getRaw/setRaw/removeRaw).
  String? _getString(String key) => _deps.storage.getRaw(key);
  Future<void> _setString(String key, String value) =>
      _deps.storage.setRaw(key, value);
  Future<void> _remove(String key) => _deps.storage.removeRaw(key);
}

/// Monitor de desvio de rota no app do responsável.
///
/// Observa o stream de localizações; quando um filho com rota definida
/// se afasta mais de 200m da linha, grava um alerta em `route_alerts`
/// (visível para todos os responsáveis vinculados) e o banner da tela
/// inicial o exibe.
///
/// Limitações do MVP:
/// - Só funciona com o app do responsável aberto (sem Cloud Functions).
/// - Não alerta durante o Modo Escola (a criança deve estar na escola).
class RouteMonitor {
  static StreamSubscription? _sub;
  static bool _running = false;

  /// Inicia o monitoramento. Idempotente.
  static Future<void> start(AppDeps deps) async {
    if (_running || !FirebaseService.available) return;
    final children = deps.storage.getChildren();
    final routes = <String, SafeRoute>{};
    for (final c in children) {
      final r = await RouteService.getRoute(deps, c.id);
      if (r != null && r.points.length >= 2) routes[c.id] = r;
    }
    if (routes.isEmpty) return;
    _running = true;
    // IDs de todos os responsáveis de cada filho (para o alerta chegar
    // a pai e mãe). Busca uma vez no início.
    final guardianIds = <String, List<String>>{};
    for (final id in routes.keys) {
      guardianIds[id] = await RemoteSync.fetchGuardianIds(id);
    }
    _sub = RemoteSync.locationsStream(routes.keys.toList()).listen(
      (snap) async {
        // Modo escola: a criança deve estar na escola; sem alerta de rota.
        final school = deps.storage.getSchoolMode();
        if (school.isActiveNow()) return;
        for (final d in snap.docs) {
          final m = d.data();
          final lat = (m['lat'] as num?)?.toDouble();
          final lng = (m['lng'] as num?)?.toDouble();
          if (lat == null || lng == null) continue;
          final route = routes[d.id];
          if (route == null) continue;
          final dist =
              RouteService.distanceToRoute(lat, lng, route.points);
          final childName = (m['childName'] as String?) ?? '';
          if (dist > RouteService.deviationMeters) {
            await _maybeAlert(deps, d.id, childName,
                guardianIds[d.id] ?? const [], lat, lng, dist);
          } else {
            // Voltou para a rota: libera para alertar de novo no
            // próximo desvio.
            await deps.storage
                .removeRaw('mfs_route_alert_${d.id}');
          }
        }
      },
      onError: (_) {},
    );
    debugPrint('[Route] monitor iniciado (${routes.length} rotas).');
  }

  static Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _running = false;
  }

  /// Alerta no máximo 1x a cada 30 minutos por filho (evita spam).
  static Future<void> _maybeAlert(
    AppDeps deps,
    String childId,
    String childName,
    List<String> gids,
    double lat,
    double lng,
    double dist,
  ) async {
    final key = 'mfs_route_alert_$childId';
    final last = deps.storage.getRaw(key);
    if (last != null) {
      final dt = DateTime.tryParse(last);
      if (dt != null &&
          DateTime.now().difference(dt).inMinutes < 30) {
        return;
      }
    }
    await deps.storage.setRaw(key, DateTime.now().toIso8601String());
    try {
      await FirebaseService.firestore.collection('route_alerts').add({
        'childId': childId,
        'childName': childName,
        'guardianIds': gids,
        'lat': lat,
        'lng': lng,
        'distanceMeters': dist.round(),
        'timestamp': FieldValue.serverTimestamp(),
        'ack': false,
      });
      debugPrint('[Route] alerta de desvio enviado.');
    } catch (e) {
      debugPrint('[Route] falha ao enviar alerta: $e');
    }
  }

  /// Stream dos alertas de rota não confirmados de um responsável.
  static Stream<List<RouteAlert>> routeAlertsStream(String guardianId) {
    if (!FirebaseService.available) {
      return Stream.value(const <RouteAlert>[]);
    }
    return FirebaseService.firestore
        .collection('route_alerts')
        .where('guardianIds', arrayContains: guardianId)
        .limit(20)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map((d) {
        final m = Map<String, dynamic>.from(d.data());
        final ts = m['timestamp'];
        if (ts is Timestamp) m['timestamp'] = ts.toDate();
        return RouteAlert.fromMap(d.id, m);
      }).toList();
      list.sort((a, b) {
        final ta = a.timestamp;
        final tb = b.timestamp;
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });
      return list
          .where((a) =>
              !a.ack &&
              (a.timestamp == null ||
                  DateTime.now().difference(a.timestamp!).inHours < 24))
          .toList();
    });
  }

  /// Marca um alerta de rota como visto.
  static Future<void> ackRouteAlert(String docId) async {
    if (!FirebaseService.available) return;
    try {
      await FirebaseService.firestore
          .collection('route_alerts')
          .doc(docId)
          .update({'ack': true});
    } catch (_) {}
  }
}
