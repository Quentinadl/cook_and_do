import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'recipe_detail_screen.dart';
import 'add_recipe_screen.dart';
import 'edit_recipe_screen.dart';

class RecipesScreen extends StatefulWidget {
  const RecipesScreen({super.key});

  @override
  State<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends State<RecipesScreen> {
  final supabase = Supabase.instance.client;
  String _selectedCategory = 'Tous';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<dynamic>> _fetchRecipes() async {
    try {
      var query = supabase.from('recipes').select('*, recipe_ingredients(quantite, unite, items(nom))');

      if (_selectedCategory != 'Tous') {
        query = query.eq('type_plat', _selectedCategory);
      }
      if (_searchController.text.trim().isNotEmpty) {
        query = query.ilike('nom', '%${_searchController.text.trim()}%');
      }
      
      final data = await query.order('nom', ascending: true);
      debugPrint('✅ Recettes trouvées : ${data.length}');
      return data;
      
    } catch (e) {
      debugPrint('❌ Erreur avec la jointure des ingrédients : $e');
      
      // PLAN B : S'il y a une erreur avec les ingrédients, on charge juste la recette !
      var fallbackQuery = supabase.from('recipes').select('*');
      if (_selectedCategory != 'Tous') {
        fallbackQuery = fallbackQuery.eq('type_plat', _selectedCategory);
      }
      if (_searchController.text.trim().isNotEmpty) {
        fallbackQuery = fallbackQuery.ilike('nom', '%${_searchController.text.trim()}%');
      }
      return await fallbackQuery.order('nom', ascending: true);
    }
  }

  void _showRecipeOptions(Map<String, dynamic> recipe) {
    // On vérifie si l'utilisateur actuel est le propriétaire de la recette
    final currentUserId = supabase.auth.currentUser?.id;
    final isOwner = recipe['user_id'] == currentUserId;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 40, left: 24, right: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(recipe['nom'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 24),
              
              // Le bouton Modifier n'apparaît QUE pour le créateur
              if (isOwner)
                ListTile(
                  leading: const Icon(Icons.edit, color: Colors.blue),
                  title: const Text('Modifier la recette'),
                  onTap: () async {
                    Navigator.pop(context);
                    await Navigator.push(context, MaterialPageRoute(builder: (context) => EditRecipeScreen(recipe: recipe)));
                    setState(() {}); 
                  },
                ),
              
              // Le bouton Programmer apparaît pour TOUT LE MONDE
              ListTile(
                leading: const Icon(Icons.calendar_month, color: Colors.green),
                title: const Text('Programmer ce repas'),
                onTap: () {
                  Navigator.pop(context);
                  _quickSchedule(recipe['id']);
                },
              ),
            ],
          ),
        );
      }
    );
  }

  Future<void> _quickSchedule(String recipeId) async {
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
                const SizedBox(height: 16),
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
                  width: double.infinity, height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    onPressed: () async {
                      final userId = supabase.auth.currentUser?.id;
                      await supabase.from('meal_plan').insert({
                        'date_prevue': selectedDate.toIso8601String().split('T')[0],
                        'type_repas': selectedMeal,
                        'recipe_id': recipeId,
                        'user_id': userId,
                      });
                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Repas ajouté à l\'agenda !')));
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
        title: const Text('Catalogue', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 24, right: 24, top: 8, bottom: 8),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Rechercher une recette...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true, fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              children: [
                _buildCategoryChip('Tous', primaryColor),
                _buildCategoryChip('Plat', primaryColor),
                _buildCategoryChip('Entrée', primaryColor),
                _buildCategoryChip('Dessert', primaryColor),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: _fetchRecipes(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text('Aucune recette trouvée.'));

                final recipes = snapshot.data!;
                return GridView.builder(
                  padding: const EdgeInsets.all(24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: recipes.length,
                  itemBuilder: (context, index) => _buildGridRecipeCard(recipes[index], primaryColor),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (context) => const AddRecipeScreen()));
          setState(() {}); 
        },
        backgroundColor: primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildCategoryChip(String label, Color primaryColor) {
    final isSelected = _selectedCategory == label;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.black87)),
        selected: isSelected,
        selectedColor: primaryColor,
        backgroundColor: Colors.grey.shade100,
        side: BorderSide.none,
        onSelected: (_) => setState(() => _selectedCategory = label),
      ),
    );
  }

  Widget _buildGridRecipeCard(Map<String, dynamic> recipe, Color primaryColor) {
    final String imageUrl = (recipe['photo_url'] != null && recipe['photo_url'].toString().trim().isNotEmpty)
        ? recipe['photo_url']
        : 'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?q=80&w=400';
    
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => RecipeDetailScreen(recipe: recipe))),
      onLongPress: () => _showRecipeOptions(recipe),
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
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: Image.network(
                  imageUrl, 
                  width: double.infinity, 
                  fit: BoxFit.cover,
                  errorBuilder: (c, e, s) => Container(color: Colors.grey.shade200, child: const Icon(Icons.restaurant, color: Colors.grey)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(recipe['nom'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(recipe['type_plat'] ?? 'Plat', style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}