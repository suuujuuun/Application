import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class OfflineStorage {
  static Database? _database;
  
  static Future<Database> get database async {
    if (kIsWeb) {
      throw UnsupportedError('Database operations are not supported on web');
    }
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }
  
  static Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'vocabulary.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: _createTables,
    );
  }
  
  static Future<void> _createTables(Database db, int version) async {
    // Vocabulary table
    await db.execute('''
      CREATE TABLE vocabulary(
        id TEXT PRIMARY KEY,
        language TEXT NOT NULL,
        term TEXT NOT NULL,
        definition TEXT NOT NULL,
        example TEXT,
        tags TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_synced INTEGER DEFAULT 0
      )
    ''');
    
    // Articles table
    await db.execute('''
      CREATE TABLE articles(
        id TEXT PRIMARY KEY,
        language TEXT NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_synced INTEGER DEFAULT 0
      )
    ''');
    
    // Guestbook table
    await db.execute('''
      CREATE TABLE guestbook(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        message TEXT NOT NULL,
        languages TEXT NOT NULL,
        created_at TEXT NOT NULL,
        is_synced INTEGER DEFAULT 0
      )
    ''');
  }
  
  // Vocabulary methods
  static Future<void> saveVocabulary(Map<String, dynamic> data) async {
    final db = await database;
    await db.insert(
      'vocabulary',
      {
        ...data,
        'is_synced': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
  
  static Future<List<Map<String, dynamic>>> getVocabularyByLanguage(String language) async {
    final db = await database;
    return await db.query(
      'vocabulary',
      where: 'language = ?',
      whereArgs: [language],
      orderBy: 'created_at DESC',
    );
  }
  
  static Future<void> updateVocabulary(String id, Map<String, dynamic> data) async {
    final db = await database;
    await db.update(
      'vocabulary',
      {
        ...data,
        'is_synced': 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  
  static Future<void> deleteVocabulary(String id) async {
    final db = await database;
    await db.delete(
      'vocabulary',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  
  // Articles methods
  static Future<void> saveArticle(Map<String, dynamic> data) async {
    final db = await database;
    await db.insert(
      'articles',
      {
        ...data,
        'is_synced': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
  
  static Future<List<Map<String, dynamic>>> getArticlesByLanguage(String language) async {
    final db = await database;
    return await db.query(
      'articles',
      where: 'language = ?',
      whereArgs: [language],
      orderBy: 'created_at DESC',
    );
  }
  
  static Future<Map<String, dynamic>?> getArticleById(String id) async {
    final db = await database;
    final result = await db.query(
      'articles',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }
  
  static Future<void> updateArticle(String id, Map<String, dynamic> data) async {
    final db = await database;
    await db.update(
      'articles',
      {
        ...data,
        'is_synced': 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  
  static Future<void> deleteArticle(String id) async {
    final db = await database;
    await db.delete(
      'articles',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  
  // Guestbook methods
  static Future<void> saveGuestbookEntry(Map<String, dynamic> data) async {
    final db = await database;
    await db.insert(
      'guestbook',
      {
        ...data,
        'languages': jsonEncode(data['languages']),
        'is_synced': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
  
  static Future<List<Map<String, dynamic>>> getGuestbookEntries() async {
    final db = await database;
    final results = await db.query(
      'guestbook',
      orderBy: 'created_at DESC',
      limit: 20,
    );
    
    return results.map((entry) {
      return {
        ...entry,
        'languages': jsonDecode(entry['languages'] as String),
      };
    }).toList();
  }
  
  static Future<void> deleteGuestbookEntry(String id) async {
    final db = await database;
    await db.delete(
      'guestbook',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  
  // Sync status methods
  static Future<List<Map<String, dynamic>>> getUnsyncedData() async {
    final db = await database;
    final unsynced = <Map<String, dynamic>>[];
    
    final vocabUnsynced = await db.query('vocabulary', where: 'is_synced = 0');
    final articlesUnsynced = await db.query('articles', where: 'is_synced = 0');
    final guestbookUnsynced = await db.query('guestbook', where: 'is_synced = 0');
    
    unsynced.addAll(vocabUnsynced.map((e) => {...e, 'table': 'vocabulary'}));
    unsynced.addAll(articlesUnsynced.map((e) => {...e, 'table': 'articles'}));
    unsynced.addAll(guestbookUnsynced.map((e) => {...e, 'table': 'guestbook'}));
    
    return unsynced;
  }
  
  static Future<void> markAsSynced(String table, String id) async {
    final db = await database;
    await db.update(
      table,
      {'is_synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  
  static Future<void> clearAllData() async {
    final db = await database;
    await db.delete('vocabulary');
    await db.delete('articles');
    await db.delete('guestbook');
  }
}