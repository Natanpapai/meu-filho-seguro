import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/safety_models.dart';
import 'storage_service.dart';

/// Trajeto persistente no aparelho do RESPONSÁVEL (v14).
///
/// O que o dono pediu: "quero que fique marcado os passinhos no
/// histórico" — os pontos do trajeto NÃO podem sumir ao recarregar o
/// app, trocar de dia ou ficar sem internet.
///
/// Como funciona:
/// - O mapa do responsável ([MapTab]) recebe a posição do filho a cada
///   ~4 s via Firestore. Cada ponto novo (que represente movimento real)
///   é gravado aqui, no armazenamento local deste aparelho, separado
///   por filho e por dia.
/// - A tela "Trajeto do dia" lê estes pontos locais e os MESCLA com os
///   pontos do Firestore (amostrados pelo app do filho a cada ~2 min),
///   removendo duplicados — o que garante os passinhos marcados de
///   forma permanente, mesmo offline.
/// - Retenção: 30 dias no aparelho (o Firestore mantém 7 dias).
///
/// Limites honestos: os pontos locais existem SÓ neste aparelho. Se o
/// responsável trocar de celular, o histórico antigo fica no aparelho
/// antigo (os pontos do Firestore, de até 7 dias, continuam valendo).
class TrailService {
  /// Distância mínima (m) do último ponto salvo para gravar um novo.
  static const double minDistanceMeters = 20;

  /// Tempo mínimo (s) entre dois pontos salvos.
  static const int minIntervalSeconds = 60;

  /// Teto de pontos por dia (segurança contra crescimento patológico).
  static const int maxPointsPerDay = 2000;

  /// Dias mantidos no aparelho.
  static const int retentionDays = 30;

  static String _key(String childId, DateTime date) =>
      'mfs_trail_${childId}_${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static String _indexKey(String childId) => 'mfs_trail_index_$childId';

  /// Grava um ponto do trajeto de hoje. Silencioso e barato: ignora
  /// pontos que não representam movimento real (>= 20 m OU >= 60 s
  /// desde o último ponto salvo).
  static Future<void> recordPoint(
    StorageService storage, {
    required String childId,
    required double lat,
    required double lng,
  }) async {
    try {
      final now = DateTime.now();
      final key = _key(childId, now);
      final raw = storage.getRaw(key);
      List<Map<String, dynamic>> pts;
      if (raw == null || raw.isEmpty) {
        pts = [];
      } else {
        try {
          pts = (jsonDecode(raw) as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        } catch (_) {
          pts = [];
        }
      }

      if (pts.isNotEmpty) {
        final last = pts.last;
        final llat = (last['lat'] as num?)?.toDouble();
        final llng = (last['lng'] as num?)?.toDouble();
        final lts = parseFirestoreTimestamp(last['ts']);
        if (llat != null && llng != null) {
          final d = _haversine(llat, llng, lat, lng);
          final dt = lts == null
              ? 0
              : now.difference(lts).inSeconds.abs();
          // Sem movimento real: não grava (economiza espaço).
          if (d < minDistanceMeters && dt < minIntervalSeconds) return;
        }
      }

      pts.add({
        'lat': lat,
        'lng': lng,
        'ts': now.toIso8601String(),
      });
      // Teto de segurança.
      while (pts.length > maxPointsPerDay) {
        pts.removeAt(0);
      }
      await storage.setRaw(key, jsonEncode(pts));
      await _touchIndex(storage, childId, key);
    } catch (e) {
      // O trajeto nunca pode derrubar o app.
      debugPrint('[Trail] falha ao gravar ponto: $e');
    }
  }

  /// Pontos locais de um dia (ordenados por horário).
  static List<HistoryPoint> pointsOfDay(
      StorageService storage, String childId, DateTime date) {
    try {
      final raw = storage.getRaw(_key(childId, date));
      if (raw == null || raw.isEmpty) return const [];
      final pts = (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map((m) => HistoryPoint(
                lat: (m['lat'] as num?)?.toDouble() ?? 0,
                lng: (m['lng'] as num?)?.toDouble() ?? 0,
                timestamp: parseFirestoreTimestamp(m['ts']),
              ))
          .where((p) => p.timestamp != null)
          .toList();
      pts.sort((a, b) => a.timestamp!.compareTo(b.timestamp!));
      return pts;
    } catch (_) {
      return const [];
    }
  }

  /// Mescla pontos do Firestore com os pontos locais, removendo
  /// duplicados (pontos a menos de 90 s um do outro contam como o
  /// mesmo). Resultado ordenado por horário.
  static List<HistoryPoint> merge(
      List<HistoryPoint> remote, List<HistoryPoint> local) {
    final all = <HistoryPoint>[...local, ...remote];
    all.sort((a, b) {
      final ta = a.timestamp;
      final tb = b.timestamp;
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return ta.compareTo(tb);
    });
    final out = <HistoryPoint>[];
    for (final p in all) {
      final t = p.timestamp;
      if (t == null) continue;
      final dup = out.any((q) =>
          q.timestamp != null &&
          (q.timestamp!.difference(t).inSeconds.abs() < 90));
      if (!dup) out.add(p);
    }
    return out;
  }

  /// Índice de dias com pontos (para limpeza de dias antigos).
  static Future<void> _touchIndex(
      StorageService storage, String childId, String key) async {
    try {
      final idxKey = _indexKey(childId);
      final raw = storage.getRaw(idxKey);
      final keys = <String>{
        if (raw != null && raw.isNotEmpty)
          ...(jsonDecode(raw) as List).map((e) => e.toString()),
        key,
      };
      // Poda dias com mais de [retentionDays].
      final cutoff = DateTime.now().subtract(
        const Duration(days: retentionDays),
      );
      final kept = <String>[];
      for (final k in keys) {
        final m = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(k);
        if (m == null) continue;
        final d = DateTime(
          int.parse(m.group(1)!),
          int.parse(m.group(2)!),
          int.parse(m.group(3)!),
        );
        if (d.isBefore(DateTime(cutoff.year, cutoff.month, cutoff.day))) {
          await storage.removeRaw(k);
        } else {
          kept.add(k);
        }
      }
      await storage.setRaw(idxKey, jsonEncode(kept));
    } catch (_) {}
  }

  static double _haversine(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    double rad(double d) => d * pi / 180;
    final dLat = rad(lat2 - lat1);
    final dLng = rad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(rad(lat1)) * cos(rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    return 2 * r * asin(sqrt(a));
  }
}
