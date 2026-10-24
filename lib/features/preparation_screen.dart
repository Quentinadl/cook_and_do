import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class PreparationScreen extends StatefulWidget {
  final Map<String, dynamic> recipe;
  const PreparationScreen({super.key, required this.recipe});

  @override
  State<PreparationScreen> createState() => _PreparationScreenState();
}

class _PreparationScreenState extends State<PreparationScreen> {
  final supabase = Supabase.instance.client;
  List<dynamic> _steps = [];
  bool _isLoading = true;

  // Contrôleur pour l'effet "cartes qui défilent"
  final PageController _pageController = PageController(viewportFraction: 0.85);
  int _currentStepIndex = 0;

  // --- LOGIQUE DU MINUTEUR ---
  int _timerSeconds = 0;
  Timer? _timer;
  bool _isTimerRunning = false;
  final TextEditingController _timerController = TextEditingController(text: '10');

  @override
  void initState() {
    super.initState();
    // EMPÊCHE L'ÉCRAN DE SE METTRE EN VEILLE
    WakelockPlus.enable(); 
    _fetchSteps();
  }

  @override
  void dispose() {
    // RÉACTIVE LA MISE EN VEILLE AUTOMATIQUE
    WakelockPlus.disable(); 
    _timer?.cancel();
    _timerController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _fetchSteps() async {
    if (widget.recipe['recipe_steps'] != null && (widget.recipe['recipe_steps'] as List).isNotEmpty) {
      _steps = widget.recipe['recipe_steps'];
      _steps.sort((a, b) => (a['ordre'] as int).compareTo(b['ordre'] as int));
      setState(() => _isLoading = false);
      return;
    }

    try {
      final data = await supabase
          .from('recipe_steps')
          .select('*')
          .eq('recipe_id', widget.recipe['id'])
          .order('ordre', ascending: true);
      if (mounted) setState(() { _steps = data; _isLoading = false; });
    } catch (e) {
      debugPrint('Erreur étapes : $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- CONTRÔLES DU MINUTEUR ---
  void _startTimer() {
    if (_timerSeconds == 0) {
      _timerSeconds = (int.tryParse(_timerController.text) ?? 10) * 60; 
    }
    setState(() => _isTimerRunning = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_timerSeconds > 0) {
          _timerSeconds--;
        } else {
          _timer?.cancel();
          _isTimerRunning = false;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⏳ Minuteur terminé !', style: TextStyle(fontSize: 18)), backgroundColor: Colors.orange, duration: Duration(seconds: 5)));
        }
      });
    });
  }

  void _pauseTimer() {
    _timer?.cancel();
    setState(() => _isTimerRunning = false);
  }

  void _resetTimer() {
    _timer?.cancel();
    setState(() {
      _isTimerRunning = false;
      _timerSeconds = 0;
    });
  }

  String _formatTime(int totalSeconds) {
    int m = totalSeconds ~/ 60;
    int s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // Ouvre le minuteur dans un panneau coulissant sur téléphone
  void _showMobileTimerSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          // On emballe le panneau existant pour qu'il se mette à jour en direct
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: _buildAssistantPanel(Theme.of(context).colorScheme.primary, setModalState),
          );
        }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    
    // Détection stricte : Largeur > 800px ET orientation Paysage
    final isLandscapeTablet = MediaQuery.of(context).size.width > 800 && MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text('En cuisine : ${widget.recipe['nom']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 1,
        centerTitle: true,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: primaryColor))
          : isLandscapeTablet
              // VUE TABLETTE (Paysage) : Écran scindé
              ? Row(
                  children: [
                    Expanded(flex: 3, child: _buildStepsCarousel(primaryColor)),
                    Container(width: 1, color: Colors.grey.shade300),
                    SizedBox(width: 350, child: _buildAssistantPanel(primaryColor, setState)),
                  ],
                )
              // VUE TÉLÉPHONE : Juste les cartes qui défilent
              : _buildStepsCarousel(primaryColor),
              
      // Sur téléphone, on ajoute un bouton flottant discret pour ouvrir le minuteur
      floatingActionButton: (!isLandscapeTablet && !_isLoading)
          ? FloatingActionButton(
              onPressed: _showMobileTimerSheet,
              backgroundColor: Colors.white,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.timer_outlined, color: _isTimerRunning ? Colors.orange : primaryColor, size: 28),
                  if (_isTimerRunning)
                    const Positioned(top: 6, right: 6, child: CircleAvatar(radius: 4, backgroundColor: Colors.red)),
                ],
              ),
            )
          : null,
    );
  }

  // --- LE DÉFILEMENT DES CARTES (ÉTAPES) ---
  Widget _buildStepsCarousel(Color primaryColor) {
    if (_steps.isEmpty) return const Center(child: Text('Aucune étape renseignée.'));

    return Column(
      children: [
        const SizedBox(height: 24),
        // Indicateur d'avancement discret en haut
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: LinearProgressIndicator(
            value: (_currentStepIndex + 1) / _steps.length,
            backgroundColor: Colors.grey.shade300,
            color: primaryColor,
            minHeight: 6,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        const SizedBox(height: 24),
        
        // Les cartes d'étapes (Le PageView)
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) => setState(() => _currentStepIndex = index),
            itemCount: _steps.length,
            itemBuilder: (context, index) {
              final step = _steps[index];
              // Animation légère pour la carte active vs inactive
              final isActive = index == _currentStepIndex;
              
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: EdgeInsets.only(
                  right: 16, left: 16, 
                  top: isActive ? 0 : 32, 
                  bottom: isActive ? 24 : 56
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [
                    if (isActive) BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 10))
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(color: primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                        child: Text('Étape ${index + 1}', style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 18)),
                      ),
                      const SizedBox(height: 32),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Text(
                            step['description'] ?? '', 
                            style: const TextStyle(fontSize: 22, height: 1.5, color: Colors.black87),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // --- LE PANNEAU MINUTEUR ---
  Widget _buildAssistantPanel(Color primaryColor, StateSetter updateState) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.timer_outlined, color: Colors.orange, size: 28),
              SizedBox(width: 12),
              Text('Minuteur', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 40),
          
          if (_timerSeconds > 0 || _isTimerRunning)
            Center(
              child: Text(_formatTime(_timerSeconds), style: const TextStyle(fontSize: 72, fontWeight: FontWeight.bold, fontFeatures: [FontFeature.tabularFigures()])),
            )
          else
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _timerController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      suffixText: 'min',
                      filled: true, fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                    ),
                  ),
                ),
              ],
            ),
            
          const SizedBox(height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (_isTimerRunning)
                IconButton(
                  onPressed: () {
                    _pauseTimer();
                    updateState(() {});
                  },
                  icon: const Icon(Icons.pause_circle_filled, size: 64, color: Colors.orange),
                )
              else
                IconButton(
                  onPressed: () {
                    _startTimer();
                    updateState(() {});
                  },
                  icon: const Icon(Icons.play_circle_fill, size: 64, color: Colors.green),
                ),
              IconButton(
                onPressed: () {
                  _resetTimer();
                  updateState(() {});
                },
                icon: const Icon(Icons.stop_circle, size: 64, color: Colors.red),
              ),
            ],
          ),
          
          const SizedBox(height: 40),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: primaryColor.withOpacity(0.05), borderRadius: BorderRadius.circular(16)),
            child: Row(
              children: [
                Icon(Icons.bolt, color: primaryColor),
                const SizedBox(width: 12),
                const Expanded(child: Text('L\'écran restera allumé automatiquement.', style: TextStyle(fontSize: 14))),
              ],
            ),
          ),
          const SizedBox(height: 24), // Marge de sécurité pour le bas (mobile)
        ],
      ),
    );
  }
}