import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/trial_service.dart';
import '../theme.dart';

/// Área do dono (v17): monitora todos os pedidos de teste numerados.
///
/// Seções: PENDENTES (botão Liberar) • ATIVOS (dias restantes + botão
/// Bloquear) • EXPIRADOS/BLOQUEADOS.
///
/// Esta tela NÃO entra no trial: sempre acessível com o PIN.
/// Alerta de duplicado: "⚠ mesmo aparelho/WhatsApp do pedido #XXX".
class OwnerAreaScreen extends StatefulWidget {
  const OwnerAreaScreen({super.key});

  @override
  State<OwnerAreaScreen> createState() => _OwnerAreaScreenState();
}

class _OwnerAreaScreenState extends State<OwnerAreaScreen> {
  final _busy = <String>{}; // docIds com ação em andamento

  Future<void> _approve(int number) async {
    final ok = await _confirm(
      'Liberar ${TrialService.displayNumber(number)}?',
      'O teste de 7 dias começa a contar agora.',
      'LIBERAR',
    );
    if (!ok) return;
    final docId = TrialService.docIdFor(number);
    setState(() => _busy.add(docId));
    try {
      await TrialService.instance.approveRequest(number);
      if (mounted) _snack('Pedido ${TrialService.displayNumber(number)} liberado!');
    } catch (e) {
      if (mounted) _snack('Falha ao liberar. Tente de novo.');
    } finally {
      if (mounted) setState(() => _busy.remove(docId));
    }
  }

  Future<void> _block(int number, String name) async {
    final ok = await _confirm(
      'Bloquear ${TrialService.displayNumber(number)} ($name)?',
      'O app dele(a) trava na hora.',
      'BLOQUEAR',
      danger: true,
    );
    if (!ok) return;
    final docId = TrialService.docIdFor(number);
    setState(() => _busy.add(docId));
    try {
      await TrialService.instance.blockRequest(number);
      if (mounted) _snack('Pedido ${TrialService.displayNumber(number)} bloqueado.');
    } catch (e) {
      if (mounted) _snack('Falha ao bloquear. Tente de novo.');
    } finally {
      if (mounted) setState(() => _busy.remove(docId));
    }
  }

  Future<bool> _confirm(
      String title, String body, String actionLabel,
      {bool danger = false}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: danger
                ? ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.danger)
                : null,
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Área do dono — testes'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: TrialService.watchRequests(),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(
                child: Text('Falha ao carregar. Confira a internet.'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Nenhum pedido ainda.\nQuando alguém solicitar o teste, '
                  'aparece aqui.',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 15, color: AppTheme.textMuted),
                ),
              ),
            );
          }
          final now = DateTime.now().toUtc();
          final pending = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          final active = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          final done = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          for (final d in docs) {
            final data = d.data();
            final st = (data['status'] as String?) ?? 'pending';
            if (st == 'pending') {
              pending.add(d);
            } else if (st == 'active') {
              final left = TrialService.daysLeftForDoc(data, now);
              if (left <= 0) {
                // Expirou sozinho: marca no servidor (lazy) e lista como tal.
                TrialService.instance
                    .markExpired((data['number'] as int?) ?? 0);
                done.add(d);
              } else {
                active.add(d);
              }
            } else {
              done.add(d);
            }
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _sectionTitle('PENDENTES', pending.length, AppTheme.accent),
              ...pending.map(_pendingCard),
              const SizedBox(height: 8),
              _sectionTitle('ATIVOS', active.length, AppTheme.primary),
              ...active.map((d) => _activeCard(d, now)),
              const SizedBox(height: 8),
              _sectionTitle(
                  'EXPIRADOS / BLOQUEADOS', done.length, AppTheme.textMuted),
              ...done.map(_doneCard),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionTitle(String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text('$label ($count)',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _pendingCard(
      QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    final number = (data['number'] as int?) ?? 0;
    final docId = d.id;
    final busy = _busy.contains(docId);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _headerRow(data),
            const SizedBox(height: 8),
            _duplicateAlert(data),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: busy ? null : () => _approve(number),
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('LIBERAR 7 DIAS'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activeCard(
      QueryDocumentSnapshot<Map<String, dynamic>> d, DateTime now) {
    final data = d.data();
    final number = (data['number'] as int?) ?? 0;
    final name = (data['name'] as String?) ?? '—';
    final docId = d.id;
    final busy = _busy.contains(docId);
    final left = TrialService.daysLeftForDoc(data, now);
    final urgent = left <= 2;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _headerRow(data),
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: urgent
                    ? AppTheme.danger.withOpacity(0.12)
                    : AppTheme.primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                left == 1
                    ? '⏳ Resta 1 dia de teste'
                    : '⏳ Restam $left dias de teste',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: urgent
                        ? AppTheme.danger
                        : AppTheme.primaryDark),
              ),
            ),
            _duplicateAlert(data),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: busy ? null : () => _block(number, name),
              style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.danger),
              child: const Text('BLOQUEAR / REVOGAR'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _doneCard(
      QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    final st = (data['status'] as String?) ?? '';
    return Card(
      color: Colors.grey.shade100,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _headerRow(data),
            const SizedBox(height: 4),
            Text(
              st == 'blocked' ? '⛔ Bloqueado' : '⌛ Expirado',
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerRow(Map<String, dynamic> data) {
    final number = (data['number'] as int?) ?? 0;
    final name = (data['name'] as String?) ?? '—';
    final zap = (data['whatsapp'] as String?) ?? '—';
    final created = data['created_at'];
    String when = '';
    if (created is Timestamp) {
      final dt = created.toDate().toLocal();
      when =
          '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primaryDark,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                TrialService.displayNumber(number),
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text('📱 $zap${when.isNotEmpty ? '   •   🕐 $when' : ''}',
            style: const TextStyle(
                fontSize: 13, color: AppTheme.textMuted)),
      ],
    );
  }

  /// Alerta de duplicado: mesmo aparelho ou WhatsApp de outro pedido.
  Widget _duplicateAlert(Map<String, dynamic> data) {
    final dup = data['duplicate'] == true;
    final prev = (data['previous_requests'] as int?) ?? 0;
    if (!dup || prev <= 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_outlined,
              size: 18, color: Colors.orange.shade900),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '⚠ Pedido duplicado: mesmo aparelho ou WhatsApp de '
              '$prev pedido(s) anterior(es).',
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.orange.shade900,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
