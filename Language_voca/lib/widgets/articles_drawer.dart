import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

class ArticlesDrawer extends StatefulWidget {
  final String language;

  const ArticlesDrawer({super.key, required this.language});

  @override
  State<ArticlesDrawer> createState() => _ArticlesDrawerState();
}

class _ArticlesDrawerState extends State<ArticlesDrawer> {
  late CollectionReference _articlesCollection;

  @override
  void initState() {
    super.initState();
    _articlesCollection = FirebaseFirestore.instance.collection('languages').doc(widget.language).collection('articles');
  }

  @override
  void didUpdateWidget(ArticlesDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.language != oldWidget.language) {
      _articlesCollection = FirebaseFirestore.instance.collection('languages').doc(widget.language).collection('articles');
      setState(() {});
    }
  }

  Future<void> _addArticle(String title, String content) async {
    if (title.isNotEmpty && content.isNotEmpty) {
      await _articlesCollection.add({'title': title, 'content': content, 'timestamp': FieldValue.serverTimestamp()});
    }
  }

  Future<void> _deleteArticle(String docId) async {
    await _articlesCollection.doc(docId).delete();
  }

  void _showAddArticleDialog() {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Article'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Title'), autofocus: true),
            const SizedBox(height: 16),
            TextField(controller: contentController, decoration: const InputDecoration(labelText: 'Content', border: OutlineInputBorder()), minLines: 5, maxLines: 10),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => _addArticle(titleController.text, contentController.text).then((_) => Navigator.of(context).pop()), child: const Text('Add')),
        ],
      ),
    );
  }

  void _showArticleContentDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: SelectableText(content)),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          AppBar(
            title: Text('Articles', style: GoogleFonts.poppins()),
            automaticallyImplyLeading: false,
            actions: [IconButton(icon: const Icon(Icons.add), onPressed: _showAddArticleDialog, tooltip: 'Add Article')],
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _articlesCollection.orderBy('timestamp', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("No articles yet. Add one!"));

                return ListView.builder(
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final doc = snapshot.data!.docs[index];
                    final title = doc['title'] ?? 'No Title';
                    final content = doc['content'] ?? '';
                    return ListTile(
                      title: Text(title),
                      onTap: () {
                        Navigator.of(context).pop(); // Close the drawer
                        _showArticleContentDialog(title, content);
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                        onPressed: () => _deleteArticle(doc.id),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
