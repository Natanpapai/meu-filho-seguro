import 'package:flutter/material.dart';
import 'app_deps.dart';
import 'services/firebase_service.dart';
import 'services/storage_service.dart';
import 'screens/child_home_screen.dart';
import 'screens/guardian_home_screen.dart';
import 'screens/welcome_screen.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Inicializa o Firebase (nuvem). Se falhar, o app segue no modo local.
  // O Firebase permite a vinculação entre 2 celulares diferentes.
  await FirebaseService.init();
  final storage = StorageService();
  await storage.init();
  final deps = AppDeps(storage);
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
      home: home,
    );
  }
}
