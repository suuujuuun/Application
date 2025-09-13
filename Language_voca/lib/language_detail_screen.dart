import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'widgets/articles_drawer.dart';
import 'widgets/vocabulary_graph_view.dart';
import 'dart:math';

class LanguageDetailScreen extends StatefulWidget {
  final String language;
  final String? collectionName;
  const LanguageDetailScreen({super.key, required this.language, this.collectionName});

  @override
  State<LanguageDetailScreen> createState() => _LanguageDetailScreenState();
}

class _LanguageDetailScreenState extends State<LanguageDetailScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late CollectionReference _vocabularyCollection;

  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearchActive = false;

  final _wordController = TextEditingController();
  final _definitionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _vocabularyCollection = FirebaseFirestore.instance.collection('languages').doc(widget.language).collection(widget.collectionName ?? 'vocabulary');
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _wordController.dispose();
    _definitionController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(LanguageDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.language != oldWidget.language || widget.collectionName != oldWidget.collectionName) {
       _vocabularyCollection = FirebaseFirestore.instance.collection('languages').doc(widget.language).collection(widget.collectionName ?? 'vocabulary');
       setState((){});
    }
  }

  Future<void> _addVocabulary() async {
    final word = _wordController.text;
    final definition = _definitionController.text;
    if (word.isNotEmpty && definition.isNotEmpty) {
      // Check for duplicates (from previous implementation)
      final querySnapshot = await _vocabularyCollection.where('word', isEqualTo: word).get();
      if (querySnapshot.docs.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"$word" is already registered.')),
          );
        }
        return;
      }

      await _vocabularyCollection.add({
        'word': word,
        'definition': definition,
        'connections': [], // Initialize with empty connections
      });
      _wordController.clear();
      _definitionController.clear();

      // Hide keyboard
      FocusScope.of(context).unfocus();

      // Close the drawer
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 800;
    final drawerWidth = isMobile ? screenWidth * 0.9 : 350.0;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        backgroundColor: _isSearchActive ? Colors.white : null,
        foregroundColor: _isSearchActive ? Colors.black : null,
        title: _isSearchActive
            ? TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search nodes...',
                  hintStyle: TextStyle(color: Colors.grey),
                  border: InputBorder.none,
                ),
                style: TextStyle(color: Colors.black, fontSize: 16),
                autofocus: true,
              )
            : Text("Vocabulary for ${widget.language}", style: GoogleFonts.poppins()),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: _isSearchActive ? Colors.black : null),
          onPressed: () => context.go('/'),
        ),
        actions: [
          if (widget.language == 'English')
            IconButton(
              icon: Icon(
                Icons.medical_services,
                color: _isSearchActive ? Colors.black : null,
              ),
              onPressed: () {
                context.go('/language/English/medical');
              },
              tooltip: 'Medical Vocabulary',
            ),
          if (widget.language == 'English')
            IconButton(
              icon: Icon(
                Icons.chat_bubble_outline,
                color: _isSearchActive ? Colors.black : null,
              ),
              onPressed: () {
                context.go('/language/English/expression');
              },
              tooltip: 'Expressions',
            ),
          if (widget.language == 'English')
            IconButton(
              icon: Icon(
                Icons.link,
                color: _isSearchActive ? Colors.black : null,
              ),
              onPressed: () {
                context.go('/language/English/phrasal_verb');
              },
              tooltip: 'Phrasal Verbs',
            ),
          if (widget.language == 'English')
            IconButton(
              icon: Icon(
                Icons.science,
                color: _isSearchActive ? Colors.black : null,
              ),
              onPressed: () {
                context.go('/language/English/science_vocabulary');
              },
              tooltip: 'Science Vocabulary',
            ),
          if (widget.language == 'English')
            IconButton(
              icon: Icon(
                Icons.business,
                color: _isSearchActive ? Colors.black : null,
              ),
              onPressed: () {
                context.go('/language/English/professional_vocabulary');
              },
              tooltip: 'Professional Vocabulary',
            ),
          IconButton(
            icon: Icon(
              _isSearchActive ? Icons.close : Icons.search,
              color: _isSearchActive ? Colors.black : null,
            ),
            onPressed: () {
              setState(() {
                _isSearchActive = !_isSearchActive;
                if (!_isSearchActive) {
                  _searchController.clear();
                }
              });
            },
            tooltip: 'Search',
          ),
          IconButton(
            icon: Icon(
              Icons.list_alt_outlined,
              color: _isSearchActive ? Colors.black : null,
            ),
            onPressed: () => context.go('/language/${widget.language}/articles'),
            tooltip: 'View Articles',
          ),
        ],
      ),
      endDrawer: Drawer(
        width: drawerWidth,
        child: _buildWordInputPanel(),
      ),
      body: SizedBox.expand(
        child: VocabularyGraphView(
          language: widget.language,
          searchQuery: _searchQuery,
        ),
      ),
      floatingActionButton: Builder(
        builder: (context) => FloatingActionButton(
          onPressed: () => Scaffold.of(context).openEndDrawer(),
          child: const Icon(Icons.add),
          tooltip: 'Add Word',
        ),
      ),
    );
  }

  Widget _buildWordInputPanel() {
    return Container(
      color: Theme.of(context).cardColor,
      padding: const EdgeInsets.all(20.0),
      child: ListView(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Add New Word', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _wordController,
            decoration: const InputDecoration(labelText: 'Word', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _definitionController,
            decoration: const InputDecoration(labelText: 'Definition', border: OutlineInputBorder()),
            maxLines: 5,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _addVocabulary,
            child: const Text('Add'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
            ),
          ),
        ],
      ),
    );
  }
}
