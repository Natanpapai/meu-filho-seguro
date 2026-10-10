import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Controle do serviço de rastreamento contínuo (foreground service nativo).
///
/// O serviço Android envia a posição do filho ao Firestore a cada 4
/// segundos, mesmo com o app em 2º plano — é o que permite ao responsável
/// ver o filho se movendo no mapa em tempo real, estilo Uber.
///
/// O compartilhamento não pode ser pausado pelo filho: é uma medida de
/// segurança definida pelo responsável.
class SharingService {
  static const _channel =
      MethodChannel('com.meufilhoseguro.app/sharing');

  /// Inicia o compartilhamento contínuo de localização.
  /// [guardianIds]: todos os responsáveis vinculados (multi-responsável).
  static Future<void> start({
    required String childId,
    required String childName,
    required String guardianId,
    List<String>? guardianIds,
  }) async {
    try {
      await _channel.invokeMethod('startSharing', {
        'childId': childId,
        'childName': childName,
        'guardianId': guardianId,
        // Pode ser null: o Kotlin ignora com `?.let`.
        'guardianIds': guardianIds,
      });
      debugPrint('[Sharing] serviço de rastreamento iniciado.');
    } catch (e) {
      debugPrint('[Sharing] falha ao iniciar: $e');
    }
  }

  /// Para o compartilhamento contínuo.
  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stopSharing');
      debugPrint('[Sharing] serviço de rastreamento parado.');
    } catch (e) {
      debugPrint('[Sharing] falha ao parar: $e');
    }
  }

  /// Verifica se o serviço está rodando.
  static Future<bool> isRunning() async {
    try {
      return await _channel.invokeMethod<bool>('isSharing') ?? false;
    } catch (_) {
      return false;
    }
  }
}
