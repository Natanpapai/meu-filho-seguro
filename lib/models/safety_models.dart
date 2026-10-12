// Modelos das funcionalidades de segurança avançada.
// Arquivo separado de models.dart para não conflitar com outras
// edições em andamento naquele arquivo.
import 'package:cloud_firestore/cloud_firestore.dart';

/// Converte o campo 'timestamp' do Firestore para [DateTime].
///
/// CORREÇÃO (v14): antes este parse tentava `DateTime.parse()` no
/// `toString()` de um `Timestamp` do Firestore
/// ("Timestamp(seconds=..., nanoseconds=...)"), o que SEMPRE falhava —
/// o timestamp vinha nulo e os pontos do trajeto eram descartados,
/// deixando o histórico do dia permanentemente vazio.
DateTime? parseFirestoreTimestamp(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  if (raw is Timestamp) return raw.toDate();
  try {
    return DateTime.parse(raw.toString());
  } catch (_) {
    return null;
  }
}

/// Ponto geográfico simples (latitude/longitude).
class RoutePoint {
  final double lat;
  final double lng;

  const RoutePoint(this.lat, this.lng);

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};

  factory RoutePoint.fromJson(Map<String, dynamic> j) => RoutePoint(
        (j['lat'] as num).toDouble(),
        (j['lng'] as num).toDouble(),
      );
}

/// Rota segura de um filho (ex.: caminho casa -> escola).
/// Se o filho se afastar mais de 200m da linha, o responsável é alertado.
class SafeRoute {
  final String childId;
  final String label;
  final List<RoutePoint> points;
  final DateTime? updatedAt;

  SafeRoute({
    required this.childId,
    required this.label,
    required this.points,
    this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'childId': childId,
        'label': label,
        'points': points.map((p) => p.toJson()).toList(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  factory SafeRoute.fromJson(Map<String, dynamic> j) => SafeRoute(
        childId: (j['childId'] as String?) ?? '',
        label: (j['label'] as String?) ?? 'Rota',
        points: ((j['points'] as List?) ?? const [])
            .map((e) => RoutePoint.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        updatedAt: j['updatedAt'] != null
            ? DateTime.tryParse(j['updatedAt'].toString())
            : null,
      );
}

/// Configuração do Modo Escola: durante o horário escolar o app
/// suprime alertas de rotina (geofence), mas o SOS continua ativo.
class SchoolModeSettings {
  final bool enabled;
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;
  final List<int> days; // DateTime.monday (1) .. DateTime.sunday (7)

  const SchoolModeSettings({
    this.enabled = false,
    this.startHour = 7,
    this.startMinute = 0,
    this.endHour = 12,
    this.endMinute = 0,
    this.days = const [1, 2, 3, 4, 5],
  });

  /// true se agora é horário escolar (para suprimir alertas de rotina).
  bool isActiveNow() {
    if (!enabled) return false;
    final now = DateTime.now();
    if (!days.contains(now.weekday)) return false;
    final start = now.hour * 60 + now.minute;
    final from = startHour * 60 + startMinute;
    final to = endHour * 60 + endMinute;
    return start >= from && start < to;
  }

  String get scheduleLabel {
    final s =
        '${startHour.toString().padLeft(2, '0')}:${startMinute.toString().padLeft(2, '0')}';
    final e =
        '${endHour.toString().padLeft(2, '0')}:${endMinute.toString().padLeft(2, '0')}';
    return '$s às $e';
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'startHour': startHour,
        'startMinute': startMinute,
        'endHour': endHour,
        'endMinute': endMinute,
        'days': days,
      };

  factory SchoolModeSettings.fromJson(Map<String, dynamic> j) =>
      SchoolModeSettings(
        enabled: (j['enabled'] as bool?) ?? false,
        startHour: (j['startHour'] as num?)?.toInt() ?? 7,
        startMinute: (j['startMinute'] as num?)?.toInt() ?? 0,
        endHour: (j['endHour'] as num?)?.toInt() ?? 12,
        endMinute: (j['endMinute'] as num?)?.toInt() ?? 0,
        days: ((j['days'] as List?) ?? const [1, 2, 3, 4, 5])
            .map((d) => (d as num).toInt())
            .toList(),
      );

  SchoolModeSettings copyWith({
    bool? enabled,
    int? startHour,
    int? startMinute,
    int? endHour,
    int? endMinute,
    List<int>? days,
  }) =>
      SchoolModeSettings(
        enabled: enabled ?? this.enabled,
        startHour: startHour ?? this.startHour,
        startMinute: startMinute ?? this.startMinute,
        endHour: endHour ?? this.endHour,
        endMinute: endMinute ?? this.endMinute,
        days: days ?? this.days,
      );
}

/// Alerta de saída da rota segura (Firestore: coleção 'route_alerts').
class RouteAlert {
  final String id;
  final String childId;
  final String childName;
  final List<String> guardianIds;
  final double? lat;
  final double? lng;
  final double? distanceMeters;
  final DateTime? timestamp;
  final bool ack;

  RouteAlert({
    required this.id,
    required this.childId,
    required this.childName,
    required this.guardianIds,
    this.lat,
    this.lng,
    this.distanceMeters,
    this.timestamp,
    this.ack = false,
  });

  factory RouteAlert.fromMap(String id, Map<String, dynamic> m) {
    final ts = parseFirestoreTimestamp(m['timestamp']);
    final gids = m['guardianIds'];
    return RouteAlert(
      id: id,
      childId: (m['childId'] as String?) ?? '',
      childName: (m['childName'] as String?) ?? '',
      guardianIds: gids is List
          ? gids.map((g) => g.toString()).toList()
          : const [],
      lat: (m['lat'] as num?)?.toDouble(),
      lng: (m['lng'] as num?)?.toDouble(),
      distanceMeters: (m['distanceMeters'] as num?)?.toDouble(),
      timestamp: ts,
      ack: (m['ack'] as bool?) ?? false,
    );
  }
}

/// Ponto do histórico do dia (trajeto).
class HistoryPoint {
  final double lat;
  final double lng;
  final DateTime? timestamp;
  final int? battery;

  HistoryPoint({required this.lat, required this.lng, this.timestamp, this.battery});

  factory HistoryPoint.fromMap(Map<String, dynamic> m) {
    return HistoryPoint(
      lat: (m['lat'] as num?)?.toDouble() ?? 0,
      lng: (m['lng'] as num?)?.toDouble() ?? 0,
      timestamp: parseFirestoreTimestamp(m['timestamp']),
      battery: (m['battery'] as num?)?.toInt(),
    );
  }
}

/// Wrapper do SosAlert com o flag de pânico silencioso.
/// (Evita editar models.dart, que está sendo editado em paralelo.)
class SosAlertInfo {
  final String id;
  final String childId;
  final String childName;
  final double? lat;
  final double? lng;
  final DateTime? timestamp;
  final bool ack;
  final bool silent;

  SosAlertInfo({
    required this.id,
    required this.childId,
    required this.childName,
    this.lat,
    this.lng,
    this.timestamp,
    this.ack = false,
    this.silent = false,
  });
}
