import 'package:flutter/services.dart';
import '../models/models.dart';

/// Serviço de alarme SOS para o responsável (versão simplificada).
///
/// Toca um alarme alto em loop usando o canal de ALARME do Android
/// (AudioAttributes.USAGE_ALARM) — fura o modo silencioso e o
/// "Não perturbe" (alarmes são exceção padrão do DND).
/// O som para quando o responsável marca o alerta como visto.
class SosAlarmService {
  static const _channel = MethodChannel('com.meufilhoseguro.app/sos_alarm');

  /// IDs de alertas que já dispararam o alarme (evita repetir).
  static final Set<String> _alarmedIds = {};

  static Future<void> init() async {
    // Nada a inicializar nesta versão simplificada.
  }

  /// Dispara o alarme para um alerta SOS (som em loop).
  /// Só dispara uma vez por alerta.
  static Future<void> triggerAlarm(SosAlert alert) async {
    if (_alarmedIds.contains(alert.id)) return;
    _alarmedIds.add(alert.id);
    try {
      await _channel.invokeMethod('playAlarm');
    } catch (_) {
      // Sem o código nativo, segue silencioso.
    }
  }

  /// Para o som do alarme.
  static Future<void> stopAlarm([String? alertId]) async {
    try {
      await _channel.invokeMethod('stopAlarm');
    } catch (_) {}
  }

  /// Limpa o registro de alarmes (ex.: ao fazer logout).
  static void reset() {
    _alarmedIds.clear();
  }
}
