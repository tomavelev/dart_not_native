/// Navigation & routing example - written as a plain Flutter app.
///
/// A [MaterialApp] with named routes, route parameters and a back/forward
/// history stack. `Navigator.of(context).pushNamed` moves between screens and
/// the platform back gesture pops them. Only the import (`widgets.dart`) renders
/// it through the platform's own views instead of the Flutter engine.
///
/// It also shows where state goes when it belongs to more than one screen:
/// [routingFavourites] is set on a user's page and counted on the home page,
/// which `setState` could not do - the screen holding it is rebuilt on the way
/// back.
library;

import 'package:dart_not_native/design_system/tokens.dart';
import 'package:dart_not_native/widgets.dart';

const routingUsers = [
  {
    'id': '1',
    'name': 'Alice Johnson',
    'email': 'alice@example.com',
    'phone': '+1 (555) 123-4567',
    'role': 'Product Manager',
  },
  {
    'id': '2',
    'name': 'Bob Smith',
    'email': 'bob@example.com',
    'phone': '+1 (555) 234-5678',
    'role': 'Engineer',
  },
  {
    'id': '3',
    'name': 'Carol White',
    'email': 'carol@example.com',
    'phone': '+1 (555) 345-6789',
    'role': 'Designer',
  },
];

const routingPosts = [
  {
    'id': '1',
    'title': 'Getting Started with Routing',
    'author': 'Alice Johnson',
    'date': '2024-01-15',
    'content':
        'Learn how to build multi-screen apps with navigation and routing...',
  },
  {
    'id': '2',
    'title': 'Multi-Screen Navigation',
    'author': 'Bob Smith',
    'date': '2024-01-20',
    'content':
        'Deep dive into route parameters, guards, and history management...',
  },
  {
    'id': '3',
    'title': 'Building Scalable Apps',
    'author': 'Carol White',
    'date': '2024-01-25',
    'content': 'Design patterns for large-scale app architecture...',
  },
];

/// The users marked as favourites, read by one screen and written by another.
///
/// A store outside the widget tree, because a `State` belongs to the screen
/// that built it and routing away disposes it. Any screen can read this one by
/// wrapping what it draws in a [ValueListenableBuilder].
final routingFavourites = ValueNotifier<Set<String>>({});

class RoutingExampleApp extends StatelessWidget {
  const RoutingExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        initialRoute: '/',
        routes: {
          '/': (context, params) => _home(context),
          '/users': (context, params) => _usersList(context),
          '/users/:id': (context, params) => _userDetail(context, params),
          '/posts': (context, params) => _postsList(context),
          '/posts/:id': (context, params) => _postDetail(context, params),
          '/settings': (context, params) => _settings(context),
        },
      );

  // --- Pages ---

  Widget _home(BuildContext context) => _page(
        title: 'Navigation Demo',
        children: [
          const Text('Navigation & Routing Example',
              style: TextStyle(
                  fontSize: FONT_SIZE_H3, fontWeight: FontWeight.w700)),
          const SizedBox(height: SPACING_SM),
          Text('Named routes, route parameters, history and guards.',
              style: TextStyle(color: Color.fromHex(COLOR_TEXT_SECONDARY))),
          const SizedBox(height: SPACING_LG),
          const Text('Quick navigation:',
              style: TextStyle(fontWeight: FontWeight.w500)),
          Row(
            children: [
              _navButton(context, 'Users List', '/users', 'nav_users'),
              _navButton(context, 'Posts List', '/posts', 'nav_posts'),
              _navButton(context, 'Settings', '/settings', 'nav_settings'),
            ],
          ),
          const SizedBox(height: SPACING_LG),
          // Set on a user's page, counted here: state neither screen owns.
          ValueListenableBuilder<Set<String>>(
            valueListenable: routingFavourites,
            builder: (context, ids, _) => Text(
              'Favourites: ${ids.length}',
              key: const ValueKey('favourites_count'),
            ),
          ),
          const SizedBox(height: SPACING_LG),
          _pathInfo(context),
        ],
      );

  Widget _usersList(BuildContext context) => _page(
        title: 'Users',
        children: [
          const Text('User Directory',
              style: TextStyle(
                  fontSize: FONT_SIZE_H4, fontWeight: FontWeight.w700)),
          const SizedBox(height: SPACING_MD),
          for (final user in routingUsers)
            Card.outlined(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user['name']!,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(user['email']!),
                      _navButton(context, 'Open', '/users/${user['id']}',
                          'user_${user['id']}'),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: SPACING_MD),
          _backButton(context),
          _pathInfo(context),
        ],
      );

  Widget _userDetail(BuildContext context, Map<String, dynamic> params) {
    final id = params['id']?.toString() ?? '?';
    final user = routingUsers.where((u) => u['id'] == id).firstOrNull;
    return _page(
      title: 'User Detail',
      children: [
        if (user == null)
          Text('User not found (ID: $id)', key: const ValueKey('detail_title'))
        else ...[
          Text(user['name']!,
              key: const ValueKey('detail_title'),
              style: const TextStyle(
                  fontSize: FONT_SIZE_H3, fontWeight: FontWeight.w700)),
          const SizedBox(height: SPACING_MD),
          Text('Email: ${user['email']}'),
          Text('Phone: ${user['phone']}'),
          Text('Role: ${user['role']}'),
          const SizedBox(height: SPACING_MD),
          ValueListenableBuilder<Set<String>>(
            valueListenable: routingFavourites,
            builder: (context, ids, _) => ElevatedButton(
              key: const ValueKey('favourite'),
              onPressed: () => routingFavourites.update(
                (ids) => ids.contains(id)
                    ? ({...ids}..remove(id))
                    : {...ids, id},
              ),
              child: Text(
                ids.contains(id) ? 'Remove favourite' : 'Add favourite',
              ),
            ),
          ),
        ],
        const SizedBox(height: SPACING_LG),
        Row(children: [_backButton(context), _navButton(context, 'Home', '/', 'home')]),
        _pathInfo(context),
      ],
    );
  }

  Widget _postsList(BuildContext context) => _page(
        title: 'Posts',
        children: [
          const Text('Recent Posts',
              style: TextStyle(
                  fontSize: FONT_SIZE_H4, fontWeight: FontWeight.w700)),
          const SizedBox(height: SPACING_MD),
          for (final post in routingPosts)
            Card.outlined(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(post['title']!,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('by ${post['author']}'),
                      _navButton(context, 'Read', '/posts/${post['id']}',
                          'post_${post['id']}'),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: SPACING_MD),
          _backButton(context),
          _pathInfo(context),
        ],
      );

  Widget _postDetail(BuildContext context, Map<String, dynamic> params) {
    final id = params['id']?.toString() ?? '?';
    final post = routingPosts.where((p) => p['id'] == id).firstOrNull;
    return _page(
      title: 'Post Detail',
      children: [
        if (post == null)
          Text('Post not found (ID: $id)', key: const ValueKey('detail_title'))
        else ...[
          Text(post['title']!,
              key: const ValueKey('detail_title'),
              style: const TextStyle(
                  fontSize: FONT_SIZE_H3, fontWeight: FontWeight.w700)),
          const SizedBox(height: SPACING_SM),
          Text('By ${post['author']} on ${post['date']}',
              style: TextStyle(color: Color.fromHex(COLOR_TEXT_SECONDARY))),
          const SizedBox(height: SPACING_MD),
          Text(post['content']!),
        ],
        const SizedBox(height: SPACING_LG),
        Row(children: [_backButton(context), _navButton(context, 'Home', '/', 'home')]),
        _pathInfo(context),
      ],
    );
  }

  Widget _settings(BuildContext context) {
    final nav = Navigator.of(context);
    return _page(
      title: 'Settings',
      children: [
        const Text('Application Settings',
            style:
                TextStyle(fontSize: FONT_SIZE_H4, fontWeight: FontWeight.w700)),
        const SizedBox(height: SPACING_MD),
        Text('Can go back: ${nav.canGoBack}',
            key: const ValueKey('can_go_back')),
        Text('Can go forward: ${nav.canGoForward}'),
        const SizedBox(height: SPACING_MD),
        const Text('Route history:',
            style: TextStyle(fontWeight: FontWeight.w500)),
        for (final (index, path) in nav.history.indexed)
          Text('${index + 1}. $path'),
        const SizedBox(height: SPACING_MD),
        _backButton(context),
        _pathInfo(context),
      ],
    );
  }

  // --- Helpers ---

  Widget _page({required String title, required List<Widget> children}) =>
      Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: children),
        ),
      );

  Widget _navButton(BuildContext context, String label, String path, String id) =>
      ElevatedButton(
        key: ValueKey(id),
        onPressed: () => Navigator.of(context).pushNamed(path),
        child: Text(label),
      );

  Widget _backButton(BuildContext context) => TextButton(
        key: const ValueKey('back'),
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Back'),
      );

  Widget _pathInfo(BuildContext context) {
    final nav = Navigator.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: SPACING_MD),
        Text('Current path: ${nav.currentPath}',
            key: const ValueKey('current_path'),
            style: TextStyle(color: Color.fromHex(COLOR_TEXT_SECONDARY))),
        Text('History: ${nav.history.join(' → ')}',
            key: const ValueKey('history'),
            style: TextStyle(color: Color.fromHex(COLOR_TEXT_SECONDARY))),
      ],
    );
  }
}
