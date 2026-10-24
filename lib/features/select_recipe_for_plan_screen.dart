import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SelectRecipeForPlanScreen extends StatefulWidget {
  final DateTime date;
  final String repas;

  const SelectRecipeForPlanScreen({super.key, required this.date, required this.repas});

  @override
  State<SelectRecipeForPlanScreen> createState() => _SelectRecipeForPlanScreenState();
}

class _SelectRecipeForPlanScreenState extends State<SelectRecipeForPlanScreen> {
  final supabase = Supabase.instance.client;
  
  bool _isLoading = true;
  List<Map<String, dynamic>> _allRecipes = [];
  List<Map<String, dynamic>> _filteredRecipes = [];
  
  // Filtres
  final TextEditingController _searchController = TextEditingController();
  List<String> _availableIngredients = [];
  String? _selectedIngredient;

  @override
  void initState() {
    super.initState();
    _loadRecipesAndIngredients();
    _searchController.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecipesAndIngredients() async {
    try {
      // 1. Charger TOUTES les recettes
      final recipesRes = await supabase.from('recipes').select('id, nom, tps_prep_min, tps_cuisson_min, photo_url');
      _allRecipes = List<Map<String, dynamic>>.from(recipesRes);

      // 2. Charger les ingrédients uniques (pour le menu déroulant de filtre)
      final itemsRes = await supabase.from('items').select('nom').order('nom', ascending: true);
      _availableIngredients = (itemsRes as List).map((i) => i['nom'].toString()).toList();

      setState(() {
        _filteredRecipes = _allRecipes;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint("Erreur chargement recettes : $e");
    }
  }

  // --- LOGIQUE DE FILTRAGE ---
  Future<void> _applyFilters() async {
    final query = _searchController.text.toLowerCase().trim();
    
    // Si aucun filtre n'est actif, on remet tout
    if (query.isEmpty && _selectedIngredient == null) {
      setState(() {
        _filteredRecipes = _allRecipes;
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      List<Map<String, dynamic>> tempRecipes = List.from(_allRecipes);

      // Filtre Textuel (Recherche locale rapide)
      if (query.isNotEmpty) {
        tempRecipes = tempRecipes.where((recipe) {
          final nom = recipe['nom'].toString().toLowerCase();
          return nom.contains(query);
        }).toList();
      }

      // Filtre par Ingrédient (Recherche via Supabase sur les relations)
      if (_selectedIngredient != null) {
        // On cherche l'ID de l'ingrédient sélectionné
        final itemRes = await supabase.from('items').select('id').eq('nom', _selectedIngredient!).single();
        final itemId = itemRes['id'];

        // On cherche toutes les recettes qui ont cet ingrédient
        final recipeIngRes = await supabase.from('recipe_ingredients').select('recipe_id').eq('item_id', itemId);
        final validRecipeIds = (recipeIngRes as List).map((r) => r['recipe_id']).toSet();

        tempRecipes = tempRecipes.where((recipe) => validRecipeIds.contains(recipe['id'])).toList();
      }

      setState(() {
        _filteredRecipes = tempRecipes;
        _isLoading = false;
      });

    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  // Action quand on clique sur une recette : on l'enregistre dans l'agenda
  Future<void> _selectRecipe(Map<String, dynamic> recipe) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      final dateStr = widget.date.toIso8601String().split('T')[0];

      // On tente une insertion ou une mise à jour (upsert manuel)
      final existing = await supabase.from('meal_plan').select('id').eq('date_prevue', dateStr).eq('type_repas', widget.repas).maybeSingle();

      if (existing != null) {
        await supabase.from('meal_plan').update({'recipe_id': recipe['id']}).eq('id', existing['id']);
      } else {
        await supabase.from('meal_plan').insert({
          'date_prevue': dateStr,
          'type_repas': widget.repas,
          'recipe_id': recipe['id'],
          'user_id': userId,
        });
      }

      if (mounted) {
        Navigator.pop(context, true); // true = l'agenda doit se rafraîchir
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Choisir une recette', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // --- ZONE DE FILTRES ---
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
            ),
            child: Column(
              children: [
                // Barre de recherche textuelle
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Rechercher par nom...',
                    hintStyle: const TextStyle(color: Colors.grey),
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 20, color: Colors.grey),
                            onPressed: () {
                              _searchController.clear();
                              _applyFilters();
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                
                // Menu déroulant pour filtrer par ingrédient
                DropdownButtonFormField<String>(
                  value: _selectedIngredient,
                  hint: const Text('Filtrer par ingrédient clé...'),
                  isExpanded: true,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                    prefixIcon: const Icon(Icons.shopping_basket_outlined, color: Colors.grey),
                  ),
                  items: [
                    const DropdownMenuItem<String>(value: null, child: Text('Tous les ingrédients')),
                    ..._availableIngredients.map((ing) => DropdownMenuItem<String>(value: ing, child: Text(ing))).toList(),
                  ],
                  onChanged: (val) {
                    setState(() => _selectedIngredient = val);
                    _applyFilters();
                  },
                ),
              ],
            ),
          ),
          
          // --- LISTE DES RECETTES ---
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: primaryColor))
                : _filteredRecipes.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off_rounded, size: 60, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            const Text('Aucune recette trouvée.', style: TextStyle(color: Colors.grey, fontSize: 16)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredRecipes.length,
                        itemBuilder: (context, index) {
                          final recipe = _filteredRecipes[index];
                          final tempsTotal = (recipe['tps_prep_min'] ?? 0) + (recipe['tps_cuisson_min'] ?? 0);

                          return InkWell(
                            onTap: () => _selectRecipe(recipe),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
                                    child: Image.network(
                                      recipe['photo_url'] ?? 'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?q=80&w=800',
                                      width: 100, height: 100, fit: BoxFit.cover,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(recipe['nom'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 2, overflow: TextOverflow.ellipsis),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            const Icon(Icons.schedule, size: 14, color: Colors.grey),
                                            const SizedBox(width: 4),
                                            Text('$tempsTotal min', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Icon(Icons.add_circle, color: primaryColor, size: 28),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}