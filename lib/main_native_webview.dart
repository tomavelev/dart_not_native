/// Runs a web view through the platform's OWN browser view, to check the
/// `WebView` node on a device.
///
///   flutter run -t lib/main_native_webview.dart -d `<device>`
///
/// The Flutter-hosted target draws a placeholder here instead; that is the
/// documented limit of that target, not a failure of this screen.
library;

import 'package:dart_not_native/widgets.dart';

class WebViewDemo extends StatelessWidget {
  const WebViewDemo({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const AppBar(title: Text('Web view')),
    body: Column(
      children: const [
        Text('Below is a real page in the platform browser view.'),
        WebView(url: 'https://example.com/', height: 420),
        Text('And this sits under it.'),
      ],
    ),
  );
}

void main() => runApp(const WebViewDemo(), title: 'Native WebView');
