import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'preparation_screen.dart';
import 'edit_recipe_screen.dart';

class RecipeDetailScreen extends StatefulWidget {
  final Map<String, dynamic> recipe;

  const RecipeDetailScreen({super.key, required this.recipe});

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  final supabase = Supabase.instance.client;
  
  // Variable d'état pour l'affichage de la note en temps réel
  late double _noteMoyenne;

  @override
  void initState() {
    super.initState();
    // On initialise avec la donnée de la base de données (ou 4.5 par défaut)
    _noteMoyenne = (widget.recipe['note_moyenne'] ?? 4.5).toDouble();
  }

  Future<Map<String, dynamic>> _fetchRecipeDetails() async {
    final recipeId = widget.recipe['id'];
    
    final ingredients = await supabase
        .from('recipe_ingredients')
        .select('quantite, unite, items(nom)')
        .eq('recipe_id', recipeId);
        
    final steps = await supabase
        .from('recipe_steps')
        .select('description, ordre')
        .eq('recipe_id', recipeId)
        .order('ordre', ascending: true);

    return {'ingredients': ingredients, 'steps': steps};
  }

  void _supprimerRecette() async {
    try {
      await supabase.from('recipes').delete().eq('id', widget.recipe['id']);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recette supprimée')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Supprimer la recette ?'),
        content: const Text('Cette action est irréversible.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(context);
              _supprimerRecette();
            },
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }

  // --- MODALE POUR LAISSER UN AVIS ---
  void _showReviewSheet(BuildContext context) {
    int noteSelectionnee = _noteMoyenne.round();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) => StatefulBuilder( 
        builder: (context, setModalState) {
          return Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Que penses-tu de cette recette ?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return IconButton(
                      iconSize: 40,
                      icon: Icon(
                        index < noteSelectionnee ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                      ),
                      onPressed: () {
                        setModalState(() {
                          noteSelectionnee = index + 1;
                        });
                      },
                    );
                  }),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () async {
                      try {
                        // 1. Sauvegarder dans Supabase
                        await supabase
                            .from('recipes')
                            .update({'note_moyenne': noteSelectionnee})
                            .eq('id', widget.recipe['id']);
                        
                        // 2. Mettre à jour l'interface locale
                        setState(() {
                          _noteMoyenne = noteSelectionnee.toDouble();
                        });

                        if (mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Avis enregistré !')));
                        }
                      } catch (e) {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
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

  // --- MODALE POUR PROGRAMMER LE REPAS ---
  void _showScheduleSheet(BuildContext context) {
    DateTime selectedDate = DateTime.now();
    String selectedMeal = 'Midi';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final primaryColor = Theme.of(context).colorScheme.primary;

          return Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Programmer cette recette', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                
                // Sélecteur de date
                ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  tileColor: Colors.grey.shade100,
                  leading: Icon(Icons.calendar_month_rounded, color: primaryColor),
                  title: Text('${selectedDate.day}/${selectedDate.month}/${selectedDate.year}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  trailing: const Icon(Icons.edit, size: 20, color: Colors.grey),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setModalState(() => selectedDate = picked);
                    }
                  },
                ),
                const SizedBox(height: 24),
                
                // Sélecteur de repas
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: ['Matin', 'Midi', 'Soir'].map((meal) {
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
                    style: FilledButton.styleFrom(
                      backgroundColor: primaryColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () async {
                      try {
                        final userId = supabase.auth.currentUser?.id;
                        await supabase.from('meal_plan').insert({
                          'date_prevue': selectedDate.toIso8601String().split('T')[0],
                          'type_repas': selectedMeal,
                          'recipe_id': widget.recipe['id'],
                          'user_id': userId,
                        });
                        
                        if (mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recette programmée !')));
                        }
                      } catch (e) {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
                      }
                    },
                    child: const Text('Programmer', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
    
    final tpsPrep = widget.recipe['tps_prep_min'] ?? 0;
    final tpsCuisson = widget.recipe['tps_cuisson_min'] ?? 0;
    final nbParts = widget.recipe['nb_parts'] ?? 2;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned(
            top: 0, left: 0, right: 0,
            height: MediaQuery.of(context).size.height * 0.45, // Correction du multiplicateur
            child: Image.network(
              widget.recipe['photo_url'] ?? 'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?q=80&w=800',
              fit: BoxFit.cover,
            ),
          ),
          FutureBuilder<Map<String, dynamic>>(
            future: _fetchRecipeDetails(),
            builder: (context, snapshot) {
              final isLoading = snapshot.connectionState == ConnectionState.waiting;
              final ingredients = snapshot.data?['ingredients'] as List<dynamic>? ?? [];
              final steps = snapshot.data?['steps'] as List<dynamic>? ?? [];

              return CustomScrollView(
                slivers: [
                  SliverAppBar(
                    expandedHeight: MediaQuery.of(context).size.height * 0.35, // Correction du multiplicateur
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    pinned: true,
                    leading: Padding(
                      padding: const EdgeInsets.only(left: 12.0, top: 8.0, bottom: 8.0),
                      child: CircleAvatar(
                        backgroundColor: primaryColor,
                        child: IconButton(icon: const Icon(Icons.chevron_left, color: Colors.white), onPressed: () => Navigator.pop(context)),
                      ),
                    ),
                    actions: [
                      GestureDetector(
                        onTap: () async {
                          final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => EditRecipeScreen(recipe: widget.recipe)));
                          if (result == true) setState(() {});
                        },
                        child: const CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.edit_outlined, color: Colors.black87)),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        backgroundColor: Colors.white,
                        child: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () => _showDeleteDialog(context)),
                      ),
                      const SizedBox(width: 16),
                    ],
                  ),
                  SliverToBoxAdapter(
                    child: Container(
                      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                      child: isLoading 
                        ? const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
                        : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
                            const SizedBox(height: 16),
                            Text(widget.recipe['nom'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, height: 1.2)),
                            const SizedBox(height: 4),
                            Text(widget.recipe['type_plat'] ?? '', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _buildInfoPill(context, Icons.kitchen, '$tpsPrep', 'Prépa'),
                                _buildInfoPill(context, Icons.local_fire_department_outlined, '$tpsCuisson', 'Cuisson'),
                                _buildInfoPill(context, Icons.people_outline, '${nbParts < 10 ? '0$nbParts' : nbParts}', 'Parts'),
                                _buildInfoPill(context, Icons.star_border, '$_noteMoyenne', 'Moy'), 
                              ],
                            ),
                            const SizedBox(height: 24),
                            const Text('Ingrédients', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            if (ingredients.isEmpty) const Text('Aucun ingrédient.', style: TextStyle(color: Colors.grey)),
                            Wrap(
                              spacing: 8, runSpacing: 12,
                              children: ingredients.map((ing) {
                                final nom = ing['items']?['nom'] ?? 'Inconnu';
                                final qty = '${ing['quantite'] ?? ''} ${ing['unite'] ?? ''}'.trim();
                                return SizedBox(
                                  width: (MediaQuery.of(context).size.width - 48) / 2, // Correction de la soustraction
                                  child: _buildIngredientItem(context, qty, nom)
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 24),
                            const Text('Préparation', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            if (steps.isEmpty) const Text('Aucune étape.', style: TextStyle(color: Colors.grey)),
                            ...steps.map((step) => _buildStepItem(context, step['ordre'], step['description'])),
                            const SizedBox(height: 16),
                            Center(
                              child: TextButton.icon(
                                onPressed: () => _showReviewSheet(context),
                                icon: Icon(Icons.star_border_rounded, color: primaryColor),
                                label: Text('Laisser un avis', style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                    ),
                  ),
                ],
              );
            }
          ),
        ],
      ),
      
      // La zone de boutons en bas avec le calendrier
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 52,
                child: FloatingActionButton.extended(
                  heroTag: 'play_btn', 
                  onPressed: () {
                    // ADAPTATION ICI : On fusionne les données pour le nouvel écran PreparationScreen
                    final recipeComplete = Map<String, dynamic>.from(widget.recipe);
                    
                    // On récupère le snapshot de l'UI pour ne pas avoir à refaire une requête
                    // Note: c'est asynchrone, mais l'utilisateur ne peut pas cliquer si c'est null
                    // car les données sont déjà affichées.
                    // On utilise le FutureBuilder pour récupérer les données actuelles
                    _fetchRecipeDetails().then((details) {
                      recipeComplete['recipe_ingredients'] = details['ingredients'];
                      recipeComplete['recipe_steps'] = details['steps'];

                      Navigator.push(
                        context, 
                        MaterialPageRoute(
                          builder: (context) => PreparationScreen(recipe: recipeComplete)
                        )
                      );
                    });
                  },
                  elevation: 6,
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  icon: const Icon(Icons.play_arrow_rounded, size: 24, color: Colors.white),
                  label: const Text('Lancer la préparation', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              height: 52, width: 52,
              child: FloatingActionButton(
                heroTag: 'calendar_btn',
                onPressed: () => _showScheduleSheet(context),
                elevation: 6,
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Icon(Icons.calendar_month_rounded, color: primaryColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoPill(BuildContext context, IconData icon, String value, String label) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return Container(
      width: 60, height: 85,
      decoration: BoxDecoration(border: Border.all(color: primaryColor, width: 1.2), borderRadius: BorderRadius.circular(30)),
      child: Column(
        children: [
          Expanded(child: Icon(icon, color: Colors.black87, size: 20)),
          Container(
            height: 42, width: double.infinity,
            decoration: BoxDecoration(color: primaryColor, borderRadius: BorderRadius.circular(30)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white, height: 1)),
                Text(label, style: const TextStyle(fontSize: 9, color: Colors.white, height: 1.2)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIngredientItem(BuildContext context, String qty, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 4.0, right: 6.0), child: CircleAvatar(radius: 3, backgroundColor: Theme.of(context).colorScheme.primary)),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(color: Colors.black87, fontSize: 12, height: 1.2),
              children: [
                if (qty.isNotEmpty) TextSpan(text: '$qty ', style: const TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(text: text),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStepItem(BuildContext context, int stepNumber, String text) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20, height: 20,
            margin: const EdgeInsets.only(right: 12, top: 2),
            decoration: BoxDecoration(color: primaryColor, shape: BoxShape.circle),
            child: Center(child: Text('$stepNumber', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10))),
          ),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.black87, fontSize: 13, height: 1.4))),
        ],
      ),
    );
  }
}