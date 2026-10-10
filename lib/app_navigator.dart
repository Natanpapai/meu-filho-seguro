import 'package:flutter/widgets.dart';

/// Chave global do Navigator do app.
///
/// Permite que o monitor de SOS ([SosMonitor]) abra o popup de emergência
/// a partir de qualquer tela — o `builder` do MaterialApp fica ACIMA do
/// Navigator na árvore, então `Navigator.of(context)` ali dentro falharia.
/// Com esta chave, o diálogo é mostrado pelo Navigator raiz e funciona
/// em todas as telas (mapa, histórico, ajustes etc.).
final appNavigatorKey = GlobalKey<NavigatorState>();
