import 'package:flutter/material.dart';
import 'personal_recipes_view.dart';
import 'discovery_view.dart';
import 'selection_view.dart'; // Ancien planning_basket_screen.dart

class RecipesHubScreen extends StatefulWidget {
  const RecipesHubScreen({super.key});

  @override
  State<RecipesHubScreen> createState() => _RecipesHubScreenState();
}

class _RecipesHubScreenState extends State<RecipesHubScreen> {
  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return DefaultTabController(
      length: 3, // On passe à 3 onglets
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Recettes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          bottom: TabBar(
            labelColor: primaryColor,
            unselectedLabelColor: Colors.grey,
            indicatorColor: primaryColor,
            indicatorWeight: 3,
            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
            tabs: const [
              Tab(text: 'Carnet', icon: Icon(Icons.menu_book_rounded)),
              Tab(text: 'Découverte', icon: Icon(Icons.travel_explore_rounded)),
              Tab(text: 'Sélection', icon: Icon(Icons.shopping_basket_rounded)),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            PersonalRecipesView(),
            DiscoveryView(),
            SelectionView(),
          ],
        ),
      ),
    );
  }
}