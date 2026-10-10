import 'package:flutter/material.dart';
import '../app_deps.dart';
import '../models/models.dart';
import '../theme.dart';

/// Locais seguros: Casa e Escola, com raio configurável.
/// O endereço é capturado do GPS atual (REAL) ou ajustado manualmente.
/// Formata o raio: metros abaixo de 1000, km acima.
String formatRadius(double meters) {
  if (meters >= 1000) {
    final km = meters / 1000;
    final txt = km == km.roundToDouble()
        ? km.toInt().toString()
        : km.toStringAsFixed(1).replaceAll('.', ',');
    return '$txt km';
  }
  return '${meters.toInt()} metros';
}

class PlacesScreen extends StatefulWidget {
  final AppDeps deps;
  const PlacesScreen({super.key, required this.deps});

  @override
  State<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends State<PlacesScreen> {
  bool _saving = false;

  Future<void> _saveFromCurrentLocation(String type, String label) async {
    setState(() => _saving = true);
    final pos = await widget.deps.location.getCurrentPosition();
    setState(() => _saving = false);
    if (pos == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Não foi possível obter sua localização. Verifique o GPS e a permissão.')),
      );
      return;
    }
    final places = widget.deps.storage.getPlaces();
    places.removeWhere((p) => p.type == type);
    places.add(SafePlace.create(
      type: type,
      label: label,
      lat: pos.latitude,
      lng: pos.longitude,
    ));
    await widget.deps.storage.savePlaces(places);
    setState(() {});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label salvo na sua posição atual!')),
    );
  }

  Future<void> _changeRadius(SafePlace place) async {
    double radius = place.radiusMeters;
    final textController =
        TextEditingController(text: radius.toInt().toString());
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Raio — ${place.label}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(formatRadius(radius),
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              Slider(
                value: radius.clamp(50, 500000),
                min: 50,
                max: 500000,
                divisions: 100,
                label: formatRadius(radius),
                onChanged: (v) {
                  setState(() {
                    radius = v;
                    textController.text = radius.toInt().toString();
                  });
                },
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: textController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Metros (digite qualquer valor)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (t) {
                        final v = double.tryParse(t.replaceAll(',', '.'));
                        if (v != null && v >= 50) {
                          setState(() => radius = v);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Sem limite de distância: digite quantos metros quiser. '
                'Quando seu filho entrar ou sair deste raio, você recebe o alerta.',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, radius),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    textController.dispose();
    if (result != null) {
      final places = widget.deps.storage.getPlaces();
      final i = places.indexWhere((p) => p.id == place.id);
      if (i >= 0) {
        places[i] = SafePlace(
          id: place.id,
          type: place.type,
          label: place.label,
          lat: place.lat,
          lng: place.lng,
          radiusMeters: result,
        );
        await widget.deps.storage.savePlaces(places);
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final places = widget.deps.storage.getPlaces();
    final casa = places.where((p) => p.type == 'casa').firstOrNull;
    final escola = places.where((p) => p.type == 'escola').firstOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Casa e Escola')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Vá até o local e toque em "Usar minha posição" para marcá-lo com o GPS. '
            'Depois ajuste o raio do alerta.',
            style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 16),
          _PlaceCard(
            icon: Icons.home,
            title: 'Casa',
            place: casa,
            saving: _saving,
            onLocate: () => _saveFromCurrentLocation('casa', 'Casa'),
            onRadius: () => _changeRadius(casa!),
          ),
          const SizedBox(height: 12),
          _PlaceCard(
            icon: Icons.school,
            title: 'Escola',
            place: escola,
            saving: _saving,
            onLocate: () => _saveFromCurrentLocation('escola', 'Escola'),
            onRadius: () => _changeRadius(escola!),
          ),
        ],
      ),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final SafePlace? place;
  final bool saving;
  final VoidCallback onLocate;
  final VoidCallback onRadius;

  const _PlaceCard({
    required this.icon,
    required this.title,
    required this.place,
    required this.saving,
    required this.onLocate,
    required this.onRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: AppTheme.primary, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600)),
                      Text(
                        place == null
                            ? 'Não definido'
                            : 'Raio de ${formatRadius(place!.radiusMeters)}',
                        style: const TextStyle(
                            fontSize: 13, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                if (place != null)
                  IconButton(
                    tooltip: 'Ajustar raio',
                    icon: const Icon(Icons.tune,
                        color: AppTheme.primary),
                    onPressed: onRadius,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: saving ? null : onLocate,
              icon: const Icon(Icons.my_location),
              label: Text(place == null
                  ? 'Usar minha posição atual'
                  : 'Atualizar posição'),
            ),
          ],
        ),
      ),
    );
  }
}
