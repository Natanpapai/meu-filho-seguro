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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Inicializa o Firebase (nuvem). Se falhar, o app segue no modo local.
  // O Firebase permite a vinculação entre 2 celulares diferentes.
  await FirebaseService.init();
  // Inicializa o serviço de alarme SOS (notificações + som de alarme).
  await SosAlarmService.init();
  final storage = StorageService();
  await storage.init();
  final deps = AppDeps(storage);
  // Se o responsável já está logado, liga a vigilância SOS em 2º plano
  // (o alarme toca mesmo com o celular bloqueado ou o app fechado).
  final g = storage.getGuardian();
  if (storage.getRole() == 'guardian' &&
      g != null &&
      g.id.isNotEmpty) {
    SosAlarmService.startWatch(g.id);
  }
  runApp(MeuFilhoSeguroApp(deps: deps));
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
