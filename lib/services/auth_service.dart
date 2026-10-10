import 'dart:convert';
import 'dart:math';
import '../models/models.dart';
import 'storage_service.dart';

/// Cadastro e login do responsável — conta local neste aparelho.
/// REAL: funciona de verdade (os dados ficam no celular).
/// Quando o Firebase for conectado, o login passa a valer nos 2 aparelhos.
class AuthService {
  final StorageService _storage;
  AuthService(this._storage);

  /// Hash simples para não guardar a senha em texto puro.
  /// (Protótipo local — com Firebase, a senha fica no servidor seguro.)
  String _hash(String input) {
    final bytes = utf8.encode('mfs::$input');
    var h1 = 0xdeadbeef, h2 = 0x41c6ce57;
    for (final b in bytes) {
      h1 = (h1 ^ b) * 2654435761 % 4294967296;
      h2 = (h2 ^ b) * 1597334677 % 4294967296;
    }
    return '${h1.toRadixString(16)}${h2.toRadixString(16)}';
  }

  Future<(bool, String?)> register({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    if (_storage.getGuardian() != null) {
      return (false, 'Já existe uma conta neste aparelho.');
    }
    final g = Guardian.create(
      name: name.trim(),
      email: email.trim(),
      phone: phone.trim(),
      passwordHash: _hash(password),
    );
    await _storage.saveGuardian(g);
    await _storage.setRole('guardian');
    return (true, null);
  }

  Future<(bool, String?)> login({
    required String email,
    required String password,
  }) async {
    final g = _storage.getGuardian();
    if (g == null) return (false, 'Nenhuma conta encontrada. Cadastre-se.');
    if (g.email.toLowerCase() != email.trim().toLowerCase() ||
        g.passwordHash != _hash(password)) {
      return (false, 'E-mail ou senha incorretos.');
    }
    await _storage.setRole('guardian');
    return (true, null);
  }

  /// Gera código de vinculação de 6 dígitos (válido por 10 minutos).
  /// O responsável mostra o código; o filho digita no celular dele.
  Future<String> generatePairCode(String childId) async {
    final code = (100000 + Random().nextInt(900000)).toString();
    final children = _storage.getChildren();
    final i = children.indexWhere((c) => c.id == childId);
    if (i < 0) throw StateError('Filho não encontrado');
    children[i] = children[i].copyWith(
      pairCode: code,
      pairCodeExpiry: DateTime.now().add(const Duration(minutes: 10)),
    );
    await _storage.saveChildren(children);
    return code;
  }

  /// Valida o código digitado no celular do filho.
  Future<(bool, String?)> pairWithCode(String code) async {
    final children = _storage.getChildren();
    final now = DateTime.now();
    for (final c in children) {
      if (c.pairCode == code.trim() &&
          c.pairCodeExpiry != null &&
          c.pairCodeExpiry!.isAfter(now)) {
        final updated = c.copyWith(paired: true, clearPairCode: true);
        await _storage.upsertChild(updated);
        await _storage.setRole('child');
        await _storage.setSessionChildId(c.id);
        return (true, null);
      }
    }
    return (false, 'Código inválido ou expirado.');
  }

  Future<void> logout() => _storage.clearSession();
}
