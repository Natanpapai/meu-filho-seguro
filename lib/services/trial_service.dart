import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'firebase_service.dart';
import 'storage_service.dart';

/// Estado do trial (v17 — aprovação manual pelo dono).
enum TrialStatus {
  /// Ainda verificando a situação inicial.
  checking,

  /// Aparelho sem pedido: mostra a tela de solicitação.
  noRequest,

  /// Pedido enviado, aguardando liberação do dono.
  pendingApproval,

  /// Trial ativo (7 dias contando da aprovação).
  active,

  /// 7 dias esgotados.
  expired,

  /// Dono bloqueou/revogou o acesso.
  blocked,
}

/// Controle do trial de 7 dias — validação com aprovação manual.
///
/// FLUXO:
/// 1. Primeiro uso → tela "Solicitar 7 dias de teste" (nome + WhatsApp).
///    O app gera um número sequencial (#001, #002...) via transação num
///    contador do Firestore e grava o pedido em `trial_requests/{numero}`
///    com status `pending`.
/// 2. O testador envia o pedido ao dono pelo WhatsApp (botão com mensagem
///    pronta).
/// 3. O dono libera na ÁREA DO DONO (tela oculta, PIN) → status `active`,
///    `trial_start` = server timestamp da aprovação. Os 7 dias contam daí.
/// 4. O app do testador escuta o documento em tempo real: aprovado libera,
///    expirado/bloqueado mostra a tela de bloqueio com "QUERO COMPRAR".
///
/// ANTI-BURLA:
/// - O pedido amarra número do teste + aparelho (ANDROID_ID, que sobrevive
///   à reinstalação) + WhatsApp + família/responsável (vinculados após
///   login/pareamento). Reinstalar gera um NOVO pedido, mas o dono vê o
///   alerta "pedido duplicado do mesmo aparelho/WhatsApp" na lista.
/// - O início efetivo nunca anda para frente (mais antigo vence).
/// - Anti-relógio: o "agora" do cálculo nunca anda para trás.
///
/// A ÁREA DO DONO não entra no trial (sempre acessível com o PIN).
class TrialService {
  /// Duração do trial em dias, contados da APROVAÇÃO.
  static const int trialDays = 7;

  /// PIN da área do dono.
  /// ←←← O DONO TROCA O PIN AQUI (é só mudar os 4 dígitos). ←←←
  static const String ownerPin = '1289';

  /// WhatsApp do dono (somente dígitos, com código do país).
  static const String ownerWhatsapp = '5521969584287';

  static const String _requestsCol = 'trial_requests';
  static const String _counterDoc = 'counters/trial_requests';

  static const String _kRequestNumber = 'mfs_trial_request_number';
  static const String _kLastSeen = 'mfs_trial_last_seen';
  static const String _kDeviceId = 'mfs_trial_device_id';

  static final TrialService instance = TrialService._();
  TrialService._();

  /// Estado atual (ouvido pela UI).
  final ValueNotifier<TrialStatus> status =
      ValueNotifier<TrialStatus>(TrialStatus.checking);

  /// Dias restantes quando ativo.
  final ValueNotifier<int> daysLeft = ValueNotifier<int>(trialDays);

  /// Número do pedido deste aparelho (null = sem pedido).
  final ValueNotifier<int?> requestNumber = ValueNotifier<int?>(null);

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  Map<String, dynamic>? _lastData;
  String? _deviceId;
  DateTime? _trialStartUtc;

  // ------------------------------------------------------------------
  // Lógica pura (testável)
  // ------------------------------------------------------------------

  static int daysRemainingFor({
    required DateTime trialStartUtc,
    required DateTime nowUtc,
    int days = trialDays,
  }) {
    return days - nowUtc.difference(trialStartUtc).inDays;
  }

  static TrialStatus statusFor(int daysRemaining) =>
      daysRemaining <= 0 ? TrialStatus.expired : TrialStatus.active;

  /// Número de exibição: 14 → "#014".
  static String displayNumber(int n) =>
      '#${n.toString().padLeft(3, '0')}';

  /// Id do documento: 14 → "0014" (ordena lexicograficamente).
  static String docIdFor(int n) => n.toString().padLeft(4, '0');

  /// Só dígitos do WhatsApp (para comparação de duplicados).
  static String digitsOnly(String raw) =>
      raw.replaceAll(RegExp(r'\D'), '');

  // ------------------------------------------------------------------
  // Inicialização
  // ------------------------------------------------------------------

  Future<void> init(StorageService storage) async {
    try {
      _deviceId = await _resolveDeviceId();
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_kRequestNumber);
      if (saved != null && FirebaseService.available) {
        requestNumber.value = saved;
        _attachListener(saved);
        status.value = TrialStatus.checking; // o listener define o resto
      } else {
        status.value = TrialStatus.noRequest;
      }
      await _touchLastSeen(prefs);
    } catch (e) {
      debugPrint('[Trial] init falhou: $e');
      status.value = TrialStatus.noRequest;
    }
  }

  /// Recalcula expiração com o "agora" (ex.: app ficou aberto virando o dia).
  Future<void> refresh() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await _touchLastSeen(prefs);
      _recomputeFromLastData();
    } catch (e) {
      debugPrint('[Trial] refresh falhou: $e');
    }
  }

  void dispose() {
    _sub?.cancel();
  }

  // ------------------------------------------------------------------
  // Pedido de teste (testador)
  // ------------------------------------------------------------------

  /// Cria o pedido de teste: número sequencial (transação, sem duplicar)
  /// + documento `trial_requests/{numero}` com status `pending`.
  /// Retorna o número gerado. Lança em caso de erro (ex.: sem internet).
  Future<int> requestTrial({
    required String name,
    required String whatsapp,
  }) async {
    if (!FirebaseService.available) {
      throw StateError('Sem conexão com a internet. Tente de novo.');
    }
    final cleanName = name.trim();
    final cleanZap = whatsapp.trim();
    if (cleanName.isEmpty || digitsOnly(cleanZap).length < 10) {
      throw ArgumentError('Informe nome e WhatsApp válidos.');
    }
    final fs = FirebaseService.firestore;
    final deviceId = _deviceId ?? await _resolveDeviceId() ?? 'unknown';

    // 1) Número sequencial (transação: dois aparelhos nunca pegam o mesmo).
    final counterRef = fs.doc(_counterDoc);
    final number = await fs.runTransaction<int>((tx) async {
      final snap = await tx.get(counterRef);
      final next = (snap.data()?['next'] as int?) ?? 1;
      tx.set(counterRef, {'next': next + 1}, SetOptions(merge: true));
      return next;
    }).timeout(const Duration(seconds: 15));

    // 2) Detecta duplicados (mesmo aparelho ou mesmo WhatsApp).
    final prevCount =
        await _countPreviousRequests(deviceId, digitsOnly(cleanZap));

    // 3) Cria o pedido.
    final docId = docIdFor(number);
    await fs.collection(_requestsCol).doc(docId).set({
      'number': number,
      'name': cleanName,
      'whatsapp': cleanZap,
      'whatsapp_digits': digitsOnly(cleanZap),
      'device_id': deviceId,
      'status': 'pending',
      'previous_requests': prevCount,
      'duplicate': prevCount > 0,
      'created_at': FieldValue.serverTimestamp(),
      'platform': 'android',
    }).timeout(const Duration(seconds: 15));

    // 4) Persiste local e passa a escutar.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kRequestNumber, number);
    requestNumber.value = number;
    _attachListener(number);
    return number;
  }

  /// Mensagem pronta do WhatsApp para enviar o pedido ao dono.
  static String whatsappRequestUrl({
    required String name,
    required int number,
  }) {
    final msg =
        'Olá! Sou $name, quero testar o Meu Filho Seguro. '
        'Meu número de teste é ${displayNumber(number)}, pode liberar?';
    return 'https://wa.me/$ownerWhatsapp?text=${Uri.encodeComponent(msg)}';
  }

  /// URL do botão "QUERO COMPRAR" (tela de bloqueio).
  static String get whatsappBuyUrl {
    const msg = 'Olá! Testei o Meu Filho Seguro por 7 dias e quero comprar!';
    return 'https://wa.me/$ownerWhatsapp?text=${Uri.encodeComponent(msg)}';
  }

  /// Vincula família/responsável ao pedido (chamado após login, cadastro
  /// ou pareamento — quando essas identidades passam a existir).
  Future<void> updateRequestFamily(StorageService storage) async {
    final number = requestNumber.value;
    if (number == null || !FirebaseService.available) return;
    try {
      final keys = _familyKeys(storage);
      if (keys.isEmpty) return;
      await FirebaseService.firestore
          .collection(_requestsCol)
          .doc(docIdFor(number))
          .set({'family_keys': keys}, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));
      debugPrint('[Trial] família vinculada ao pedido ${displayNumber(number)}.');
    } catch (e) {
      debugPrint('[Trial] updateRequestFamily falhou: $e');
    }
  }

  // ------------------------------------------------------------------
  // Escuta em tempo real (testador)
  // ------------------------------------------------------------------

  void _attachListener(int number) {
    _sub?.cancel();
    _sub = FirebaseService.firestore
        .collection(_requestsCol)
        .doc(docIdFor(number))
        .snapshots()
        .listen(_handleDoc, onError: (Object e) {
      debugPrint('[Trial] listener falhou: $e');
    });
  }

  void _handleDoc(DocumentSnapshot<Map<String, dynamic>> snap) {
    _lastData = snap.data();
    _recomputeFromLastData();
  }

  void _recomputeFromLastData() {
    _recomputeFromLastDataAsync();
  }

  Future<void> _recomputeFromLastDataAsync() async {
    final data = _lastData;
    if (data == null) {
      // Documento sumiu (dono apagou?) → trata como bloqueado.
      status.value = TrialStatus.blocked;
      return;
    }
    final st = (data['status'] as String?) ?? 'pending';
    switch (st) {
      case 'pending':
        status.value = TrialStatus.pendingApproval;
        break;
      case 'blocked':
        status.value = TrialStatus.blocked;
        break;
      case 'expired':
        status.value = TrialStatus.expired;
        break;
      case 'active':
        final ts = data['trial_start'];
        if (ts is Timestamp) {
          _trialStartUtc = ts.toDate().toUtc();
          final left = daysRemainingFor(
            trialStartUtc: _trialStartUtc!,
            nowUtc: await _effectiveNow(),
          );
          daysLeft.value = left;
          status.value = statusFor(left);
          debugPrint('[Trial] ativo, restantes=$left');
        } else {
          status.value = TrialStatus.pendingApproval;
        }
        break;
      default:
        status.value = TrialStatus.pendingApproval;
    }
  }

  // ------------------------------------------------------------------
  // Área do dono (protegida por PIN na UI)
  // ------------------------------------------------------------------

  bool checkPin(String pin) => pin == ownerPin;

  /// Stream de todos os pedidos (mais recentes primeiro) para a área do dono.
  static Stream<QuerySnapshot<Map<String, dynamic>>> watchRequests() {
    return FirebaseService.firestore
        .collection(_requestsCol)
        .orderBy('number', descending: true)
        .snapshots();
  }

  /// Libera o pedido: status=active, trial_start = agora (servidor).
  /// Os 7 dias contam a partir daqui.
  Future<void> approveRequest(int number) async {
    await FirebaseService.firestore
        .collection(_requestsCol)
        .doc(docIdFor(number))
        .update({
      'status': 'active',
      'approved_at': FieldValue.serverTimestamp(),
      'trial_start': FieldValue.serverTimestamp(),
    }).timeout(const Duration(seconds: 15));
    debugPrint('[Trial] pedido ${displayNumber(number)} LIBERADO.');
  }

  /// Bloqueia/revoga o acesso do pedido.
  Future<void> blockRequest(int number, {String reason = ''}) async {
    await FirebaseService.firestore
        .collection(_requestsCol)
        .doc(docIdFor(number))
        .update({
      'status': 'blocked',
      'blocked_at': FieldValue.serverTimestamp(),
      'block_reason': reason,
    }).timeout(const Duration(seconds: 15));
    debugPrint('[Trial] pedido ${displayNumber(number)} BLOQUEADO.');
  }

  /// Marca como expirado (chamado pela área do dono ao listar um ativo
  /// cujo prazo já passou — mantém o servidor consistente).
  Future<void> markExpired(int number) async {
    try {
      await FirebaseService.firestore
          .collection(_requestsCol)
          .doc(docIdFor(number))
          .update({'status': 'expired'}).timeout(
              const Duration(seconds: 10));
    } catch (_) {}
  }

  /// Dias restantes de um pedido (para a lista do dono).
  static int daysLeftForDoc(Map<String, dynamic> data, DateTime nowUtc) {
    final ts = data['trial_start'];
    if (ts is! Timestamp) return trialDays;
    return daysRemainingFor(
        trialStartUtc: ts.toDate().toUtc(), nowUtc: nowUtc);
  }

  // ------------------------------------------------------------------
  // Internos
  // ------------------------------------------------------------------

  /// Conta pedidos anteriores do mesmo aparelho OU mesmo WhatsApp
  /// (para o alerta de duplicado). O pedido atual ainda não existe.
  Future<int> _countPreviousRequests(
      String deviceId, String whatsappDigits) async {
    try {
      final col = FirebaseService.firestore.collection(_requestsCol);
      final ids = <String>{};
      final byDevice = await col
          .where('device_id', isEqualTo: deviceId)
          .get()
          .timeout(const Duration(seconds: 10));
      for (final d in byDevice.docs) {
        ids.add(d.id);
      }
      if (whatsappDigits.isNotEmpty) {
        final byZap = await col
            .where('whatsapp_digits', isEqualTo: whatsappDigits)
            .get()
            .timeout(const Duration(seconds: 10));
        for (final d in byZap.docs) {
          ids.add(d.id);
        }
      }
      return ids.length;
    } catch (e) {
      debugPrint('[Trial] contagem de duplicados falhou: $e');
      return 0;
    }
  }

  /// Chaves de família/responsável desta sessão (amarração extra):
  /// - `uid_<firebaseUid>`: conta Firebase (entre aparelhos/reinstalações)
  /// - `gid_<guardianId local>`: responsável (igual no filho pareado)
  /// - `cid_<childId>`: perfil do filho
  List<String> _familyKeys(StorageService storage) {
    final keys = <String>[];
    final role = storage.getRole();
    if (role == 'guardian') {
      String? uid;
      if (FirebaseService.available) {
        try {
          uid = fb_auth.FirebaseAuth.instance.currentUser?.uid;
        } catch (_) {}
      }
      if (uid != null && uid.isNotEmpty) keys.add('uid_$uid');
      final g = storage.getGuardian();
      if (g != null && g.id.isNotEmpty) keys.add('gid_${g.id}');
    } else if (role == 'child') {
      for (final gid in storage.getGuardianIds()) {
        if (gid.isNotEmpty) keys.add('gid_$gid');
      }
      final single = storage.getGuardianId();
      if (single != null &&
          single.isNotEmpty &&
          !keys.contains('gid_$single')) {
        keys.add('gid_$single');
      }
      final childId = storage.getSessionChildId();
      if (childId != null && childId.isNotEmpty) keys.add('cid_$childId');
    }
    return keys;
  }

  /// "Agora" anti-relógio: nunca anda para trás (usa o maior instante
  /// já visto, persistido). Mexer o relógio para trás não estende o trial;
  /// adiantar o relógio antecipa o bloqueio (comportamento padrão).
  Future<DateTime> _effectiveNow() async {
    final prefs = await SharedPreferences.getInstance();
    var now = DateTime.now().toUtc();
    final lastSeen = _parseUtc(prefs.getString(_kLastSeen));
    if (lastSeen != null && lastSeen.isAfter(now)) now = lastSeen;
    await prefs.setString(_kLastSeen, now.toIso8601String());
    return now;
  }

  Future<void> _touchLastSeen(SharedPreferences prefs) async {
    var now = DateTime.now().toUtc();
    final lastSeen = _parseUtc(prefs.getString(_kLastSeen));
    if (lastSeen != null && lastSeen.isAfter(now)) now = lastSeen;
    await prefs.setString(_kLastSeen, now.toIso8601String());
  }

  Future<String?> _resolveDeviceId() async {
    try {
      final android = await DeviceInfoPlugin().androidInfo;
      final id = android.id;
      if (id.isNotEmpty) return 'android_$id';
    } catch (e) {
      debugPrint('[Trial] ANDROID_ID indisponível: $e');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      var uuid = prefs.getString(_kDeviceId);
      if (uuid == null || uuid.isEmpty) {
        uuid = 'uuid_${const Uuid().v4()}';
        await prefs.setString(_kDeviceId, uuid);
      }
      return uuid;
    } catch (_) {
      return null;
    }
  }

  DateTime? _parseUtc(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    return DateTime.tryParse(iso)?.toUtc();
  }
}
