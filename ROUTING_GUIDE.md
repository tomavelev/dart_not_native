# Routing Guide

Navigation in dart_not_native is a plain-Flutter `MaterialApp` with named routes,
imported from `package:dart_not_native/widgets.dart`. The route table, the
history stack and the platform back gesture come with it — and, as everywhere in
the facade, the only difference from a real Flutter app is that import.

The working example is `lib/examples/apps/routing_example_app.dart`.

## A single screen vs. a routed app

For one screen, pass `home`:

```dart
runApp(MaterialApp(home: const HomeScreen()));
```

For several, pass `initialRoute` and a `routes` map. Each entry maps a path to a
builder that returns the screen:

```dart
MaterialApp(
  initialRoute: '/',
  routes: {
    '/':            (context, params) => const HomeScreen(),
    '/users':       (context, params) => const UsersList(),
    '/users/:id':   (context, params) => UserDetail(id: params['id']),
    '/settings':    (context, params) => const Settings(),
  },
)
```

A route builder is a `RouteWidgetBuilder`:

```dart
typedef RouteWidgetBuilder = Widget Function(
  BuildContext context,
  Map<String, dynamic> params,
);
```

## Route parameters

A segment starting with `:` is a parameter. `'/users/:id'` matched against
`/users/42` gives `params['id'] == '42'`:

```dart
'/users/:id': (context, params) {
  final id = params['id']?.toString() ?? '?';
  return UserDetail(id: id);
},
```

Parameters are strings; parse them yourself (`int.tryParse(params['id'])`).

## Moving between screens

Get the navigator from any `BuildContext` with `Navigator.of(context)`:

```dart
// Go to a route.
Navigator.of(context).pushNamed('/users/42');

// Go back (pops the current route, or closes a dialog/sheet if one is open).
Navigator.of(context).pop();

// Go back with a result.
Navigator.of(context).pop('saved');
```

`pop()` is overloaded on purpose: if a dialog or bottom sheet is open it closes
that first; otherwise it pops the route. So one back action does the right thing
whether a modal is up or not.

## The history stack

The navigator exposes the stack, for a back button or a breadcrumb:

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

## The platform back gesture

You get it for free. The Android back button and the iOS edge-swipe pop the
top route, and on the first screen they hand control back to the platform
(the app closes or backgrounds). On the web the browser Back button pops the
same stack, and an in-app `pop()` updates the URL — the history is one stack,
however the user moves through it. There is nothing to wire.

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
          '/':          (context, params) => const _Home(),
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
