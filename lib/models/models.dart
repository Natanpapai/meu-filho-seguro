import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Perfil do responsável (pai/mãe).
class Guardian {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String passwordHash;
  final bool isPremium;

  Guardian({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.passwordHash,
    this.isPremium = false,
  });

  factory Guardian.create({
    required String name,
    required String email,
    required String phone,
    required String passwordHash,
  }) {
    return Guardian(
      id: _uuid.v4(),
      name: name,
      email: email,
      phone: phone,
      passwordHash: passwordHash,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'phone': phone,
        'passwordHash': passwordHash,
        'isPremium': isPremium,
      };

  factory Guardian.fromJson(Map<String, dynamic> j) => Guardian(
        id: j['id'],
        name: j['name'],
        email: j['email'],
        phone: j['phone'],
        passwordHash: j['passwordHash'],
        isPremium: j['isPremium'] ?? false,
      );
}

/// Perfil do filho(a).
class Child {
  final String id;
  final String name;
  final String nickname;
  final DateTime birthDate;
  final String? photoPath;
  final String? pairCode;
  final DateTime? pairCodeExpiry;
  final bool paired;

  // Último estado conhecido (atualizado pelo app do filho ou simulação)
  final double? lastLat;
  final double? lastLng;
  final DateTime? lastUpdate;
  final int? batteryLevel;
  final String status; // em_casa | na_escola | a_caminho | desconhecido

  Child({
    required this.id,
    required this.name,
    required this.nickname,
    required this.birthDate,
    this.photoPath,
    this.pairCode,
    this.pairCodeExpiry,
    this.paired = false,
    this.lastLat,
    this.lastLng,
    this.lastUpdate,
    this.batteryLevel,
    this.status = 'desconhecido',
  });

  factory Child.create({
    required String name,
    required String nickname,
    required DateTime birthDate,
    String? photoPath,
  }) {
    return Child(
      id: _uuid.v4(),
      name: name,
      nickname: nickname,
      birthDate: birthDate,
      photoPath: photoPath,
    );
  }

  Child copyWith({
    String? pairCode,
    DateTime? pairCodeExpiry,
    bool? paired,
    double? lastLat,
    double? lastLng,
    DateTime? lastUpdate,
    int? batteryLevel,
    String? status,
    bool clearPairCode = false,
  }) {
    return Child(
      id: id,
      name: name,
      nickname: nickname,
      birthDate: birthDate,
      photoPath: photoPath,
      pairCode: clearPairCode ? null : (pairCode ?? this.pairCode),
      pairCodeExpiry:
          clearPairCode ? null : (pairCodeExpiry ?? this.pairCodeExpiry),
      paired: paired ?? this.paired,
      lastLat: lastLat ?? this.lastLat,
      lastLng: lastLng ?? this.lastLng,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      status: status ?? this.status,
    );
  }

  int get age {
    final now = DateTime.now();
    int a = now.year - birthDate.year;
    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      a--;
    }
    return a;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'nickname': nickname,
        'birthDate': birthDate.toIso8601String(),
        'photoPath': photoPath,
        'pairCode': pairCode,
        'pairCodeExpiry': pairCodeExpiry?.toIso8601String(),
        'paired': paired,
        'lastLat': lastLat,
        'lastLng': lastLng,
        'lastUpdate': lastUpdate?.toIso8601String(),
        'batteryLevel': batteryLevel,
        'status': status,
      };

  factory Child.fromJson(Map<String, dynamic> j) => Child(
        id: j['id'],
        name: j['name'],
        nickname: j['nickname'] ?? '',
        birthDate: DateTime.parse(j['birthDate']),
        photoPath: j['photoPath'],
        pairCode: j['pairCode'],
        pairCodeExpiry: j['pairCodeExpiry'] != null
            ? DateTime.parse(j['pairCodeExpiry'])
            : null,
        paired: j['paired'] ?? false,
        lastLat: (j['lastLat'] as num?)?.toDouble(),
        lastLng: (j['lastLng'] as num?)?.toDouble(),
        lastUpdate: j['lastUpdate'] != null
            ? DateTime.parse(j['lastUpdate'])
            : null,
        batteryLevel: j['batteryLevel'],
        status: j['status'] ?? 'desconhecido',
      );
}

/// Local seguro: casa ou escola, com raio configurável.
class SafePlace {
  final String id;
  final String type; // 'casa' | 'escola'
  final String label;
  final double lat;
  final double lng;
  final double radiusMeters;

  SafePlace({
    required this.id,
    required this.type,
    required this.label,
    required this.lat,
    required this.lng,
    this.radiusMeters = 150,
  });

  factory SafePlace.create({
    required String type,
    required String label,
    required double lat,
    required double lng,
    double radiusMeters = 150,
  }) {
    return SafePlace(
      id: _uuid.v4(),
      type: type,
      label: label,
      lat: lat,
      lng: lng,
      radiusMeters: radiusMeters,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'label': label,
        'lat': lat,
        'lng': lng,
        'radiusMeters': radiusMeters,
      };

  factory SafePlace.fromJson(Map<String, dynamic> j) => SafePlace(
        id: j['id'],
        type: j['type'],
        label: j['label'],
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        radiusMeters: (j['radiusMeters'] as num?)?.toDouble() ?? 150,
      );
}

/// Evento registrado no histórico.
class LocationEvent {
  final String id;
  final String childId;
  final String childName;
  final String type; // chegou_escola | saiu_escola | chegou_casa | saiu_casa | sos | atualizacao
  final DateTime timestamp;
  final double? lat;
  final double? lng;

  LocationEvent({
    required this.id,
    required this.childId,
    required this.childName,
    required this.type,
    required this.timestamp,
    this.lat,
    this.lng,
  });

  factory LocationEvent.create({
    required String childId,
    required String childName,
    required String type,
    double? lat,
    double? lng,
  }) {
    return LocationEvent(
      id: _uuid.v4(),
      childId: childId,
      childName: childName,
      type: type,
      timestamp: DateTime.now(),
      lat: lat,
      lng: lng,
    );
  }

  String get description {
    switch (type) {
      case 'chegou_escola':
        return 'Chegou na escola';
      case 'saiu_escola':
        return 'Saiu da escola';
      case 'chegou_casa':
        return 'Chegou em casa';
      case 'saiu_casa':
        return 'Saiu de casa';
      case 'sos':
        return 'SOS acionado!';
      case 'atualizacao':
        return 'Localização atualizada';
      default:
        return type;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'childId': childId,
        'childName': childName,
        'type': type,
        'timestamp': timestamp.toIso8601String(),
        'lat': lat,
        'lng': lng,
      };

  factory LocationEvent.fromJson(Map<String, dynamic> j) => LocationEvent(
        id: j['id'],
        childId: j['childId'],
        childName: j['childName'] ?? '',
        type: j['type'],
        timestamp: DateTime.parse(j['timestamp']),
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
      );
}
