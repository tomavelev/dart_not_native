/// Controls gallery - one of each thing a finger, a screen reader or a device
/// test has to be able to find, written as a plain Flutter app.
///
/// The other examples were written before the widget layer had boxes, layers,
/// dropdowns, tabs and a bottom bar, so nothing drove those on a device. This
/// is the screen the `e2e/agent-device` flows walk: every control has a `Key`
/// (which a renderer exposes as the element's id) and prints what it heard
/// into a line of text a flow can read back.
library;

import 'package:dart_not_native/widgets.dart';

class ControlsGalleryApp extends StatefulWidget {
  const ControlsGalleryApp({super.key});

  @override
  State<ControlsGalleryApp> createState() => _ControlsGalleryAppState();
}

class _ControlsGalleryAppState extends State<ControlsGalleryApp> {
  static const _fruits = ['Apple', 'Banana', 'Cherry'];
  static const _sections = ['One', 'Two', 'Three'];

  int _page = 0;

  // Touch
  int _taps = 0;
  int _holds = 0;
  int _cards = 0;
  bool _starred = false;
  int _ignored = 0;

  // Choose
  String _fruit = _fruits.first;
  int _section = 0;
  double _volume = 30;
  bool _terms = false;
  bool _alerts = false;
  String _plan = 'free';

  // Feedback
  final _email = TextEditingController();
  String? _emailError;
  String _status = 'Nothing yet';
  int _info = 0;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Controls Gallery'),
        actions: [
          IconButton(
            key: const ValueKey('info'),
            tooltip: 'About this screen',
            icon: const Icon(Icons.info_outline),
            onPressed: () => setState(() => _info++),
          ),
        ],
      ),
      body: switch (_page) {
        0 => _touch(),
        1 => _choose(),
        _ => _feedback(context),
      },
      bottomNavigationBar: BottomNavigationBar(
        key: const ValueKey('pages'),
        currentIndex: _page,
        onTap: (index) => setState(() => _page = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.touch_app), label: 'Touch'),
          BottomNavigationBarItem(icon: Icon(Icons.tune), label: 'Choose'),
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Feedback'),
        ],
      ),
    );
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
    ),
  );

  Widget _tile(String label, {Color color = const Color(0xFFE3F2FD)}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label),
      );

  // -- Touch: boxes, layers, a scroller ---------------------------------------

  Widget _touch() => SingleChildScrollView(
    key: const ValueKey('touch_scroll'),
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('About opened: $_info', key: const ValueKey('info_count')),
        _heading('Boxes that take a touch'),
        InkWell(
          key: const ValueKey('tap_box'),
          onTap: () => setState(() => _taps++),
          child: _tile('Tap me'),
        ),
        Text('Taps: $_taps', key: const ValueKey('tap_count')),
        const SizedBox(height: 8),
        GestureDetector(
          key: const ValueKey('hold_box'),
          onLongPress: () => setState(() => _holds++),
          child: _tile('Hold me'),
        ),
        Text('Holds: $_holds', key: const ValueKey('hold_count')),
        const SizedBox(height: 8),
        // A tappable card with a button of its own inside it.
        InkWell(
          key: const ValueKey('card'),
          onTap: () => setState(() => _cards++),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Expanded(child: Text('Open the card')),
                  IconButton(
                    key: const ValueKey('star'),
                    tooltip: _starred ? 'Remove star' : 'Add star',
                    icon: Icon(_starred ? Icons.star : Icons.star_border),
                    onPressed: () => setState(() => _starred = !_starred),
                  ),
                ],
              ),
            ),
          ),
        ),
        Text(
          'Card opened: $_cards, starred: ${_starred ? 'yes' : 'no'}',
          key: const ValueKey('card_count'),
        ),
        const SizedBox(height: 8),
        IgnorePointer(
          child: InkWell(
            key: const ValueKey('ignored_box'),
            onTap: () => setState(() => _ignored++),
            child: _tile('Cannot be tapped', color: const Color(0xFFEEEEEE)),
          ),
        ),
        Text('Ignored taps: $_ignored', key: const ValueKey('ignored_count')),
        _heading('Layers'),
        SizedBox(
          height: 96,
          child: Stack(
            key: const ValueKey('layers'),
            children: [
              Container(color: const Color(0xFFFFF3E0)),
              const Positioned(left: 12, top: 12, child: Text('Underneath')),
              Positioned(
                right: 12,
                bottom: 12,
                child: Container(
                  key: const ValueKey('on_top'),
                  padding: const EdgeInsets.all(6),
                  color: const Color(0xFFFB8C00),
                  child: const Text('On top'),
                ),
              ),
            ],
          ),
        ),
        _heading('Things with a name but no text'),
        Row(
          children: [
            const Icon(Icons.warning, semanticLabel: 'Warning'),
            const SizedBox(width: 12),
            // Decoration: nobody named it, so a screen reader skips it.
            const Icon(Icons.circle),
            const SizedBox(width: 12),
            Semantics(
              key: const ValueKey('weather'),
              label: 'Sunny, 24 degrees',
              child: const Icon(Icons.wb_sunny),
            ),
            const SizedBox(width: 12),
            Semantics(
              key: const ValueKey('chart'),
              label: 'Bar chart: three bars',
              image: true,
              child: CustomPaint(
                size: const Size(72, 40),
                painter: _Bars(),
              ),
            ),
          ],
        ),
        _heading('A long way down'),
        for (var row = 1; row <= 12; row++)
          ListTile(key: ValueKey('row_$row'), title: Text('Row $row')),
        const Text('The end of the page', key: ValueKey('page_end')),
      ],
    ),
  );

  // -- Choose: dropdown, tabs, slider, checkbox, switch, radio ----------------

  Widget _choose() => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('One of a list'),
        DropdownButton<String>(
          key: const ValueKey('fruit'),
          value: _fruit,
          items: [
            for (final fruit in _fruits)
              DropdownMenuItem(value: fruit, child: Text(fruit)),
          ],
          onChanged: (value) => setState(() => _fruit = value ?? _fruit),
        ),
        Text('Fruit: $_fruit', key: const ValueKey('fruit_value')),
        _heading('Tabs'),
        Tabs(
          key: const ValueKey('sections'),
          tabs: _sections,
          selectedIndex: _section,
          onChanged: (index) => setState(() => _section = index),
        ),
        Text(
          'Section: ${_sections[_section]}',
          key: const ValueKey('section_value'),
        ),
        _heading('A value in a range'),
        Slider(
          key: const ValueKey('volume'),
          value: _volume,
          max: 100,
          divisions: 10,
          onChanged: (value) => setState(() => _volume = value),
        ),
        Text(
          'Volume: ${_volume.round()}',
          key: const ValueKey('volume_value'),
        ),
        _heading('On or off'),
        CheckboxListTile(
          key: const ValueKey('terms'),
          title: const Text('Accept the terms'),
          value: _terms,
          onChanged: (value) => setState(() => _terms = value ?? false),
        ),
        SwitchListTile(
          key: const ValueKey('alerts'),
          title: const Text('Send me alerts'),
          value: _alerts,
          onChanged: (value) => setState(() => _alerts = value),
        ),
        RadioListTile<String>(
          key: const ValueKey('plan_free'),
          title: const Text('Free plan'),
          value: 'free',
          groupValue: _plan,
          onChanged: (value) => setState(() => _plan = value ?? _plan),
        ),
        RadioListTile<String>(
          key: const ValueKey('plan_pro'),
          title: const Text('Pro plan'),
          value: 'pro',
          groupValue: _plan,
          onChanged: (value) => setState(() => _plan = value ?? _plan),
        ),
        Text(
          'Terms: ${_terms ? 'accepted' : 'not accepted'}, '
          'alerts: ${_alerts ? 'on' : 'off'}, plan: $_plan',
          key: const ValueKey('choices'),
        ),
      ],
    ),
  );

  // -- Feedback: a field with an error, a dialog, a snackbar, progress --------

  Widget _feedback(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('A field that can be wrong'),
        TextField(
          key: const ValueKey('email'),
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: 'Email',
            hintText: 'you@example.com',
            errorText: _emailError,
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          key: const ValueKey('check_email'),
          onPressed: () => setState(() {
            final ok = _email.text.contains('@');
            _emailError = ok ? null : 'Enter a valid email';
            _status = ok ? 'Email accepted' : 'Email rejected';
          }),
          child: const Text('Check email'),
        ),
        _heading('Asking and telling'),
        ElevatedButton(
          key: const ValueKey('open_dialog'),
          onPressed: () => _confirm(context),
          child: const Text('Delete something'),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          key: const ValueKey('show_snackbar'),
          onPressed: () {
            setState(() => _status = 'Saved');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Draft saved'),
                action: SnackBarAction(
                  label: 'Undo',
                  onPressed: () => setState(() => _status = 'Save undone'),
                ),
              ),
            );
          },
          child: const Text('Save a draft'),
        ),
        const SizedBox(height: 8),
        const ElevatedButton(
          key: ValueKey('disabled'),
          onPressed: null,
          child: Text('Not available'),
        ),
        const SizedBox(height: 8),
        Text('Status: $_status', key: const ValueKey('status')),
        _heading('Waiting'),
        const LinearProgressIndicator(key: ValueKey('progress'), value: 0.4),
        const SizedBox(height: 12),
        const CircularProgressIndicator(key: ValueKey('spinner')),
      ],
    ),
  );

  Future<void> _confirm(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this item?'),
        content: const Text('It cannot be brought back.'),
        actions: [
          TextButton(
            key: const ValueKey('dialog_cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const ValueKey('dialog_delete'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _status = confirmed == true ? 'Deleted' : 'Kept');
  }
}

class _Bars extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF1976D2);
    for (var bar = 0; bar < 3; bar++) {
      final height = size.height * (bar + 1) / 3;
      canvas.drawRect(
        Rect.fromLTWH(bar * 26.0, size.height - height, 20, height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
