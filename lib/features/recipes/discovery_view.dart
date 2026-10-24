import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/spoonacular_service.dart';
import '../../features/recipe_detail_screen.dart';

class DiscoveryView extends StatefulWidget {
  const DiscoveryView({super.key});

  @override
  State<DiscoveryView> createState() => _DiscoveryViewState();
}

class _DiscoveryViewState extends State<DiscoveryView> {
  final supabase = Supabase.instance.client;
  final SpoonacularService _apiService = SpoonacularService();
  final TextEditingController _searchController = TextEditingController();
  
  bool _isLoading = false;
  bool _isProcessing = false; 
  List<dynamic> _searchResults = [];

  @override
  void initState() {
    super.initState();
    _performSearch('healthy'); 
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) return;
    setState(() => _isLoading = true);
    final results = await _apiService.searchRecipes(query);
    if (mounted) setState(() { _searchResults = results; _isLoading = false; });
  }

  Future<void> _addToPlanningBasket(int spoonacularId) async {
    setState(() => _isProcessing = true);
    try {
      final fullRecipe = await _apiService.getOrCreateRecipe(spoonacularId);
      if (fullRecipe == null) throw Exception("Erreur création recette");

      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      await supabase.from('planning_selections').insert({
        'user_id': userId,
        'recipe_id': fullRecipe['id'],
      });
      
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ajouté à la sélection !')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur ou déjà sélectionnée.')));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: TextField(
                controller: _searchController,
                onSubmitted: _performSearch,
                decoration: InputDecoration(
                  hintText: 'Pâtes, Poulet, Vegan...',
                  prefixIcon: const Icon(Icons.travel_explore, color: Colors.grey),
                  filled: true, fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: primaryColor))
                  : GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 0.75,
                      ),
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        return _buildApiRecipeCard(_searchResults[index], primaryColor);
                      },
                    ),
            ),
          ],
        ),
        if (_isProcessing)
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
    );
  }

  Widget _buildApiRecipeCard(Map<String, dynamic> apiRecipe, Color primaryColor) {
    final String imageUrl = (apiRecipe['image'] != null && apiRecipe['image'].toString().trim().isNotEmpty)
        ? apiRecipe['image']
        : 'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?q=80&w=200';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: Image.network(imageUrl, width: double.infinity, fit: BoxFit.cover, errorBuilder: (c, e, s) => Container(color: Colors.grey.shade200, child: const Icon(Icons.restaurant, color: Colors.grey))),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(apiRecipe['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity, height: 32,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero, side: BorderSide(color: primaryColor),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: Icon(Icons.add, size: 14, color: primaryColor),
                    label: Text('Sélectionner', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primaryColor)),
                    onPressed: () => _addToPlanningBasket(apiRecipe['id']),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}