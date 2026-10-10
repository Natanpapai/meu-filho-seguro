import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/safety_models.dart';
import 'firebase_service.dart';

/// Histórico do dia: trajeto do filho com horários.
///
/// Como o Firestore guarda só a posição ATUAL em `locations/{childId}`,
/// o app do filho grava pontos amostrados (a cada ~2 min) em
/// `history/{childId}/points/{autoId}`.
///
/// - Sem Firebase: não grava nada (fallback gracioso); o histórico local
///   de eventos (chegadas/saídas/SOS) continua funcionando.
/// - Pontos com mais de 7 dias são apagados automaticamente (1x ao dia).
class HistoryService {
  static bool get _fb => FirebaseService.available;
  static FirebaseFirestore get _db => FirebaseService.firestore;

  /// Grava um ponto do trajeto. Chamado a cada ~2 min pelo app do filho.
  static Future<void> recordPoint({
    required String childId,
    required double lat,
    required double lng,
    int? battery,
  }) async {
    if (!_fb) return;
    try {
      final data = <String, dynamic>{
        'lat': lat,
        'lng': lng,
        'timestamp': FieldValue.serverTimestamp(),
      };
      if (battery != null) data['battery'] = battery;
      await _db
          .collection('history')
          .doc(childId)
          .collection('points')
          .add(data);
    } catch (e) {
      debugPrint('[History] falha ao gravar ponto: $e');
    }
  }

  /// Apaga pontos com mais de 7 dias (chamar 1x ao dia).
  static Future<void> cleanupOldPoints(String childId) async {
    if (!_fb) return;
    try {
      final cutoff =
          DateTime.now().subtract(const Duration(days: 7));
      final snap = await _db
          .collection('history')
          .doc(childId)
          .collection('points')
          .where('timestamp', isLessThan: Timestamp.fromDate(cutoff))
          .limit(200)
          .get();
      if (snap.docs.isEmpty) return;
      final batch = _db.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      debugPrint('[History] ${snap.docs.length} pontos antigos apagados.');
    } catch (e) {
      debugPrint('[History] falha na limpeza: $e');
    }
  }

  /// Pontos de um dia específico (ordenados por horário).
  /// [date] usa apenas ano/mês/dia.
  static Future<List<HistoryPoint>> pointsOfDay(
      String childId, DateTime date) async {
    if (!_fb) return const [];
    try {
      final start = DateTime(date.year, date.month, date.day);
      final end = start.add(const Duration(days: 1));
      final snap = await _db
          .collection('history')
          .doc(childId)
          .collection('points')
          .where('timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('timestamp', isLessThan: Timestamp.fromDate(end))
          // Teto alto: um dia inteiro de amostragem a cada 2 min dá
          // ~720 pontos; 1500 garante que nada do dia seja cortado.
          .limit(1500)
          .get();
      final points = snap.docs
          .map((d) =>
              HistoryPoint.fromMap(Map<String, dynamic>.from(d.data())))
          .where((p) => p.timestamp != null)
          .toList();
      points.sort((a, b) => a.timestamp!.compareTo(b.timestamp!));
      return points;
    } catch (e) {
      debugPrint('[History] falha ao ler pontos do dia: $e');
      return const [];
    }
  }

  /// Lê a posição atual do próprio filho (para amostragem do histórico).
  static Future<({double lat, double lng, int? battery})?>
      readOwnLocation(String childId) async {
    if (!_fb) return null;
    try {
      final doc =
          await _db.collection('locations').doc(childId).get();
      final m = doc.data();
      if (m == null) return null;
      final lat = (m['lat'] as num?)?.toDouble();
      final lng = (m['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      return (
        lat: lat,
        lng: lng,
        battery: (m['battery'] as num?)?.toInt()
      );
    } catch (_) {
      return null;
    }
  }
}
