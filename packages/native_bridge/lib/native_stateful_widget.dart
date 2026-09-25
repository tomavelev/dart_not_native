import 'package:flutter/material.dart';
import 'native_bridge.dart';

/// A reusable stateful widget that binds to a native method.
///
/// Usage:
/// ```dart
/// NativeStatefulWidget(
///   nativeMethodName: 'increment_counter',
///   label: 'Counter',
///   initialMethodName: 'get_counter',
///   resetMethodName: 'reset_counter',
/// )
/// ```
class NativeStatefulWidget extends StatefulWidget {
  /// Name of the native method to invoke when action is triggered.
  final String nativeMethodName;

  /// Display label for this widget.
  final String label;

  /// Native method to call on init to get initial value.
  final String initialMethodName;

  /// Native method to call when reset is triggered.
  final String resetMethodName;

  /// Optional callback when value changes.
  final ValueChanged<int>? onValueChanged;

  /// Optional custom action button label (default: 'Invoke').
  final String actionButtonLabel;

  /// Optional custom reset button label (default: 'Reset').
  final String resetButtonLabel;

  /// Whether to show the reset button.
  final bool showResetButton;

  const NativeStatefulWidget({
    Key? key,
    required this.nativeMethodName,
    required this.label,
    this.initialMethodName = 'get_value',
    this.resetMethodName = 'reset_value',
    this.onValueChanged,
    this.actionButtonLabel = 'Invoke',
    this.resetButtonLabel = 'Reset',
    this.showResetButton = true,
  }) : super(key: key);

  @override
  State<NativeStatefulWidget> createState() => _NativeStatefulWidgetState();
}

class _NativeStatefulWidgetState extends State<NativeStatefulWidget> {
  int _value = 0;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadInitialValue();
  }

  Future<void> _loadInitialValue() async {
    try {
      final result = NativeBridge.callMethod(widget.initialMethodName);
      setState(() {
        _value = result;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      debugPrint('Failed to load initial value: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load value';
      });
    }
  }

  Future<void> _invokeNativeMethod() async {
    try {
      final result = NativeBridge.callMethod(widget.nativeMethodName);
      setState(() {
        _value = result;
        _errorMessage = null;
      });
      widget.onValueChanged?.call(_value);
    } catch (e) {
      debugPrint('Failed to invoke native method: $e');
      setState(() {
        _errorMessage = 'Method failed: $e';
      });
    }
  }

  Future<void> _reset() async {
    try {
      NativeBridge.callMethod(widget.resetMethodName);
      setState(() {
        _value = 0;
        _errorMessage = null;
      });
    } catch (e) {
      debugPrint('Failed to reset: $e');
      setState(() {
        _errorMessage = 'Reset failed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(widget.label, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        if (_isLoading)
          const CircularProgressIndicator()
        else if (_errorMessage != null)
          Text(_errorMessage!, style: TextStyle(color: Colors.red))
        else
          Text('$_value', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FloatingActionButton(
              onPressed: _isLoading ? null : _invokeNativeMethod,
              tooltip: widget.actionButtonLabel,
              child: const Icon(Icons.add),
            ),
            if (widget.showResetButton) ...[
              const SizedBox(width: 16),
              FloatingActionButton(
                onPressed: _isLoading ? null : _reset,
                tooltip: widget.resetButtonLabel,
                child: const Icon(Icons.refresh),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
