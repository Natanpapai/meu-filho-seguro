import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../models/safety_models.dart';

/// Armazenamento local (no próprio celular).
/// REAL: funciona de verdade neste aparelho.
/// PROTÓTIPO: a sincronização entre os 2 celulares virá com o Firebase.
class StorageService {
  static const _kGuardian = 'mfs_guardian';
  static const _kChildren = 'mfs_children';
  static const _kPlaces = 'mfs_places';
  static const _kEvents = 'mfs_events';
  static const _kSessionChildId = 'mfs_session_child_id';
  static const _kRole = 'mfs_role'; // 'guardian' | 'child'
  static const _kGuardianId =
      'mfs_guardian_id'; // id do responsável (para o celular do filho)

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ---- Sessão / papel ----
  /// Notifica mudanças de sessão (login, cadastro, vinculação, logout).
  /// O monitor global de SOS ([SosMonitor]) escuta este notificador para
  /// começar a vigiar assim que o responsável entra — mesmo que o login
  /// aconteça depois do app já estar aberto (nesse caso o `builder` do
  /// MaterialApp não é reconstruído sozinho).
  final ValueNotifier<int> authTick = ValueNotifier<int>(0);

  void _bumpAuth() => authTick.value++;

  Future<void> setRole(String role) {
    _bumpAuth();
    return _prefs.setString(_kRole, role);
  }
  String? getRole() => _prefs.getString(_kRole);
  Future<void> setSessionChildId(String id) =>
      _prefs.setString(_kSessionChildId, id);
  String? getSessionChildId() => _prefs.getString(_kSessionChildId);

  /// ID do responsável, salvo no celular do filho no momento da
  /// vinculação. Usado para enviar SOS e localização ao Firestore
  /// endereçados ao responsável certo.
  Future<void> setGuardianId(String id) =>
      _prefs.setString(_kGuardianId, id);
  String? getGuardianId() => _prefs.getString(_kGuardianId);
  Future<void> clearSession() async {
    await _prefs.remove(_kRole);
    await _prefs.remove(_kSessionChildId);
    _bumpAuth();
  }

  // ---- Responsável ----
  Future<void> saveGuardian(Guardian g) {
    _bumpAuth();
    return _prefs.setString(_kGuardian, jsonEncode(g.toJson()));
  }
  Guardian? getGuardian() {
    final raw = _prefs.getString(_kGuardian);
    if (raw == null) return null;
    return Guardian.fromJson(jsonDecode(raw));
  }

  // ---- Filhos ----
  Future<void> saveChildren(List<Child> children) => _prefs.setString(
      _kChildren, jsonEncode(children.map((c) => c.toJson()).toList()));
  List<Child> getChildren() {
    final raw = _prefs.getString(_kChildren);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => Child.fromJson(e)).toList();
  }

  Future<void> upsertChild(Child child) async {
    final children = getChildren();
    final i = children.indexWhere((c) => c.id == child.id);
    if (i >= 0) {
      children[i] = child;
    } else {
      children.add(child);
    }
    await saveChildren(children);
  }

  Future<void> removeChild(String id) async {
    final children = getChildren()..removeWhere((c) => c.id == id);
    await saveChildren(children);
  }

  // ---- Locais ----
  Future<void> savePlaces(List<SafePlace> places) => _prefs.setString(
      _kPlaces, jsonEncode(places.map((p) => p.toJson()).toList()));
  List<SafePlace> getPlaces() {
    final raw = _prefs.getString(_kPlaces);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => SafePlace.fromJson(e)).toList();
  }

  // ---- Eventos ----
  Future<void> addEvent(LocationEvent e) async {
    final events = getEvents()..insert(0, e);
    // mantém no máximo 500 eventos
    final trimmed = events.take(500).toList();
    await _prefs.setString(
        _kEvents, jsonEncode(trimmed.map((x) => x.toJson()).toList()));
  }

  List<LocationEvent> getEvents() {
    final raw = _prefs.getString(_kEvents);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => LocationEvent.fromJson(e)).toList();
  }

  List<LocationEvent> getEventsForChild(String childId) =>
      getEvents().where((e) => e.childId == childId).toList();

  // ---- Acesso genérico (chaves cruas) ----
  // Usado por funcionalidades novas (rota, modo escola, etc.) sem
  // precisar de método dedicado para cada chave.
  String? getRaw(String key) => _prefs.getString(key);
  Future<void> setRaw(String key, String value) =>
      _prefs.setString(key, value);
  Future<void> removeRaw(String key) => _prefs.remove(key);

  // ---- IDs dos responsáveis (multi-responsável) ----
  // No celular do filho: lista de todos os responsáveis vinculados,
  // usada para endereçar SOS e localização a pai e mãe.
  static const _kGuardianIds = 'mfs_guardian_ids';
  List<String> getGuardianIds() {
    final raw = _prefs.getString(_kGuardianIds);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List).map((e) => e.toString()).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> setGuardianIds(List<String> ids) =>
      _prefs.setString(_kGuardianIds, jsonEncode(ids));

  // ---- Modo Escola ----
  static const _kSchoolMode = 'mfs_school_mode';
  SchoolModeSettings getSchoolMode() {
    final raw = _prefs.getString(_kSchoolMode);
    if (raw == null || raw.isEmpty) return const SchoolModeSettings();
    try {
      return SchoolModeSettings.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const SchoolModeSettings();
    }
  }

  Future<void> setSchoolMode(SchoolModeSettings s) =>
      _prefs.setString(_kSchoolMode, jsonEncode(s.toJson()));
}
