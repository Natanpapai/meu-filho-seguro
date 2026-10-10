import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../models/safety_models.dart';
import 'firebase_service.dart';

/// Sincronização em tempo real entre os 2 celulares via Firestore.
///
/// - O FILHO envia: alertas SOS (coleção 'sos_alerts') e localização
///   periódica (documento 'locations/{childId}').
/// - O RESPONSÁVEL lê: stream de SOS e stream de localizações.
///
/// Tudo aqui é no-op quando o Firebase está indisponível
/// ([FirebaseService.available] == false): nenhum método lança exceção.
class RemoteSync {
  static bool get _fb => FirebaseService.available;

  static FirebaseFirestore get _db => FirebaseService.firestore;

  // ---------------- SOS ----------------

  /// Envia um alerta SOS do filho para o Firestore.
  /// O responsável vê em segundos via [sosAlertsStream].
  ///
  /// [guardianIds]: todos os responsáveis vinculados (pai e mãe).
  /// [silent]: pânico silencioso — não faz barulho no celular do filho
  /// (o responsável recebe normalmente, com alarme).
  static Future<void> sendSosAlert({
    required String childId,
    required String childName,
    required String guardianId,
    double? lat,
    double? lng,
    List<String>? guardianIds,
    bool silent = false,
  }) async {
    if (!_fb) return;
    try {
      final gids =
          (guardianIds == null || guardianIds.isEmpty) ? [guardianId] : guardianIds;
      await _db.collection('sos_alerts').add({
        'childId': childId,
        'childName': childName,
        'guardianId': guardianId,
        'guardianIds': gids,
        'lat': lat,
        'lng': lng,
        'timestamp': FieldValue.serverTimestamp(),
        'ack': false,
        'silent': silent,
      });
      debugPrint('[Sync] SOS enviado para o Firestore.');
    } catch (e) {
      debugPrint('[Sync] falha ao enviar SOS: $e');
    }
  }

  /// Stream dos alertas SOS endereçados a um responsável,
  /// mais recentes primeiro. A ordenação é feita no cliente para
  /// não exigir índice composto no Firestore.
  ///
  /// Usa `guardianIds` (array) para suportar múltiplos responsáveis.
  static Stream<List<SosAlert>> sosAlertsStream(String guardianId) {
    return sosAlertsInfoStream(guardianId).map(
        (infos) => infos
            .map((i) => SosAlert(
                  id: i.id,
                  childId: i.childId,
                  childName: i.childName,
                  guardianId: guardianId,
                  lat: i.lat,
                  lng: i.lng,
                  timestamp: i.timestamp,
                  ack: i.ack,
                ))
            .toList());
  }

  /// Versão do stream de SOS que inclui o flag de pânico silencioso.
  static Stream<List<SosAlertInfo>> sosAlertsInfoStream(String guardianId) {
    if (!_fb) return Stream.value(const <SosAlertInfo>[]);
    return _db
        .collection('sos_alerts')
        .where('guardianIds', arrayContains: guardianId)
        .limit(30)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map((d) {
        final m = Map<String, dynamic>.from(d.data());
        final ts = m['timestamp'];
        DateTime? dt;
        if (ts is Timestamp) {
          dt = ts.toDate();
        } else if (ts != null) {
          try {
            dt = DateTime.parse(ts.toString());
          } catch (_) {}
        }
        return SosAlertInfo(
          id: d.id,
          childId: (m['childId'] as String?) ?? '',
          childName: (m['childName'] as String?) ?? '',
          lat: (m['lat'] as num?)?.toDouble(),
          lng: (m['lng'] as num?)?.toDouble(),
          timestamp: dt,
          ack: (m['ack'] as bool?) ?? false,
          silent: (m['silent'] as bool?) ?? false,
        );
      }).toList();
      list.sort((a, b) {
        final ta = a.timestamp;
        final tb = b.timestamp;
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });
      return list;
    });
  }

  /// Marca um alerta SOS como visto pelo responsável.
  static Future<void> ackSosAlert(String docId) async {
    if (!_fb) return;
    try {
      await _db.collection('sos_alerts').doc(docId).update({'ack': true});
    } catch (e) {
      debugPrint('[Sync] falha ao confirmar SOS: $e');
    }
  }

  // ---------------- LOCALIZAÇÃO ----------------

  /// Envia a localização atual do filho para o Firestore
  /// (documento 'locations/{childId}'). Chamado periodicamente
  /// pelo app do filho e ao tocar em "Atualizar minha localização".
  /// [speed] em m/s e [heading] em graus (0-360), quando disponíveis.
  /// [guardianIds]: todos os responsáveis vinculados (multi-responsável).
  static Future<void> sendLocation({
    required String childId,
    required String childName,
    required String guardianId,
    required double lat,
    required double lng,
    int? battery,
    double? speed,
    double? heading,
    List<String>? guardianIds,
  }) async {
    if (!_fb) return;
    try {
      final gids =
          (guardianIds == null || guardianIds.isEmpty) ? [guardianId] : guardianIds;
      await _db.collection('locations').doc(childId).set(
        {
          'childId': childId,
          'childName': childName,
          'guardianId': guardianId,
          'guardianIds': gids,
          'lat': lat,
          'lng': lng,
          'battery': battery,
          if (speed != null) 'speed': speed,
          if (heading != null) 'heading': heading,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      debugPrint('[Sync] localização enviada para o Firestore.');
    } catch (e) {
      debugPrint('[Sync] falha ao enviar localização: $e');
    }
  }

  /// Stream do documento de localização de um filho.
  /// Retorna null quando não há dados ainda.
  static Stream<DocumentSnapshot<Map<String, dynamic>>> locationStream(
      String childId) {
    if (!_fb) return Stream.value(null).cast();
    return _db.collection('locations').doc(childId).snapshots();
  }

  /// Stream das localizações de vários filhos de uma vez
  /// (para o mapa do responsável).
  static Stream<QuerySnapshot<Map<String, dynamic>>> locationsStream(
      List<String> childIds) {
    if (!_fb || childIds.isEmpty) {
      return const Stream.empty();
    }
    // whereIn aceita no máximo 10 valores.
    final ids = childIds.length > 10 ? childIds.sublist(0, 10) : childIds;
    return _db
        .collection('locations')
        .where(FieldPath.documentId, whereIn: ids)
        .snapshots();
  }

  // ---------------- MULTI-RESPONSÁVEL ----------------

  /// Lê a lista de responsáveis vinculados a um filho
  /// (documento 'child_guardians/{childId}').
  static Future<List<String>> fetchGuardianIds(String childId) async {
    if (!_fb) return const [];
    try {
      final doc =
          await _db.collection('child_guardians').doc(childId).get();
      final data = doc.data();
      if (data == null) return const [];
      final ids = data['guardianIds'];
      if (ids is List) {
        return ids.map((e) => e.toString()).toList();
      }
      return const [];
    } catch (e) {
      debugPrint('[Sync] falha ao ler responsáveis: $e');
      return const [];
    }
  }

  /// Adiciona um responsável à lista de vinculados do filho
  /// (usado na vinculação do 1º e do 2º responsável).
  static Future<void> addGuardianToChild(
      String childId, String guardianId) async {
    if (!_fb) return;
    try {
      await _db.collection('child_guardians').doc(childId).set({
        'guardianIds': FieldValue.arrayUnion([guardianId]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('[Sync] responsável vinculado ao filho.');
    } catch (e) {
      debugPrint('[Sync] falha ao vincular responsável: $e');
    }
  }
}
