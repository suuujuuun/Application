import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'offline_storage.dart';

class SyncService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  static Future<bool> isOnline() async {
    try {
      // Try to get a simple document to test connectivity
      await _firestore.collection('test').limit(1).get();
      return true;
    } catch (e) {
      return false;
    }
  }
  
  static Future<void> syncToFirestore() async {
    if (kIsWeb) {
      if (kDebugMode) print('Web platform - skipping offline sync to Firestore');
      return;
    }
    
    if (!await isOnline()) {
      if (kDebugMode) print('Offline - skipping sync to Firestore');
      return;
    }
    
    try {
      final unsyncedData = await OfflineStorage.getUnsyncedData();
      
      for (final item in unsyncedData) {
        final table = item['table'] as String;
        final id = item['id'] as String;
        
        // Remove metadata before syncing
        final data = Map<String, dynamic>.from(item);
        data.remove('table');
        data.remove('is_synced');
        
        if (table == 'vocabulary') {
          await _syncVocabularyItem(data);
        } else if (table == 'articles') {
          await _syncArticleItem(data);
        } else if (table == 'guestbook') {
          await _syncGuestbookItem(data);
        }
        
        await OfflineStorage.markAsSynced(table, id);
      }
    } catch (e) {
      if (kDebugMode) print('Sync to Firestore failed: $e');
    }
  }
  
  static Future<void> _syncVocabularyItem(Map<String, dynamic> data) async {
    final language = data['language'] as String;
    String collectionName;
    
    switch (language) {
      case 'English':
        collectionName = 'Med_voca'; // or determine based on content
        break;
      case 'French':
        collectionName = 'french_vocabulary';
        break;
      default:
        collectionName = '${language.toLowerCase()}_vocabulary';
    }
    
    await _firestore.collection(collectionName).doc(data['id']).set(data);
  }
  
  static Future<void> _syncArticleItem(Map<String, dynamic> data) async {
    final language = data['language'] as String;
    await _firestore
        .collection('languages')
        .doc(language)
        .collection('articles')
        .doc(data['id'])
        .set(data);
  }
  
  static Future<void> _syncGuestbookItem(Map<String, dynamic> data) async {
    // Parse languages back to array for Firestore
    if (data['languages'] is String) {
      data['languages'] = jsonDecode(data['languages']);
    }
    // Convert timestamp
    data['timestamp'] = FieldValue.serverTimestamp();
    data.remove('created_at');
    
    await _firestore.collection('guestbook').doc(data['id']).set(data);
  }
  
  static Future<void> syncFromFirestore() async {
    if (kIsWeb) {
      if (kDebugMode) print('Web platform - skipping offline sync from Firestore');
      return;
    }
    
    if (!await isOnline()) {
      if (kDebugMode) print('Offline - skipping sync from Firestore');
      return;
    }
    
    try {
      // Sync vocabulary collections
      await _syncVocabularyFromFirestore();
      
      // Sync articles
      await _syncArticlesFromFirestore();
      
      // Sync guestbook
      await _syncGuestbookFromFirestore();
      
    } catch (e) {
      if (kDebugMode) print('Sync from Firestore failed: $e');
    }
  }
  
  static Future<void> _syncVocabularyFromFirestore() async {
    final collections = ['Med_voca', 'expression', 'phrasal_verb'];
    
    for (final collection in collections) {
      try {
        final snapshot = await _firestore.collection(collection).get();
        
        for (final doc in snapshot.docs) {
          final data = doc.data();
          data['id'] = doc.id;
          data['language'] = 'English'; // These are all English collections
          
          // Ensure required fields exist
          data['term'] ??= data['word'] ?? '';
          data['definition'] ??= data['meaning'] ?? '';
          data['example'] ??= '';
          data['tags'] ??= '';
          data['created_at'] ??= DateTime.now().toIso8601String();
          data['updated_at'] ??= DateTime.now().toIso8601String();
          
          await OfflineStorage.saveVocabulary(data);
          await OfflineStorage.markAsSynced('vocabulary', doc.id);
        }
      } catch (e) {
        if (kDebugMode) print('Failed to sync $collection: $e');
      }
    }
  }
  
  static Future<void> _syncArticlesFromFirestore() async {
    final languages = ['English', 'French', 'Japanese', 'Korean', 'Spanish', 'Chinese'];
    
    for (final language in languages) {
      try {
        final snapshot = await _firestore
            .collection('languages')
            .doc(language)
            .collection('articles')
            .get();
        
        for (final doc in snapshot.docs) {
          final data = doc.data();
          data['id'] = doc.id;
          data['language'] = language;
          
          await OfflineStorage.saveArticle(data);
          await OfflineStorage.markAsSynced('articles', doc.id);
        }
      } catch (e) {
        if (kDebugMode) print('Failed to sync articles for $language: $e');
      }
    }
  }
  
  static Future<void> _syncGuestbookFromFirestore() async {
    try {
      final snapshot = await _firestore
          .collection('guestbook')
          .orderBy('timestamp', descending: true)
          .limit(20)
          .get();
      
      for (final doc in snapshot.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        data['created_at'] = (data['timestamp'] as Timestamp?)?.toDate().toIso8601String() ?? DateTime.now().toIso8601String();
        
        await OfflineStorage.saveGuestbookEntry(data);
        await OfflineStorage.markAsSynced('guestbook', doc.id);
      }
    } catch (e) {
      if (kDebugMode) print('Failed to sync guestbook: $e');
    }
  }
  
  static Future<void> fullSync() async {
    if (kIsWeb) {
      if (kDebugMode) print('Web platform - skipping offline sync operations');
      return;
    }
    await syncFromFirestore();
    await syncToFirestore();
  }
}