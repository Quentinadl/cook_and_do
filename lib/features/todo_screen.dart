import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class TodoScreen extends StatefulWidget {
  const TodoScreen({super.key});

  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  
  List<Map<String, dynamic>> _lists = [];
  String? _selectedListId;
  List<Map<String, dynamic>> _tasks = [];
  
  String _sortBy = 'Priorité'; // 'Priorité' ou 'Échéance'

  final List<String> _pastelColors = [
    '#E2CBF7', '#BAE1FF', '#FFB3BA', '#FFDFBA', '#FFFFBA', '#BAFFC9', '#E0E0E0',
  ];

  @override
  void initState() {
    super.initState();
    _fetchTaskLists();
  }

  // --- REQUÊTES SUPABASE ---

  Future<void> _fetchTaskLists() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final res = await supabase.from('task_lists').select().order('created_at', ascending: true);
      if (!mounted) return;
      
      _lists = List<Map<String, dynamic>>.from(res);

      if (_lists.isNotEmpty) {
        if (!_lists.any((l) => l['id'] == _selectedListId)) {
          _selectedListId = _lists.first['id'];
        }
        await _fetchTasksForSelectedList();
      } else {
        await _saveList(null, 'Aujourd\'hui', _pastelColors[0]);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchTasksForSelectedList() async {
    if (_selectedListId == null || !mounted) return;
    try {
      final query = supabase.from('tasks').select().eq('list_id', _selectedListId!);
      List<dynamic> res;
      
      if (_sortBy == 'Priorité') {
        res = await query
            .order('est_complete', ascending: true)
            .order('priorite', ascending: true)
            .order('date_echeance', ascending: true, nullsFirst: false);
      } else {
        res = await query
            .order('est_complete', ascending: true)
            .order('date_echeance', ascending: true, nullsFirst: false)
            .order('priorite', ascending: true);
      }

      if (mounted) {
        setState(() {
          _tasks = List<Map<String, dynamic>>.from(res);
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
        final res = await supabase.from('task_lists').insert({
          'titre': title, 'couleur': hexColor, 'user_id': userId,
        }).select().single();
        if (mounted) setState(() => _selectedListId = res['id']);
      } else {
        await supabase.from('task_lists').update({'titre': title, 'couleur': hexColor}).eq('id', id);
      }
      await _fetchTaskLists();
    } catch (e) {
      debugPrint('Erreur sauvegarde liste: $e');
    }
  }

  Future<void> _deleteList(String id) async {
    try {
      await supabase.from('task_lists').delete().eq('id', id);
      await _fetchTaskLists();
    } catch (e) {
      debugPrint('Erreur suppression liste: $e');
    }
  }

  Future<void> _toggleTask(String id, bool currentStatus) async {
    if (mounted) {
      setState(() => _tasks.firstWhere((t) => t['id'] == id)['est_complete'] = !currentStatus);
    }
    try {
      await supabase.from('tasks').update({'est_complete': !currentStatus}).eq('id', id);
      await _fetchTasksForSelectedList();
    } catch (e) {
      debugPrint('Erreur toggle: $e');
    }
  }

  // Fonction pour basculer le drapeau de priorité
  Future<void> _togglePriority(String id, String currentPriority) async {
    final newPriority = currentPriority == 'Haute' ? 'Normale' : 'Haute';
    if (mounted) {
      setState(() => _tasks.firstWhere((t) => t['id'] == id)['priorite'] = newPriority);
    }
    try {
      await supabase.from('tasks').update({'priorite': newPriority}).eq('id', id);
      await _fetchTasksForSelectedList();
    } catch (e) {
      debugPrint('Erreur toggle priorite: $e');
    }
  }

  Future<void> _saveTask(String? id, String title, String desc, String prio, DateTime? date, String listId) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      final data = {
        'titre': title,
        'description': desc,
        'priorite': prio,
        'date_echeance': date?.toIso8601String().split('T')[0],
        'list_id': listId,
        'user_id': userId,
      };

      if (id == null) {
        data['est_complete'] = "false";
        await supabase.from('tasks').insert(data);
      } else {
        await supabase.from('tasks').update(data).eq('id', id);
      }
      
      if (mounted) setState(() => _selectedListId = listId);
      await _fetchTasksForSelectedList();
    } catch (e) {
      debugPrint('Erreur sauvegarde tâche: $e');
    }
  }

  Future<void> _deleteTask(String id) async {
    try {
      await supabase.from('tasks').delete().eq('id', id);
      await _fetchTasksForSelectedList();
    } catch (e) {
      debugPrint('Erreur suppression tâche: $e');
    }
  }

  Future<void> _deleteCompletedTasks() async {
    try {
      await supabase.from('tasks').delete().eq('list_id', _selectedListId!).eq('est_complete', true);
      await _fetchTasksForSelectedList();
    } catch (e) {
      debugPrint('Erreur nettoyage: $e');
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
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: () {
                          Navigator.pop(context);
                          _deleteList(existingList['id']);
                        },
                      ),
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

  void _showTaskBottomSheet({Map<String, dynamic>? existingTask}) {
    final titleController = TextEditingController(text: existingTask?['titre'] ?? '');
    final descController = TextEditingController(text: existingTask?['description'] ?? '');
    String prioriteSelectionnee = existingTask?['priorite'] ?? 'Normale';
    DateTime? dateEcheance = existingTask?['date_echeance'] != null ? DateTime.parse(existingTask!['date_echeance']) : null;
    String listeAttribuee = existingTask?['list_id'] ?? _selectedListId!;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final primaryColor = Theme.of(context).colorScheme.primary;
          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)))),
                const SizedBox(height: 24),
                Text(existingTask == null ? 'Créer une tâche' : 'Modifier la tâche', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                
                Expanded(
                  child: ListView(
                    children: [
                      TextField(
                        controller: titleController,
                        decoration: InputDecoration(hintText: 'Titre de la tâche', filled: true, fillColor: Colors.grey.shade100, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: descController,
                        maxLines: 3,
                        decoration: InputDecoration(hintText: 'Description...', filled: true, fillColor: Colors.grey.shade100, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
                      ),
                      const SizedBox(height: 24),
                      
                      const Text('Détails', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 12),
                      
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: listeAttribuee,
                              decoration: InputDecoration(filled: true, fillColor: Colors.grey.shade50, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 16)),
                              items: _lists.map((l) => DropdownMenuItem<String>(value: l['id'], child: Text(l['titre'], overflow: TextOverflow.ellipsis))).toList(),
                              onChanged: (val) => setModalState(() => listeAttribuee = val!),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                final picked = await showDatePicker(context: context, initialDate: dateEcheance ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
                                if (picked != null) setModalState(() => dateEcheance = picked);
                              },
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                                decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(16)),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.calendar_today, size: 16, color: dateEcheance == null ? Colors.grey : primaryColor),
                                    const SizedBox(width: 8),
                                    Text(dateEcheance == null ? 'Échéance' : DateFormat('dd MMM').format(dateEcheance!), style: TextStyle(color: dateEcheance == null ? Colors.grey : Colors.black87, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      const Text('Priorité', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 12),
                      Row(
                        children: ['Normale', 'Haute'].map((prio) {
                          final isSelected = prioriteSelectionnee == prio;
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Center(child: Text(prio)),
                                selected: isSelected,
                                selectedColor: prio == 'Haute' ? Colors.redAccent.withOpacity(0.1) : primaryColor.withOpacity(0.1),
                                labelStyle: TextStyle(color: isSelected ? (prio == 'Haute' ? Colors.red : primaryColor) : Colors.black87, fontWeight: FontWeight.bold),
                                backgroundColor: Colors.grey.shade50,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                side: BorderSide(color: isSelected ? (prio == 'Haute' ? Colors.redAccent : primaryColor) : Colors.transparent),
                                onSelected: (val) => setModalState(() => prioriteSelectionnee = prio),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                
                Padding(
                  padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                  child: Row(
                    children: [
                      if (existingTask != null) ...[
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 28),
                          onPressed: () {
                            Navigator.pop(context);
                            _deleteTask(existingTask['id']);
                          },
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: SizedBox(
                          height: 54,
                          child: FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                            onPressed: () {
                              if (titleController.text.trim().isNotEmpty) {
                                Navigator.pop(context);
                                _saveTask(existingTask?['id'], titleController.text.trim(), descController.text.trim(), prioriteSelectionnee, dateEcheance, listeAttribuee);
                              }
                            },
                            child: const Text('Enregistrer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          ),
                        ),
                      ),
                    ],
                  ),
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
            icon: Icon(_sortBy == 'Priorité' ? Icons.sort_rounded : Icons.calendar_month_rounded, color: Colors.black87),
            tooltip: 'Trier par',
            onPressed: () {
              setState(() => _sortBy = _sortBy == 'Priorité' ? 'Échéance' : 'Priorité');
              _fetchTasksForSelectedList();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Trié par $_sortBy'), duration: const Duration(seconds: 1)));
            },
          ),
          // --- L'ICÔNE A ÉTÉ MODIFIÉE ICI ---
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded, color: Colors.black87),
            tooltip: 'Nettoyer les tâches terminées',
            onPressed: _deleteCompletedTasks,
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
                    'Mes Tâches',
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
                              _fetchTasksForSelectedList();
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

            // --- LISTE DES TÂCHES ---
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: primaryColor))
                  : _tasks.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_outline, size: 60, color: Colors.grey.shade200),
                              const SizedBox(height: 16),
                              Text('Tout est à jour.', style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(left: 24, right: 24, top: 8, bottom: 100),
                          itemCount: _tasks.length,
                          itemBuilder: (context, index) {
                            final task = _tasks[index];
                            final isComplete = task['est_complete'] ?? false;
                            final isHaute = task['priorite'] == 'Haute';
                            final hasDate = task['date_echeance'] != null;

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
                                  onLongPress: () => _showTaskBottomSheet(existingTask: task),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        GestureDetector(
                                          onTap: () => _toggleTask(task['id'], isComplete),
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
                                                task['titre'],
                                                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16, decoration: isComplete ? TextDecoration.lineThrough : null, color: isComplete ? Colors.grey.shade400 : Colors.black87),
                                              ),
                                              if (hasDate) ...[
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    Icon(Icons.access_time_rounded, size: 14, color: Colors.grey.shade400),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      DateFormat('dd MMM').format(DateTime.parse(task['date_echeance'])),
                                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                                                    ),
                                                  ],
                                                ),
                                              ]
                                            ],
                                          ),
                                        ),
                                        
                                        GestureDetector(
                                          onTap: () => _togglePriority(task['id'], task['priorite'] ?? 'Normale'),
                                          child: Padding(
                                            padding: const EdgeInsets.only(left: 8.0, top: 4.0, bottom: 4.0),
                                            child: Icon(
                                              isHaute ? Icons.flag : Icons.flag_outlined, 
                                              color: isHaute ? listColor : Colors.grey.shade300,
                                              size: 24,
                                            ),
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
        onPressed: () => _showTaskBottomSheet(),
        backgroundColor: primaryColor,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
    );
  }
}