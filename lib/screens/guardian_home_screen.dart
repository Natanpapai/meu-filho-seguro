import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../app_deps.dart';
import '../models/models.dart';
import '../services/firebase_service.dart';
import '../services/sos_alarm_service.dart';
import '../services/sync_service.dart';
import '../theme.dart';
import 'add_child_screen.dart';
import 'map_tab.dart';
import 'history_tab.dart';
import 'settings_tab.dart';
import 'pairing_screen.dart';
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
  Widget build(BuildContext context) {
    final guardian = widget.deps.storage.getGuardian();
    final titles = ['Meus filhos', 'Mapa', 'Histórico', 'Ajustes'];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_tab]),
        actions: [
          const ConnectivityChip(),
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
class _SosBanner extends StatelessWidget {
  final AppDeps deps;
  const _SosBanner({required this.deps});

  @override
  Widget build(BuildContext context) {
    if (!FirebaseService.available) return const SizedBox.shrink();
    final gid = deps.storage.getGuardian()?.id;
    if (gid == null || gid.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<List<SosAlert>>(
      stream: RemoteSync.sosAlertsStream(gid),
      builder: (context, snap) {
        final alerts = (snap.data ?? const <SosAlert>[])
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
            SosAlarmService.triggerAlarm(a);
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
  final SosAlert alert;
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
                      const Text(
                        'SOS ACIONADO!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
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

/// Texto "há X" que atualiza sozinho a cada segundo — mostra segundos
/// quando a atualização é recente (tempo real).
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
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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
    return Text(
      'Atualizado ${_ago()}'
      '${widget.batteryLevel != null ? ' • Bateria ${widget.batteryLevel}%' : ''}',
      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
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
