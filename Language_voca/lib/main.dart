import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

import 'language_detail_screen.dart';
import 'screens/article_list_screen.dart';
import 'screens/article_detail_screen.dart';
import 'screens/add_article_screen.dart';
import 'screens/edit_article_screen.dart';

// Router configuration
final GoRouter _router = GoRouter(
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (BuildContext context, GoRouterState state) {
        return const FolderScreen();
      },
      routes: <RouteBase>[
        GoRoute(
          path: 'language/:lang',
          builder: (BuildContext context, GoRouterState state) {
            final String language = state.pathParameters['lang']!;
            return LanguageDetailScreen(language: language);
          },
          routes: <RouteBase>[
            GoRoute(
              path: 'articles',
              builder: (BuildContext context, GoRouterState state) {
                final String language = state.pathParameters['lang']!;
                return ArticleListScreen(language: language);
              },
              routes: <RouteBase>[
                GoRoute(
                  path: 'add',
                  builder: (BuildContext context, GoRouterState state) {
                    final String language = state.pathParameters['lang']!;
                    return AddArticleScreen(language: language);
                  },
                ),
                GoRoute(
                  path: ':articleId',
                  builder: (BuildContext context, GoRouterState state) {
                    final String language = state.pathParameters['lang']!;
                    final String articleId = state.pathParameters['articleId']!;
                    return ArticleDetailScreen(language: language, articleId: articleId);
                  },
                ),
                GoRoute(
                  path: ':articleId/edit',
                  builder: (BuildContext context, GoRouterState state) {
                    final String language = state.pathParameters['lang']!;
                    final String articleId = state.pathParameters['articleId']!;
                    return EditArticleScreen(language: language, articleId: articleId);
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: _router,
      title: 'Study-tool-Fr1',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.light),
        scaffoldBackgroundColor: Colors.white,
        textTheme: GoogleFonts.poppinsTextTheme(Theme.of(context).textTheme),
        elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), textStyle: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500))),
        useMaterial3: true,
      ),
    );
  }
}

class FolderScreen extends StatefulWidget {
  const FolderScreen({super.key});

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  final List<String> _folders = ['English', 'French', 'Japanese', 'Korean', 'Spanish', 'Chinese'];
  final Map<String, String> _languageFlags = {
    'English': '🇬🇧', 'French': '🇫🇷', 'Japanese': '🇯🇵', 'Korean': '🇰🇷', 'Spanish': '🇪🇸', 'Chinese': '🇨🇳',
  };

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  List<String> _selectedLanguages = [];

  // Add guestbook entry to Firestore
  Future<void> _addGuestbookEntry() async {
    if (_nameController.text.isNotEmpty && _messageController.text.isNotEmpty && _selectedLanguages.isNotEmpty) {
      await FirebaseFirestore.instance.collection('guestbook').add({
        'name': _nameController.text,
        'message': _messageController.text,
        'languages': _selectedLanguages,
        'timestamp': FieldValue.serverTimestamp(),
      });
      _nameController.clear();
      _messageController.clear();
      setState(() => _selectedLanguages.clear());
      FocusScope.of(context).unfocus();
    }
  }

  // Delete guestbook entry from Firestore
  void _deleteGuestbookEntry(String docId) {
    FirebaseFirestore.instance.collection('guestbook').doc(docId).delete();
  }

  // Show language selection dialog
  void _showLanguageSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) {
        List<String> tempSelectedLanguages = List.from(_selectedLanguages);
        return AlertDialog(
          title: const Text('Select Languages'),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              return Wrap(
                spacing: 8.0,
                children: _folders.map((language) {
                  final isSelected = tempSelectedLanguages.contains(language);
                  return ChoiceChip(
                    label: Text(language),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          tempSelectedLanguages.add(language);
                        } else {
                          tempSelectedLanguages.remove(language);
                        }
                      });
                    },
                  );
                }).toList(),
              );
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                setState(() {
                  _selectedLanguages = tempSelectedLanguages;
                });
                Navigator.of(context).pop();
              },
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Our study folders', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
        centerTitle: true, backgroundColor: Colors.white, elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: Center(
          child: Column(
            children: [
              // --- Folder Section ---
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: GridView.builder(
                  padding: const EdgeInsets.all(20.0),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 10.0, mainAxisSpacing: 10.0, childAspectRatio: 0.9),
                  itemCount: _folders.length + 1, // +1 for the decorative add button
                  itemBuilder: (context, index) {
                    if (index == _folders.length) {
                      // This is the decorative "Add" button
                      return Card(
                        elevation: 2,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add, size: 30, color: Colors.grey.shade600),
                            const SizedBox(height: 4),
                            Text('Add', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade700)),
                          ],
                        ),
                      );
                    }
                    
                    final folderName = _folders[index];
                    final flag = _languageFlags[folderName] ?? '🏳️';
                    return GestureDetector(
                      onTap: () => context.go('/language/$folderName'), // Navigate to detail screen
                      child: Card(
                        elevation: 2,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                Icon(Icons.folder, size: 45, color: Theme.of(context).colorScheme.primary.withOpacity(0.8)),
                                Positioned(child: Text(flag, style: const TextStyle(fontSize: 16))),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(folderName, style: GoogleFonts.poppins(fontSize: 11), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 30),

              // --- Guestbook Section ---
              Transform.scale(
                scale: 0.9,
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
                        child: Text('Guestbook', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold)),
                      ),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(controller: _nameController, style: const TextStyle(fontSize: 13), decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.all(10))),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(icon: const Icon(Icons.language, size: 16), label: const Text('Languages', style: TextStyle(fontSize: 12)), onPressed: _showLanguageSelectionDialog, style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8))),
                            if (_selectedLanguages.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Wrap(spacing: 5.0, runSpacing: 4.0, children: _selectedLanguages.map((lang) => Chip(label: Text(lang, style: const TextStyle(fontSize: 10)), padding: const EdgeInsets.all(2), visualDensity: VisualDensity.compact)).toList()),
                              ),
                            const SizedBox(height: 8),
                            TextField(controller: _messageController, style: const TextStyle(fontSize: 13), decoration: const InputDecoration(labelText: 'Message', border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.all(10))),
                            const SizedBox(height: 10),
                            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _addGuestbookEntry, child: const Text('Post'))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.only(left: 4.0, bottom: 6.0),
                        child: Text('Posts', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                      Container(
                        height: 220,
                        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(8)),
                        child: StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance.collection('guestbook').orderBy('timestamp', descending: true).snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                              return const Center(child: Text("Be the first to post!"));
                            }

                            return ListView.builder(
                              padding: const EdgeInsets.all(6),
                              itemCount: snapshot.data!.docs.length,
                              itemBuilder: (context, index) {
                                final doc = snapshot.data!.docs[index];
                                final data = doc.data() as Map<String, dynamic>;
                                final name = data['name'] ?? 'No Name';
                                final message = data['message'] ?? 'No Message';
                                final languages = (data['languages'] as List<dynamic>? ?? []).join(', ');

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  elevation: 1,
                                  child: ListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                    title: Text('"$message"', style: GoogleFonts.poppins(fontSize: 11, fontStyle: FontStyle.italic)),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 4.0, bottom: 2.0),
                                      child: Text('- $name (studying $languages)', style: GoogleFonts.poppins(color: Colors.black87, fontSize: 10)),
                                    ),
                                    trailing: IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent), onPressed: () => _deleteGuestbookEntry(doc.id)),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.only(top: 24.0),
                child: Text('Developed by Kyle Lee', style: GoogleFonts.poppins(color: Colors.grey[600], fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
