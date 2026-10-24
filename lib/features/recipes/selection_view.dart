import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SelectionView extends StatefulWidget {
  const SelectionView({super.key});

  @override
  State<SelectionView> createState() => _SelectionViewState();
}

class _SelectionViewState extends State<SelectionView> {
  final supabase = Supabase.instance.client;
  List<dynamic> _selections = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchBasket();
  }

  Future<void> _fetchBasket() async {
    setState(() => _isLoading = true);
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return; 

    try {
      final data = await supabase
          .from('planning_selections')
          .select('id, recipe_id, recipes(*)')
          .eq('user_id', userId);
      if (mounted) setState(() { _selections = data; _isLoading = false; });
    } catch (e) {
      debugPrint('Erreur fetch panier : $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openAssignmentModal(Map<String, dynamic> selection) {
    DateTime selectedDate = DateTime.now();
    String selectedMeal = 'Midi';
    final recipe = selection['recipes'];
    final selectionId = selection['id'];
    final recipeId = selection['recipe_id'];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final primaryColor = Theme.of(context).colorScheme.primary;
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 32, top: 32, left: 24, right: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(recipe['nom'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center, maxLines: 2),
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
                      Navigator.pop(context);
                      await _assignMealAndClearBasket(selectionId, recipeId, selectedDate, selectedMeal);
                    },
                    child: const Text('Valider pour ce repas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                )
              ],
            ),
          );
        }
      ),
    );
  }

  Future<void> _assignMealAndClearBasket(String selectionId, String recipeId, DateTime date, String mealType) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return; 

    try {
      await supabase.from('meal_plan').insert({
        'user_id': userId,
        'recipe_id': recipeId,
        'date_prevue': date.toIso8601String().split('T')[0],
        'type_repas': mealType,
      });
      await supabase.from('planning_selections').delete().eq('id', selectionId);
      _fetchBasket();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Repas programmé !')));
    } catch (e) {
      debugPrint('Erreur d\'attribution : $e');
    }
  }

  Future<void> _removeSelection(String selectionId) async {
    try {
      await supabase.from('planning_selections').delete().eq('id', selectionId);
      _fetchBasket();
    } catch (e) {
      debugPrint('Erreur suppression : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.white,
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: primaryColor))
          : _selections.isEmpty
              ? _buildEmptyState(primaryColor)
              : ListView.builder(
                  padding: const EdgeInsets.all(24),
                  itemCount: _selections.length,
                  itemBuilder: (context, index) {
                    final selection = _selections[index];
                    final recipe = selection['recipes'];
                    return _buildBasketCard(selection, recipe, primaryColor);
                  },
                ),
    );
  }

  Widget _buildEmptyState(Color primaryColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shopping_bag_outlined, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('Ta sélection est vide', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
          const SizedBox(height: 8),
          Text('Pioche des idées dans ton\ncarnet ou le catalogue mondial.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _buildBasketCard(Map<String, dynamic> selection, Map<String, dynamic> recipe, Color primaryColor) {
    final String imageUrl = (recipe['photo_url'] != null && recipe['photo_url'].toString().trim().isNotEmpty)
        ? recipe['photo_url']
        : 'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?q=80&w=200';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(imageUrl, width: 80, height: 80, fit: BoxFit.cover, errorBuilder: (c,e,s) => Container(width: 80, height: 80, color: Colors.grey.shade200)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(recipe['nom'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 36,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: primaryColor, padding: const EdgeInsets.symmetric(horizontal: 16)),
                      icon: const Icon(Icons.calendar_month, size: 16),
                      label: const Text('Programmer', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: () => _openAssignmentModal(selection),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, color: Colors.grey.shade400),
              onPressed: () => _removeSelection(selection['id']),
            )
          ],
        ),
      ),
    );
  }
}