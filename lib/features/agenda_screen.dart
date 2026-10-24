import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';

class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  final supabase = Supabase.instance.client;
  
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay = DateTime.now();
  
  // Dictionnaire qui stocke les événements (repas et tâches) par jour
  Map<DateTime, List<dynamic>> _events = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAllEvents();
  }

  // Permet de normaliser la date (retirer les heures/minutes) pour le dictionnaire
  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  Future<void> _loadAllEvents() async {
    setState(() => _isLoading = true);
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    final Map<DateTime, List<dynamic>> newEvents = {};

    try {
      // 1. Récupérer les repas
      final meals = await supabase
          .from('meal_plan')
          .select('*, recipes(nom, photo_url)')
          .eq('user_id', userId);

      for (var meal in meals) {
        if (meal['date_prevue'] != null) {
          final date = _normalizeDate(DateTime.parse(meal['date_prevue']));
          meal['is_meal'] = true; // Tag pour différencier à l'affichage
          if (newEvents[date] == null) newEvents[date] = [];
          newEvents[date]!.add(meal);
        }
      }

      // 2. Récupérer les tâches avec une date d'échéance
      final tasks = await supabase
          .from('tasks')
          .select('*')
          .eq('user_id', userId)
          .not('date_echeance', 'is', null);

      for (var task in tasks) {
        final date = _normalizeDate(DateTime.parse(task['date_echeance']));
        task['is_meal'] = false; // Tag pour tâche
        if (newEvents[date] == null) newEvents[date] = [];
        newEvents[date]!.add(task);
      }

      if (mounted) {
        setState(() {
          _events = newEvents;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Erreur chargement agenda : $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<dynamic> _getEventsForDay(DateTime day) {
    return _events[_normalizeDate(day)] ?? [];
  }

  Future<void> _deleteMeal(String mealPlanId) async {
    try {
      await supabase.from('meal_plan').delete().eq('id', mealPlanId);
      _loadAllEvents(); // Rafraîchir
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Repas annulé.')));
    } catch (e) {
      debugPrint('Erreur suppression repas: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final selectedEvents = _getEventsForDay(_selectedDay ?? _focusedDay);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Mon Agenda', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          // --- LE CALENDRIER ---
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: TableCalendar(
              locale: 'fr_FR',
              firstDay: DateTime.utc(2023, 1, 1),
              lastDay: DateTime.utc(2030, 12, 31),
              focusedDay: _focusedDay,
              calendarFormat: _calendarFormat,
              startingDayOfWeek: StartingDayOfWeek.monday,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              eventLoader: _getEventsForDay,
              onDaySelected: (selectedDay, focusedDay) {
                if (!isSameDay(_selectedDay, selectedDay)) {
                  setState(() {
                    _selectedDay = selectedDay;
                    _focusedDay = focusedDay;
                  });
                }
              },
              onFormatChanged: (format) {
                if (_calendarFormat != format) setState(() => _calendarFormat = format);
              },
              onPageChanged: (focusedDay) => _focusedDay = focusedDay,
              
              // Design du calendrier
              calendarStyle: CalendarStyle(
                todayDecoration: BoxDecoration(color: primaryColor.withOpacity(0.3), shape: BoxShape.circle),
                selectedDecoration: BoxDecoration(color: primaryColor, shape: BoxShape.circle),
                markerDecoration: BoxDecoration(color: Colors.orange.shade300, shape: BoxShape.circle),
              ),
              headerStyle: const HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                titleTextStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // --- LISTE DES ÉVÉNEMENTS DU JOUR ---
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: primaryColor))
                : selectedEvents.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.event_available, size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text('Rien de prévu ce jour.', style: TextStyle(color: Colors.grey.shade600)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        itemCount: selectedEvents.length,
                        itemBuilder: (context, index) {
                          final event = selectedEvents[index];
                          final isMeal = event['is_meal'] == true;

                          if (isMeal) {
                            final recipe = event['recipes'];
                            final isMidi = event['type_repas'] == 'Midi';
                            return _buildEventCard(
                              title: recipe['nom'] ?? 'Recette supprimée',
                              subtitle: 'Repas du ${event['type_repas']}',
                              icon: isMidi ? Icons.wb_sunny : Icons.nights_stay,
                              iconColor: isMidi ? Colors.orange : Colors.indigo,
                              trailingIcon: Icons.cancel_outlined,
                              onTrailingTap: () => _deleteMeal(event['id']),
                            );
                          } else {
                            // C'est une tâche
                            return _buildEventCard(
                              title: event['titre'],
                              subtitle: 'Tâche à faire',
                              icon: Icons.check_circle_outline,
                              iconColor: Colors.green,
                            );
                          }
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventCard({required String title, required String subtitle, required IconData icon, required Color iconColor, IconData? trailingIcon, VoidCallback? onTrailingTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: iconColor.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        trailing: trailingIcon != null
            ? IconButton(icon: Icon(trailingIcon, color: Colors.red.shade300), onPressed: onTrailingTap)
            : null,
      ),
    );
  }
}