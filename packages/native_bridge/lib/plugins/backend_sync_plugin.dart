// Backend sync plugin for offline-first architecture
// This is the plugin architecture - implementation coming soon

enum SyncStatus { pending, synced, error, conflicted }

enum RetryStrategy { exponential, linear, none }

class RetryPolicy {
  final int maxRetries;
  final Duration initialDelay;
  final RetryStrategy strategy;

  const RetryPolicy({
    this.maxRetries = 3,
    this.initialDelay = const Duration(seconds: 1),
    this.strategy = RetryStrategy.exponential,
  });
}

class PendingOperation {
  final String id;
  final String operation;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int retryCount;
  final DateTime? lastAttempt;
  final String? error;

  PendingOperation({
    required this.id,
    required this.operation,
    required this.payload,
    required this.createdAt,
    this.retryCount = 0,
    this.lastAttempt,
    this.error,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'operation': operation,
    'payload': payload,
    'createdAt': createdAt.toIso8601String(),
    'retryCount': retryCount,
    'lastAttempt': lastAttempt?.toIso8601String(),
    'error': error,
  };

  factory PendingOperation.fromJson(Map<String, dynamic> json) =>
      PendingOperation(
        id: json['id'],
        operation: json['operation'],
        payload: json['payload'],
        createdAt: DateTime.parse(json['createdAt']),
        retryCount: json['retryCount'] ?? 0,
        lastAttempt: json['lastAttempt'] != null
            ? DateTime.parse(json['lastAttempt'])
            : null,
        error: json['error'],
      );
}

typedef ConflictResolver =
    Map<String, dynamic> Function(
      Map<String, dynamic> local,
      Map<String, dynamic> remote,
    );

typedef OnSuccess = void Function(Map<String, dynamic>);
typedef OnError = void Function(String error);

/// Backend sync plugin for offline-first apps.
///
/// Usage:
/// ```dart
/// void main() {
///   NativeBridge.use(BackendSyncPlugin(
///     apiUrl: 'https://api.example.com',
///     syncInterval: Duration(seconds: 30),
///   ));
///   runApp(MyApp());
/// }
/// ```
abstract class BackendSyncPlugin {
  /// Initialize with API URL and configuration
  static Future<void> initialize({
    required String apiUrl,
    Duration syncInterval = const Duration(seconds: 30),
    ConflictResolver? conflictResolver,
    bool enableLogging = false,
  }) async {
    // Implementation in concrete class
    throw UnimplementedError();
  }

  /// Optimistic update: update locally, sync in background
  ///
  /// UI updates immediately. Sync happens async.
  /// If sync fails, onError callback is called.
  static Future<void> optimisticUpdate({
    required String operation,
    required Map<String, dynamic> payload,
    required OnSuccess onSuccess,
    required OnError onError,
  }) async {
    throw UnimplementedError();
  }

  /// Blocking update: wait for backend confirmation
  ///
  /// UI waits for backend. Use for auth, payments, etc.
  /// Throws on error.
  static Future<Map<String, dynamic>> blockingUpdate({
    required String operation,
    required Map<String, dynamic> payload,
    Duration? timeout,
  }) async {
    throw UnimplementedError();
  }

  /// Queue operation: persist and retry when offline
  ///
  /// Returns true if queued immediately (offline).
  /// Returns false if synced immediately (online).
  static Future<bool> queueOperation({
    required String operation,
    required Map<String, dynamic> payload,
    RetryPolicy? retryPolicy,
  }) async {
    throw UnimplementedError();
  }

  /// Get all pending operations
  static Future<List<PendingOperation>> getPendingOperations() async {
    throw UnimplementedError();
  }

  /// Clear all pending operations
  static Future<void> clearPendingOperations() async {
    throw UnimplementedError();
  }

  /// Force immediate sync of all pending operations
  static Future<void> syncNow() async {
    throw UnimplementedError();
  }

  /// Monitor network status changes
  ///
  /// Emits true when online, false when offline.
  static Stream<bool> onNetworkStatusChanged() {
    throw UnimplementedError();
  }

  /// Get current network status
  static Future<bool> isOnline() async {
    throw UnimplementedError();
  }

  /// Configure conflict resolution strategy
  static void configureConflictResolver(ConflictResolver resolver) {
    throw UnimplementedError();
  }

  /// Subscribe to sync events
  static Stream<SyncEvent> onSyncEvent() {
    throw UnimplementedError();
  }
}

/// Sync event for monitoring
class SyncEvent {
  final String operationId;
  final String operation;
  final SyncEventType type;
  final DateTime timestamp;
  final String? error;
  final Map<String, dynamic>? response;

  SyncEvent({
    required this.operationId,
    required this.operation,
    required this.type,
    required this.timestamp,
    this.error,
    this.response,
  });
}

enum SyncEventType {
  started, // Sync started
  success, // Operation synced successfully
  error, // Sync failed
  conflict, // Conflict detected
  retrying, // Retrying after failure
  queued, // Operation queued (offline)
}

/// Example: Implementing the plugin (sketch)
///
/// ```dart
/// class BackendSyncPluginImpl extends BackendSyncPlugin {
///   static final _instance = BackendSyncPluginImpl._();
///   late String _apiUrl;
///   late PersistenceLayer _persistence;
///   final _syncQueue = <PendingOperation>[];
///   final _networkController = StreamController<bool>();
///   bool _isOnline = true;
///
///   factory BackendSyncPluginImpl() => _instance;
///   BackendSyncPluginImpl._();
///
///   @override
///   static Future<void> initialize({...}) async {
///     // Load persisted pending ops
///     // Start network monitoring
///     // Start sync loop
///   }
///
///   @override
///   static Future<void> optimisticUpdate({...}) async {
///     // Add to queue
///     // Start background sync
///   }
///
///   @override
///   static Future<Map> blockingUpdate({...}) async {
///     // Send immediately
///     // Wait for response
///   }
///
///   // ...
/// }
/// ```

// Persistence layer abstraction
abstract class PersistenceLayer {
  Future<void> savePendingOperations(List<PendingOperation> ops);
  Future<List<PendingOperation>> loadPendingOperations();
  Future<void> clearPendingOperations();
  Future<void> saveOperation(PendingOperation op);
  Future<void> deleteOperation(String operationId);
}
