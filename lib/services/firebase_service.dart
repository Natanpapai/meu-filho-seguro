import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Camada de acesso ao Firebase (Firestore + Auth).
///
/// O Firebase é OPCIONAL: se a inicialização falhar (sem google-services.json,
/// sem rede, etc.), [available] fica false e o app continua funcionando 100%
/// no modo local. Todo o código que usa Firebase deve checar [available]
/// antes e ter fallback local.
class FirebaseService {
  /// true quando o Firebase inicializou com sucesso neste aparelho.
  static bool available = false;

  /// Inicializa o Firebase. Nunca lança exceção: em caso de falha,
  /// apenas marca [available] como false e o app segue no modo local.
  static Future<void> init() async {
    try {
      await Firebase.initializeApp();
      available = true;
      debugPrint('[Firebase] inicializado com sucesso.');
    } catch (e) {
      available = false;
      debugPrint('[Firebase] indisponível, usando modo local: $e');
    }
  }

  /// Atalho para o Firestore. Só chamar quando [available] for true.
  static FirebaseFirestore get firestore => FirebaseFirestore.instance;

  /// Atalho para o Firebase Auth. Só chamar quando [available] for true.
  static FirebaseAuth get auth => FirebaseAuth.instance;
}
