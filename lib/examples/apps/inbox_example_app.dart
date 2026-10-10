/// Inbox - a long list with a bottom sheet, a confirm dialog and an undo
/// snackbar, written as a plain Flutter app.
///
/// Ten thousand messages go through a `ListView.builder`, which builds only the
/// rows near the visible ones. A row's actions open in `showModalBottomSheet`;
/// deleting asks with `showDialog` and then offers Undo through
/// `ScaffoldMessenger.showSnackBar`. Only the import - `widgets.dart` in place
/// of Flutter's material - renders it through the platform's own views.
library;

import 'package:dart_not_native/widgets.dart';

class Message {
  final int id;
  final String from;
  final String subject;
  final String preview;
  bool read;

  Message({
    required this.id,
    required this.from,
    required this.subject,
    required this.preview,
    this.read = false,
  });
}

class InboxApp extends StatefulWidget {
  const InboxApp({super.key, this.count = 10000});

  final int count;

  @override
  State<InboxApp> createState() => _InboxAppState();
}

class _InboxAppState extends State<InboxApp> {
  static const _senders = ['Ada', 'Grace', 'Linus', 'Margaret', 'Dennis'];
  // As long as a real preview is. The row keeps them to one line and ends
  // them with an ellipsis, which is what stops an unknown length from pushing
  // a fixed-height row out of shape.
  static const _previews = [
    'Notes from today\'s sync, including the bits we said we would write '
        'down and then did not',
    'The build is green again after the flake in the storage tests',
    'Design review moved to 3pm - the room with the broken blind, sorry',
    'Thanks for the quick turnaround on this, it unblocked the whole thing',
    'Draft attached for your review whenever you have a moment this week',
  ];

  late final List<Message> messages = [
    for (var id = 1; id <= widget.count; id++)
      Message(
        id: id,
        from: _senders[id % _senders.length],
        subject: 'Message $id',
        preview: _previews[id % _previews.length],
        read: id % 3 == 0,
      ),
  ];

  /// The last deletion, while Undo is still on offer.
  ({Message message, int index})? _lastDeleted;

  int get unreadCount => messages.where((m) => !m.read).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Inbox ($unreadCount unread)')),
      body: ListView.builder(
        key: const ValueKey('inbox'),
        itemCount: messages.length,
        itemExtent: 104,
        itemBuilder: (context, index) => _row(context, messages[index]),
      ),
    );
  }

  Widget _row(BuildContext context, Message message) => SwipeActions(
        key: ValueKey('swipe_${message.id}'),
        actions: [
          SwipeAction(
            label: 'Delete',
            onPressed: () => _delete(context, message),
          ),
        ],
        // The other way, where iOS Mail puts it.
        leadingActions: [
          SwipeAction(
            label: message.read ? 'Unread' : 'Read',
            color: '#1976d2',
            onPressed: () => setState(() => message.read = !message.read),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
          spacing: 12,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.from,
                    style: TextStyle(
                      fontWeight:
                          message.read ? FontWeight.w400 : FontWeight.w700,
                    ),
                  ),
                  Text(
                    message.subject,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    message.preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF757575)),
                  ),
                ],
              ),
            ),
            IconButton(
              key: ValueKey('actions_${message.id}'),
              icon: const Icon(Icons.more_vert),
              tooltip: 'Actions for ${message.subject}',
              onPressed: () => _showActions(context, message),
            ),
          ],
          ),
        ),
      );

  void _showActions(BuildContext context, Message message) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            message.subject,
            key: const ValueKey('sheet_title'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextButton(
            key: const ValueKey('sheet_toggle_read'),
            onPressed: () {
              Navigator.of(context).pop();
              setState(() => message.read = !message.read);
            },
            child: Text(message.read ? 'Mark as unread' : 'Mark as read'),
          ),
          ElevatedButton(
            key: const ValueKey('sheet_delete'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => _confirmDelete(context, message),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, Message message) {
    // Opens over the sheet, which stays until the delete is confirmed.
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('confirm_delete'),
        title: const Text('Delete message?'),
        content: Text(
          '"${message.subject}" from ${message.from} will be deleted.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('confirm_cancel'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            key: const ValueKey('confirm_ok'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.of(context).pop(); // the dialog
              Navigator.of(context).pop(); // the sheet under it
              _delete(context, message);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _delete(BuildContext context, Message message) {
    final index = messages.indexOf(message);
    if (index < 0) return;
    setState(() => messages.removeAt(index));
    _lastDeleted = (message: message, index: index);
    // Undo is for the last deletion, so the bar for the one before it goes
    // now: snackbars queue, and left alone this one would wait ten seconds
    // behind it.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Message deleted'),
          // Long enough to read the message and reach the button.
          duration: const Duration(seconds: 10),
          action: SnackBarAction(label: 'Undo', onPressed: _undo),
        ),
      );
  }

  void _undo() {
    final deleted = _lastDeleted;
    if (deleted == null) return;
    setState(() => messages.insert(deleted.index, deleted.message));
    _lastDeleted = null;
  }
}
