import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class ShoppingScreen extends StatefulWidget {
  const ShoppingScreen({super.key});

  @override
  State<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends State<ShoppingScreen> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  
  List<Map<String, dynamic>> _lists = [];
  String? _selectedListId;
  List<Map<String, dynamic>> _items = [];

  // Palette de couleurs pastel pour les listes
  final List<String> _pastelColors = [
    '#BAE1FF', '#E2CBF7', '#FFB3BA', '#FFDFBA', '#FFFFBA', '#BAFFC9', '#E0E0E0',
  ];

  final List<String> _unites = ['pièce', 'g', 'kg', 'ml', 'cl', 'L', 'c.à.s', 'c.à.c'];

  @override
  void initState() {
    super.initState();
    _fetchShoppingLists();
  }

  // --- REQUÊTES SUPABASE ---

  Future<void> _fetchShoppingLists() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final res = await supabase.from('shopping_lists').select().order('created_at', ascending: true);
      if (!mounted) return;
      
      _lists = List<Map<String, dynamic>>.from(res);

      if (_lists.isNotEmpty) {
        if (!_lists.any((l) => l['id'] == _selectedListId)) {
          _selectedListId = _lists.first['id'];
        }
        await _fetchItemsForSelectedList();
      } else {
        await _saveList(null, 'Courses de la semaine', _pastelColors[0]);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchItemsForSelectedList() async {
    if (_selectedListId == null || !mounted) return;
    try {
      final res = await supabase
          .from('shopping_items')
          .select()
          .eq('list_id', _selectedListId!)
          .order('est_achete', ascending: true)
          .order('nom', ascending: true);
          
      if (mounted) {
        setState(() {
          _items = List<Map<String, dynamic>>.from(res);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveList(String? id, String title, String hexColor) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (id == null) {
        final res = await supabase.from('shopping_lists').insert({
          'titre': title, 'couleur': hexColor, 'user_id': userId,
        }).select().single();
        if (mounted) setState(() => _selectedListId = res['id']);
      } else {
        await supabase.from('shopping_lists').update({'titre': title, 'couleur': hexColor}).eq('id', id);
      }
      await _fetchShoppingLists();
    } catch (e) {
      debugPrint('Erreur sauvegarde liste: $e');
    }
  }

  Future<void> _deleteList(String id) async {
    try {
      await supabase.from('shopping_lists').delete().eq('id', id);
      await _fetchShoppingLists();
    } catch (e) {
      debugPrint('Erreur suppression liste: $e');
    }
  }

  Future<void> _saveItem(String? id, String name, double? qty, String? unit, String listId) async {
    try {
      final data = {
        'nom': name[0].toUpperCase() + name.substring(1), 
        'quantite': qty, // Peut être nul si non renseigné
        'unite': unit,   // Peut être nul si non renseigné
        'list_id': listId,
      };

      if (id == null) {
        data['est_achete'] = false;
        await supabase.from('shopping_items').insert(data);
      } else {
        await supabase.from('shopping_items').update(data).eq('id', id);
      }
      
      if (mounted) setState(() => _selectedListId = listId);
      await _fetchItemsForSelectedList();
    } catch (e) {
      debugPrint('Erreur sauvegarde article: $e');
    }
  }

  Future<void> _deleteItem(String id) async {
    try {
      await supabase.from('shopping_items').delete().eq('id', id);
      await _fetchItemsForSelectedList();
    } catch (e) {
      debugPrint('Erreur suppression article: $e');
    }
  }

  Future<void> _toggleItem(String id, bool currentStatus) async {
    if (mounted) {
      setState(() => _items.firstWhere((i) => i['id'] == id)['est_achete'] = !currentStatus);
    }
    try {
      await supabase.from('shopping_items').update({'est_achete': !currentStatus}).eq('id', id);
      await _fetchItemsForSelectedList();
    } catch (e) {
      debugPrint('Erreur toggle: $e');
    }
  }

  Future<void> _deleteCheckedItems() async {
    try {
      await supabase.from('shopping_items').delete().eq('list_id', _selectedListId!).eq('est_achete', true);
      await _fetchItemsForSelectedList();
    } catch (e) {
      debugPrint('Erreur nettoyage: $e');
    }
  }

  // --- ALGORITHME DE GÉNÉRATION ---
  Future<void> _generateFromMealPlan() async {
    setState(() => _isLoading = true);
    try {
      final todayStr = DateTime.now().toIso8601String().split('T')[0];
      final mealPlans = await supabase.from('meal_plan').select('recipe_id').gte('date_prevue', todayStr);

      if ((mealPlans as List).isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucun repas programmé à venir !')));
        setState(() => _isLoading = false);
        return;
      }

      final recipeIds = mealPlans.map((m) => m['recipe_id']).toSet().toList();
      final ingredientsRes = await supabase.from('recipe_ingredients').select('quantite, unite, items(nom)').inFilter('recipe_id', recipeIds);

      Map<String, double> aggregatedMap = {};
      for (var ing in ingredientsRes) {
        final nom = ing['items']?['nom'] ?? 'Article';
        final unite = ing['unite'] ?? 'pièce';
        final qte = (ing['quantite'] as num?)?.toDouble() ?? 1.0;
        
        final key = '${nom.toLowerCase().trim()}_$unite';
        aggregatedMap[key] = (aggregatedMap[key] ?? 0.0) + qte;
      }

      await supabase.from('shopping_items').delete().eq('list_id', _selectedListId!);

      for (var entry in aggregatedMap.entries) {
        final parts = entry.key.split('_');
        final nom = parts[0];
        final unite = parts[1];
        await supabase.from('shopping_items').insert({
          'list_id': _selectedListId,
          'nom': nom[0].toUpperCase() + nom.substring(1),
          'quantite': entry.value,
          'unite': unite,
          'est_achete': false,
        });
      }

      await _fetchItemsForSelectedList();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Liste auto-générée avec succès ! ✨')));
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  Color _hexToColor(String hex) => Color(int.parse(hex.replaceFirst('#', '0xFF')));

  // --- MODALES (BOTTOM SHEETS) ---

  void _showListBottomSheet({Map<String, dynamic>? existingList}) {
    final titleController = TextEditingController(text: existingList?['titre'] ?? '');
    String selectedColor = existingList?['couleur'] ?? _pastelColors[0];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final primaryColor = Theme.of(context).colorScheme.primary;
          return Container(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 24, top: 24, left: 24, right: 24),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)))),
                const SizedBox(height: 24),
                Text(existingList == null ? 'Nouvelle liste' : 'Modifier la liste', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(hintText: 'Nom de la liste', filled: true, fillColor: Colors.grey.shade100, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
                ),
                const SizedBox(height: 20),
                const Text('Couleur', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12, runSpacing: 12,
                  children: _pastelColors.map((hex) {
                    final isSelected = selectedColor == hex;
                    return GestureDetector(
                      onTap: () => setModalState(() => selectedColor = hex),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 42, height: 42,
                        decoration: BoxDecoration(
                          color: _hexToColor(hex),
                          shape: BoxShape.circle,
                          border: isSelected ? Border.all(color: Colors.black87, width: 2.5) : Border.all(color: Colors.transparent),
                        ),
                        child: isSelected ? const Icon(Icons.check, size: 20, color: Colors.black87) : null,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    if (existingList != null) ...[
                      IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () { Navigator.pop(context); _deleteList(existingList['id']); }),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                          onPressed: () {
                            if (titleController.text.trim().isNotEmpty) {
                              Navigator.pop(context);
                              _saveList(existingList?['id'], titleController.text.trim(), selectedColor);
                            }
                          },
                          child: const Text('Enregistrer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showItemBottomSheet({Map<String, dynamic>? existingItem}) {
    final nameController = TextEditingController(text: existingItem?['nom'] ?? '');
    final qtyController = TextEditingController(text: existingItem?['quantite']?.toString() ?? '');
    String selectedUnit = existingItem?['unite'] ?? 'pièce';
    String listeAttribuee = existingItem?['list_id'] ?? _selectedListId!;

    if (!_unites.contains(selectedUnit)) _unites.add(selectedUnit);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final primaryColor = Theme.of(context).colorScheme.primary;
          return Container(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 24, top: 24, left: 24, right: 24),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)))),
                const SizedBox(height: 24),
                Text(existingItem == null ? 'Ajouter un article' : 'Modifier l\'article', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(hintText: 'Nom de l\'article (ex: Ruban adhésif)', filled: true, fillColor: Colors.grey.shade100, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
                ),
                const SizedBox(height: 16),
                
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: qtyController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(hintText: 'Qté (Optionnel)', filled: true, fillColor: Colors.grey.shade100, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        value: selectedUnit,
                        decoration: InputDecoration(filled: true, fillColor: Colors.grey.shade100, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 16)),
                        items: _unites.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                        onChanged: (val) => setModalState(() => selectedUnit = val!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                DropdownButtonFormField<String>(
                  value: listeAttribuee,
                  decoration: InputDecoration(filled: true, fillColor: Colors.grey.shade50, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 16)),
                  items: _lists.map((l) => DropdownMenuItem<String>(value: l['id'], child: Text(l['titre'], overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (val) => setModalState(() => listeAttribuee = val!),
                ),
                const SizedBox(height: 32),

                Row(
                  children: [
                    if (existingItem != null) ...[
                      IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 28), onPressed: () { Navigator.pop(context); _deleteItem(existingItem['id']); }),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: SizedBox(
                        height: 54,
                        child: FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                          onPressed: () {
                            if (nameController.text.trim().isNotEmpty) {
                              Navigator.pop(context);
                              // Si le champ est vide, on envoie "null"
                              final qty = qtyController.text.trim().isEmpty ? null : double.tryParse(qtyController.text);
                              final unit = qtyController.text.trim().isEmpty ? null : selectedUnit;
                              
                              _saveItem(existingItem?['id'], nameController.text.trim(), qty, unit, listeAttribuee);
                            }
                          },
                          child: const Text('Enregistrer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final String currentDate = DateFormat('MMM dd, yyyy').format(DateTime.now());

    Color listColor = primaryColor;
    if (_selectedListId != null && _lists.isNotEmpty) {
      final currentList = _lists.firstWhere((l) => l['id'] == _selectedListId, orElse: () => _lists.first);
      listColor = _hexToColor(currentList['couleur'] ?? _pastelColors[0]);
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome, color: Colors.black87),
            tooltip: 'Générer depuis l\'agenda',
            onPressed: _generateFromMealPlan,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded, color: Colors.black87),
            tooltip: 'Nettoyer les articles achetés',
            onPressed: _deleteCheckedItems,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- EN-TÊTE TYPOGRAPHIQUE DESIGN ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Mes Courses',
                    style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.black87, letterSpacing: -0.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    currentDate,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // --- SÉLECTEUR DE LISTES (STYLE ONGLET PILLULE) ---
            if (_lists.isNotEmpty)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100, 
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ..._lists.map((list) {
                        final isSelected = list['id'] == _selectedListId;

                        return GestureDetector(
                          onLongPress: () => _showListBottomSheet(existingList: list),
                          onTap: () {
                            if (mounted) {
                              setState(() => _selectedListId = list['id']);
                              _fetchItemsForSelectedList();
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.white : Colors.transparent, 
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: isSelected ? [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2))] : [],
                            ),
                            child: Center(
                              child: Text(
                                list['titre'],
                                style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.w500, fontSize: 14, color: isSelected ? Colors.black87 : Colors.grey.shade600),
                              ),
                            ),
                          ),
                        );
                      }),
                      GestureDetector(
                        onTap: () => _showListBottomSheet(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          color: Colors.transparent,
                          child: const Icon(Icons.add, color: Colors.grey, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            
            const SizedBox(height: 16),

            // --- LISTE DES ARTICLES ---
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: primaryColor))
                  : _items.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.shopping_basket_outlined, size: 60, color: Colors.grey.shade200),
                              const SizedBox(height: 16),
                              Text('Ta liste est vide.', style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
                              const SizedBox(height: 4),
                              Text('Clique sur la baguette en haut ou sur +.', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(left: 24, right: 24, top: 8, bottom: 100),
                          itemCount: _items.length,
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            final isComplete = item['est_achete'] ?? false;
                            
                            // Vérifie si la quantité existe
                            final hasQuantity = item['quantite'] != null && item['quantite'].toString().isNotEmpty;
                            final qte = item['quantite'];
                            final unite = item['unite'] ?? '';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.grey.shade100, width: 1.5),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onLongPress: () => _showItemBottomSheet(existingItem: item),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        // Case à cocher dynamique (couleur de la liste)
                                        GestureDetector(
                                          onTap: () => _toggleItem(item['id'], isComplete),
                                          child: AnimatedContainer(
                                            duration: const Duration(milliseconds: 200),
                                            width: 26, height: 26,
                                            decoration: BoxDecoration(
                                              color: isComplete ? listColor : Colors.transparent,
                                              shape: BoxShape.circle,
                                              border: Border.all(color: isComplete ? listColor : Colors.grey.shade400, width: 1.5),
                                            ),
                                            child: isComplete ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item['nom'],
                                                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16, decoration: isComplete ? TextDecoration.lineThrough : null, color: isComplete ? Colors.grey.shade400 : Colors.black87),
                                              ),
                                              // Si la quantité est renseignée, on l'affiche, sinon on ne met rien !
                                              if (hasQuantity) ...[
                                                const SizedBox(height: 2),
                                                Text('$qte $unite', style: TextStyle(color: isComplete ? Colors.grey.shade300 : Colors.grey.shade500, fontSize: 13)),
                                              ]
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showItemBottomSheet(),
        backgroundColor: primaryColor,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
    );
  }
}