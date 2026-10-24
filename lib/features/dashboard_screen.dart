import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'recipe_detail_screen.dart';
import 'agenda_screen.dart';
// IMPORTANT : Ajuste ces imports selon la structure de ton projet
import '../features/todo_screen.dart'; 
import '../features/shopping_screen.dart'; 

class DashboardScreen extends StatefulWidget {
  final VoidCallback? onNavigateToShopping;

  const DashboardScreen({super.key, this.onNavigateToShopping});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;

  // Données de la journée
  Map<String, dynamic>? _midiMeal;
  Map<String, dynamic>? _soirMeal;
  List<Map<String, dynamic>> _todos = [];
  List<Map<String, dynamic>> _activeShoppingLists = [];
  
  // Statistiques pour l'en-tête
  int _totalTasksToday = 0;
  int _completedTasksToday = 0;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Color _hexToColor(String hex) => Color(int.parse(hex.replaceFirst('#', '0xFF')));

  Future<void> _loadDashboardData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    try {
      final todayStr = DateTime.now().toIso8601String().split('T')[0];

      // 1. Récupération des Repas du jour
      final mealsRes = await supabase
          .from('meal_plan')
          .select('type_repas, recipes(*)')
          .eq('date_prevue', todayStr);
      
      final todayMeals = List<Map<String, dynamic>>.from(mealsRes);
      _midiMeal = null;
      _soirMeal = null;

      for (var m in todayMeals) {
        // Sécurisation : Supabase peut renvoyer une Liste ou une Map selon la structure
        Map<String, dynamic>? recipeData;
        if (m['recipes'] is List && (m['recipes'] as List).isNotEmpty) {
          recipeData = (m['recipes'] as List).first as Map<String, dynamic>;
        } else if (m['recipes'] is Map) {
          recipeData = m['recipes'] as Map<String, dynamic>;
        }

        if (recipeData != null) {
          if (m['type_repas'] == 'Midi') _midiMeal = recipeData;
          if (m['type_repas'] == 'Soir') _soirMeal = recipeData;
        }
      }

      // 2. Récupération des Tâches (Du jour + Urgentes non datées)
      final allTasksRes = await supabase
          .from('tasks')
          .select()
          .eq('est_complete', false);
          
      final allTasks = List<Map<String, dynamic>>.from(allTasksRes);
      
      // Filtrer pour l'affichage (Date du jour OU Haute priorité)
      _todos = allTasks.where((t) => 
        t['date_echeance'] == todayStr || t['priorite'] == 'Haute'
      ).toList();
      
      // Trier par priorité puis date
      _todos.sort((a, b) {
        if (a['priorite'] == 'Haute' && b['priorite'] != 'Haute') return -1;
        if (a['priorite'] != 'Haute' && b['priorite'] == 'Haute') return 1;
        return 0;
      });

      // On limite l'affichage à 4 tâches pour ne pas surcharger la chronologie
      if (_todos.length > 4) _todos = _todos.sublist(0, 4);

      // Calcul des stats pour l'en-tête
      final tasksTodayStats = await supabase
          .from('tasks')
          .select('est_complete')
          .eq('date_echeance', todayStr);
          
      _totalTasksToday = tasksTodayStats.length;
      _completedTasksToday = tasksTodayStats.where((t) => t['est_complete'] == true).length;

      // 3. Récupération des Listes de courses dynamiques
      final listsRes = await supabase.from('shopping_lists').select('id, titre, couleur');
      List<Map<String, dynamic>> activeShopping = [];
      
      for (var l in listsRes) {
        final itemsRes = await supabase
            .from('shopping_items')
            .select('id')
            .eq('list_id', l['id'])
            .eq('est_achete', false);
            
        if (itemsRes.isNotEmpty) {
          activeShopping.add({
            'titre': l['titre'],
            'count': itemsRes.length,
            'couleur': l['couleur'] ?? '#E0E0E0'
          });
        }
      }
      _activeShoppingLists = activeShopping;

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Erreur Dashboard: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleDashboardTask(String id) async {
    setState(() {
      _todos.removeWhere((t) => t['id'] == id);
      _completedTasksToday++;
    });
    try {
      await supabase.from('tasks').update({'est_complete': true}).eq('id', id);
    } catch (e) {
      debugPrint('Erreur validation tâche: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final String currentDate = DateFormat('EEEE d MMMM', 'fr_FR').format(DateTime.now());
    final formattedDate = currentDate[0].toUpperCase() + currentDate.substring(1);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: primaryColor))
            : RefreshIndicator(
                onRefresh: _loadDashboardData,
                color: primaryColor,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    // ==========================================
                    // 1. EN-TÊTE FIXE (Date & Bilan)
                    // ==========================================
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 24.0, right: 24.0, top: 32.0, bottom: 24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              formattedDate,
                              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.black87, letterSpacing: -1),
                            ),
                            const SizedBox(height: 8),
                            // Mini bilan de la journée
                            Row(
                              children: [
                                _buildMiniStat(Icons.restaurant_menu_rounded, '${(_midiMeal != null ? 1 : 0) + (_soirMeal != null ? 1 : 0)}/2 repas'),
                                const SizedBox(width: 16),
                                _buildMiniStat(Icons.check_circle_outline_rounded, '$_completedTasksToday/$_totalTasksToday tâches'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ==========================================
                    // 2. LA BARRE D'ACTIONS ÉCLAIRS
                    // ==========================================
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Row(
                          children: [
                            Expanded(child: _buildQuickAction(context, 'Agenda', Icons.calendar_month_rounded, primaryColor, () async {
                              await Navigator.push(context, MaterialPageRoute(builder: (context) => const AgendaScreen()));
                              _loadDashboardData();
                            })),
                            const SizedBox(width: 12),
                            Expanded(child: _buildQuickAction(context, 'Tâche', Icons.add_task_rounded, Colors.orange.shade700, () async {
                              await Navigator.push(context, MaterialPageRoute(builder: (context) => const TodoScreen()));
                              _loadDashboardData();
                            })),
                            const SizedBox(width: 12),
                            Expanded(child: _buildQuickAction(context, 'Courses', Icons.shopping_basket_rounded, Colors.blue.shade700, () {
                              if (widget.onNavigateToShopping != null) {
                                widget.onNavigateToShopping!();
                              } else {
                                Navigator.push(context, MaterialPageRoute(builder: (context) => const ShoppingScreen()));
                              }
                            })),
                          ],
                        ),
                      ),
                    ),

                    // ==========================================
                    // 3. LA CHRONOLOGIE DE LA JOURNÉE
                    // ==========================================
                    SliverPadding(
                      padding: const EdgeInsets.only(top: 40, left: 24, right: 24, bottom: 100),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          
                          // --- REPAS DE MIDI (Uniquement si programmé) ---
                          if (_midiMeal != null) ...[
                            _buildTimelineHeader('Ce midi', Icons.wb_sunny_rounded, primaryColor),
                            const SizedBox(height: 16),
                            _buildModernRecipeCard(context, _midiMeal!, primaryColor),
                            const SizedBox(height: 40),
                          ],
                          
                          // --- TÂCHES DU JOUR ---
                          _buildTimelineHeader('À faire aujourd\'hui', Icons.format_list_bulleted_rounded, Colors.black87),
                          const SizedBox(height: 16),
                          _todos.isEmpty
                            ? _buildEmptyTimelineState('Ta journée est libre !', 'Ajouter une tâche', Icons.add_task_rounded, () async {
                                await Navigator.push(context, MaterialPageRoute(builder: (context) => const TodoScreen()));
                                _loadDashboardData();
                              })
                            : Container(
                                padding: const EdgeInsets.only(top: 16, bottom: 4, left: 16, right: 16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: Colors.grey.shade200, width: 1.5),
                                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
                                ),
                                child: Column(
                                  children: _todos.map((todo) => _buildTodoItem(primaryColor, todo, todo['priorite'] == 'Haute')).toList(),
                                ),
                              ),

                          const SizedBox(height: 40),

                          // --- REPAS DU SOIR (Uniquement si programmé) ---
                          if (_soirMeal != null) ...[
                            _buildTimelineHeader('Ce soir', Icons.nights_stay_rounded, Colors.indigo),
                            const SizedBox(height: 16),
                            _buildModernRecipeCard(context, _soirMeal!, primaryColor),
                            const SizedBox(height: 40),
                          ],

                          // --- POINT SUR LES COURSES ---
                          if (_activeShoppingLists.isNotEmpty) ...[
                            _buildTimelineHeader('Point sur les courses', Icons.shopping_bag_outlined, Colors.black87),
                            const SizedBox(height: 16),
                            ..._activeShoppingLists.map((list) {
                              final listColor = _hexToColor(list['couleur']);
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [BoxShadow(color: listColor.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))],
                                ),
                                child: Material(
                                  color: listColor,
                                  borderRadius: BorderRadius.circular(20),
                                  child: InkWell(
                                    onTap: () {
                                      if (widget.onNavigateToShopping != null) {
                                        widget.onNavigateToShopping!();
                                      } else {
                                        Navigator.push(context, MaterialPageRoute(builder: (context) => const ShoppingScreen()));
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(20),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                            child: const Icon(Icons.shopping_basket_outlined, color: Colors.black87),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(list['titre'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
                                                const SizedBox(height: 2),
                                                Text('${list['count']} articles à acheter', style: const TextStyle(color: Colors.black54, fontSize: 13, fontWeight: FontWeight.w500)),
                                              ],
                                            ),
                                          ),
                                          const Icon(Icons.chevron_right, color: Colors.black54),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ],
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  // --- WIDGETS REUTILISABLES POUR LE NOUVEAU DESIGN ---

  Widget _buildMiniStat(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade500),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildQuickAction(BuildContext context, String label, IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            border: Border.all(color: color.withOpacity(0.2)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimelineHeader(String title, IconData icon, Color iconColor) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: iconColor.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, size: 18, color: iconColor),
        ),
        const SizedBox(width: 12),
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
      ],
    );
  }

  Widget _buildEmptyTimelineState(String message, String buttonText, IconData icon, VoidCallback onTap) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200, style: BorderStyle.solid),
      ),
      child: Column(
        children: [
          Text(message, style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onTap,
            icon: Icon(icon, size: 18),
            label: Text(buttonText, style: const TextStyle(fontWeight: FontWeight.bold)),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.primary,
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildTodoItem(Color color, Map<String, dynamic> task, bool isHaute) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _toggleDashboardTask(task['id']),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              children: [
                Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(
                    border: Border.all(color: isHaute ? Colors.redAccent : Colors.grey.shade400, width: 2),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(task['titre'], style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.black87)),
                ),
                if (isHaute)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: const Text('Urgent', style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernRecipeCard(BuildContext context, Map<String, dynamic> recipe, Color primaryColor) {
    final tempsTotal = (recipe['tps_prep_min'] ?? 0) + (recipe['tps_cuisson_min'] ?? 0);
    // On sécurise le parsing de la note au cas où ce serait null
    final note = double.tryParse(recipe['note_moyenne']?.toString() ?? '4.5')?.toStringAsFixed(1) ?? '4.5';

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => RecipeDetailScreen(recipe: recipe))),
      child: Container(
        height: 180,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: Colors.grey.shade200,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 15, offset: const Offset(0, 8))],
          image: DecorationImage(
            image: NetworkImage(recipe['photo_url'] ?? 'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?q=80&w=800'),
            fit: BoxFit.cover,
          ),
        ),
        child: Stack(
          children: [
            // Dégradé sombre pour toujours bien lire le texte
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                ),
              ),
            ),
            Positioned(
              top: 16, left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(16)),
                child: Row(
                  children: [
                    const Icon(Icons.schedule, size: 14),
                    const SizedBox(width: 4),
                    Text('$tempsTotal min', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 16, left: 16, right: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(recipe['nom'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(recipe['type_plat'] ?? 'Plat', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
                      Row(
                        children: [
                          const Icon(Icons.star, size: 14, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(note, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                        ],
                      )
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}