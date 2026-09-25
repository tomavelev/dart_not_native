import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';

typedef NativeMethodC =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Char> methodName,
      ffi.Pointer<ffi.Char> args,
    );
typedef NativeMethodDart =
    int Function(ffi.Pointer<ffi.Char> methodName, ffi.Pointer<ffi.Char> args);

late final ffi.DynamicLibrary _lib;
late final NativeMethodDart _callNative;

void initializeMobile(String libraryName) {
  _lib = Platform.isAndroid
      ? ffi.DynamicLibrary.open(libraryName)
      : ffi.DynamicLibrary.process();

  _callNative = _lib
      .lookup<ffi.NativeFunction<NativeMethodC>>('call_native')
      .asFunction();
}

void initializeWeb() {
  // No-op for mobile
}

int callNativeMethod(String methodName, String args) {
  final methodNamePtr = methodName.toNativeUtf8();
  final argsPtr = args.toNativeUtf8();
  try {
    return _callNative(methodNamePtr.cast(), argsPtr.cast());
  } finally {
    malloc.free(methodNamePtr);
    malloc.free(argsPtr);
  }
}
