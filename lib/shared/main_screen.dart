import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../features/dashboard_screen.dart';

import '../features/todo_screen.dart';
import '../features/shopping_screen.dart';
import '../features/recipes_screen.dart';
import '../features/agenda_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  // 1. On crée un "Navigateur" indépendant pour chaque onglet
  // CORRECTION : Il faut 5 GlobalKey car tu as 5 onglets !
  final List<GlobalKey<NavigatorState>> _navigatorKeys = [
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(), // Le 5ème !
  ];

  // Fonction pour changer d'onglet ou revenir à la racine de l'onglet actif
  void _selectTab(int index) {
    if (index == _currentIndex) {
      // Si l'utilisateur clique sur l'icône de l'onglet où il est DÉJÀ, 
      // on le ramène tout au début de cet onglet (très intuitif)
      _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
    } else {
      setState(() => _currentIndex = index);
    }
  }

  // Constructeur de navigation imbriquée
  Widget _buildNavigator(int index, Widget rootWidget) {
    return Offstage(
      offstage: _currentIndex != index, // Cache les onglets inactifs
      child: Navigator(
        key: _navigatorKeys[index],
        onGenerateRoute: (routeSettings) {
          return MaterialPageRoute(
            builder: (context) => rootWidget,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // PopScope permet d'intercepter le bouton "Retour" physique du téléphone Android
    return PopScope(
      canPop: false, // Empêche de fermer l'app brutalement
      onPopInvoked: (didPop) async {
        if (didPop) return;

        final NavigatorState? currentNavigator = _navigatorKeys[_currentIndex].currentState;
        
        // S'il y a une page ouverte DANS l'onglet actuel (ex: Détail d'une recette), on retourne en arrière
        if (currentNavigator != null && currentNavigator.canPop()) {
          currentNavigator.pop();
        } else {
          // Sinon, on est à la racine de l'onglet.
          if (_currentIndex != 0) {
            // Si on n'est pas sur l'Accueil, le bouton retour nous y ramène
            _selectTab(0);
          } else {
            // Si on est sur l'Accueil, on ferme l'application
            SystemNavigator.pop();
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        // Stack permet d'empiler tous les onglets, mais Offstage (au-dessus) masque ceux qui ne sont pas cliqués
        body: Stack(
          children: [
            // CORRECTION : L'onglet Courses est maintenant à l'index 4
            _buildNavigator(0, DashboardScreen(onNavigateToShopping: () => _selectTab(4))), 
            _buildNavigator(1, const AgendaScreen()),
            _buildNavigator(2, const RecipesScreen()),
            _buildNavigator(3, const TodoScreen()),
            _buildNavigator(4, const ShoppingScreen()),
          ],
        ),
        
        // La barre de navigation reste IMMOBILE tout en bas du Scaffold !
        bottomNavigationBar: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -5))],
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.grid_view_rounded, 'Accueil'),
              _buildNavItem(1, Icons.calendar_month_rounded, 'Agenda'), 
              _buildNavItem(2, Icons.restaurant_menu_rounded, 'Recettes'),
              _buildNavItem(3, Icons.check_circle_outline_rounded, 'Tâches'),
              _buildNavItem(4, Icons.shopping_bag_outlined, 'Courses'),
            ],
          ),
        ),
      ),
    );
  }

  // --- WIDGET DES BOUTONS DE NAVIGATION ---
  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: () => _selectTab(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: EdgeInsets.symmetric(horizontal: isSelected ? 16 : 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? primaryColor : Colors.grey.shade400, size: 24),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}