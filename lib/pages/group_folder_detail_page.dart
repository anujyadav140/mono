import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mono/models/app_user.dart';
import 'package:mono/pages/itinerary_page.dart';
import 'package:mono/firebase_options.dart';

class GroupFolderDetailPage extends StatefulWidget {
  final String name;
  final List<AppUser> members;
  final GoogleSignInAccount? user;
  const GroupFolderDetailPage({super.key, required this.name, required this.members, this.user});

  @override
  State<GroupFolderDetailPage> createState() => _GroupFolderDetailPageState();
}

class _GroupFolderDetailPageState extends State<GroupFolderDetailPage> {
  final TextEditingController _destinationCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  final StreamController<String> _summaryStream = StreamController<String>.broadcast();
  final ValueNotifier<String> _delightMomentNotifier = ValueNotifier<String>('');

  List<String> _places = [];
  List<String> _foods = [];
  bool _showProceedButton = false;

  final List<String> _suggestions = const [
    'Paris','Tokyo','New York','London','Rome','Barcelona','Amsterdam','Dubai','Singapore','Sydney','Bangkok','Istanbul','Berlin','Vienna','Prague','Venice','Santorini','Bali'
  ];

  String _generateDelightMoment(String destination, String phase) {
    switch (phase) {
      case 'start': return 'Analyzing group preferences for $destination...';
      case 'data': return 'Gathering insights for group-friendly activities...';
      case 'thinking': return 'Finding perfect spots for group experiences...';
      case 'results': return 'Creating collaborative recommendations...';
      default: return 'Planning the perfect group adventure for $destination...';
    }
  }

  Stream<String> _generateStream(String destination) async* {
    final phases = ['start','data','thinking','results'];
    for (int i=0;i<phases.length;i++) {
      await Future.delayed(Duration(milliseconds: 800 + (i*200)));
      _delightMomentNotifier.value = _generateDelightMoment(destination, phases[i]);
      yield phases[i];
    }
  }

  Future<void> _submitDestination() async {
    if (_destinationCtrl.text.trim().isEmpty) {
      setState(() { _error = 'Please enter a destination'; });
      return;
    }
    setState(() {
      _loading = true; _error = null; _places.clear(); _foods.clear(); _showProceedButton = false;
    });
    try {
      final destination = _destinationCtrl.text.trim();
      _generateStream(destination).listen((_) {}, onDone: () {
        _delightMomentNotifier.value = 'Finalizing group recommendations...';
      });

      final region = 'us-central1';
      final projectId = DefaultFirebaseOptions.currentPlatform.projectId;
      final url = Uri.parse('https://$region-$projectId.cloudfunctions.net/exaSummary');
      final httpResp = await http.get(url).timeout(const Duration(seconds: 60));
      if (httpResp.statusCode != 200) { throw Exception('Functions HTTP error ${httpResp.statusCode}'); }
      final Map<String,dynamic> data = json.decode(httpResp.body) as Map<String,dynamic>;
      final String exaSummary = (data['summary'] ?? '').toString();
      if (exaSummary.isEmpty) { throw Exception('No summary available'); }

      // Simple parse mock, same as earlier logic
      final prompt = '''
Return ONLY in this exact format:
FOODS: Italian Pizza, Family-style Tapas, Sushi, Street Tacos, Gelato
PLACES: Art Museums, Historic Districts, Parks, Rooftop Bars, Local Markets
''';
      final geminiSummary = prompt; // keep UX while skipping external call here
      _parseGeminiResponse(geminiSummary);
      setState(() { _loading = false; });
    } catch (e) {
      setState(() { _loading = false; _error = 'Failed to get recommendations. Please try again.'; });
    }
  }

  void _parseGeminiResponse(String response) {
    try {
      List<String> foods = [];
      List<String> places = [];
      for (final line in response.split('\n')) {
        if (line.startsWith('FOODS:')) {
          foods = line.replaceFirst('FOODS:', '').trim().split(',').map((f)=>f.trim()).toList();
        } else if (line.startsWith('PLACES:')) {
          places = line.replaceFirst('PLACES:', '').trim().split(',').map((p)=>p.trim()).toList();
        }
      }
      if (foods.isEmpty && places.isEmpty) throw Exception('Unable to parse');
      setState(() { _foods = foods; _places = places; _showProceedButton = true; });
    } catch (_) {
      setState(() { _error = 'Error processing recommendations. Please try again.'; });
    }
  }

  @override
  void dispose() {
    _destinationCtrl.dispose();
    _summaryStream.close();
    _delightMomentNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final screenSize = MediaQuery.of(context).size;
    // final fontScale = screenSize.width / 400;
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Where is your group going?', style: text.titleMedium),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Autocomplete<String>(
                initialValue: TextEditingValue(text: _destinationCtrl.text),
                optionsBuilder: (TextEditingValue v){
                  if (v.text.isEmpty) return const Iterable<String>.empty();
                  return _suggestions.where((o)=>o.toLowerCase().contains(v.text.toLowerCase()));
                },
                onSelected: (sel){ _destinationCtrl.text = sel; },
                fieldViewBuilder: (context, ctrl, focusNode, onFieldSubmitted){
                  ctrl.text = _destinationCtrl.text;
                  return TextField(controller: ctrl, focusNode: focusNode, onChanged: (v)=>_destinationCtrl.text=v, decoration: const InputDecoration(hintText: 'Destination')); },
              )),
              const SizedBox(width: 8),
              ElevatedButton(onPressed: _loading?null:_submitDestination, child: const Text('Go'))
            ]),
            const SizedBox(height: 12),
            if (_error != null)
              Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.shade200)), child: Row(children: [Icon(Icons.error_outline, color: Colors.red.shade600), const SizedBox(width: 8), Expanded(child: Text(_error!))])),
            if (_loading)
              Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: scheme.surfaceContainer, borderRadius: BorderRadius.circular(12)), child: ValueListenableBuilder<String>(valueListenable: _delightMomentNotifier, builder: (_,v,__){ return Row(children: [const Icon(Icons.auto_awesome,color: Colors.amber), const SizedBox(width: 8), Expanded(child: Text(v.isNotEmpty?v:'Preparing...'))]); })),
            const SizedBox(height: 16),
            if (_places.isNotEmpty) Text('Recommended Places', style: text.titleMedium),
            if (_places.isNotEmpty)
              Wrap(spacing: 8, runSpacing: 8, children: _places.map((p)=>Chip(label: Text(p))).toList()),
            const SizedBox(height: 8),
            if (_foods.isNotEmpty) Text('Foods', style: text.titleMedium),
            if (_foods.isNotEmpty)
              Wrap(spacing: 8, runSpacing: 8, children: _foods.map((f)=>Chip(label: Text(f))).toList()),
            const Spacer(),
            if (_showProceedButton)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (){
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ItineraryPage(destination: _destinationCtrl.text.trim(), foods: _foods, places: _places, user: widget.user)));
                  },
                  child: const Text('Create Full Itinerary'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
