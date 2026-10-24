import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

class AddRecipeScreen extends StatefulWidget {
  const AddRecipeScreen({super.key});

  @override
  State<AddRecipeScreen> createState() => _AddRecipeScreenState();
}

class _AddRecipeScreenState extends State<AddRecipeScreen> {
  final supabase = Supabase.instance.client;
  
  final _nomController = TextEditingController();
  final _prepController = TextEditingController();
  final _cuissonController = TextEditingController();
  final _portionsController = TextEditingController(text: '2');
  String _typePlat = 'Plat';
  
  // Listes dynamiques pour ingrédients et étapes
  final List<Map<String, TextEditingController>> _ingredients = [
    {'nom': TextEditingController(), 'quantite': TextEditingController(), 'unite': TextEditingController(text: 'unité')}
  ];
  final List<TextEditingController> _steps = [TextEditingController()];
  
  File? _imageFile; 
  Uint8List? _webImage; 
  bool _isLoading = false;

  @override
  void dispose() {
    _nomController.dispose();
    _prepController.dispose();
    _cuissonController.dispose();
    _portionsController.dispose();
    for (var ing in _ingredients) {
      ing['nom']?.dispose();
      ing['quantite']?.dispose();
      ing['unite']?.dispose();
    }
    for (var step in _steps) {
      step.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1000, imageQuality: 85);

    if (pickedFile != null) {
      if (kIsWeb) {
        final webImageBytes = await pickedFile.readAsBytes();
        setState(() => _webImage = webImageBytes);
      } else {
        setState(() => _imageFile = File(pickedFile.path));
      }
    }
  }

  Future<String?> _uploadImage() async {
    if (_imageFile == null && _webImage == null) return null;
    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      if (kIsWeb && _webImage != null) {
         await supabase.storage.from('recipes').uploadBinary(fileName, _webImage!);
      } else if (_imageFile != null) {
         await supabase.storage.from('recipes').upload(fileName, _imageFile!);
      }
      return supabase.storage.from('recipes').getPublicUrl(fileName);
    } catch (e) {
      debugPrint('Erreur upload : $e');
      return null;
    }
  }

  Future<void> _saveRecipe() async {
    if (_nomController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Le nom de la recette est obligatoire.')));
      return;
    }
    setState(() => _isLoading = true);

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Utilisateur non connecté');

      String? imageUrl = await _uploadImage();

      // 1. Sauvegarde de la recette
      final savedRecipe = await supabase.from('recipes').insert({
        'user_id': userId,
        'nom': _nomController.text.trim(),
        'type_plat': _typePlat,
        'tps_prep_min': int.tryParse(_prepController.text) ?? 15,
        'tps_cuisson_min': int.tryParse(_cuissonController.text) ?? 15,
        'nb_parts': int.tryParse(_portionsController.text) ?? 2,
        'photo_url': imageUrl,
        'is_public': false,
      }).select().single();

      final recipeId = savedRecipe['id'];

      // 2. Sauvegarde des ingrédients
      for (var ing in _ingredients) {
        final nom = ing['nom']!.text.trim();
        if (nom.isEmpty) continue;
        
        var itemRes = await supabase.from('items').select('id').eq('nom', nom).maybeSingle();
        String itemId;
        if (itemRes == null) {
          final newItem = await supabase.from('items').insert({'user_id': userId, 'nom': nom, 'is_public': false}).select('id').single();
          itemId = newItem['id'];
        } else {
          itemId = itemRes['id'];
        }

        await supabase.from('recipe_ingredients').insert({
          'recipe_id': recipeId,
          'item_id': itemId,
          'quantite': double.tryParse(ing['quantite']!.text.replaceAll(',', '.')) ?? 1.0,
          'unite': ing['unite']!.text.trim(),
        });
      }

      // 3. Sauvegarde des étapes
      for (int i = 0; i < _steps.length; i++) {
        final desc = _steps[i].text.trim();
        if (desc.isEmpty) continue;
        await supabase.from('recipe_steps').insert({
          'recipe_id': recipeId,
          'ordre': i + 1,
          'description': desc,
        });
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recette créée avec succès !')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Nouvelle recette'), backgroundColor: Colors.white, elevation: 0, centerTitle: true),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: primaryColor))
          : Center(
              child: ConstrainedBox(
                // Contrainte Tablette : le formulaire ne dépassera jamais 800px de large
                constraints: const BoxConstraints(maxWidth: 800),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          width: double.infinity, height: 200,
                          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade300)),
                          child: _imageFile != null || _webImage != null
                              ? ClipRRect(borderRadius: BorderRadius.circular(20), child: kIsWeb ? Image.memory(_webImage!, fit: BoxFit.cover) : Image.file(_imageFile!, fit: BoxFit.cover))
                              : Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_a_photo_outlined, size: 40, color: Colors.grey.shade400), const SizedBox(height: 12), Text('Ajouter une photo', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold))]),
                        ),
                      ),
                      const SizedBox(height: 32),
                      
                      const Text('Informations', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      TextField(controller: _nomController, decoration: InputDecoration(labelText: 'Nom', filled: true, fillColor: Colors.grey.shade50, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none))),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _typePlat,
                        decoration: InputDecoration(labelText: 'Catégorie', filled: true, fillColor: Colors.grey.shade50, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
                        items: ['Entrée', 'Plat', 'Dessert'].map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
                        onChanged: (val) => setState(() => _typePlat = val!),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: TextField(controller: _prepController, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Prépa (min)', filled: true, fillColor: Colors.grey.shade50, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)))),
                          const SizedBox(width: 16),
                          Expanded(child: TextField(controller: _cuissonController, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Cuisson (min)', filled: true, fillColor: Colors.grey.shade50, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)))),
                          const SizedBox(width: 16),
                          Expanded(child: TextField(controller: _portionsController, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Parts', filled: true, fillColor: Colors.grey.shade50, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)))),
                        ],
                      ),
                      
                      const SizedBox(height: 32),
                      const Text('Ingrédients', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      ..._ingredients.asMap().entries.map((entry) {
                        int idx = entry.key;
                        var ing = entry.value;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            children: [
                              Expanded(flex: 3, child: TextField(controller: ing['nom'], decoration: InputDecoration(hintText: 'Ex: Tomate', filled: true, fillColor: Colors.grey.shade50, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)))),
                              const SizedBox(width: 8),
                              Expanded(flex: 1, child: TextField(controller: ing['quantite'], keyboardType: TextInputType.number, decoration: InputDecoration(hintText: 'Qté', filled: true, fillColor: Colors.grey.shade50, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)))),
                              const SizedBox(width: 8),
                              Expanded(flex: 1, child: TextField(controller: ing['unite'], decoration: InputDecoration(hintText: 'g, ml...', filled: true, fillColor: Colors.grey.shade50, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)))),
                              IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.red), onPressed: () => setState(() => _ingredients.removeAt(idx))),
                            ],
                          ),
                        );
                      }),
                      TextButton.icon(onPressed: () => setState(() => _ingredients.add({'nom': TextEditingController(), 'quantite': TextEditingController(), 'unite': TextEditingController(text: 'unité')})), icon: const Icon(Icons.add), label: const Text('Ajouter un ingrédient')),

                      const SizedBox(height: 32),
                      const Text('Étapes de préparation', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      ..._steps.asMap().entries.map((entry) {
                        int idx = entry.key;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            children: [
                              CircleAvatar(backgroundColor: primaryColor.withOpacity(0.1), child: Text('${idx + 1}', style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold))),
                              const SizedBox(width: 16),
                              Expanded(child: TextField(controller: _steps[idx], maxLines: null, decoration: InputDecoration(hintText: 'Décrire l\'étape...', filled: true, fillColor: Colors.grey.shade50, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)))),
                              IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.red), onPressed: () => setState(() => _steps.removeAt(idx))),
                            ],
                          ),
                        );
                      }),
                      TextButton.icon(onPressed: () => setState(() => _steps.add(TextEditingController())), icon: const Icon(Icons.add), label: const Text('Ajouter une étape')),

                      const SizedBox(height: 40),
                      SizedBox(width: double.infinity, height: 56, child: FilledButton(style: FilledButton.styleFrom(backgroundColor: primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), onPressed: _saveRecipe, child: const Text('Créer la recette', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)))),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}