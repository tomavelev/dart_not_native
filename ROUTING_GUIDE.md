# Routing Guide

Navigation in dart_not_native is Flutter's, imported from
`package:dart_not_native/widgets.dart`: `Navigator.push` with a
`MaterialPageRoute`, or a `MaterialApp` with named routes. An app built on
go_router has a third way, `package:dart_not_native/router.dart`, which is
go_router's API. All three share one back gesture.

The working example for named routes is
`lib/examples/apps/routing_example_app.dart`.

One thing is different from Flutter in all three, and it is worth knowing
before anything else: **pages do not transition.** A pushed page replaces what
was on screen at once - no slide, no fade, no `Hero`.

## Pushing a page

Exactly as in Flutter:

```dart
final saved = await Navigator.push<bool>(
  context,
  MaterialPageRoute(builder: (context) => const EditScreen()),
);
if (saved == true) { /* ... */ }

// in EditScreen:
Navigator.pop(context, true);
```

`push` answers with a future that completes with the value given to `pop`.
The pages beneath a pushed one keep their `State` and are exactly as they were
when it is popped. An `AppBar` on a page that can be popped gains a back
button on its own, unless `automaticallyImplyLeading` is false.

`pushReplacement`, `pushAndRemoveUntil`, `popUntil`, `maybePop` and `canPop`
are there, on `Navigator` and on `Navigator.of(context)`. `PageRouteBuilder`
is accepted and its `transitionsBuilder` is never called.

`Navigator.of(context)` works from any widget tree - `runApp` puts a navigator
at the root - so pushing a page needs no `MaterialApp`.

## Named routes

For one screen, pass `home`:

```dart
runApp(MaterialApp(home: const HomeScreen()));
```

For several, pass `initialRoute` and a `routes` map. A route builder is
Flutter's `(context) => Widget`; one that takes a second parameter is given
the path's parameters:

```dart
MaterialApp(
  initialRoute: '/',
  routes: {
    '/':            (context) => const HomeScreen(),
    '/users':       (context) => const UsersList(),
    '/users/:id':   (context, params) => UserDetail(id: params['id'] as String),
    '/settings':    (context) => const Settings(),
  },
)
```

The second form is a `RouteWidgetBuilder`:

```dart
typedef RouteWidgetBuilder = Widget Function(
  BuildContext context,
  Map<String, dynamic> params,
);
```

Because the map holds both shapes it is typed `Map<String, Function>`; a
builder of any other shape throws an `ArgumentError` when its route is built.

### Route parameters

A segment starting with `:` is a parameter. `'/users/:id'` matched against
`/users/42` gives `params['id'] == '42'`:

```dart
'/users/:id': (context, params) {
  final id = params['id']?.toString() ?? '?';
  return UserDetail(id: id);
},
```

Parameters are strings; parse them yourself (`int.tryParse('${params['id']}')`).

### Moving between named routes

```dart
// Go to a route.
Navigator.of(context).pushNamed('/users/42');

// Go back (closes a dialog or sheet if one is open, else pops).
Navigator.of(context).pop();
```

`pop()` is overloaded on purpose: if a dialog or bottom sheet is open it closes
that first; otherwise it pops a pushed page; otherwise it steps the named
router back. So one back action does the right thing whether a modal is up or
not.

### The history stack

The navigator exposes the named router's stack, for a back button or a
breadcrumb. These three are the framework's own - Flutter's `NavigatorState`
has no such members:

| Member | Returns |
| --- | --- |
| `currentPath` | the current route's path, e.g. `/users/42` |
| `history` | every path on the stack, oldest first |
| `canGoBack` | whether there is a screen to pop to |

```dart
final nav = Navigator.of(context);
if (nav.canGoBack) TextButton(onPressed: nav.pop, child: const Text('Back'));
Text('You are at ${nav.currentPath}');
```

## go_router's API

An app that routes with go_router changes one import and removes the
dependency:

```dart
import 'package:dart_not_native/router.dart';
import 'package:dart_not_native/widgets.dart';

final router = GoRouter(
  initialLocation: '/',
  redirect: (context, state) => signedIn ? null : '/login',
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
        GoRoute(
          path: '/guests/:id',
          builder: (context, state) => GuestScreen(state.pathParameters['id']!),
        ),
      ],
    ),
  ],
);

void main() => runApp(MaterialApp.router(routerConfig: router));
```

`context.go`, `context.push`, `context.pop`, `context.replace` and the named
variants, `redirect` at the router and on a route, `refreshListenable`,
`errorBuilder`, `GoRouterState` with `pathParameters`, `uri`,
`matchedLocation` and `extra`.

It is a subset and says where it stops:

- no `pageBuilder`, `Page`s or transitions;
- no `StatefulShellRoute`, no navigator keys, no `onExit`;
- a path parameter matches one whole segment - inline patterns (`:id(\d+)`)
  are not supported;
- with a browser history attached, `push` writes a history entry too (in
  go_router only `go` changes the URL by default).

## The platform back gesture

On Android and iOS you get it for free: the back button and the edge swipe
close the topmost dialog or sheet, then pop a pushed page or step the named
router back, and on the first screen hand control back to the platform (the
app closes or backgrounds). Android needs `MainActivity` to extend
`FlutterFragmentActivity` - INTEGRATION.md §5.1.

**On the web it depends on how the app routes.** `MaterialApp(routes:)` and
`Navigator.push` reach the browser's history with nothing to wire (below).
`GoRouter` is mirrored once it is handed the adapter:

```dart
// lib/main_web.dart
import 'package:dart_not_native/web.dart'
    show BrowserHistoryAdapter, bindBrowserBack;

Future<void> main() async {
  final history = BrowserHistoryAdapter();
  final router = buildRouter(initialLocation: history.currentPath ?? '/')
    ..attachHistory(history);
  await runApp(MaterialApp.router(routerConfig: router));
  bindBrowserBack();
}
```

Every `go` and `push` then becomes a history entry written to the URL
fragment (`#/guests/7`), so a reload or a deep link lands on the same screen
and the browser's Back button pops in-app navigation before leaving the page.

`MaterialApp(routes:)` is mirrored by itself. Each named route is a history
entry and a fragment in the URL (`#/settings`), the browser's Back button pops
it, and a reload or a link straight to `#/settings` opens that page over the
first one, so Back from it is the app's first screen.

A page pushed with `Navigator.push` has no name to put in the URL, so the URL
does not change - but Back pops it. While a navigator has a pushed page the
app keeps one history entry of its own behind it, which is what Back lands
on; it goes when the last page does. Where a router is already in the
history, its entries do that job.

Two things this does not do. The browser's **Forward** button does not bring
back a page that Back popped. And a dialog or sheet over
the app's *first* screen has nothing behind it, so Back there still leaves
the page. An app that wants its own history - paths instead of fragments -
sets `HistoryAdapter.platform` before `runApp`.

## A complete example

```dart
import 'package:dart_not_native/widgets.dart';

void main() => runApp(const RoutingApp());

class RoutingApp extends StatelessWidget {
  const RoutingApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        initialRoute: '/',
        routes: {
          '/':          (context) => const _Home(),
          '/users/:id': (context, params) => _User(id: params['id'] as String),
        },
      );
}

class _Home extends StatelessWidget {
  const _Home();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const AppBar(title: Text('Home')),
        body: Center(
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pushNamed('/users/42'),
            child: const Text('Open user 42'),
          ),
        ),
      );
}

class _User extends StatelessWidget {
  const _User({required this.id});
  final String id;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('User $id')),
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back'),
          ),
        ),
      );
}
```

The same tree renders through Android Views, UIKit and the DOM — see
`EXAMPLES_DIRECTORY.md` for how each example is launched.
