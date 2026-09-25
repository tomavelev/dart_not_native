/// Web implementation of NativeBridge using in-memory state.
///
/// All state is stored in Dart globals and lives in browser memory.
/// Future plugins can implement persistence (localStorage, IndexedDB, backend sync).

// ============ Global State ============
// These would typically be managed by plugin systems for persistence

int _counterValue = 0;
int _toggleValue = 0;
int _sliderValue = 0;

// ============ Counter Methods ============

int _getCounter() => _counterValue;

int _incrementCounter() {
  _counterValue++;
  return _counterValue;
}

void _resetCounter() {
  _counterValue = 0;
}

// ============ Toggle Methods ============

int _getToggle() => _toggleValue;

int _toggleButton() {
  _toggleValue = _toggleValue == 0 ? 1 : 0;
  return _toggleValue;
}

void _resetToggle() {
  _toggleValue = 0;
}

// ============ Slider Methods ============

int _getSlider() => _sliderValue;

int _incrementSlider() {
  if (_sliderValue < 100) {
    _sliderValue += 10;
  }
  return _sliderValue;
}

void _resetSlider() {
  _sliderValue = 0;
}

// ============ Bridge Interface ============

void initializeMobile(String libraryName) {
  // No-op for web
}

void initializeWeb() {
  // Initialize web bridge - state is already in memory
  // Future: Could load persisted state from localStorage here
}

int callNativeMethod(String methodName, String args) {
  // Log bridge calls to show framework is working
  print('🌐 WEB BRIDGE: methodName=$methodName (in-memory Dart methods)');

  switch (methodName) {
    // Counter
    case 'get_counter':
      print('   → Getting counter value: $_counterValue');
      return _getCounter();
    case 'increment_counter':
      final result = _incrementCounter();
      print('   → Counter incremented to: $result');
      return result;
    case 'reset_counter':
      _resetCounter();
      print('   → Counter reset to 0');
      return 0;

    // Toggle
    case 'get_toggle':
      return _getToggle();
    case 'toggle_button':
      return _toggleButton();
    case 'reset_toggle':
      _resetToggle();
      return 0;

    // Slider
    case 'get_slider':
      return _getSlider();
    case 'increment_slider':
      return _incrementSlider();
    case 'reset_slider':
      _resetSlider();
      return 0;

    default:
      throw UnimplementedError('Method not implemented: $methodName');
  }
}
