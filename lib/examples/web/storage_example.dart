/// Web entry for the storage example: DOM + Material CSS, no Flutter.
///
/// Regular values go to localStorage as they are; secure values are encrypted
/// with the browser's own AES-GCM before they get there, under a key the
/// browser keeps and will not hand out.
///
/// Build with maestro/web/build_examples.sh.
library;

import 'package:dart_not_native/web.dart';
import 'package:dart_not_native/widgets.dart' show hostApp;

import '../apps/storage_example_app.dart';

// The default prefixes overlap ('dnn.' is a prefix of 'dnn.secure.'), which
// would make the regular store list the secure keys as well, so give the two
// stores disjoint prefixes.
void main() => runWebApp(
      hostApp(
        StorageExampleApp(
          storage: LocalStorageService(prefix: 'dnn.plain.'),
          secureStorage: WebSecureStorage(prefix: 'dnn.secret.'),
        ),
      ),
    );
