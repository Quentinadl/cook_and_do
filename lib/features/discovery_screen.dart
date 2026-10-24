import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/spoonacular_service.dart'; // Ajuste le chemin
import 'recipe_detail_screen.dart';

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  final supabase = Supabase.instance.client;
  final SpoonacularService _apiService = SpoonacularService();
  final TextEditingController _searchController = TextEditingController();
  
  bool _isLoading = false;
  bool _isFetchingDetails = false;
  List<dynamic> _searchResults = [];
  
  // Préférences utilisateur
  List<String> _userDiets = [];
  List<String> _userIntolerances = [];

  @override
  void initState() {
    super.initState();
    _loadUserPreferencesAndSearch();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUserPreferencesAndSearch() async {
    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId != null) {
        final profile = await supabase.from('profiles').select('preferences_alimentaires, intolérances').eq('id', userId).maybeSingle();
        if (profile != null) {
          _userDiets = List<String>.from(profile['preferences_alimentaires'] ?? []);
          _userIntolerances = List<String>.from(profile['intolérances'] ?? []);
        }
      }
      // On lance une recherche par défaut (ex: recettes populaires ou saines)
      await _performSearch('healthy'); 
    } catch (e) {
      debugPrint('Erreur init découverte : $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) return;
    setState(() => _isLoading = true);
    
    // On utilise les préférences du profil pour filtrer l'API automatiquement
    final results = await _apiService.searchRecipes(
      query, 
      diets: _userDiets, 
      intolerances: _userIntolerances
    );
    
    if (mounted) {
      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
    }
  }

  // L'action magique : On télécharge/récupère la recette complète avant de l'afficher
  Future<void> _openRecipeDetails(int spoonacularId) async {
    setState(() => _isFetchingDetails = true);
    
    final fullRecipe = await _apiService.getOrCreateRecipe(spoonacularId);
    
    if (mounted) {
      setState(() => _isFetchingDetails = false);
      if (fullRecipe != null) {
        Navigator.push(context, MaterialPageRoute(builder: (context) => RecipeDetailScreen(recipe: fullRecipe)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible de charger cette recette.')));
      }
    }
  }

  // Modale rapide pour programmer directement depuis le catalogue
  Future<void> _quickSchedule(int spoonacularId) async {
    setState(() => _isFetchingDetails = true);
    final fullRecipe = await _apiService.getOrCreateRecipe(spoonacularId);
    setState(() => _isFetchingDetails = false);

    if (fullRecipe == null || !mounted) return;

    // Ouvre une petite modale de sélection de date/repas (similaire à celle qu'on a déjà)
    DateTime selectedDate = DateTime.now();
    String selectedMeal = 'Midi';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final primaryColor = Theme.of(context).colorScheme.primary;
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 32, top: 32, left: 32, right: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Programmer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                
                ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  tileColor: Colors.grey.shade100,
                  leading: Icon(Icons.calendar_month_rounded, color: primaryColor),
                  title: Text('${selectedDate.day}/${selectedDate.month}/${selectedDate.year}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  onTap: () async {
                    final picked = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                    if (picked != null) setModalState(() => selectedDate = picked);
                  },
                ),
                const SizedBox(height: 24),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: ['Midi', 'Soir'].map((meal) {
                    final isSelected = selectedMeal == meal;
                    return ChoiceChip(
                      label: Text(meal, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.black87)),
                      selected: isSelected,
                      selectedColor: primaryColor,
                      backgroundColor: Colors.grey.shade100,
                      onSelected: (selected) {
                        if (selected) setModalState(() => selectedMeal = meal);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 32),
                
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    onPressed: () async {
                      try {
                        final userId = supabase.auth.currentUser?.id;
                        await supabase.from('meal_plan').insert({
                          'date_prevue': selectedDate.toIso8601String().split('T')[0],
                          'type_repas': selectedMeal,
                          'recipe_id': fullRecipe['id'], // On utilise l'ID Supabase nouvellement créé !
                          'user_id': userId,
                        });
                        if (mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ajouté au planning !')));
                        }
                      } catch (e) {
                        debugPrint('Erreur plan: $e');
                      }
                    },
                    child: const Text('Valider', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                )
              ],
            ),
          );
        }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Catalogue Mondial', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // --- BARRE DE RECHERCHE ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: TextField(
                  controller: _searchController,
                  onSubmitted: _performSearch,
                  decoration: InputDecoration(
                    hintText: 'Pâtes, Poulet, Vegan...',
                    hintStyle: const TextStyle(color: Colors.grey),
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 20, color: Colors.grey),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                  ),
                ),
              ),

              // --- GRILLE DE RESULTATS ---
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: primaryColor))
                    : _searchResults.isEmpty
                        ? const Center(child: Text('Aucune recette trouvée.', style: TextStyle(color: Colors.grey)))
                        : GridView.builder(
                            padding: const EdgeInsets.all(24),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              childAspectRatio: 0.75, // Format portrait pour bien voir l'image
                            ),
                            itemCount: _searchResults.length,
                            itemBuilder: (context, index) {
                              final apiRecipe = _searchResults[index];
                              
                              return GestureDetector(
                                onTap: () => _openRecipeDetails(apiRecipe['id']),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.grey.shade200),
                                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Image
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                                          child: apiRecipe['image'] != null
                                            ? Image.network(apiRecipe['image'], width: double.infinity, fit: BoxFit.cover)
                                            : Container(color: Colors.grey.shade200, child: const Icon(Icons.restaurant, color: Colors.grey)),
                                        ),
                                      ),
                                      // Contenu texte et bouton
                                      Padding(
                                        padding: const EdgeInsets.all(12.0),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              apiRecipe['title'] ?? 'Sans nom',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 8),
                                            SizedBox(
                                              width: double.infinity,
                                              height: 32,
                                              child: OutlinedButton(
                                                style: OutlinedButton.styleFrom(
                                                  padding: EdgeInsets.zero,
                                                  side: BorderSide(color: primaryColor.withOpacity(0.5)),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                ),
                                                onPressed: () => _quickSchedule(apiRecipe['id']),
                                                child: Text('Prévoir', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primaryColor)),
                                              ),
                                            ),
                                          ],
                                        ),
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

          // OVERLAY DE CHARGEMENT PENDANT LE TÉLÉCHARGEMENT DE LA RECETTE
          if (_isFetchingDetails)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: primaryColor),
                      const SizedBox(height: 16),
                      const Text('Importation...', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}