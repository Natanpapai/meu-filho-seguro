import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
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
  static Future<void> sendSosAlert({
    required String childId,
    required String childName,
    required String guardianId,
    double? lat,
    double? lng,
  }) async {
    if (!_fb) return;
    try {
      await _db.collection('sos_alerts').add({
        'childId': childId,
        'childName': childName,
        'guardianId': guardianId,
        'lat': lat,
        'lng': lng,
        'timestamp': FieldValue.serverTimestamp(),
        'ack': false,
      });
      debugPrint('[Sync] SOS enviado para o Firestore.');
    } catch (e) {
      debugPrint('[Sync] falha ao enviar SOS: $e');
    }
  }

  /// Stream dos alertas SOS endereçados a um responsável,
  /// mais recentes primeiro. A ordenação é feita no cliente para
  /// não exigir índice composto no Firestore.
  static Stream<List<SosAlert>> sosAlertsStream(String guardianId) {
    if (!_fb) return Stream.value(const []);
    return _db
        .collection('sos_alerts')
        .where('guardianId', isEqualTo: guardianId)
        .limit(30)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map((d) {
        final m = Map<String, dynamic>.from(d.data());
        // O Firestore entrega Timestamp; o modelo espera DateTime.
        final ts = m['timestamp'];
        if (ts is Timestamp) m['timestamp'] = ts.toDate();
        return SosAlert.fromMap(d.id, m);
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
  static Future<void> sendLocation({
    required String childId,
    required String childName,
    required String guardianId,
    required double lat,
    required double lng,
    int? battery,
    double? speed,
    double? heading,
  }) async {
    if (!_fb) return;
    try {
      await _db.collection('locations').doc(childId).set(
        {
          'childId': childId,
          'childName': childName,
          'guardianId': guardianId,
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
}
