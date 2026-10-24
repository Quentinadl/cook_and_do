import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AgendaConfigScreen extends StatefulWidget {
  const AgendaConfigScreen({super.key});

  @override
  State<AgendaConfigScreen> createState() => _AgendaConfigScreenState();
}

class _AgendaConfigScreenState extends State<AgendaConfigScreen> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _preferences = [];

  @override
  void initState() {
    super.initState();
    _fetchPreferences();
  }

  Future<void> _fetchPreferences() async {
    try {
      final data = await supabase
          .from('user_preferences')
          .select()
          .order('ordre', ascending: true);
      setState(() {
        _preferences = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updatePreference(String id, String field, bool value) async {
    setState(() {
      _preferences.firstWhere((element) => element['id'] == id)[field] = value;
    });
    try {
      await supabase.from('user_preferences').update({field: value}).eq('id', id);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur de mise à jour: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Configuration de l\'Agenda', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(24),
              itemCount: _preferences.length,
              itemBuilder: (context, index) {
                final pref = _preferences[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(pref['jour'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const Divider(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Activer le Midi', style: TextStyle(color: Colors.grey)),
                          Switch(
                            activeColor: primaryColor,
                            value: pref['activer_midi'],
                            onChanged: (val) => _updatePreference(pref['id'], 'activer_midi', val),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Activer le Soir', style: TextStyle(color: Colors.grey)),
                          Switch(
                            activeColor: primaryColor,
                            value: pref['activer_soir'],
                            onChanged: (val) => _updatePreference(pref['id'], 'activer_soir', val),
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
}