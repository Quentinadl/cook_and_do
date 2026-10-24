import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';

// Importe tes écrans ici
import 'features/auth/login_screen.dart'; 
import 'shared/main_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. Initialisation de la langue française
  await initializeDateFormatting('fr_FR', null);

  // 2. Initialisation de Supabase
  await Supabase.initialize(
    url: 'https://hzrrwkhuaavmihlmjcqx.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh6cnJ3a2h1YWF2bWlobG1qY3F4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk2NTA2NjksImV4cCI6MjEwNTIyNjY2OX0.Ybb6b1O5VkIdaztoA0AnMit4fhFxBDazSShGqJGUqD4',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cook & Do',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF235347)), // Ton vert principal
        useMaterial3: true,
      ),
      home: const AuthGate(), // C'est l'aiguilleur qui prend le relais
    );
  }
}

// --- L'AIGUILLEUR (AuthGate) ---
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      // On écoute les changements de session Supabase en temps réel
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        
        // Si on a une session active, on va sur le Dashboard (MainScreen)
        final session = snapshot.data?.session;
        if (session != null) {
          return const MainScreen();
        }
        
        // Sinon, on renvoie vers l'écran de connexion
        return const LoginScreen();
      },
    );
  }
}