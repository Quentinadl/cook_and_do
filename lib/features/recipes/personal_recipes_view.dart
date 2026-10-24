import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../recipe_detail_screen.dart'; 
import '../add_recipe_screen.dart'; // Ajuste si nécessaire
import '../edit_recipe_screen.dart'; // Ajuste si nécessaire

class PersonalRecipesView extends StatefulWidget {
  const PersonalRecipesView({super.key});

  @override
  State<PersonalRecipesView> createState() => _PersonalRecipesViewState();
}

class _PersonalRecipesViewState extends State<PersonalRecipesView> {
  final supabase = Supabase.instance.client;
  String _selectedCategory = 'Tous';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<dynamic>> _fetchPersonalRecipes() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return []; 

    var query = supabase.from('recipes').select('*, recipe_ingredients(items(nom))');
    query = query.eq('user_id', userId).neq('is_public', true);
    
    if (_selectedCategory != 'Tous' && _selectedCategory != 'Populaire') {
      query = query.eq('type_plat', _selectedCategory);
    }
    if (_searchController.text.trim().isNotEmpty) {
      query = query.ilike('nom', '%${_searchController.text.trim()}%');
    }
    
    List<dynamic> data;
    if (_selectedCategory == 'Populaire') {
      data = await query.order('note_moyenne', ascending: false);
    } else {
      // CORRECTION: Tri alphabétique car created_at n'existe pas
      data = await query.order('nom', ascending: true);
    }
    return data;
  }

  Future<void> _addToPlanningBasket(String recipeId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return; 

    try {
      await supabase.from('planning_selections').insert({
        'user_id': userId,
        'recipe_id': recipeId,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ajouté à ta sélection !')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Déjà dans ta sélection.')));
    }
  }

  void _showRecipeOptions(Map<String, dynamic> recipe) {
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
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue),
                title: const Text('Modifier la recette'),
                onTap: () async {
                  Navigator.pop(context);
                  await Navigator.push(context, MaterialPageRoute(builder: (context) => EditRecipeScreen(recipe: recipe)));
                  setState(() {}); 
                },
              ),
              ListTile(
                leading: const Icon(Icons.shopping_basket, color: Colors.orange),
                title: const Text('Ajouter à la sélection'),
                onTap: () {
                  Navigator.pop(context);
                  _addToPlanningBasket(recipe['id']);
                },
              ),
            ],
          ),
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 8),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Rechercher...',
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
                _buildCategoryChip('Populaire', primaryColor),
                _buildCategoryChip('Plat', primaryColor),
                _buildCategoryChip('Entrée', primaryColor),
                _buildCategoryChip('Dessert', primaryColor),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: _fetchPersonalRecipes(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text('Aucune recette trouvée.'));

                final recipes = snapshot.data!;
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  itemCount: recipes.length,
                  itemBuilder: (context, index) => _buildRecipeCard(recipes[index], primaryColor),
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

  Widget _buildRecipeCard(Map<String, dynamic> recipe, Color primaryColor) {
    final tempsTotal = (recipe['tps_prep_min'] ?? 0) + (recipe['tps_cuisson_min'] ?? 0);
    // Gestion robuste de l'image
    final String imageUrl = (recipe['photo_url'] != null && recipe['photo_url'].toString().trim().isNotEmpty)
        ? recipe['photo_url']
        : 'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?q=80&w=200';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => RecipeDetailScreen(recipe: recipe))),
        onLongPress: () => _showRecipeOptions(recipe), // APPUI LONG ICI
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  imageUrl, width: 80, height: 80, fit: BoxFit.cover,
                  errorBuilder: (c, e, s) => Container(width: 80, height: 80, color: Colors.grey.shade200, child: const Icon(Icons.restaurant, color: Colors.grey)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(recipe['nom'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.schedule, size: 14, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Text('$tempsTotal min', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.add_circle_outline, color: primaryColor),
                onPressed: () => _addToPlanningBasket(recipe['id']),
              )
            ],
          ),
        ),
      ),
    );
  }
}