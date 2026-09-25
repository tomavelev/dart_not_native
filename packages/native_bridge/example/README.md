# dart_not_native example

One screen, three targets, no per-platform code.

```bash
flutter pub get

flutter run            # Flutter paints the tree
```

To render with Android Views or iOS UIViews instead, change `main()` to
`runNativeApp(CounterApp(), nativeViews: true)`.

For the web build - real DOM, no Flutter engine:

```bash
dart compile js -O2 -o web/main.dart.js lib/main.dart
cp -r ../web_shell/. web/
```
