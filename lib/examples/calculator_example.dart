import 'package:dart_not_native/material.dart';

import 'apps/calculator_app.dart';

/// Simple Calculator - pure Flutter, no native code.
/// Demonstrates a stateful app without native backing.

void main() {
  // No NativeBridge needed for pure Dart apps
  runApp(const CalculatorApp());
}

class CalculatorApp extends StatelessWidget {
  const CalculatorApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Calculator',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const CalculatorPage(title: 'Calculator'),
    );
  }
}

class CalculatorPage extends StatefulWidget {
  const CalculatorPage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

class _CalculatorPageState extends State<CalculatorPage> {
  final _logic = CalculatorLogic();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          // Display
          Expanded(
            flex: 1,
            child: Container(
              width: double.infinity,
              color: Colors.grey[900],
              padding: const EdgeInsets.all(20),
              child: Align(
                alignment: Alignment.bottomRight,
                child: Text(
                  _logic.display,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          // Buttons
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  _buildButtonRow(['C', '←', '÷', '×']),
                  _buildButtonRow(['7', '8', '9', '-']),
                  _buildButtonRow(['4', '5', '6', '+']),
                  _buildButtonRow(['1', '2', '3', '=']),
                  _buildButtonRow(['0', '.', '=']),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButtonRow(List<String> buttons) {
    return Expanded(
      child: Row(children: buttons.map((btn) => _buildButton(btn)).toList()),
    );
  }

  Widget _buildButton(String label) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _getButtonColor(label),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: () => _handleButtonPress(label),
          child: Text(
            label,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  Color _getButtonColor(String label) {
    if (label == '=') return Colors.green;
    if (['C', '←'].contains(label)) return Colors.red;
    if (['+', '-', '×', '÷'].contains(label)) return Colors.orange;
    return Colors.grey[700]!;
  }

  void _handleButtonPress(String label) {
    setState(() => _logic.press(label));
  }
}
