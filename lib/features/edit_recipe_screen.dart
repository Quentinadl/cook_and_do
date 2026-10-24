import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

class EditRecipeScreen extends StatefulWidget {
  final Map<String, dynamic> recipe;
  const EditRecipeScreen({super.key, required this.recipe});

  @override
  State<EditRecipeScreen> createState() => _EditRecipeScreenState();
}

class _EditRecipeScreenState extends State<EditRecipeScreen> {
  final supabase = Supabase.instance.client;
  
  late TextEditingController _nomController;
  late TextEditingController _prepController;
  late TextEditingController _cuissonController;
  late TextEditingController _portionsController;
  late String _typePlat;
  
  File? _imageFile; 
  Uint8List? _webImage; 
  String? _existingImageUrl;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nomController = TextEditingController(text: widget.recipe['nom']);
    _prepController = TextEditingController(text: widget.recipe['tps_prep_min']?.toString() ?? '15');
    _cuissonController = TextEditingController(text: widget.recipe['tps_cuisson_min']?.toString() ?? '15');
    _portionsController = TextEditingController(text: widget.recipe['nb_parts']?.toString() ?? '2');
    _typePlat = widget.recipe['type_plat'] ?? 'Plat';
    _existingImageUrl = widget.recipe['photo_url'];
  }

  @override
  void dispose() {
    _nomController.dispose();
    _prepController.dispose();
    _cuissonController.dispose();
    _portionsController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1000, imageQuality: 85);

    if (pickedFile != null) {
      if (kIsWeb) {
        final webImageBytes = await pickedFile.readAsBytes();
        setState(() { _webImage = webImageBytes; _existingImageUrl = null; });
      } else {
        setState(() { _imageFile = File(pickedFile.path); _existingImageUrl = null; });
      }
    }
  }

  Future<String?> _uploadImage() async {
    if (_imageFile == null && _webImage == null) return _existingImageUrl;
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
      return _existingImageUrl;
    }
  }

  Future<void> _updateRecipe() async {
    if (_nomController.text.trim().isEmpty) return;
    setState(() => _isLoading = true);

    try {
      String? imageUrl = await _uploadImage();

      await supabase.from('recipes').update({
        'nom': _nomController.text.trim(),
        'type_plat': _typePlat,
        'tps_prep_min': int.tryParse(_prepController.text) ?? 15,
        'tps_cuisson_min': int.tryParse(_cuissonController.text) ?? 15,
        'nb_parts': int.tryParse(_portionsController.text) ?? 2,
        'photo_url': imageUrl,
      }).eq('id', widget.recipe['id']);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recette modifiée !')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteRecipe() async {
    setState(() => _isLoading = true);
    try {
      await supabase.from('recipes').delete().eq('id', widget.recipe['id']);
      if (mounted) {
        Navigator.pop(context); // Ferme l'écran d'édition
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recette supprimée.')));
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
      appBar: AppBar(
        title: const Text('Modifier la recette'), backgroundColor: Colors.white, elevation: 0, centerTitle: true,
        actions: [IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: _deleteRecipe)],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: primaryColor))
          : Center(
              child: ConstrainedBox(
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
                              ? ClipRRect(borderRadius: BorderRadius.circular(20), child: kIsWeb && _webImage != null ? Image.memory(_webImage!, fit: BoxFit.cover) : Image.file(_imageFile!, fit: BoxFit.cover))
                              : _existingImageUrl != null
                                  ? ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.network(_existingImageUrl!, fit: BoxFit.cover))
                                  : Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_a_photo_outlined, size: 40, color: Colors.grey.shade400), const SizedBox(height: 12), Text('Modifier la photo', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold))]),
                        ),
                      ),
                      const SizedBox(height: 32),
                      
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
                      
                      const SizedBox(height: 40),
                      SizedBox(width: double.infinity, height: 56, child: FilledButton(style: FilledButton.styleFrom(backgroundColor: primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), onPressed: _updateRecipe, child: const Text('Sauvegarder', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)))),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}