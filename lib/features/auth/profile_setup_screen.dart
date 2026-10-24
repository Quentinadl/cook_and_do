import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/main_screen.dart'; // Assure-toi que l'import pointe vers ton MainScreen

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final supabase = Supabase.instance.client;
  bool _isLoading = false;

  final List<String> _regimes = ['Végétarien', 'Vegan', 'Sans Gluten', 'Pescétarien', 'Keto'];
  final List<String> _selectedRegimes = [];

  final List<String> _intolerances = ['Laitier', 'Arachides', 'Soja', 'Œufs', 'Fruits de mer'];
  final List<String> _selectedIntolerances = [];

  Future<void> _saveProfile() async {
    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception("Utilisateur non connecté");

      await supabase.from('profiles').update({
        'preferences_alimentaires': _selectedRegimes,
        'intolérances': _selectedIntolerances,
      }).eq('id', userId);

      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MainScreen()));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _toggleSelection(List<String> list, String item) {
    setState(() {
      if (list.contains(item)) {
        list.remove(item);
      } else {
        list.add(item);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Ton profil', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Dis-nous en plus sur toi', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87)),
              const SizedBox(height: 8),
              Text('Ces informations personnaliseront tes recommandations de recettes.', style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
              const SizedBox(height: 32),

              const Text('Régimes alimentaires', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8, runSpacing: 12,
                children: _regimes.map((regime) {
                  final isSelected = _selectedRegimes.contains(regime);
                  return ChoiceChip(
                    label: Text(regime, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.black87)),
                    selected: isSelected,
                    selectedColor: primaryColor,
                    backgroundColor: Colors.grey.shade100,
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onSelected: (_) => _toggleSelection(_selectedRegimes, regime),
                  );
                }).toList(),
              ),
              const SizedBox(height: 32),

              const Text('Allergies & Intolérances', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8, runSpacing: 12,
                children: _intolerances.map((intol) {
                  final isSelected = _selectedIntolerances.contains(intol);
                  return ChoiceChip(
                    label: Text(intol, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.black87)),
                    selected: isSelected,
                    selectedColor: Colors.redAccent,
                    backgroundColor: Colors.grey.shade100,
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onSelected: (_) => _toggleSelection(_selectedIntolerances, intol),
                  );
                }).toList(),
              ),
              
              const SizedBox(height: 60),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  onPressed: _isLoading ? null : _saveProfile,
                  child: _isLoading
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Terminer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MainScreen())),
                  child: const Text('Passer cette étape', style: TextStyle(color: Colors.grey)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}