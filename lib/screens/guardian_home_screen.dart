import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../app_deps.dart';
import '../models/models.dart';
import '../models/safety_models.dart';
import '../services/firebase_service.dart';
import '../services/route_service.dart';
import '../services/sos_alarm_service.dart';
import '../services/sync_service.dart';
import '../theme.dart';
import 'add_child_screen.dart';
import 'map_tab.dart';
import 'history_tab.dart';
import 'settings_tab.dart';
import 'pairing_screen.dart';
import 'second_guardian_pairing_screen.dart';
import 'safety_screen.dart';
import '../widgets/connectivity_chip.dart';

/// Tela principal do responsável: filhos, status, mapa, histórico e ajustes.
class GuardianHomeScreen extends StatefulWidget {
  final AppDeps deps;
  const GuardianHomeScreen({super.key, required this.deps});

  @override
  State<GuardianHomeScreen> createState() => _GuardianHomeScreenState();
}

class _GuardianHomeScreenState extends State<GuardianHomeScreen> {
  int _tab = 0;

  void _refresh() => setState(() {});

  @override
  void initState() {
    super.initState();
    // Monitor de desvio de rota (só com Firebase e rotas definidas).
    RouteMonitor.start(widget.deps);
  }

  @override
  void dispose() {
    RouteMonitor.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final guardian = widget.deps.storage.getGuardian();
    final titles = ['Meus filhos', 'Mapa', 'Histórico', 'Ajustes'];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_tab]),
        actions: [
          const ConnectivityChip(),
          IconButton(
            tooltip: 'Central de segurança',
            icon: const Icon(Icons.shield_outlined),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SafetyScreen(deps: widget.deps),
                ),
              );
              _refresh();
              // Rotas podem ter mudado: reinicia o monitor.
              RouteMonitor.stop();
              RouteMonitor.start(widget.deps);
            },
          ),
          if (_tab == 0)
            IconButton(
              tooltip: 'Vincular celular do filho',
              icon: const Icon(Icons.qr_code),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        PairingScreen(deps: widget.deps, mode: 'guardian'),
                  ),
                );
                _refresh();
              },
            ),
        ],
      ),
      body: switch (_tab) {
        0 => _HomeTab(deps: widget.deps, onChanged: _refresh),
        1 => MapTab(deps: widget.deps),
        2 => HistoryTab(deps: widget.deps),
        _ => SettingsTab(deps: widget.deps, guardian: guardian),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.family_restroom_outlined),
              selectedIcon: Icon(Icons.family_restroom),
              label: 'Filhos'),
          NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map),
              label: 'Mapa'),
          NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history),
              label: 'Histórico'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Ajustes'),
        ],
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  final AppDeps deps;
  final VoidCallback onChanged;
  const _HomeTab({required this.deps, required this.onChanged});

  static const _statusLabel = {
    'em_casa': 'Em casa',
    'na_escola': 'Na escola',
    'a_caminho': 'A caminho',
    'desconhecido': 'Sem dados',
  };

  static const _statusColor = {
    'em_casa': Color(0xFF2E7D32),
    'na_escola': Color(0xFF1565C0),
    'a_caminho': Color(0xFFEF6C00),
    'desconhecido': Color(0xFF9E9E9E),
  };

  @override
  Widget build(BuildContext context) {
    final children = deps.storage.getChildren();
    return RefreshIndicator(
      onRefresh: () async => onChanged(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SosBanner(deps: deps),
          _FullScreenAlertBanner(deps: deps),
          _RouteBanner(deps: deps),
          _BatteryBanner(deps: deps),
          _OfflineBanner(deps: deps),
          if (children.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    Icon(Icons.child_care,
                        size: 56,
                        color: AppTheme.primary.withValues(alpha: 0.5)),
                    const SizedBox(height: 12),
                    const Text(
                      'Nenhum filho cadastrado ainda',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Cadastre seu filho e vincule o celular dele para começar a acompanhar.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 13, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => SecondGuardianPairingScreen(
                                  deps: deps)),
                        );
                        onChanged();
                      },
                      icon: const Icon(Icons.family_restroom_outlined,
                          size: 18),
                      label: const Text('Vincular como 2º responsável'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...children.map((c) => _LiveChildCard(
                  deps: deps,
                  child: c,
                  onTap: () {},
                  onDelete: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Remover filho?'),
                        content: Text(
                            'Remover ${c.name} da sua conta? O histórico será mantido.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancelar'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Remover',
                                style: TextStyle(color: AppTheme.danger)),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await deps.storage.removeChild(c.id);
                      onChanged();
                    }
                  },
                )),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final added = await Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => AddChildScreen(deps: deps)),
              );
              if (added == true) onChanged();
            },
            icon: const Icon(Icons.add),
            label: const Text('Cadastrar filho(a)'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Banner de alertas SOS em tempo real (via Firestore).
/// Aparece no topo da aba "Filhos" segundos após o filho acionar o SOS.
/// Também dispara o alarme sonoro (fura silencioso/DND) + popup full-screen.
/// Alertas de pânico silencioso mostram o selo correspondente.
class _SosBanner extends StatelessWidget {
  final AppDeps deps;
  const _SosBanner({required this.deps});

  @override
  Widget build(BuildContext context) {
    if (!FirebaseService.available) return const SizedBox.shrink();
    final gid = deps.storage.getGuardian()?.id;
    if (gid == null || gid.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<List<SosAlertInfo>>(
      stream: RemoteSync.sosAlertsInfoStream(gid),
      builder: (context, snap) {
        final alerts = (snap.data ?? const <SosAlertInfo>[])
            .where((a) => !a.ack)
            .where((a) =>
                a.timestamp == null ||
                DateTime.now().difference(a.timestamp!).inHours < 24)
            .toList();
        if (alerts.isEmpty) return const SizedBox.shrink();
        // Dispara o alarme (som + popup) para cada alerta novo.
        // O SosAlarmService garante que cada alerta toca só uma vez.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          for (final a in alerts) {
            SosAlarmService.triggerAlarm(SosAlert(
              id: a.id,
              childId: a.childId,
              childName: a.childName,
              guardianId: gid,
              lat: a.lat,
              lng: a.lng,
              timestamp: a.timestamp,
              ack: a.ack,
            ));
          }
        });
        return Column(
          children: [
            for (final a in alerts) _SosCard(alert: a),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

class _SosCard extends StatelessWidget {
  final SosAlertInfo alert;
  const _SosCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFD32F2F),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Colors.white, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'SOS ACIONADO!',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                          if (alert.silent) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white
                                    .withValues(alpha: 0.25),
                                borderRadius:
                                    BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'silencioso',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        '${alert.childName} • ${AppTheme.timeAgo(alert.timestamp)}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFFD32F2F),
                    ),
                    onPressed: () {
                      // Para o som do alarme e dispensa o banner.
                      SosAlarmService.stopAlarm(alert.id);
                      RemoteSync.ackSosAlert(alert.id);
                    },
                    child: const Text('Marcar como visto'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Banner de permissão de tela cheia (v14).
///
/// No Android 14+, o sistema BLOQUEIA o alerta SOS em tela cheia por
/// cima da tela bloqueada a menos que o usuário libere "alertas em
/// tela cheia" nas configurações — sem isso, com a tela bloqueada só
/// o SOM toca (o problema reportado pelo dono). Este banner aparece
/// no topo da aba Filhos enquanto a permissão não estiver liberada,
/// com botão direto para as configurações do sistema.
class _FullScreenAlertBanner extends StatefulWidget {
  final AppDeps deps;
  const _FullScreenAlertBanner({required this.deps});

  @override
  State<_FullScreenAlertBanner> createState() =>
      _FullScreenAlertBannerState();
}

class _FullScreenAlertBannerState extends State<_FullScreenAlertBanner> {
  bool? _granted;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final ok = await SosAlarmService.canUseFullScreenIntent();
    if (mounted) setState(() => _granted = ok);
  }

  @override
  Widget build(BuildContext context) {
    // Ainda verificando ou já liberado: não mostra nada.
    if (_granted ?? true) return const SizedBox.shrink();
    return Column(
      children: [
        Card(
          color: const Color(0xFFFFF3E0),
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFFFB74D), width: 1.5),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Color(0xFFEF6C00), size: 28),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'ALERTA EM TELA CHEIA BLOQUEADO',
                        style: TextStyle(
                          color: Color(0xFFE65100),
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'O celular está bloqueando a tela vermelha de emergência. '
                  'Com a tela bloqueada, o SOS vai tocar SÓ o som — você '
                  'não vai ver o alerta. Libere nas configurações:',
                  style:
                      TextStyle(fontSize: 13, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF6C00),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    await SosAlarmService
                        .openFullScreenIntentSettings();
                    // Re-verifica ao voltar das configurações.
                    await Future.delayed(
                        const Duration(seconds: 1));
                    _check();
                  },
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  label:
                      const Text('Liberar nas configurações do celular'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Banner de alerta de desvio de rota (via Firestore).
class _RouteBanner extends StatelessWidget {  final AppDeps deps;
  const _RouteBanner({required this.deps});

  @override
  Widget build(BuildContext context) {
    if (!FirebaseService.available) return const SizedBox.shrink();
    final gid = deps.storage.getGuardian()?.id;
    if (gid == null || gid.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<List<RouteAlert>>(
      stream: RouteMonitor.routeAlertsStream(gid),
      builder: (context, snap) {
        final alerts = snap.data ?? const <RouteAlert>[];
        if (alerts.isEmpty) return const SizedBox.shrink();
        return Column(
          children: [
            for (final a in alerts)
              Card(
                color: const Color(0xFFEF6C00),
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.route_outlined,
                              color: Colors.white, size: 30),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'SAIU DA ROTA',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1,
                                  ),
                                ),
                                Text(
                                  '${a.childName} • ${AppTheme.timeAgo(a.timestamp)}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13),
                                ),
                                if (a.distanceMeters != null)
                                  Text(
                                    '${(a.distanceMeters! / 1000).toStringAsFixed(1)} km fora do caminho esperado',
                                    style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor:
                              const Color(0xFFEF6C00),
                        ),
                        onPressed: () =>
                            RouteMonitor.ackRouteAlert(a.id),
                        child: const Text('Marcar como visto'),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

/// Banner de bateria fraca do celular do filho (< 20%).
/// Alerta 1x ao dia por filho para não virar spam.
class _BatteryBanner extends StatelessWidget {
  final AppDeps deps;
  const _BatteryBanner({required this.deps});

  @override
  Widget build(BuildContext context) {
    if (!FirebaseService.available) return const SizedBox.shrink();
    final children = deps.storage.getChildren();
    if (children.isEmpty) return const SizedBox.shrink();
    final ids = children.map((c) => c.id).toList();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: RemoteSync.locationsStream(ids),
      builder: (context, snap) {
        final low = <String, int>{}; // childId -> battery
        for (final d in snap.data?.docs ?? const []) {
          final m = d.data();
          final batt = (m['battery'] as num?)?.toInt();
          if (batt != null && batt < 20) {
            // Só mostra 1x ao dia por filho.
            final today =
                '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
            final key = 'mfs_batt_alert_${d.id}_$today';
            if (deps.storage.getRaw(key) == null) {
              low[d.id] = batt;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                deps.storage.setRaw(key, '1');
              });
            }
          }
        }
        if (low.isEmpty) return const SizedBox.shrink();
        final names = low.keys.map((id) {
          Child? found;
          for (final x in children) {
            if (x.id == id) {
              found = x;
              break;
            }
          }
          final name = (found != null && found.nickname.isNotEmpty)
              ? found.nickname
              : (found?.name ?? 'Seu filho');
          return '$name (${low[id]}%)';
        }).join(', ');
        return Column(
          children: [
            Card(
              color: const Color(0xFFF9A825),
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.battery_alert,
                        color: Colors.white, size: 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'BATERIA FRACA',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                          Text(
                            '$names — peça para carregar o celular para não perder o rastreamento.',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

/// Banner de filho OFFLINE: sem localização há mais de 5 minutos.
///
/// O filho pode estar com o celular desligado, sem internet ou com o app
/// morto pelo sistema. É impossível rastrear um celular desligado — o que
/// o responsável vê aqui é a ÚLTIMA posição conhecida, com o tempo desde
/// a última atualização. O banner some sozinho quando o filho voltar a
/// enviar a localização.
class _OfflineBanner extends StatefulWidget {
  final AppDeps deps;
  const _OfflineBanner({required this.deps});

  @override
  State<_OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<_OfflineBanner> {
  Timer? _timer;

  /// Limite para considerar o filho offline.
  static const _offlineAfter = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    // Atualiza o "há X min" periodicamente (sem novos dados, o
    // StreamBuilder não reconstruiria sozinho).
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _offlineFor(DateTime updatedAt) {
    final diff = DateTime.now().difference(updatedAt);
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    return m == 0 ? 'há $h h' : 'há $h h $m min';
  }

  @override
  Widget build(BuildContext context) {
    if (!FirebaseService.available) return const SizedBox.shrink();
    final children = widget.deps.storage.getChildren();
    if (children.isEmpty) return const SizedBox.shrink();
    final ids = children.map((c) => c.id).toList();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: RemoteSync.locationsStream(ids),
      builder: (context, snap) {
        final offline = <String, DateTime>{}; // childId -> updatedAt
        final now = DateTime.now();
        for (final d in snap.data?.docs ?? const []) {
          final m = d.data();
          final ts = m['updatedAt'];
          final updatedAt = ts is Timestamp ? ts.toDate() : null;
          // Sem nenhum dado de localização, não há "última posição":
          // não mostra o banner (o card já indica "Sem dados").
          if (updatedAt == null) continue;
          if (now.difference(updatedAt) >= _offlineAfter) {
            offline[d.id] = updatedAt;
          }
        }
        if (offline.isEmpty) return const SizedBox.shrink();
        final names = offline.keys.map((id) {
          Child? found;
          for (final x in children) {
            if (x.id == id) {
              found = x;
              break;
            }
          }
          final name = (found != null && found.nickname.isNotEmpty)
              ? found.nickname
              : (found?.name ?? 'Seu filho');
          return '$name (${_offlineFor(offline[id]!)})';
        }).join(', ');
        return Column(
          children: [
            Card(
              color: const Color(0xFFC62828),
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.signal_wifi_off,
                        color: Colors.white, size: 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'FILHO OFFLINE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                          Text(
                            '⚠️ $names sem enviar localização. '
                            'Pode ser celular desligado ou sem internet. '
                            'O mapa mostra a última posição conhecida.',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

/// Card do filho com localização ao vivo: mescla os dados locais com
/// a posição mais recente vinda do Firestore (celular do filho).
class _LiveChildCard extends StatelessWidget {
  final AppDeps deps;
  final Child child;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _LiveChildCard({
    required this.deps,
    required this.child,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (!FirebaseService.available) {
      return _ChildCard(child: child, onTap: onTap, onDelete: onDelete);
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: RemoteSync.locationStream(child.id),
      builder: (context, snap) {
        var merged = child;
        bool? moving;
        final data = snap.data?.data();
        if (data != null) {
          final lat = (data['lat'] as num?)?.toDouble();
          final lng = (data['lng'] as num?)?.toDouble();
          final ts = data['updatedAt'];
          final updatedAt = ts is Timestamp ? ts.toDate() : null;
          final speed = (data['speed'] as num?)?.toDouble();
          // Acima de ~2 km/h considera em movimento.
          if (speed != null) moving = speed > 0.6;
          if (lat != null && lng != null &&
              (child.lastLat == null ||
                  (updatedAt != null &&
                      (child.lastUpdate == null ||
                          updatedAt.isAfter(child.lastUpdate!))))) {
            merged = child.copyWith(
              lastLat: lat,
              lastLng: lng,
              lastUpdate: updatedAt ?? child.lastUpdate,
              batteryLevel: (data['battery'] as num?)?.toInt() ??
                  child.batteryLevel,
            );
          }
        }
        return _ChildCard(
            child: merged, onTap: onTap, onDelete: onDelete, moving: moving);
      },
    );
  }
}

/// Texto "há X" que atualiza sozinho — mostra segundos quando a
/// atualização é recente (tempo real).
///
/// OTIMIZAÇÃO: atualiza a cada 5 segundos em vez de 1 (5x menos rebuilds).
/// A diferença visual é mínima ("há 10 s" em vez de "há 12 s").
class _LiveAgo extends StatefulWidget {
  final DateTime? updatedAt;
  final int? batteryLevel;
  const _LiveAgo({this.updatedAt, this.batteryLevel});

  @override
  State<_LiveAgo> createState() => _LiveAgoState();
}

class _LiveAgoState extends State<_LiveAgo> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Quando a última atualização tem mais de 5 minutos, o texto muda para
  /// "Última localização há X" em tom de alerta: o filho pode estar
  /// offline (celular desligado, sem internet) e o que se vê no mapa é
  /// a última posição conhecida — não a posição atual.
  bool get _isStale {
    final dt = widget.updatedAt;
    if (dt == null) return true;
    return DateTime.now().difference(dt).inMinutes >= 5;
  }

  String _ago() {
    final dt = widget.updatedAt;
    if (dt == null) return 'nunca';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'há ${diff.inSeconds} s';
    return AppTheme.timeAgo(dt);
  }

  @override
  Widget build(BuildContext context) {
    final lowBattery =
        widget.batteryLevel != null && widget.batteryLevel! < 20;
    final stale = _isStale;
    return RichText(
      text: TextSpan(
        style:
            const TextStyle(fontSize: 11, color: AppTheme.textMuted),
        children: [
          TextSpan(
            text: stale ? 'Última localização ${_ago()}' : 'Atualizado ${_ago()}',
            style: TextStyle(
              color: stale ? Colors.orange.shade800 : null,
              fontWeight: stale ? FontWeight.bold : null,
            ),
          ),
          if (widget.batteryLevel != null)
            TextSpan(
              text: ' • Bateria ${widget.batteryLevel}%',
              style: TextStyle(
                color: lowBattery ? Colors.orange.shade700 : null,
                fontWeight: lowBattery ? FontWeight.bold : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _ChildCard extends StatelessWidget {
  final Child child;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  /// true = em movimento, false = parado, null = sem dados de velocidade.
  final bool? moving;

  const _ChildCard(
      {required this.child,
      required this.onTap,
      required this.onDelete,
      this.moving});

  @override
  Widget build(BuildContext context) {
    final color = _HomeTab._statusColor[child.status] ?? Colors.grey;
    final label = _HomeTab._statusLabel[child.status] ?? child.status;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                backgroundImage: child.photoPath != null
                    ? FileImage(File(child.photoPath!))
                    : null,
                child: child.photoPath == null
                    ? Text(
                        child.nickname.isNotEmpty
                            ? child.nickname[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary),
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      child.nickname.isNotEmpty
                          ? child.nickname
                          : child.name,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${child.name} • ${child.age} anos',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                    color: color, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                label,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: color),
                              ),
                            ],
                          ),
                        ),
                        if (!child.paired) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Não vinculado',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orange),
                            ),
                          ),
                        ],
                        if (moving != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: (moving!
                                      ? Colors.green
                                      : Colors.grey)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                      color: moving!
                                          ? Colors.green
                                          : Colors.grey,
                                      shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  moving! ? 'Em movimento' : 'Parado',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: moving!
                                          ? Colors.green.shade700
                                          : Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    _LiveAgo(
                      updatedAt: child.lastUpdate,
                      batteryLevel: child.batteryLevel,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.more_vert, color: AppTheme.textMuted),
                onPressed: () => showModalBottomSheet(
                  context: context,
                  builder: (_) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.delete_outline,
                              color: AppTheme.danger),
                          title: const Text('Remover filho(a)',
                              style: TextStyle(color: AppTheme.danger)),
                          onTap: () {
                            Navigator.pop(context);
                            onDelete();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
