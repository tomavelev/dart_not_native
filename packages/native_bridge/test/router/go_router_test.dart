/// The go_router-shaped router, mounted on an in-memory renderer and driven
/// the way an app drives it.
library;

import 'dart:async';

import 'package:dart_not_native/core.dart'
    show InMemoryRenderer, NativeUIApp, SystemBack, WidgetNode;
import 'package:dart_not_native/router.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/tree.dart' as tree;

class _Mounted {
  _Mounted(this.router)
    : app = hostApp(MaterialApp.router(routerConfig: router)) {
    app.onChanged = () => renders++;
    app.mount(renderer);
  }

  final GoRouter router;
  final NativeUIApp app;
  final InMemoryRenderer renderer = InMemoryRenderer();
  int renders = 0;

  WidgetNode get root => renderer.tree!;
  List<String> get texts => tree.texts(root);
  String? text(String id) =>
      tree.nodeById(root, id)?.props['content'] as String?;

  Future<void> tap(String id) async {
    final node = tree.nodeById(root, id)!;
    await renderer.handleEvent(node.props['eventId'] as String, {});
  }
}

/// A page that says where it is, as its route sees it.
GoRouterWidgetBuilder _page(String label) =>
    (context, state) =>
        Text('$label ${state.uri}', key: const ValueKey('page'));

/// Counts how often it is created and disposed, to see a `State` come and go.
class _Lifecycle {
  int created = 0;
  int disposed = 0;
}

class _Counted extends StatefulWidget {
  const _Counted(this.life, {this.child, this.id = 'count'});
  final _Lifecycle life;
  final Widget? child;
  final String id;
  @override
  State<_Counted> createState() => _CountedState();
}

class _CountedState extends State<_Counted> {
  int taps = 0;

  @override
  void initState() {
    super.initState();
    widget.life.created++;
  }

  @override
  void dispose() {
    widget.life.disposed++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text('$taps', key: ValueKey(widget.id)),
      ElevatedButton(
        key: ValueKey('${widget.id}_tap'),
        onPressed: () => setState(() => taps++),
        child: const Text('+'),
      ),
      if (widget.child != null) widget.child!,
    ],
  );
}

/// A platform history that records what it is asked, for the web wiring.
class _FakeHistory extends HistoryAdapter {
  final List<String> calls = [];
  @override
  bool get hasStack => true;
  @override
  void push(String path) => calls.add('push $path');
  @override
  void replace(String path) => calls.add('replace $path');
  @override
  void back() => calls.add('back');
  @override
  void forward() => calls.add('forward');
}

void main() {
  tearDown(SystemBack.clearHandlers);

  group('matching', () {
    GoRouter router({String initialLocation = '/'}) => GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(path: '/', builder: _page('home')),
        GoRoute(
          path: '/users',
          builder: _page('users'),
          routes: [
            GoRoute(
              path: ':id',
              name: 'user',
              builder: (_, state) => Text(
                'user ${state.pathParameters['id']}',
                key: const ValueKey('page'),
              ),
              routes: [
                GoRoute(
                  path: 'posts/:postId',
                  name: 'post',
                  builder: (_, state) => Text(
                    'post ${state.pathParameters['id']}/'
                    '${state.pathParameters['postId']} '
                    '${state.matchedLocation} ${state.fullPath}',
                    key: const ValueKey('page'),
                  ),
                ),
              ],
            ),
          ],
        ),
        // Would also fit `/users/new`, but the table's order is its priority.
        GoRoute(path: '/users/new', builder: _page('never')),
        GoRoute(
          path: '/search',
          name: 'search',
          builder: (_, state) => Text(
            'search ${state.uri.queryParameters['q']}',
            key: const ValueKey('page'),
          ),
        ),
      ],
      errorBuilder: (_, state) =>
          Text('error ${state.error!.message}', key: const ValueKey('page')),
    );

    test('starts at the initial location', () {
      final m = _Mounted(router());
      expect(m.text('page'), 'home /');
    });

    test('a deep initial location is matched directly', () {
      final m = _Mounted(router(initialLocation: '/users/7'));
      expect(m.text('page'), 'user 7');
    });

    test('go moves to a static path', () {
      final m = _Mounted(router());
      m.router.go('/users');
      expect(m.text('page'), 'users /users');
      expect(m.router.state.matchedLocation, '/users');
    });

    test('a path parameter is extracted, and decoded', () {
      final m = _Mounted(router());
      m.router.go('/users/ann%20lee');
      expect(m.text('page'), 'user ann lee');
    });

    test('nested routes join relative paths and keep the parents\' '
        'parameters', () {
      final m = _Mounted(router());
      m.router.go('/users/7/posts/42');
      expect(
        m.text('page'),
        'post 7/42 /users/7/posts/42 /users/:id/posts/:postId',
      );
    });

    test('the first route that fits wins', () {
      final m = _Mounted(router());
      m.router.go('/users/new');
      expect(m.text('page'), 'user new');
    });

    test('query parameters arrive on the uri', () {
      final m = _Mounted(router());
      m.router.go('/search?q=cake');
      expect(m.text('page'), 'search cake');
      expect(m.router.state.matchedLocation, '/search');
    });

    test('a trailing slash is the same place', () {
      final m = _Mounted(router());
      m.router.go('/users/');
      expect(m.text('page'), 'users /users');
    });

    test('an unknown location reaches the errorBuilder', () {
      final m = _Mounted(router());
      m.router.go('/nowhere');
      expect(m.text('page'), 'error no routes for location: /nowhere');
      expect(m.router.state.error, isA<GoException>());
    });

    test('a segment too many is not a match', () {
      final m = _Mounted(router());
      m.router.go('/search/extra');
      expect(m.text('page'), startsWith('error'));
    });

    test('without an errorBuilder there is still a page', () {
      final m = _Mounted(
        GoRouter(
          routes: [GoRoute(path: '/', builder: _page('home'))],
        ),
      );
      m.router.go('/nowhere');
      expect(m.texts.single, contains('no routes for location: /nowhere'));
    });

    test('goNamed fills in path and query parameters', () {
      final m = _Mounted(router());
      m.router.goNamed(
        'post',
        pathParameters: {'id': '7', 'postId': 'a b'},
        queryParameters: {'ref': 'home'},
      );
      expect(m.router.state.uri.toString(), '/users/7/posts/a%20b?ref=home');
      expect(m.router.state.name, 'post');
      expect(m.router.state.pathParameters, {'id': '7', 'postId': 'a b'});
    });

    test('an unknown name, or a missing parameter, is an error', () {
      final r = router();
      expect(() => r.goNamed('nope'), throwsA(isA<GoError>()));
      expect(() => r.goNamed('user'), throwsA(isA<GoError>()));
    });

    test('the state carries extra, name, path and fullPath', () {
      final m = _Mounted(router());
      m.router.go('/users/7', extra: 'payload');
      final state = m.router.state;
      expect(state.extra, 'payload');
      expect(state.name, 'user');
      expect(state.path, ':id');
      expect(state.fullPath, '/users/:id');
      expect(state.matchedLocation, '/users/7');
    });

    test('the router notifies its listeners when it moves', () {
      final r = router();
      var notified = 0;
      r.addListener(() => notified++);
      r.go('/users');
      expect(notified, 1);
    });
  });

  group('GoRouterState.of and the context helpers', () {
    test('a page reads its own state from the context', () {
      final m = _Mounted(
        GoRouter(
          initialLocation: '/guests/7?tab=gifts',
          routes: [
            GoRoute(
              path: '/guests/:id',
              builder: (_, _) => const _ReadsState(),
            ),
          ],
        ),
      );

      expect(m.text('state'), '/guests/7?tab=gifts 7 /guests/:id');
    });

    test(
      'context.go, GoRouter.of and GoRouterState.of work from a callback',
      () async {
        final seen = <String>[];
        final m = _Mounted(
          GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, _) => ElevatedButton(
                  key: const ValueKey('to_guests'),
                  onPressed: () {
                    seen.add(GoRouterState.of(context).uri.path);
                    context.go('/guests');
                    seen.add(GoRouter.of(context).state.uri.path);
                  },
                  child: const Text('guests'),
                ),
              ),
              GoRoute(path: '/guests', builder: _page('guests')),
            ],
          ),
        );

        await m.tap('to_guests');

        expect(m.text('page'), 'guests /guests');
        expect(seen, ['/', '/guests']);
      },
    );

    test('a context no router is drawn in has none', () {
      late BuildContext captured;
      final renderer = InMemoryRenderer();
      hostApp(_Capture((context) => captured = context)).mount(renderer);

      expect(GoRouter.maybeOf(captured), isNull);
      expect(() => GoRouter.of(captured), throwsA(isA<GoError>()));
    });
  });

  group('ShellRoute', () {
    late _Lifecycle shell;
    late _Lifecycle page;

    GoRouter router() => GoRouter(
      routes: [
        GoRoute(path: '/login', builder: _page('login')),
        ShellRoute(
          builder: (context, state, child) => _Counted(
            shell,
            id: 'shell',
            child: Column(
              children: [
                Text(
                  'at ${GoRouterState.of(context).uri.path}',
                  key: const ValueKey('shell_at'),
                ),
                child,
              ],
            ),
          ),
          routes: [
            GoRoute(path: '/', builder: (_, _) => _Counted(page)),
            GoRoute(path: '/guests', builder: (_, _) => _Counted(page)),
            GoRoute(path: '/tasks/:id', builder: (_, _) => _Counted(page)),
          ],
        ),
      ],
    );

    setUp(() {
      shell = _Lifecycle();
      page = _Lifecycle();
    });

    test('wraps the page of whichever of its routes is showing', () {
      final m = _Mounted(router());
      expect(m.text('shell_at'), 'at /');
      expect(m.text('count'), '0');

      m.router.go('/guests');

      expect(m.text('shell_at'), 'at /guests');
    });

    test('its State survives navigation between its routes', () async {
      final m = _Mounted(router());
      await m.tap('shell_tap');

      m.router.go('/guests');
      m.router.go('/tasks/3');

      expect(m.text('shell'), '1');
      expect(shell.created, 1);
      expect(shell.disposed, 0);
    });

    test('a page\'s State is dropped when its route is left - even for a '
        'route that builds the same widget', () async {
      final m = _Mounted(router());
      await m.tap('count_tap');
      expect(m.text('count'), '1');

      m.router.go('/guests');

      expect(m.text('count'), '0');
      expect(page.created, 2);
      expect(page.disposed, 1);
    });

    test('a different parameter is a different page', () async {
      final m = _Mounted(router());
      m.router.go('/tasks/1');
      await m.tap('count_tap');

      m.router.go('/tasks/2');

      expect(m.text('count'), '0');
    });

    test('a different query is the same page', () async {
      final m = _Mounted(router());
      m.router.go('/guests');
      await m.tap('count_tap');

      m.router.go('/guests?filter=confirmed');

      expect(m.text('count'), '1');
      expect(page.disposed, 1, reason: 'only the home page was left');
    });

    test('leaving the shell drops it', () {
      final m = _Mounted(router());

      m.router.go('/login');

      expect(m.text('page'), 'login /login');
      expect(shell.disposed, 1);
      expect(page.disposed, 1);
    });
  });

  group('redirect', () {
    test('runs on every navigation, with the incoming location', () {
      var signedIn = false;
      final asked = <String>[];
      final m = _Mounted(
        GoRouter(
          redirect: (_, state) {
            asked.add(state.matchedLocation);
            if (!signedIn && state.matchedLocation != '/login') return '/login';
            return null;
          },
          routes: [
            GoRoute(path: '/', builder: _page('home')),
            GoRoute(path: '/guests', builder: _page('guests')),
            GoRoute(path: '/login', builder: _page('login')),
          ],
        ),
      );
      expect(m.text('page'), 'login /login', reason: 'the initial location');
      expect(asked, ['/', '/login']);

      m.router.go('/guests');
      expect(m.text('page'), 'login /login');

      signedIn = true;
      m.router.go('/guests');
      expect(m.text('page'), 'guests /guests');
    });

    test('is given a context', () {
      BuildContext? given;
      _Mounted(
        GoRouter(
          redirect: (context, _) {
            given = context;
            return null;
          },
          routes: [GoRoute(path: '/', builder: _page('home'))],
        ),
      );
      expect(given, isNotNull);
    });

    test('runs again when refreshListenable fires', () {
      final session = ValueNotifier(true);
      final m = _Mounted(
        GoRouter(
          refreshListenable: session,
          redirect: (_, state) {
            final atLogin = state.matchedLocation == '/login';
            if (!session.value) return atLogin ? null : '/login';
            return atLogin ? '/' : null;
          },
          routes: [
            GoRoute(path: '/', builder: _page('home')),
            GoRoute(path: '/login', builder: _page('login')),
          ],
        ),
      );
      expect(m.text('page'), 'home /');

      session.value = false;
      expect(m.text('page'), 'login /login');

      session.value = true;
      expect(m.text('page'), 'home /');
    });

    test('refresh re-runs it without moving when it has nothing to say', () {
      var asked = 0;
      final m = _Mounted(
        GoRouter(
          redirect: (_, _) {
            asked++;
            return null;
          },
          routes: [GoRoute(path: '/', builder: _page('home'))],
        ),
      );
      final renders = m.renders;

      m.router.refresh();

      expect(asked, 2);
      expect(m.text('page'), 'home /');
      expect(m.renders, renders + 1);
    });

    test('a route\'s own redirect runs after the router\'s, parents first', () {
      final order = <String>[];
      final m = _Mounted(
        GoRouter(
          redirect: (_, _) {
            order.add('top');
            return null;
          },
          routes: [
            GoRoute(path: '/', builder: _page('home')),
            GoRoute(
              path: '/old',
              redirect: (_, _) {
                order.add('parent');
                return null;
              },
              builder: _page('old'),
              routes: [
                GoRoute(
                  path: 'page',
                  redirect: (_, state) {
                    order.add('child ${state.matchedLocation}');
                    return '/';
                  },
                ),
              ],
            ),
          ],
        ),
      );
      order.clear();

      m.router.go('/old/page');

      expect(m.text('page'), 'home /');
      expect(order, ['top', 'parent', 'child /old/page', 'top']);
    });

    test('an asynchronous redirect lands when it resolves', () async {
      final gate = Completer<String?>();
      final m = _Mounted(
        GoRouter(
          redirect: (_, state) =>
              state.matchedLocation == '/slow' ? gate.future : null,
          routes: [
            GoRoute(path: '/', builder: _page('home')),
            GoRoute(path: '/slow', builder: _page('slow')),
            GoRoute(path: '/done', builder: _page('done')),
          ],
        ),
      );

      m.router.go('/slow');
      expect(m.text('page'), 'home /', reason: 'still deciding');

      gate.complete('/done');
      await pumpEventQueue();

      expect(m.text('page'), 'done /done');
    });

    test('an asynchronous redirect overtaken by a later navigation is '
        'dropped', () async {
      final gate = Completer<String?>();
      final m = _Mounted(
        GoRouter(
          redirect: (_, state) =>
              state.matchedLocation == '/slow' ? gate.future : null,
          routes: [
            GoRoute(path: '/', builder: _page('home')),
            GoRoute(path: '/slow', builder: _page('slow')),
            GoRoute(path: '/other', builder: _page('other')),
          ],
        ),
      );

      m.router.go('/slow');
      m.router.go('/other');
      gate.complete(null);
      await pumpEventQueue();

      expect(m.text('page'), 'other /other');
    });

    test(
      'nothing is drawn until an asynchronous first redirect settles',
      () async {
        final gate = Completer<String?>();
        final m = _Mounted(
          GoRouter(
            redirect: (_, state) =>
                state.matchedLocation == '/' ? gate.future : null,
            routes: [
              GoRoute(path: '/', builder: _page('home')),
              GoRoute(path: '/login', builder: _page('login')),
            ],
          ),
        );
        expect(m.texts, isEmpty);

        gate.complete('/login');
        await pumpEventQueue();

        expect(m.text('page'), 'login /login');
      },
    );

    test('a loop is caught and shown as an error', () {
      final m = _Mounted(
        GoRouter(
          initialLocation: '/c',
          redirect: (_, state) => switch (state.matchedLocation) {
            '/a' => '/b',
            '/b' => '/a',
            _ => null,
          },
          routes: [
            for (final path in ['/a', '/b', '/c'])
              GoRoute(path: path, builder: _page(path)),
          ],
          errorBuilder: (_, state) =>
              Text(state.error!.message, key: const ValueKey('page')),
        ),
      );

      m.router.go('/a');

      expect(m.text('page'), 'redirect loop detected /a => /b => /a');
    });

    test('more than five redirects in a row is given up on', () {
      GoRouter router(int hops) => GoRouter(
        initialLocation: '/start',
        redirect: (_, state) {
          final at = int.tryParse(state.matchedLocation.substring(1));
          return at == null || at >= hops ? null : '/${at + 1}';
        },
        routes: [
          GoRoute(path: '/start', builder: _page('start')),
          GoRoute(
            path: '/:n',
            builder: (_, state) => Text(
              'hop ${state.pathParameters['n']}',
              key: const ValueKey('page'),
            ),
          ),
        ],
        errorBuilder: (_, state) =>
            Text(state.error!.message, key: const ValueKey('page')),
      );

      final five = _Mounted(router(5));
      five.router.go('/0');
      expect(five.text('page'), 'hop 5');

      final six = _Mounted(router(6));
      six.router.go('/0');
      expect(
        six.text('page'),
        'too many redirects /0 => /1 => /2 => /3 => /4 => /5 => /6',
      );
    });

    test('a route with only a redirect that lets it through is an error', () {
      final m = _Mounted(
        GoRouter(
          routes: [
            GoRoute(path: '/', builder: _page('home')),
            GoRoute(path: '/hollow', redirect: (_, _) => null),
          ],
          errorBuilder: (_, state) =>
              Text(state.error!.message, key: const ValueKey('page')),
        ),
      );

      m.router.go('/hollow');

      expect(m.text('page'), startsWith('no page for location: /hollow'));
    });

    test('a navigation made before the router is drawn is redirected when '
        'it is', () {
      final router = GoRouter(
        redirect: (_, state) =>
            state.matchedLocation == '/secret' ? '/login' : null,
        routes: [
          GoRoute(path: '/', builder: _page('home')),
          GoRoute(path: '/secret', builder: _page('secret')),
          GoRoute(path: '/login', builder: _page('login')),
        ],
      )..go('/secret');

      final m = _Mounted(router);

      expect(m.text('page'), 'login /login');
    });
  });

  group('push and pop', () {
    GoRouter router() => GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: _page('home'),
          routes: [
            GoRoute(
              path: 'guests',
              builder: _page('guests'),
              routes: [GoRoute(path: ':id', builder: _page('guest'))],
            ),
          ],
        ),
        GoRoute(path: '/form', builder: _page('form')),
        GoRoute(path: '/other', builder: _page('other')),
      ],
    );

    test('push puts a page on top; pop takes it off again', () {
      final m = _Mounted(router());
      expect(m.router.canPop(), isFalse);

      m.router.push('/form');
      expect(m.text('page'), 'form /form');
      expect(m.router.canPop(), isTrue);

      m.router.pop();
      expect(m.text('page'), 'home /');
      expect(m.router.canPop(), isFalse);
    });

    test('push completes with what the page is popped with', () async {
      final m = _Mounted(router());

      final result = m.router.push<String>('/form');
      m.router.pop('saved');

      expect(await result, 'saved');
    });

    test('pushes stack', () {
      final m = _Mounted(router());
      m.router.push('/form');
      m.router.push('/other');

      m.router.pop();
      expect(m.text('page'), 'form /form');
      m.router.pop();
      expect(m.text('page'), 'home /');
    });

    test('popping with nothing to pop is an error', () {
      final m = _Mounted(router());
      expect(() => m.router.pop(), throwsA(isA<GoError>()));
    });

    test('go clears what was pushed, answering it with nothing', () async {
      final m = _Mounted(router());
      final result = m.router.push<String>('/form');

      m.router.go('/other');

      expect(await result, isNull);
      expect(m.router.canPop(), isFalse);
      expect(m.text('page'), 'other /other');
    });

    test('a page nested under another pops to its parent', () {
      final m = _Mounted(router());
      m.router.go('/guests/7');
      expect(m.router.canPop(), isTrue);

      m.router.pop();
      expect(m.text('page'), 'guests /guests');
      expect(m.router.state.matchedLocation, '/guests');

      m.router.pop();
      expect(m.text('page'), 'home /');
      expect(m.router.canPop(), isFalse);
    });

    test('replace swaps the top page and keeps what is under it', () async {
      final m = _Mounted(router());
      final result = m.router.push<String>('/form');

      m.router.replace('/other');
      expect(m.text('page'), 'other /other');

      // Still the pushed page, as far as whoever pushed it can tell.
      m.router.pop('done');
      expect(await result, 'done');
      expect(m.text('page'), 'home /');
    });

    test('the page under a pushed one keeps its State', () async {
      final life = _Lifecycle();
      final m = _Mounted(
        GoRouter(
          routes: [
            GoRoute(path: '/', builder: (_, _) => _Counted(life)),
            GoRoute(path: '/form', builder: _page('form')),
          ],
        ),
      );
      await m.tap('count_tap');

      m.router.push('/form');
      expect(m.text('count'), isNull, reason: 'covered');
      expect(life.disposed, 0);

      m.router.pop();
      expect(m.text('count'), '1');
      expect(life.created, 1);
    });

    test('so does the parent page under a nested one', () async {
      final life = _Lifecycle();
      final m = _Mounted(
        GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => _Counted(life),
              routes: [GoRoute(path: 'detail', builder: _page('detail'))],
            ),
          ],
        ),
      );
      await m.tap('count_tap');

      m.router.go('/detail');
      expect(m.text('page'), 'detail /detail');
      m.router.pop();

      expect(m.text('count'), '1');
      expect(life.created, 1);
    });

    test('a page pushed within a shell appears in the frame already there; '
        'one from outside covers it', () async {
      final shell = _Lifecycle();
      final m = _Mounted(
        GoRouter(
          routes: [
            GoRoute(path: '/login', builder: _page('login')),
            ShellRoute(
              builder: (_, _, child) =>
                  _Counted(shell, id: 'shell', child: child),
              routes: [
                GoRoute(path: '/', builder: _page('home')),
                GoRoute(path: '/guests', builder: _page('guests')),
              ],
            ),
          ],
        ),
      );
      await m.tap('shell_tap');

      m.router.push('/guests');
      expect(m.text('page'), 'guests /guests');
      expect(m.text('shell'), '1');
      expect(shell.created, 1);

      m.router.push('/login');
      expect(m.text('page'), 'login /login');
      expect(m.text('shell'), isNull);

      m.router.pop();
      m.router.pop();
      expect(m.text('page'), 'home /');
      expect(m.text('shell'), '1');
      expect(shell.created, 1);
      expect(shell.disposed, 0);
    });

    test('the context helpers reach the same stack', () async {
      String? popped;
      final m = _Mounted(
        GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, _) => ElevatedButton(
                key: const ValueKey('open'),
                onPressed: () async =>
                    popped = await context.push<String>('/form'),
                child: const Text('open'),
              ),
            ),
            GoRoute(
              path: '/form',
              builder: (context, _) => ElevatedButton(
                key: const ValueKey('close'),
                onPressed: () {
                  if (context.canPop()) context.pop('closed');
                },
                child: const Text('close'),
              ),
            ),
          ],
        ),
      );

      await m.tap('open');
      await m.tap('close');
      await pumpEventQueue();

      expect(popped, 'closed');
      expect(tree.nodeById(m.root, 'open'), isNotNull);
    });

    test('a pushed location is redirected like any other', () {
      final m = _Mounted(
        GoRouter(
          redirect: (_, state) =>
              state.matchedLocation == '/form' ? '/other' : null,
          routes: [
            GoRoute(path: '/', builder: _page('home')),
            GoRoute(path: '/form', builder: _page('form')),
            GoRoute(path: '/other', builder: _page('other')),
          ],
        ),
      );

      m.router.push('/form');

      expect(m.text('page'), 'other /other');
      expect(m.router.canPop(), isTrue);
    });

    test('a refresh that redirects takes the pushed pages with it', () async {
      final session = ValueNotifier(true);
      final m = _Mounted(
        GoRouter(
          refreshListenable: session,
          redirect: (_, state) =>
              session.value || state.matchedLocation == '/login'
              ? null
              : '/login',
          routes: [
            GoRoute(path: '/', builder: _page('home')),
            GoRoute(path: '/form', builder: _page('form')),
            GoRoute(path: '/login', builder: _page('login')),
          ],
        ),
      );
      final result = m.router.push<String>('/form');

      session.value = false;

      expect(m.text('page'), 'login /login');
      expect(m.router.canPop(), isFalse);
      expect(await result, isNull);
    });
  });

  group('the platform back gesture', () {
    GoRouter router() => GoRouter(
      routes: [
        GoRoute(path: '/', builder: _page('home')),
        GoRoute(path: '/guests', builder: _page('guests')),
        GoRoute(path: '/form', builder: _page('form')),
        GoRoute(path: '/login', builder: _page('login')),
      ],
    );

    test('pops a pushed page', () {
      final m = _Mounted(router());
      m.router.push('/form');

      expect(SystemBack.dispatch(), isTrue);

      expect(m.text('page'), 'home /');
    });

    test('is left to the platform when there is nothing to pop', () {
      final m = _Mounted(router());
      m.router.go('/guests');

      expect(SystemBack.dispatch(), isFalse);
      expect(m.text('page'), 'guests /guests');
    });

    test('is no longer handled once the router is disposed', () {
      final m = _Mounted(router());
      m.router.push('/form');

      m.router.dispose();

      expect(SystemBack.dispatch(), isFalse);
    });
  });

  group('attachHistory', () {
    late _FakeHistory history;

    _Mounted mount({GoRouterRedirect? redirect, Listenable? refresh}) {
      history = _FakeHistory();
      return _Mounted(
        GoRouter(
          redirect: redirect,
          refreshListenable: refresh,
          routes: [
            GoRoute(path: '/', builder: _page('home')),
            GoRoute(path: '/guests', builder: _page('guests')),
            GoRoute(path: '/form', builder: _page('form')),
            GoRoute(path: '/login', builder: _page('login')),
          ],
        )..attachHistory(history),
      );
    }

    test('writes where the app starts into the current entry', () {
      mount();
      expect(history.calls, ['replace /']);
    });

    test('writes the redirected start, not the one asked for', () {
      mount(
        redirect: (_, state) =>
            state.matchedLocation == '/login' ? null : '/login',
      );
      expect(history.calls, ['replace /login']);
    });

    test('go and push each add an entry', () {
      final m = mount();
      m.router.go('/guests?filter=confirmed');
      m.router.push('/form');

      expect(history.calls.skip(1), [
        'push /guests?filter=confirmed',
        'push /form',
      ]);
    });

    test('going where the app already is adds none', () {
      final m = mount();
      m.router.go('/');
      expect(history.calls.skip(1), ['replace /']);
    });

    test('the browser\'s Forward returns to the page Back left, and writes '
        'nothing', () {
      final m = mount();
      m.router.go('/guests');
      m.router.push('/form');
      SystemBack.dispatch();
      SystemBack.dispatch();
      expect(m.text('page'), 'home /');
      history.calls.clear();

      expect(SystemBack.dispatchForward(), isTrue);
      expect(m.text('page'), 'guests /guests');
      expect(SystemBack.dispatchForward(), isTrue);
      expect(m.text('page'), 'form /form');

      expect(SystemBack.dispatchForward(), isFalse, reason: 'nothing ahead');
      expect(history.calls, isEmpty);
    });

    test('Forward has nowhere to go once the app has gone somewhere else',
        () {
      final m = mount();
      m.router.go('/guests');
      SystemBack.dispatch();
      m.router.go('/form');

      expect(SystemBack.dispatchForward(), isFalse);
      expect(m.text('page'), 'form /form');
    });

    test('the browser\'s Back returns to the entry before, and writes '
        'nothing back', () {
      final m = mount();
      m.router.go('/guests');
      m.router.push('/form');
      history.calls.clear();

      // The browser has already moved by the time it reports Back.
      expect(SystemBack.dispatch(), isTrue);
      expect(m.text('page'), 'guests /guests');
      expect(m.router.canPop(), isFalse);

      expect(SystemBack.dispatch(), isTrue);
      expect(m.text('page'), 'home /');

      expect(history.calls, isEmpty);
      expect(SystemBack.dispatch(), isFalse, reason: 'nothing before this');
    });

    test('Back answers a push that was awaiting a result', () async {
      final m = mount();
      final result = m.router.push<String>('/form');

      SystemBack.dispatch();

      expect(await result, isNull);
    });

    test('an in-app pop steps the browser back, and ignores the pop it '
        'reports', () {
      final m = mount();
      m.router.push('/form');
      history.calls.clear();

      m.router.pop();
      expect(history.calls, ['back']);

      // The popstate the browser raises for that back().
      expect(SystemBack.dispatch(), isTrue);
      expect(m.text('page'), 'home /');
    });

    test('a redirect on Back rewrites the entry it landed on', () {
      var signedIn = true;
      final m = mount(
        redirect: (_, state) =>
            signedIn || state.matchedLocation == '/login' ? null : '/login',
      );
      m.router.go('/guests');
      m.router.go('/form');
      history.calls.clear();
      signedIn = false;

      SystemBack.dispatch();

      expect(m.text('page'), 'login /login');
      expect(history.calls, ['replace /login']);
    });

    test('a redirect on refresh rewrites the current entry', () {
      final session = ValueNotifier(true);
      final m = mount(
        refresh: session,
        redirect: (_, state) =>
            session.value || state.matchedLocation == '/login'
            ? null
            : '/login',
      );
      m.router.go('/guests');
      history.calls.clear();

      session.value = false;

      expect(history.calls, ['replace /login']);
    });

    test('Back consumed by something else puts the entry back', () {
      final m = mount();
      m.router.go('/guests');
      history.calls.clear();
      // A dialog, registered after the router, takes the gesture.
      SystemBack.addHandler(() => true);

      SystemBack.dispatch();

      expect(m.text('page'), 'guests /guests');
      expect(history.calls, ['push /guests']);
    });

    test('attached after the app is running, it starts from where the app '
        'is', () {
      history = _FakeHistory();
      final m = _Mounted(
        GoRouter(
          routes: [
            GoRoute(path: '/', builder: _page('home')),
            GoRoute(path: '/guests', builder: _page('guests')),
          ],
        ),
      );
      m.router.go('/guests');

      m.router.attachHistory(history);

      expect(history.calls, ['replace /guests']);
      expect(SystemBack.handlerCount, 1, reason: 'rebound, not bound twice');
    });
  });

  group('dispose', () {
    test('stops following refreshListenable', () {
      final session = ValueNotifier(0);
      var asked = 0;
      final m = _Mounted(
        GoRouter(
          refreshListenable: session,
          redirect: (_, _) {
            asked++;
            return null;
          },
          routes: [GoRoute(path: '/', builder: _page('home'))],
        ),
      );
      asked = 0;

      m.router.dispose();
      session.value++;

      expect(asked, 0);
      expect(session.hasListeners, isFalse);
    });

    test('answers pushes still waiting', () async {
      final m = _Mounted(
        GoRouter(
          routes: [
            GoRoute(path: '/', builder: _page('home')),
            GoRoute(path: '/form', builder: _page('form')),
          ],
        ),
      );
      final result = m.router.push<String>('/form');

      m.router.dispose();

      expect(await result, isNull);
    });
  });
}

class _ReadsState extends StatelessWidget {
  const _ReadsState();

  @override
  Widget build(BuildContext context) {
    final state = GoRouterState.of(context);
    return Text(
      '${state.uri} ${state.pathParameters['id']} ${state.fullPath}',
      key: const ValueKey('state'),
    );
  }
}

class _Capture extends StatelessWidget {
  const _Capture(this.onBuild);
  final void Function(BuildContext context) onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild(context);
    return const SizedBox();
  }
}
