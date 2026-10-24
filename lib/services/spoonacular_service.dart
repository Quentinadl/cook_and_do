import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class SpoonacularService {
  // Remplace par ta vraie clé API Spoonacular
  static const String _apiKey = '8fa3c2b2ed804035a10f2bbf8c74f113';
  static const String _baseUrl = 'https://api.spoonacular.com/recipes';

  final supabase = Supabase.instance.client;

  // --------------------------------------------------------
  // 1. RECHERCHE LÉGÈRE (Ne consomme qu'1 point de quota)
  // --------------------------------------------------------
  Future<List<dynamic>> searchRecipes(
    String query, {
    List<String>? diets,
    List<String>? intolerances,
  }) async {
    try {
      // Construction de l'URL avec les filtres du profil utilisateur
      String url =
          '$_baseUrl/complexSearch?apiKey=$_apiKey&query=$query&number=15';

      if (diets != null && diets.isNotEmpty) {
        url += '&diet=${diets.join(',')}';
      }
      if (intolerances != null && intolerances.isNotEmpty) {
        url += '&intolerances=${intolerances.join(',')}';
      }

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['results'] as List<dynamic>;
      } else {
        throw Exception('Erreur API: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Erreur searchRecipes: $e');
      return [];
    }
  }

  // --------------------------------------------------------
  // 2. LE CACHE INTELLIGENT (Supabase d'abord, API ensuite)
  // --------------------------------------------------------
  Future<Map<String, dynamic>?> getOrCreateRecipe(int spoonacularId) async {
    try {
      // ÉTAPE A : Vérifier si la recette est DÉJÀ dans notre Supabase
      final existingRecipe = await supabase
          .from('recipes')
          .select(
            '*, recipe_ingredients(quantite, unite, items(nom)), recipe_steps(ordre, description)',
          )
          .eq('spoonacular_id', spoonacularId)
          .maybeSingle();

      if (existingRecipe != null) {
        debugPrint('🎯 Recette trouvée dans Supabase (Cache) ! 0 appel API.');
        return existingRecipe;
      }

      // ÉTAPE B : Si absente, on interroge Spoonacular pour les détails complets
      debugPrint('🌐 Recette absente. Appel à Spoonacular...');
      final response = await http.get(
        Uri.parse('$_baseUrl/$spoonacularId/information?apiKey=$_apiKey'),
      );

      if (response.statusCode != 200)
        throw Exception('Erreur de récupération des détails API');

      final apiData = json.decode(response.body);

      // ÉTAPE C : On convertit et sauvegarde dans NOTRE base de données
      return await _saveRecipeToSupabase(apiData);
    } catch (e) {
      debugPrint('Erreur getOrCreateRecipe: $e');
      return null;
    }
  }

  // --------------------------------------------------------
  // 3. SAUVEGARDE EN BASE DE DONNÉES (La mécanique interne)
  // --------------------------------------------------------
  Future<Map<String, dynamic>> _saveRecipeToSupabase(
    Map<String, dynamic> apiData,
  ) async {
    // On récupère ton ID utilisateur pour le donner à Supabase
    final userId = supabase.auth.currentUser?.id;

    final prepMinutes =
        apiData['preparationMinutes'] ??
        (apiData['readyInMinutes'] != null
            ? apiData['readyInMinutes'] / 2
            : 15);
    final cookMinutes =
        apiData['cookingMinutes'] ??
        (apiData['readyInMinutes'] != null
            ? apiData['readyInMinutes'] / 2
            : 15);
    final servings = apiData['servings'] ?? 2;

    // 1. Insérer la recette principale (en public, mais avec ton ID comme "importateur")
    final savedRecipe = await supabase
        .from('recipes')
        .insert({
          'user_id':
              userId, // <-- CORRECTION : Le bouclier RLS te laisse passer !
          'spoonacular_id': apiData['id'],
          'is_public': true,
          'nom': apiData['title'] ?? 'Recette sans nom',
          'photo_url': apiData['image'],
          'tps_prep_min': prepMinutes.round(),
          'tps_cuisson_min': cookMinutes.round(),
          'nb_parts': servings.round(),
          'note_moyenne': 4.5,
          'description': apiData['summary'],
        })
        .select()
        .single();

    final recipeId = savedRecipe['id'];

    // 2. Gérer les Ingrédients
    if (apiData['extendedIngredients'] != null) {
      for (var ing in apiData['extendedIngredients']) {
        final ingredientName = ing['nameClean'] ?? ing['name'];
        if (ingredientName == null) continue;

        var itemRes = await supabase
            .from('items')
            .select('id')
            .eq('nom', ingredientName)
            .maybeSingle();
        String itemId;

        if (itemRes == null) {
          final newItem = await supabase
              .from('items')
              .insert({
                'user_id': userId, // <-- CORRECTION ICI AUSSI
                'nom': ingredientName,
                'is_public': true,
                'spoonacular_id': ing['id'],
              })
              .select('id')
              .single();
          itemId = newItem['id'];
        } else {
          itemId = itemRes['id'];
        }

        await supabase.from('recipe_ingredients').insert({
          'recipe_id': recipeId,
          'item_id': itemId,
          'quantite': (ing['amount'] ?? 1.0).toDouble(),
          'unite': ing['unit'] ?? 'unité',
        });
      }
    }

    // 3. Gérer les Étapes de préparation
    if (apiData['analyzedInstructions'] != null &&
        (apiData['analyzedInstructions'] as List).isNotEmpty) {
      final steps = apiData['analyzedInstructions'][0]['steps'];
      for (var step in steps) {
        await supabase.from('recipe_steps').insert({
          'recipe_id': recipeId,
          'ordre': step['number'],
          'description': step['step'],
        });
      }
    }

    return await supabase
        .from('recipes')
        .select(
          '*, recipe_ingredients(quantite, unite, items(nom)), recipe_steps(ordre, description)',
        )
        .eq('id', recipeId)
        .single();
  }
}
