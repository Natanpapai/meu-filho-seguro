import 'package:flutter/services.dart';
import '../models/models.dart';

/// Som de alarme disponível no sistema.
class AlarmSound {
  final String title;
  final String uri;
  const AlarmSound({required this.title, required this.uri});
}

/// Serviço de alarme SOS para o responsável.
///
/// Toca um alarme alto em loop usando o canal de ALARME do Android
/// (AudioAttributes.USAGE_ALARM) — fura o modo silencioso e o
/// "Não perturbe" (alarmes são exceção padrão do DND).
/// O som para quando o responsável marca o alerta como visto.
///
/// Além do som via app aberto, um serviço nativo de vigilância
/// (SosWatchService) ouve o Firestore e toca o alarme mesmo com o
/// celular bloqueado ou o app fechado.
class SosAlarmService {
  static const _channel = MethodChannel('com.meufilhoseguro.app/sos_alarm');

  /// IDs de alertas que já dispararam o alarme (evita repetir).
  static final Set<String> _alarmedIds = {};

  static Future<void> init() async {
    // Nada a inicializar nesta versão.
  }

  /// Dispara o alarme para um alerta SOS (som em loop).
  /// Só dispara uma vez por alerta. Se o serviço de vigilância nativo
  /// já estiver tocando, não duplica o som.
  static Future<void> triggerAlarm(SosAlert alert) async {
    if (_alarmedIds.contains(alert.id)) return;
    _alarmedIds.add(alert.id);
    try {
      final watching = await _channel.invokeMethod<bool>('isWatchAlarming');
      if (watching == true) return; // nativo já está tocando
    } catch (_) {}
    try {
      await _channel.invokeMethod('playAlarm');
    } catch (_) {
      // Sem o código nativo, segue silencioso.
    }
  }

  /// Para o som do alarme (app + serviço de vigilância).
  static Future<void> stopAlarm([String? alertId]) async {
    try {
      await _channel.invokeMethod('stopAlarm');
    } catch (_) {}
  }

  /// Lista os sons de alarme disponíveis no sistema.
  static Future<List<AlarmSound>> getAlarmSounds() async {
    try {
      final list = await _channel.invokeListMethod('getAlarmSounds');
      return (list ?? const [])
          .map((m) => AlarmSound(
                title: (m['title'] as String?) ?? 'Alarme',
                uri: (m['uri'] as String?) ?? '',
              ))
          .where((s) => s.uri.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Toca o som uma vez (sem loop) para pré-visualização.
  static Future<void> previewSound(String uri) async {
    try {
      await _channel.invokeMethod('previewAlarm', {'uri': uri});
    } catch (_) {}
  }

  /// Salva o som escolhido pelo responsável.
  static Future<void> saveAlarmSound(String uri) async {
    try {
      await _channel.invokeMethod('saveAlarmSound', {'uri': uri});
    } catch (_) {}
  }

  /// Retorna o URI do som escolhido (vazio = padrão do sistema).
  static Future<String> getSavedAlarmSound() async {
    try {
      final uri = await _channel.invokeMethod<String>('getAlarmSound');
      return uri ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Toca o som SALVO pelo caminho real do alarme (playAlarm sem
  /// argumentos = usa o que está nas preferências). Serve para o
  /// usuário testar se a troca funcionou de ponta a ponta.
  /// Toca por [seconds] e para sozinho.
  static Future<void> testSavedSound({int seconds = 3}) async {
    try {
      await _channel.invokeMethod('playAlarm');
      await Future.delayed(Duration(seconds: seconds));
      await _channel.invokeMethod('stopAlarm');
    } catch (_) {}
  }

  /// Inicia a vigilância SOS em 2º plano (toca mesmo com tela bloqueada).
  static Future<void> startWatch(String guardianId) async {
    try {
      await _channel.invokeMethod('startWatch', {'guardianId': guardianId});
    } catch (_) {}
  }

  /// Para a vigilância SOS em 2º plano.
  static Future<void> stopWatch() async {
    try {
      await _channel.invokeMethod('stopWatch');
    } catch (_) {}
  }

  /// Limpa o registro de alarmes (ex.: ao fazer logout).
  static void reset() {
    _alarmedIds.clear();
  }

  /// Verifica se o sistema permite notificações em tela cheia
  /// (necessário para a tela de emergência estilo Defesa Civil abrir
  /// por cima da tela bloqueada). No Android 14+ o usuário precisa
  /// liberar nas configurações — sem isso, o alerta não aparece.
  static Future<bool> canUseFullScreenIntent() async {
    try {
      final ok =
          await _channel.invokeMethod<bool>('canUseFullScreenIntent');
      return ok ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Abre as configurações do sistema para liberar o alerta em tela cheia.
  static Future<void> openFullScreenIntentSettings() async {
    try {
      await _channel.invokeMethod('openFullScreenIntentSettings');
    } catch (_) {}
  }
}
