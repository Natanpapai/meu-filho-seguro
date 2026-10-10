import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/storage_service.dart';

class AppDeps {
  final StorageService storage;
  late final AuthService auth;
  final LocationService location = LocationService();

  AppDeps(this.storage) {
    auth = AuthService(storage);
  }
}

/// Lógica de geofencing: detecta entrada/saída de casa e escola
/// e registra os eventos no histórico.
class Geofence {
  static Future<String> checkTransitions({
    required Child child,
    required double lat,
    required double lng,
    required List<SafePlace> places,
    required StorageService storage,
  }) async {
    String newStatus = 'a_caminho';
    for (final p in places) {
      final d = LocationService.distanceMeters(lat, lng, p.lat, p.lng);
      if (d <= p.radiusMeters) {
        newStatus = p.type == 'casa' ? 'em_casa' : 'na_escola';
        break;
      }
    }

    final oldStatus = child.status;
    if (newStatus != oldStatus) {
      String? eventType;
      if (newStatus == 'na_escola') {
        eventType = 'chegou_escola';
      } else if (newStatus == 'em_casa') {
        eventType = 'chegou_casa';
      } else if (oldStatus == 'na_escola') {
        eventType = 'saiu_escola';
      } else if (oldStatus == 'em_casa') {
        eventType = 'saiu_casa';
      }
      if (eventType != null) {
        await storage.addEvent(LocationEvent.create(
          childId: child.id,
          childName: child.name,
          type: eventType,
          lat: lat,
          lng: lng,
        ));
      }
    }
    return newStatus;
  }
}
