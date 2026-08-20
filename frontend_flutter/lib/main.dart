import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'screens/flashscore_home_screen.dart';
import 'screens/accumulator_screen.dart';
import 'screens/crypto_macro_screen.dart';
import 'screens/accumulator_v2_screen.dart';
import 'screens/crypto_macro_v2_screen.dart';
import 'screens/quantfury_crypto_swap_screen.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> _initNotifications() async {
  const AndroidInitializationSettings androidInit =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const DarwinInitializationSettings iosInit = DarwinInitializationSettings();
  const InitializationSettings initSettings =
      InitializationSettings(android: androidInit, iOS: iosInit);
  try {
    await flutterLocalNotificationsPlugin.initialize(initSettings);
  } catch (_) {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initNotifications();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tiago IA · Futebol + Trading + GPT',
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      home: const LoginScreen(),
      routes: <String, WidgetBuilder>{
        '/login': (_) => const LoginScreen(),
        '/home': (_) => const MainScreen(),
        '/flashscore': (_) => const FlashScoreHomeScreen(),
        '/accumulator': (_) => const AccumulatorScreen(),
        '/crypto-macro': (_) => const CryptoMacroScreen(),
        '/accumulator-v2': (_) => const AccumulatorV2Screen(),
        '/crypto-macro-v2': (_) => const CryptoMacroV2Screen(),
        '/crypto-swap-quantfury': (_) => const QuantfuryCryptoSwapScreen(),
      },
    );
  }
}
