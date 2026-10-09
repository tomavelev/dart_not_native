# dart_not_native example

One screen, three targets, no per-platform code.

```bash
flutter pub get

flutter run            # Flutter paints the tree
```

To render with Android Views or iOS UIViews instead, change `main()` to
`runNativeApp(CounterApp(), nativeViews: true)`.

A release build needs `--no-tree-shake-icons`
(`flutter build apk --release --no-tree-shake-icons`): icons are made from
codepoints at run time, which Flutter's icon tree shaker refuses.

This example is written against the protocol (`NativeUIApp`, `UIBuilder`). An
app is more usually written against the Flutter-shaped layer in
`package:dart_not_native/widgets.dart` - see the package README.

For the web build - real DOM, no Flutter engine:

```bash
dart compile js -O2 -o web/main.dart.js lib/main.dart
cp -r ../web_shell/. web/
```
