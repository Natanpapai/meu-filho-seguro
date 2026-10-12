import 'package:flutter/services.dart';

/// Permissões de sistema (v15).
///
/// Centraliza as verificações/aberturas de configurações que mantêm o
/// app funcionando em 2º plano e fazem o alerta de emergência aparecer
/// por cima da tela bloqueada:
///
/// - **Ignorar otimização de bateria**: sem isso, o Android (principalmente
///   em aparelhos Xiaomi/Samsung) mata o serviço de rastreamento do filho
///   e o serviço de vigilância SOS do responsável — causando "passinhos
///   com buracos" e "o alerta não apareceu".
/// - **Alertas em tela cheia** (Android 14+): sem liberar, a notificação
///   de emergência não abre por cima da tela bloqueada.
/// - **Aparecer por cima de outros apps**: camada extra de segurança para
///   o alerta abrir mesmo se o full-screen intent falhar no aparelho.
///
/// Usa o mesmo canal nativo do alarme SOS
/// (`com.meufilhoseguro.app/sos_alarm`).
class SystemPermissions {
  static const _channel = MethodChannel('com.meufilhoseguro.app/sos_alarm');

  /// true se o app já está liberado da otimização de bateria.
  static Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      final ok = await _channel
          .invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Abre o pedido do sistema para ignorar a otimização de bateria
  /// deste app. Retorna true se a tela abriu.
  static Future<bool> openBatteryOptimizationSettings() async {
    try {
      final ok = await _channel
          .invokeMethod<bool>('openBatteryOptimizationSettings');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// true se pode desenhar por cima de outros apps.
  static Future<bool> canDrawOverlays() async {
    try {
      final ok =
          await _channel.invokeMethod<bool>('canDrawOverlays');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Abre as configurações de "aparecer por cima de outros apps".
  static Future<bool> openOverlaySettings() async {
    try {
      final ok =
          await _channel.invokeMethod<bool>('openOverlaySettings');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}
