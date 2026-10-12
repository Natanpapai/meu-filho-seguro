import 'dart:async';
import 'package:flutter/material.dart';
import 'app_deps.dart';
import 'app_navigator.dart';
import 'services/firebase_service.dart';
import 'services/sos_alarm_service.dart';
import 'services/storage_service.dart';
import 'screens/child_home_screen.dart';
import 'screens/guardian_home_screen.dart';
import 'screens/welcome_screen.dart';
import 'theme.dart';
import 'widgets/sos_monitor.dart';

/// Ponto de entrada do app.
///
/// CORREÇÃO (v14 — "o app apresenta falhas e desloga"):
/// - `runZonedGuarded` + `FlutterError.onError`: qualquer erro assíncrono
///   não tratado (ex.: uma falha de rede num listener do Firestore, um
///   timer que dispara após dispose) agora é REPORTADO em vez de matar
///   o isolate — antes, esse tipo de erro derrubava o app inteiro
///   ("apresenta falhas") sem deixar rastro.
/// - Validação da sessão na abertura: se o papel salvo for 'guardian'
///   mas o perfil do responsável estiver ausente/corrompido, a sessão
///   parcial é limpa de forma deliberada e o app abre na tela de boas-
///   vindas — em vez de abrir "meio logado" (sem vigilância SOS) e, no
///   próximo arranque, cair na tela de login como se tivesse "deslogado
///   sozinho".
void main() async {
  // 1) Captura erros do framework (build, layout, etc.).
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[v14] FlutterError: ${details.exceptionAsString()}');
    debugPrint('[v14] stack: ${details.stack}');
  };

  // 2) Captura erros assíncronos não tratados (zona raiz): antes eles
  //    matavam o isolate e o app fechava sozinho.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // Inicializa o Firebase (nuvem). Se falhar, o app segue no modo local.
    // O Firebase permite a vinculação entre 2 celulares diferentes.
    await FirebaseService.init();
    // Inicializa o serviço de alarme SOS (notificações + som de alarme).
    await SosAlarmService.init();
    final storage = StorageService();
    await storage.init();
    final deps = AppDeps(storage);

    // Validação da sessão: papel sem perfil = sessão parcial/corrompida.
    // Limpa de forma deliberada (o usuário faz login de novo) em vez de
    // deixar o app num estado "meio logado" que parece logout espontâneo.
    final role = storage.getRole();
    if (role == 'guardian') {
      final g = storage.getGuardian();
      if (g == null || g.id.isEmpty) {
        debugPrint(
            '[v14] sessão parcial detectada (papel guardian sem perfil): '
            'limpando.');
        await storage.clearSession();
      }
    } else if (role == 'child') {
      if (storage.getSessionChildId() == null) {
        debugPrint('[v14] sessão parcial de filho: limpando.');
        await storage.clearSession();
      }
    }

    // Se o responsável já está logado, liga a vigilância SOS em 2º plano
    // (o alarme toca mesmo com o celular bloqueado ou o app fechado).
    final g = storage.getGuardian();
    if (storage.getRole() == 'guardian' &&
        g != null &&
        g.id.isNotEmpty) {
      SosAlarmService.startWatch(g.id);
      // Auto-cura: garante que o ID atual deste responsável esteja na
      // lista de vinculados de cada filho (se o ID mudou, o SOS volta a
      // chegar neste aparelho — antes ia só para o outro responsável).
      deps.auth.ensureGuardianLinked();
    }
    runApp(MeuFilhoSeguroApp(deps: deps));
  }, (error, stack) {
    // Erro assíncrono não tratado: registra, mas NÃO derruba o app.
    debugPrint('[v14] ERRO NÃO TRATADO (zona): $error');
    debugPrint('[v14] stack: $stack');
  });
}

class MeuFilhoSeguroApp extends StatelessWidget {
  final AppDeps deps;
  const MeuFilhoSeguroApp({super.key, required this.deps});

  @override
  Widget build(BuildContext context) {
    Widget home;
    final role = deps.storage.getRole();
    if (role == 'guardian' && deps.storage.getGuardian() != null) {
      home = GuardianHomeScreen(deps: deps);
    } else if (role == 'child' && deps.storage.getSessionChildId() != null) {
      home = ChildHomeScreen(deps: deps);
    } else {
      home = WelcomeScreen(deps: deps);
    }

    return MaterialApp(
      title: 'Meu Filho Seguro',
      theme: AppTheme.theme,
      debugShowCheckedModeBanner: false,
      // Chave global: o monitor de SOS abre o popup pelo Navigator raiz,
      // funcionando em qualquer tela (o builder fica acima do Navigator).
      navigatorKey: appNavigatorKey,
      // Monitor global de SOS: popup + som em qualquer tela do app,
      // inclusive nas telas abertas após o login.
      builder: (context, child) =>
          SosMonitor(deps: deps, child: child ?? const SizedBox.shrink()),
      home: home,
    );
  }
}
