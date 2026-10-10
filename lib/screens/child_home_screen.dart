import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import '../app_deps.dart';
import '../models/models.dart';
import '../services/firebase_service.dart';
import '../services/history_service.dart';
import '../services/sharing_service.dart';
import '../services/sync_service.dart';
import '../theme.dart';
import 'profile_screen.dart';
import 'welcome_screen.dart';

/// Tela principal do filho(a).
///
/// O que é REAL nesta versão:
/// - Botão SOS registra o alerta e envia ao responsável via Firebase
///   (quando disponível) com data, hora e posição GPS.
/// - "Atualizar minha localização" usa o GPS de verdade e envia
///   a posição ao responsável via Firebase.
/// - Rastreamento contínuo: um serviço em primeiro plano envia a posição
///   ao responsável a cada 4 segundos, mesmo com o app em 2º plano
///   (estilo Uber). Não pode ser pausado pelo filho: é uma medida de
///   segurança definida pelo responsável.
/// - Nível de bateria é lido do aparelho.
///
/// Sem Firebase/rede, tudo continua funcionando localmente neste aparelho.
class ChildHomeScreen extends StatefulWidget {
  final AppDeps deps;
  const ChildHomeScreen({super.key, required this.deps});

  @override
  State<ChildHomeScreen> createState() => _ChildHomeScreenState();
}

class _ChildHomeScreenState extends State<ChildHomeScreen> {
  Child? _child;
  bool _updating = false;
  String? _message;
  bool _sharing = false;

  /// IDs de todos os responsáveis vinculados (multi-responsável).
  List<String> _guardianIdsCache = [];

  /// Amostrador do histórico do dia (a cada 2 minutos).
  Timer? _historyTimer;

  @override
  void initState() {
    super.initState();
    _load();
    // Inicia o rastreamento contínuo (foreground service, a cada 4s)
    // assim que a tela do filho abre. Não há opção de pausar: é uma
    // medida de segurança definida pelo responsável.
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) _startSharing();
    });
    // Amostragem do histórico do dia + atualização da lista de
    // responsáveis (a cada 2 minutos, só com compartilhamento ativo).
    _historyTimer =
        Timer.periodic(const Duration(minutes: 2), (_) async {
      if (!mounted || !_sharing) return;
      await _refreshGuardianIds();
      await _recordHistoryPoint();
    });
    // Limpeza de pontos antigos 1x ao dia.
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) _cleanupHistory();
    });
  }

  @override
  void dispose() {
    _historyTimer?.cancel();
    super.dispose();
  }

  /// Grava um ponto do trajeto do dia no Firestore.
  Future<void> _recordHistoryPoint() async {
    final child = _child;
    if (child == null || !FirebaseService.available) return;
    final loc = await HistoryService.readOwnLocation(child.id);
    if (loc == null) return;
    await HistoryService.recordPoint(
      childId: child.id,
      lat: loc.lat,
      lng: loc.lng,
      battery: loc.battery,
    );
  }

  Future<void> _cleanupHistory() async {
    final child = _child;
    if (child == null) return;
    final today =
        '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
    final key = 'mfs_history_clean_$today';
    if (widget.deps.storage.getRaw(key) != null) return;
    await HistoryService.cleanupOldPoints(child.id);
    await widget.deps.storage.setRaw(key, '1');
  }

  void _load() {
    final id = widget.deps.storage.getSessionChildId();
    if (id == null) return;
    final children = widget.deps.storage.getChildren();
    _child = children.where((c) => c.id == id).firstOrNull;
    setState(() {});
  }

  /// ID do responsável: no mesmo aparelho vem do cadastro local;
  /// no celular do filho, foi guardado na vinculação.
  String _guardianId() =>
      widget.deps.storage.getGuardian()?.id ??
      widget.deps.storage.getGuardianId() ??
      '';

  /// Lista de TODOS os responsáveis vinculados (multi-responsável).
  /// Usa o cache local e atualiza do Firestore quando possível.
  Future<List<String>> _guardianIds() async {
    if (_guardianIdsCache.isNotEmpty) return _guardianIdsCache;
    return _refreshGuardianIds();
  }

  Future<List<String>> _refreshGuardianIds() async {
    var ids = widget.deps.storage.getGuardianIds();
    if (ids.isEmpty) {
      final single = _guardianId();
      if (single.isNotEmpty) ids = [single];
    }
    if (FirebaseService.available && _child != null) {
      final fresh = await RemoteSync.fetchGuardianIds(_child!.id);
      if (fresh.isNotEmpty) {
        ids = fresh;
        await widget.deps.storage.setGuardianIds(ids);
      }
    }
    _guardianIdsCache = ids;
    return ids;
  }

  /// Inicia o serviço de rastreamento contínuo (4s, mesmo em 2º plano).
  /// É chamado automaticamente ao abrir a tela e não há opção de
  /// pausar pelo filho (medida de segurança do responsável).
  Future<void> _startSharing() async {
    final child = _child;
    if (child == null || !FirebaseService.available) return;
    // Só compartilha se o filho estiver vinculado a um responsável.
    if (_guardianId().isEmpty) return;
    await _refreshGuardianIds();
    await SharingService.start(
      childId: child.id,
      childName: child.name,
      guardianId: _guardianId(),
      // Multi-responsável: o serviço nativo grava o array `guardianIds`
      // no Firestore para que pai e mãe recebam todos os alertas.
      guardianIds: _guardianIdsCache.isNotEmpty ? _guardianIdsCache : null,
    );
    final running = await SharingService.isRunning();
    if (mounted) setState(() => _sharing = running);
  }

  Future<void> _updateLocation() async {
    if (_child == null) return;
    setState(() {
      _updating = true;
      _message = null;
    });
    final pos = await widget.deps.location.getCurrentPosition();
    int battery = 0;
    try {
      battery = await Battery().batteryLevel;
    } catch (_) {}
    if (pos == null) {
      setState(() {
        _updating = false;
        _message =
            'Não consegui sua localização. Verifique se o GPS está ligado e a permissão concedida.';
      });
      return;
    }
    final places = widget.deps.storage.getPlaces();
    // Modo escola: suprime alertas de rotina (chegou/saiu), mas o
    // status continua atualizando e o SOS segue funcionando.
    final schoolActive =
        widget.deps.storage.getSchoolMode().isActiveNow();
    final newStatus = await Geofence.checkTransitions(
      child: _child!,
      lat: pos.latitude,
      lng: pos.longitude,
      places: places,
      storage: widget.deps.storage,
      suppressRoutineEvents: schoolActive,
    );
    final updated = _child!.copyWith(
      lastLat: pos.latitude,
      lastLng: pos.longitude,
      lastUpdate: DateTime.now(),
      batteryLevel: battery,
      status: newStatus,
    );
    await widget.deps.storage.upsertChild(updated);
    await widget.deps.storage.addEvent(LocationEvent.create(
      childId: _child!.id,
      childName: _child!.name,
      type: 'atualizacao',
      lat: pos.latitude,
      lng: pos.longitude,
    ));
    // Envia também ao responsável via Firestore (tempo real).
    // Multi-responsável: envia para pai e mãe.
    final gids = await _guardianIds();
    await RemoteSync.sendLocation(
      childId: _child!.id,
      childName: _child!.name,
      guardianId: _guardianId(),
      lat: pos.latitude,
      lng: pos.longitude,
      battery: battery,
      speed: pos.speed,
      heading: pos.heading,
      guardianIds: gids,
    );
    _child = updated;
    setState(() {
      _updating = false;
      _message = 'Localização atualizada com sucesso!';
    });
  }

  Future<void> _sos() async {
    if (_child == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Acionar SOS?'),
        content: const Text(
          'Isso registra um alerta de emergência com a sua localização atual. '
          'Nesta versão, o alerta fica registrado no app — ele não liga para a emergência.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sim, é emergência'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final pos = await widget.deps.location.getCurrentPosition();
    await widget.deps.storage.addEvent(LocationEvent.create(
      childId: _child!.id,
      childName: _child!.name,
      type: 'sos',
      lat: pos?.latitude,
      lng: pos?.longitude,
    ));
    // Envia o SOS ao responsável via Firestore — ele vê em segundos.
    // Multi-responsável: envia para pai e mãe.
    final gids = await _guardianIds();
    await RemoteSync.sendSosAlert(
      childId: _child!.id,
      childName: _child!.name,
      guardianId: _guardianId(),
      lat: pos?.latitude,
      lng: pos?.longitude,
      guardianIds: gids,
    );
    if (!mounted) return;
    final notified = FirebaseService.available;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 8),
            Text('SOS registrado'),
          ],
        ),
        content: Text(
          notified
              ? 'Seu responsável foi avisado com a sua localização atual. '
                  'Procure um adulto de confiança ou ligue 190 se precisar de ajuda imediata.'
              : 'Seu alerta foi registrado com data, hora e localização. '
                  'Procure um adulto de confiança ou ligue 190 se precisar de ajuda imediata.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Pânico silencioso: envia o alerta SEM confirmação, SEM som e SEM
  /// vibração neste celular — para situações em que o filho não pode
  /// chamar atenção. O responsável recebe normalmente (com alarme).
  /// A mensagem de confirmação é neutra, como disfarce.
  Future<void> _silentSos() async {
    if (_child == null) return;
    final pos = await widget.deps.location.getCurrentPosition();
    int battery = 0;
    try {
      battery = await Battery().batteryLevel;
    } catch (_) {}
    await widget.deps.storage.addEvent(LocationEvent.create(
      childId: _child!.id,
      childName: _child!.name,
      type: 'sos',
      lat: pos?.latitude,
      lng: pos?.longitude,
    ));
    final gids = await _guardianIds();
    await RemoteSync.sendSosAlert(
      childId: _child!.id,
      childName: _child!.name,
      guardianId: _guardianId(),
      lat: pos?.latitude,
      lng: pos?.longitude,
      guardianIds: gids,
      silent: true,
    );
    // Atualiza a posição junto, sem chamar atenção.
    if (pos != null) {
      await RemoteSync.sendLocation(
        childId: _child!.id,
        childName: _child!.name,
        guardianId: _guardianId(),
        lat: pos.latitude,
        lng: pos.longitude,
        battery: battery,
        guardianIds: gids,
      );
    }
    if (!mounted) return;
    // Confirmação neutra (disfarce).
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tudo certo por aqui. 👍'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final child = _child;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meu Filho Seguro'),
        actions: [
          IconButton(
            tooltip: 'Meus Dados',
            icon: const Icon(Icons.person_outline),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => ProfileScreen(deps: widget.deps)),
              );
            },
          ),
          IconButton(
            tooltip: 'Sair',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              // O compartilhamento NÃO é interrompido no logout: é uma
              // medida de segurança e continua rodando em 2º plano.
              await widget.deps.auth.logout();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                    builder: (_) => WelcomeScreen(deps: widget.deps)),
                (_) => false,
              );
            },
          ),
        ],
      ),
      body: child == null
          ? const Center(child: Text('Perfil não encontrado.'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Text(
                            'Olá, ${child.nickname.isNotEmpty ? child.nickname : child.name}!',
                            style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: _sharing ? Colors.green : Colors.grey,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  _sharing
                                      ? 'Compartilhando sua localização em tempo real'
                                      : 'Ativando compartilhamento...',
                                  style: const TextStyle(
                                      fontSize: 14,
                                      color: AppTheme.textMuted),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Última atualização: ${AppTheme.timeAgo(child.lastUpdate)}'
                            '${child.batteryLevel != null ? ' • Bateria ${child.batteryLevel}%' : ''}',
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _updating ? null : _updateLocation,
                    icon: _updating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.my_location),
                    label: const Text('Atualizar minha localização'),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 13, color: AppTheme.textMuted),
                    ),
                  ],
                  const SizedBox(height: 32),
                  const Text(
                    'Em caso de emergência, aperte o botão:',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: _sos,
                    child: Container(
                      height: 190,
                      decoration: BoxDecoration(
                        color: AppTheme.danger,
                        borderRadius: BorderRadius.circular(100),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.danger
                                .withValues(alpha: 0.4),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.sos,
                              size: 56, color: Colors.white),
                          SizedBox(height: 4),
                          Text(
                            'SOS',
                            style: TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Botão de pânico silencioso: discreto, sem confirmação,
                  // sem som nem vibração neste aparelho. O responsável
                  // recebe o alerta normalmente (com alarme).
                  Center(
                    child: TextButton.icon(
                      onPressed: _silentSos,
                      icon: const Icon(Icons.volume_off_outlined,
                          size: 16, color: AppTheme.textMuted),
                      label: const Text(
                        'Pedir ajuda sem chamar atenção',
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.textMuted),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sua localização é compartilhada com seu responsável como medida de segurança.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
    );
  }
}
