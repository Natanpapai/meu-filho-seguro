import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import 'firebase_service.dart';
import 'sos_alarm_service.dart';
import 'storage_service.dart';
import 'sync_service.dart';
import 'trial_service.dart';

/// Cadastro, login e vinculação do responsável.
///
/// Funciona em dois modos:
/// - LOCAL (sempre disponível): os dados ficam neste aparelho.
/// - FIREBASE (quando disponível): login via Firebase Auth e códigos de
///   vinculação via Firestore, permitindo vincular 2 celulares diferentes.
///
/// O Firebase é uma camada ADICIONAL: se ele falhar ou estiver sem rede,
/// tudo continua funcionando no modo local como antes.
class AuthService {
  final StorageService _storage;
  AuthService(this._storage);

  /// Hash simples para não guardar a senha em texto puro no modo local.
  String _hash(String input) {
    final bytes = utf8.encode('mfs::$input');
    var h1 = 0xdeadbeef, h2 = 0x41c6ce57;
    for (final b in bytes) {
      h1 = (h1 ^ b) * 2654435761 % 4294967296;
      h2 = (h2 ^ b) * 1597334677 % 4294967296;
    }
    return '${h1.toRadixString(16)}${h2.toRadixString(16)}';
  }

  bool get _fb => FirebaseService.available;

  Future<(bool, String?)> register({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    if (_storage.getGuardian() != null) {
      return (false, 'Já existe uma conta neste aparelho.');
    }

    // Tenta criar a conta também no Firebase Auth (login multi-aparelho).
    // Se já existir ou a rede falhar, segue no modo local.
    String? firebaseUid;
    if (_fb) {
      try {
        final cred = await fb_auth.FirebaseAuth.instance
            .createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
        firebaseUid = cred.user?.uid;
        await cred.user?.updateDisplayName(name.trim());
      } on fb_auth.FirebaseAuthException catch (e) {
        // Conta já existe no Firebase: tudo bem, o login vai reutilizá-la.
        debugPrint('[Auth] Firebase register: ${e.code}');
      } catch (e) {
        debugPrint('[Auth] Firebase register falhou, modo local: $e');
      }
    }

    final g = Guardian.create(
      name: name.trim(),
      email: email.trim(),
      phone: phone.trim(),
      passwordHash: _hash(password),
    );
    await _storage.saveGuardian(g);
    await _storage.setRole('guardian');
    // Liga a vigilância SOS em 2º plano (alarme mesmo com tela bloqueada).
    _startSosWatch();
    ensureGuardianLinked();

    // Guarda o perfil do responsável no Firestore para reconstruir
    // o login em outro aparelho se os dados locais forem apagados.
    if (_fb && firebaseUid != null) {
      try {
        await FirebaseService.firestore
            .collection('guardians')
            .doc(firebaseUid)
            .set({
          'name': g.name,
          'email': g.email,
          'phone': g.phone,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('[Auth] salvar perfil no Firestore falhou: $e');
      }
    }

    // v17: amarra a família/responsável ao pedido de teste.
    TrialService.instance.updateRequestFamily(_storage);
    return (true, null);
  }

  /// Atualiza os dados do perfil do responsável (nome e telefone).
  ///
  /// Salva localmente e, se houver login via Firebase Auth, sincroniza
  /// com o documento `guardians/{uid}` no Firestore (merge).
  /// O e-mail não é editável aqui porque é a credencial de login.
  Future<(bool, String?)> updateGuardianProfile({
    required String name,
    required String phone,
  }) async {
    final g = _storage.getGuardian();
    if (g == null) return (false, 'Nenhuma conta encontrada.');
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return (false, 'Informe o nome.');
    final updated = g.copyWith(name: trimmedName, phone: phone.trim());
    await _storage.saveGuardian(updated);
    if (_fb) {
      try {
        final uid = fb_auth.FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          await FirebaseService.firestore
              .collection('guardians')
              .doc(uid)
              .set({
            'name': updated.name,
            'phone': updated.phone,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      } catch (e) {
        debugPrint('[Auth] atualizar perfil no Firestore falhou: $e');
        // O dado local já foi salvo; não falha a operação.
      }
    }
    return (true, null);
  }

  Future<(bool, String?)> login({
    required String email,
    required String password,
  }) async {
    // 1) Tenta o Firebase Auth primeiro (vale nos 2 aparelhos).
    if (_fb) {
      try {
        final cred = await fb_auth.FirebaseAuth.instance
            .signInWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
        final uid = cred.user?.uid;
        // Reconstrói o perfil local a partir do Firestore, se necessário.
        var g = _storage.getGuardian();
        if (g == null && uid != null) {
          g = await _fetchGuardianProfile(uid, email.trim());
          if (g != null) await _storage.saveGuardian(g);
        }
        // CORREÇÃO (v14 — "desloga sozinho"): antes o login retornava
        // sucesso mesmo sem perfil local do responsável (ex.: doc
        // 'guardians/{uid}' apagado/ausente). O app abria "meio logado"
        // — sem vigilância SOS — e no próximo arranque caía na tela de
        // boas-vindas, parecendo logout espontâneo. Agora:
        // - se o Firebase autenticou mas não há perfil em lugar nenhum,
        //   cria um perfil local mínimo a partir do próprio usuário do
        //   Firebase (uid/e-mail/nome) — a sessão fica COMPLETA;
        // - o sucesso só é retornado com perfil válido em mãos.
        if (g == null && uid != null) {
          final fbUser = cred.user;
          g = Guardian.create(
            name: (fbUser?.displayName?.trim().isNotEmpty ?? false)
                ? fbUser!.displayName!.trim()
                : email.trim(),
            email: email.trim(),
            phone: fbUser?.phoneNumber ?? '',
            passwordHash: _hash('__firebase__$uid'),
          );
          await _storage.saveGuardian(g);
          debugPrint(
              '[Auth] perfil local reconstruído a partir do Firebase Auth.');
        }
        if (g == null || g.id.isEmpty) {
          return (false,
              'Login incompleto: não foi possível carregar seu perfil. '
              'Tente de novo.');
        }
        await _storage.setRole('guardian');
        // Liga a vigilância SOS em 2º plano.
        _startSosWatch();
        ensureGuardianLinked();
        // v17: amarra a família/responsável ao pedido de teste.
        TrialService.instance.updateRequestFamily(_storage);
        return (true, null);
      } on fb_auth.FirebaseAuthException catch (e) {
        // Conta não existe no Firebase ou senha errada: tenta o modo local.
        debugPrint('[Auth] Firebase login: ${e.code}, tentando local.');
      } catch (e) {
        debugPrint('[Auth] Firebase login falhou, tentando local: $e');
      }
    }

    // 2) Fallback: login local (comportamento original).
    final g = _storage.getGuardian();
    if (g == null) return (false, 'Nenhuma conta encontrada. Cadastre-se.');
    if (g.email.toLowerCase() != email.trim().toLowerCase() ||
        g.passwordHash != _hash(password)) {
      return (false, 'E-mail ou senha incorretos.');
    }
    await _storage.setRole('guardian');
    // Liga a vigilância SOS em 2º plano.
    _startSosWatch();
    ensureGuardianLinked();
    // v17: amarra a família/responsável ao pedido de teste.
    TrialService.instance.updateRequestFamily(_storage);
    return (true, null);
  }

  /// Envia o e-mail de redefinição de senha do Firebase Auth.
  ///
  /// Retorna (true, null) em caso de sucesso ou (false, mensagem) com
  /// erro amigável em português. O Firebase cuida do resto: o usuário
  /// recebe o e-mail e redefine a senha pelo link.
  Future<(bool, String?)> sendPasswordReset(String email) async {
    final clean = email.trim();
    if (clean.isEmpty || !clean.contains('@')) {
      return (false, 'Informe um e-mail válido.');
    }
    if (!_fb) {
      return (false, 'Sem conexão com a internet. Tente de novo.');
    }
    try {
      await fb_auth.FirebaseAuth.instance.sendPasswordResetEmail(
        email: clean,
      );
      return (true, null);
    } on fb_auth.FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'invalid-email':
          return (false, 'Informe um e-mail válido.');
        case 'user-not-found':
          return (false, 'Não encontramos uma conta com este e-mail.');
        case 'network-request-failed':
          return (false, 'Sem conexão com a internet. Tente de novo.');
        case 'too-many-requests':
          return (false, 'Muitas tentativas. Aguarde um pouco e tente de novo.');
        default:
          debugPrint('[Auth] sendPasswordReset: ${e.code}');
          return (false, 'Não foi possível enviar o e-mail. Tente de novo.');
      }
    } catch (e) {
      debugPrint('[Auth] sendPasswordReset falhou: $e');
      return (false, 'Não foi possível enviar o e-mail. Tente de novo.');
    }
  }

  /// Busca o perfil do responsável no Firestore (para reconstruir o
  /// login local quando o Firebase Auth autentica mas o aparelho não
  /// tem os dados salvos).
  Future<Guardian?> _fetchGuardianProfile(String uid, String email) async {
    try {
      final doc = await FirebaseService.firestore
          .collection('guardians')
          .doc(uid)
          .get();
      final data = doc.data();
      if (data == null) return null;
      return Guardian.create(
        name: (data['name'] as String?) ?? email,
        email: (data['email'] as String?) ?? email,
        phone: (data['phone'] as String?) ?? '',
        // A senha real fica só no Firebase Auth; o hash local não é usado
        // quando o login passa pelo Firebase.
        passwordHash: _hash('__firebase__$uid'),
      );
    } catch (e) {
      debugPrint('[Auth] buscar perfil no Firestore falhou: $e');
      return null;
    }
  }

  /// Gera código de vinculação de 6 dígitos (válido por 10 minutos).
  /// O responsável mostra o código; o filho digita no celular dele.
  ///
  /// O código é salvo no Firestore (coleção 'pair_codes') para funcionar
  /// entre 2 aparelhos diferentes, e também localmente como fallback.
  Future<String> generatePairCode(String childId) async {
    final code = (100000 + Random().nextInt(900000)).toString();
    final children = _storage.getChildren();
    final i = children.indexWhere((c) => c.id == childId);
    if (i < 0) throw StateError('Filho não encontrado');
    final child = children[i];
    final expiry = DateTime.now().add(const Duration(minutes: 10));

    // Salva localmente (fallback / mesmo aparelho).
    children[i] = child.copyWith(
      pairCode: code,
      pairCodeExpiry: expiry,
    );
    await _storage.saveChildren(children);

    // Salva no Firestore para vinculação entre aparelhos.
    if (_fb) {
      try {
        final guardian = _storage.getGuardian();
        await FirebaseService.firestore
            .collection('pair_codes')
            .doc(code)
            .set({
          'childId': child.id,
          'childName': child.name,
          'childNickname': child.nickname,
          'childBirthDate': child.birthDate.toIso8601String(),
          'childGender': child.gender,
          'guardianId': guardian?.id,
          'guardianName': guardian?.name,
          'expiry': Timestamp.fromDate(expiry),
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        // Sem rede: o código local continua valendo neste aparelho.
        debugPrint('[Auth] salvar código no Firestore falhou: $e');
      }
    }

    return code;
  }

  /// Valida o código digitado no celular do filho.
  ///
  /// Primeiro tenta o Firestore (vinculação entre 2 aparelhos); se não
  /// achar ou o Firebase estiver indisponível, usa o armazenamento local
  /// (mesmo aparelho).
  Future<(bool, String?)> pairWithCode(String code) async {
    final clean = code.trim();

    // 1) Tenta o Firestore (cross-device).
    if (_fb) {
      try {
        final doc = await FirebaseService.firestore
            .collection('pair_codes')
            .doc(clean)
            .get();
        final data = doc.data();
        if (data != null) {
          final expiry = (data['expiry'] as Timestamp?)?.toDate();
          if (expiry != null && expiry.isAfter(DateTime.now())) {
            // Código válido: cria o perfil do filho neste aparelho.
            final child = Child(
              id: (data['childId'] as String?) ?? clean,
              name: (data['childName'] as String?) ?? 'Filho(a)',
              nickname: (data['childNickname'] as String?) ?? '',
              birthDate: DateTime.tryParse(
                      (data['childBirthDate'] as String?) ?? '') ??
                  DateTime.now(),
              gender: (data['childGender'] as String?) ?? 'boy',
              paired: true,
            );
            await _storage.upsertChild(child);
            await _storage.setRole('child');
            await _storage.setSessionChildId(child.id);
            // Guarda o id do responsável neste aparelho para que o SOS
            // e a localização periódica cheguem ao responsável certo.
            final gid = data['guardianId'] as String?;
            if (gid != null && gid.isNotEmpty) {
              await _storage.setGuardianId(gid);
              await _storage.setGuardianIds([gid]);
            }
            // Registra este responsável na lista de vinculados do filho
            // (multi-responsável: pai e mãe recebem tudo).
            if (gid != null && gid.isNotEmpty) {
              await RemoteSync.addGuardianToChild(child.id, gid);
            }
            // Uso único: apaga o código para não ser reutilizado.
            await doc.reference.delete();
            // v17: amarra a família ao pedido de teste (celular do filho).
            TrialService.instance.updateRequestFamily(_storage);
            return (true, null);
          } else {
            // Código expirado no Firestore: apaga e informa.
            try {
              await doc.reference.delete();
            } catch (_) {}
            return (false, 'Código inválido ou expirado.');
          }
        }
        // Não achou no Firestore: pode ser código local (offline).
      } catch (e) {
        debugPrint('[Auth] buscar código no Firestore falhou: $e');
      }
    }

    // 2) Fallback local (mesmo aparelho).
    final children = _storage.getChildren();
    final now = DateTime.now();
    for (final c in children) {
      if (c.pairCode == clean &&
          c.pairCodeExpiry != null &&
          c.pairCodeExpiry!.isAfter(now)) {
        final updated = c.copyWith(paired: true, clearPairCode: true);
        await _storage.upsertChild(updated);
        await _storage.setRole('child');
        await _storage.setSessionChildId(c.id);
        // v17: amarra a família ao pedido de teste (pareamento local).
        TrialService.instance.updateRequestFamily(_storage);
        return (true, null);
      }
    }
    return (false, 'Código inválido ou expirado.');
  }

  /// Vincula um SEGUNDO responsável ao mesmo filho (ex.: a mãe, quando
  /// o pai já vinculou).
  ///
  /// O segundo responsável digita um código gerado pelo primeiro
  /// responsável (mesmo fluxo de "Gerar código"). Em vez de criar um
  /// perfil de filho, este método:
  /// 1. adiciona o responsável à lista `child_guardians/{childId}`;
  /// 2. cria o perfil do filho localmente neste aparelho (para ver
  ///    localização e receber SOS);
  /// 3. apaga o código (uso único).
  Future<(bool, String?)> pairGuardianWithCode(String code) async {
    final myGuardian = _storage.getGuardian();
    if (myGuardian == null || myGuardian.id.isEmpty) {
      return (false, 'Faça login como responsável primeiro.');
    }
    if (!_fb) {
      return (false, 'Sem conexão. Ative a internet para vincular.');
    }
    final clean = code.trim();
    try {
      final doc = await FirebaseService.firestore
          .collection('pair_codes')
          .doc(clean)
          .get();
      final data = doc.data();
      if (data == null) {
        return (false, 'Código inválido ou expirado.');
      }
      final expiry = (data['expiry'] as Timestamp?)?.toDate();
      if (expiry == null || !expiry.isAfter(DateTime.now())) {
        try {
          await doc.reference.delete();
        } catch (_) {}
        return (false, 'Código inválido ou expirado.');
      }
      final childId = (data['childId'] as String?) ?? clean;
      // 1) Entra na lista de responsáveis do filho.
      await RemoteSync.addGuardianToChild(childId, myGuardian.id);
      // 2) Cria o perfil do filho neste aparelho.
      final child = Child(
        id: childId,
        name: (data['childName'] as String?) ?? 'Filho(a)',
        nickname: (data['childNickname'] as String?) ?? '',
        birthDate:
            DateTime.tryParse((data['childBirthDate'] as String?) ?? '') ??
                DateTime.now(),
        paired: true,
      );
      await _storage.upsertChild(child);
      await _storage.setRole('guardian');
      // Liga a vigilância SOS em 2º plano para este responsável também
      // (alarme mesmo com app fechado/tela bloqueada).
      _startSosWatch();
      ensureGuardianLinked();
      // 3) Uso único.
      await doc.reference.delete();
      // v17: amarra a família ao pedido de teste (2º responsável).
      TrialService.instance.updateRequestFamily(_storage);
      return (true, null);
    } catch (e) {
      debugPrint('[Auth] vincular 2º responsável falhou: $e');
      return (false, 'Não foi possível vincular. Tente de novo.');
    }
  }

  Future<void> logout() async {
    // Para a vigilância SOS em 2º plano e o som do alarme.
    try {
      await SosAlarmService.stopWatch();
    } catch (_) {}
    SosAlarmService.reset();
    // Limpa o cache de streams do Firestore (evita vazar dados
    // da conta anterior e força nova assinatura no próximo login).
    RemoteSync.clearStreamCache();
    // Desloga do Firebase Auth também, se estiver disponível.
    if (_fb) {
      try {
        await fb_auth.FirebaseAuth.instance.signOut();
      } catch (_) {}
    }
    return _storage.clearSession();
  }

  /// Liga a vigilância SOS nativa (alarme mesmo com tela bloqueada).
  void _startSosWatch() {
    final g = _storage.getGuardian();
    if (g != null && g.id.isNotEmpty) {
      SosAlarmService.startWatch(g.id);
    }
  }

  /// Garante que o ID ATUAL deste responsável esteja na lista de
  /// vinculados de cada filho conhecido (`child_guardians/{childId}`).
  ///
  /// Por que: o ID local do responsável pode mudar (ex.: reinstalou o
  /// app e o login reconstruiu o perfil com um ID novo), mas o
  /// Firestore guardava o ID antigo — o SOS do filho ia endereçado ao
  /// ID antigo e este aparelho nunca recebia o alerta (só o outro
  /// responsável recebia). O `arrayUnion` é idempotente: chamar sempre
  /// é seguro e barato.
  Future<void> ensureGuardianLinked() async {
    if (!_fb) return;
    final g = _storage.getGuardian();
    if (g == null || g.id.isEmpty) return;
    for (final c in _storage.getChildren()) {
      try {
        await RemoteSync.addGuardianToChild(c.id, g.id);
      } catch (_) {}
    }
  }
}
