import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class ArticleListScreen extends StatelessWidget {
  final String language;

  const ArticleListScreen({super.key, required this.language});

  Future<void> _deleteArticle(BuildContext context, String articleId) async {
    try {
      await FirebaseFirestore.instance
          .collection('languages')
          .doc(language)
          .collection('articles')
          .doc(articleId)
          .delete();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Article deleted'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting article: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('$language Articles'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('languages')
            .doc(language)
            .collection('articles')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final articles = snapshot.data?.docs ?? [];

          return ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: articles.length + 1,
            itemBuilder: (context, index) {
              // Add vertical spacing between cards
              final topPadding = index == 0 ? 0.0 : 8.0;

              // --- Add New Article Card ---
              if (index == 0) {
                return Padding(
                  padding: EdgeInsets.only(top: topPadding, bottom: 8.0),
                  child: _buildAddArticleCard(context),
                );
              }

              // --- Article Cards ---
              final articleIndex = index - 1;
              final article = articles[articleIndex];
              final data = article.data() as Map<String, dynamic>;
              final title = data['title'] ?? 'No Title';
              final content = data['content'] ?? 'No Content';

              return Padding(
                padding: EdgeInsets.only(top: topPadding, bottom: 8.0),
                child: Dismissible(
                  key: Key(article.id),
                  direction: DismissDirection.endToStart,
                  onDismissed: (direction) {
                    _deleteArticle(context, article.id);
                  },
                  background: _buildDismissibleBackground(),
                  child: _buildArticleCard(context, article.id, title, content),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildDismissibleBackground() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.redAccent,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20.0),
      child: const Icon(Icons.delete_sweep_outlined, color: Colors.white, size: 30),
    );
  }

  Widget _buildAddArticleCard(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => context.go('/language/$language/articles/add'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_circle_outline, color: Theme.of(context).primaryColor, size: 24),
              const SizedBox(width: 12),
              Text(
                'Add New Article',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).primaryColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildArticleCard(
      BuildContext context, String articleId, String title, String content) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => context.go('/language/$language/articles/$articleId'),
        borderRadius: BorderRadius.circular(12),
        // This SizedBox forces the card to take the full width
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, // Align text to the left
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  content,
                  style: GoogleFonts.openSans(fontSize: 14, color: Colors.black54),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
