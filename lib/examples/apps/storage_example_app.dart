/// Storage plugin example - written as a plain Flutter app.
///
/// The storage back end is injected, so the same app runs on
/// SharedPreferences/secure storage on mobile and on localStorage on web. Only
/// the import (`widgets.dart`) renders it through the platform's own views
/// instead of the Flutter engine.
library;

import 'package:dart_not_native/design_system/tokens.dart';
import 'package:dart_not_native/storage/storage_service.dart';
import 'package:dart_not_native/widgets.dart';

class StorageExampleApp extends StatefulWidget {
  const StorageExampleApp({
    super.key,
    required this.storage,
    required this.secureStorage,
  });

  final StorageService storage;
  final SecureStorageService secureStorage;

  @override
  State<StorageExampleApp> createState() => _StorageExampleAppState();
}

class _StorageExampleAppState extends State<StorageExampleApp> {
  StorageService get storage => widget.storage;
  SecureStorageService get secureStorage => widget.secureStorage;

  Map<String, dynamic> storedData = {};
  Map<String, String> secureData = {};
  String encryptionStatus = 'Checking...';
  String message = 'Ready';

  @override
  void initState() {
    _initialize();
  }

  Future<void> _initialize() async {
    final available = await secureStorage.isEncryptionAvailable();
    encryptionStatus = available ? 'Enabled' : 'Disabled (web fallback)';
    await _loadAllData();
  }

  Future<void> _saveRegularData() async {
    try {
      await storage.setString('app_name', 'MyApp');
      await storage.setString('user_locale', 'en_US');
      await storage.setInt('app_launches', 42);
      await storage.setDouble('app_rating', 4.5);
      await storage.setBool('onboarding_complete', true);
      await storage.setStringList('recent_searches', [
        'flutter',
        'dart',
        'storage',
      ]);
      message = 'Regular data saved';
      await _loadAllData();
    } catch (e) {
      setState(() => message = 'Failed to save: $e');
    }
  }

  Future<void> _saveSecureData() async {
    try {
      await secureStorage.setString(
        'auth_token',
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9',
      );
      await secureStorage.setString(
        'user_password',
        'super_secret_password_123',
      );
      await secureStorage.setString('api_key', 'sk_live_abc123xyz789');
      await secureStorage.setBool('biometric_enabled', true);
      message = 'Secure data saved';
      await _loadAllData();
    } catch (e) {
      setState(() => message = 'Failed to save secure data: $e');
    }
  }

  Future<void> _testDataTypes() async {
    try {
      await storage.setString('test_string', 'Hello World');
      await storage.setInt('test_int', 12345);
      await storage.setDouble('test_double', 3.14159);
      await storage.setBool('test_bool', true);
      await storage.setStringList('test_list', ['item1', 'item2', 'item3']);

      final str = await storage.getString('test_string');
      final number = await storage.getInt('test_int');
      final decimal = await storage.getDouble('test_double');
      final flag = await storage.getBool('test_bool');
      final list = await storage.getStringList('test_list');

      message =
          'Types OK: $str / $number / $decimal / $flag / ${list?.join(", ")}';
      await _loadAllData();
    } catch (e) {
      setState(() => message = 'Type test failed: $e');
    }
  }

  Future<void> _clearAll() async {
    try {
      await storage.clear();
      await secureStorage.clear();
      message = 'All data cleared';
      await _loadAllData();
    } catch (e) {
      setState(() => message = 'Failed to clear: $e');
    }
  }

  Future<void> _loadAllData() async {
    final all = await storage.getAll();
    final keys = await secureStorage.getKeys();
    final secure = <String, String>{};
    for (final key in keys) {
      final value = await secureStorage.getString(key);
      if (value == null) continue;
      // Show only the first characters of secrets.
      secure[key] = value.length > 10 ? '${value.substring(0, 10)}...' : value;
    }
    setState(() {
      storedData = all;
      secureData = secure;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppBar(title: Text('Storage Plugin Demo')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Encryption: $encryptionStatus',
                key: const ValueKey('encryption_status'),
                style: const TextStyle(fontWeight: FontWeight.w500)),
            Text('Status: $message',
                key: const ValueKey('status'),
                style: TextStyle(color: Color.fromHex(COLOR_TEXT_SECONDARY))),
            const SizedBox(height: SPACING_MD),
            Wrap(
              spacing: SPACING_SM,
              runSpacing: SPACING_SM,
              children: [
                ElevatedButton(
                  key: const ValueKey('save_regular'),
                  onPressed: _saveRegularData,
                  child: const Text('Save Regular'),
                ),
                ElevatedButton(
                  key: const ValueKey('save_secure'),
                  onPressed: _saveSecureData,
                  child: const Text('Save Secure'),
                ),
                TextButton(
                  key: const ValueKey('load_all'),
                  onPressed: _loadAllData,
                  child: const Text('Reload'),
                ),
                ElevatedButton(
                  key: const ValueKey('test_types'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                  onPressed: _testDataTypes,
                  child: const Text('Test Types'),
                ),
                ElevatedButton(
                  key: const ValueKey('clear_all'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: _clearAll,
                  child: const Text('Clear All'),
                ),
              ],
            ),
            const SizedBox(height: SPACING_MD),
            Row(
              spacing: SPACING_LG,
              children: [
                _section('Regular storage (unencrypted)', 'regular', {
                  for (final e in storedData.entries) e.key: _format(e.value),
                }),
                _section('Secure storage (encrypted)', 'secure', secureData),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, String idPrefix, Map<String, dynamic> data) =>
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: FONT_SIZE_H5, fontWeight: FontWeight.w700)),
            Text('${data.length} keys', key: ValueKey('${idPrefix}_count')),
            const SizedBox(height: SPACING_SM),
            if (data.isEmpty)
              Text('(empty)',
                  style: TextStyle(color: Color.fromHex(COLOR_TEXT_SECONDARY)))
            else
              for (final entry in data.entries)
                Text('${entry.key}: ${entry.value}',
                    key: ValueKey('${idPrefix}_${entry.key}')),
          ],
        ),
      );

  static String _format(dynamic value) =>
      value is List ? value.join(', ') : '$value';
}
