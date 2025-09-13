// Stub implementation for web platform
class OfflineStorage {
  static Future<void> saveGuestbookEntry(Map<String, dynamic> data) async {
    throw UnsupportedError('Offline storage is not supported on web');
  }
  
  static Future<void> deleteGuestbookEntry(String id) async {
    throw UnsupportedError('Offline storage is not supported on web');
  }
  
  static Future<void> markAsSynced(String table, String id) async {
    throw UnsupportedError('Offline storage is not supported on web');
  }
  
  static Future<List<Map<String, dynamic>>> getUnsyncedData() async {
    throw UnsupportedError('Offline storage is not supported on web');
  }
  
  static Future<void> saveVocabulary(Map<String, dynamic> data) async {
    throw UnsupportedError('Offline storage is not supported on web');
  }
  
  static Future<List<Map<String, dynamic>>> getVocabularyByLanguage(String language) async {
    throw UnsupportedError('Offline storage is not supported on web');
  }
  
  static Future<void> updateVocabulary(String id, Map<String, dynamic> data) async {
    throw UnsupportedError('Offline storage is not supported on web');
  }
  
  static Future<void> deleteVocabulary(String id) async {
    throw UnsupportedError('Offline storage is not supported on web');
  }
  
  static Future<void> saveArticle(Map<String, dynamic> data) async {
    throw UnsupportedError('Offline storage is not supported on web');
  }
  
  static Future<List<Map<String, dynamic>>> getArticlesByLanguage(String language) async {
    throw UnsupportedError('Offline storage is not supported on web');
  }
  
  static Future<Map<String, dynamic>?> getArticleById(String id) async {
    throw UnsupportedError('Offline storage is not supported on web');
  }
  
  static Future<void> updateArticle(String id, Map<String, dynamic> data) async {
    throw UnsupportedError('Offline storage is not supported on web');
  }
  
  static Future<void> deleteArticle(String id) async {
    throw UnsupportedError('Offline storage is not supported on web');
  }
  
  static Future<List<Map<String, dynamic>>> getGuestbookEntries() async {
    throw UnsupportedError('Offline storage is not supported on web');
  }
  
  static Future<void> clearAllData() async {
    throw UnsupportedError('Offline storage is not supported on web');
  }
}