# dart_not_native example

One screen, three targets, no per-platform code.

```bash
flutter pub get

flutter run            # Flutter paints the tree
```

To render with Android Views or iOS UIViews instead, change `main()` to
`runNativeApp(CounterApp(), nativeViews: true)`.

A release build needs no icon flag: every Material glyph is a constant the
tree shaker can see.

This example is written against the protocol (`NativeUIApp`, `UIBuilder`). An
app is more usually written against the Flutter-shaped layer in
`package:dart_not_native/widgets.dart` - see the package README.

For the web build - real DOM, no Flutter engine:

```bash
dart compile js -O2 -o web/main.dart.js lib/main.dart
cp -r ../web_shell/. web/
```
