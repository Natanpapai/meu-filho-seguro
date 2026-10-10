import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/models.dart';

/// Serviço de alarme SOS para o responsável.
///
/// Quando um alerta SOS chega (via Firestore), este serviço:
/// 1. Toca um alarme alto em loop usando o canal de ALARME do Android
///    (AudioAttributes.USAGE_ALARM) — fura o modo silencioso e o
///    "Não perturbe" (alarmes são exceção padrão do DND).
/// 2. Mostra uma notificação full-screen que aparece mesmo com a
///    tela bloqueada (fullScreenIntent + categoria alarm).
///
/// O som para quando o responsável marca o alerta como visto ou
/// toca na notificação.
class SosAlarmService {
  static const _channel = MethodChannel('com.meufilhoseguro.app/sos_alarm');
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  /// IDs de alertas que já dispararam o alarme (evita repetir).
  static final Set<String> _alarmedIds = {};

  /// Inicializa o plugin de notificações. Chamar uma vez no main().
  static Future<void> init() async {
    if (_initialized) return;
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Canal de alta prioridade para o alarme SOS.
    const channel = AndroidNotificationChannel(
      'sos_alarm_channel_v1',
      'Alerta SOS',
      description: 'Alarme de emergência quando o filho aciona o SOS',
      importance: Importance.max,
      playSound: false, // o som é tocado via MethodChannel (canal ALARME)
      enableVibration: true,
    );
    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _initialized = true;
  }

  /// Dispara o alarme para um alerta SOS (som + popup full-screen).
  /// Só dispara uma vez por alerta.
  static Future<void> triggerAlarm(SosAlert alert) async {
    if (_alarmedIds.contains(alert.id)) return;
    _alarmedIds.add(alert.id);

    // 1. Som do alarme (canal ALARME do Android — fura silencioso/DND).
    try {
      await _channel.invokeMethod('playAlarm');
    } catch (_) {
      // Sem o código nativo, segue só com a notificação.
    }

    // 2. Notificação full-screen (aparece até com a tela bloqueada).
    const androidDetails = AndroidNotificationDetails(
      'sos_alarm_channel_v1',
      'Alerta SOS',
      channelDescription: 'Alarme de emergência quando o filho aciona o SOS',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      visibility: NotificationVisibility.public,
      enableVibration: true,
      playSound: false,
      ongoing: true,
      autoCancel: false,
    );
    const details = NotificationDetails(android: androidDetails);
    await _notifications.show(
      alert.id.hashCode,
      '🆘 SOS ACIONADO!',
      '${alert.childName} precisa de ajuda agora!',
      details,
      payload: 'sos:${alert.id}',
    );
  }

  /// Para o som do alarme e remove a notificação.
  static Future<void> stopAlarm([String? alertId]) async {
    try {
      await _channel.invokeMethod('stopAlarm');
    } catch (_) {}
    if (alertId != null) {
      await _notifications.cancel(alertId.hashCode);
    } else {
      await _notifications.cancelAll();
    }
  }

  /// Limpa o registro de alarmes (ex.: ao fazer logout).
  static void reset() {
    _alarmedIds.clear();
  }

  static void _onNotificationTap(NotificationResponse response) {
    // Ao tocar na notificação, para o som. O app abre na tela do SOS
    // pelo payload (tratado na tela inicial do responsável).
    stopAlarm();
  }
}
