/// What a render reported going wrong.
///
/// A renderer used to answer with a string, which said everything and meant
/// nothing: a caller that wanted to know *which* node types could not be drawn
/// had to parse prose. This is that answer with its parts separated, so a host
/// can branch on the kind, list the types, and still print something readable.
library;

/// The kind of trouble a render ran into.
enum RenderErrorKind {
  /// The tree used node types this renderer has no way to draw. The rest of the
  /// screen is on display; [RenderError.nodeTypes] names what is missing, drawn
  /// as a placeholder.
  unknownNodeType,

  /// The render itself failed - an exception on the platform side, a message
  /// the renderer could not read. What is on screen is whatever survived.
  renderFailed,
}

/// One problem from one render.
class RenderError {
  const RenderError({
    required this.kind,
    required this.message,
    this.nodeTypes = const {},
    this.cause,
    this.stackTrace,
  });

  /// The tree asked for types this renderer cannot draw.
  factory RenderError.unknownNodeTypes(Set<String> types) => RenderError(
        kind: RenderErrorKind.unknownNodeType,
        message: 'Unknown node type(s): ${(types.toList()..sort()).join(', ')}',
        nodeTypes: types,
      );

  /// The render failed outright.
  factory RenderError.failed(
    String message, {
    Object? cause,
    StackTrace? stackTrace,
  }) =>
      RenderError(
        kind: RenderErrorKind.renderFailed,
        message: message,
        cause: cause,
        stackTrace: stackTrace,
      );

  final RenderErrorKind kind;

  /// Readable, and the whole of what a renderer used to return.
  final String message;

  /// The node types the renderer could not draw, for
  /// [RenderErrorKind.unknownNodeType]; empty otherwise.
  final Set<String> nodeTypes;

  /// The thrown object, where a render threw rather than reported.
  final Object? cause;
  final StackTrace? stackTrace;

  /// Reads what a native renderer sent back over its channel.
  ///
  /// Accepts the structured map the renderers send now
  /// (`{error: ..., unknownTypes: [...]}`) and the bare string they used to,
  /// so a native half built before this still reports something useful rather
  /// than nothing.
  static RenderError? fromChannel(Object? result) {
    if (result == null) return null;
    if (result is Map) {
      final types = (result['unknownTypes'] as List?)
              ?.map((type) => type.toString())
              .toSet() ??
          const <String>{};
      if (types.isNotEmpty) return RenderError.unknownNodeTypes(types);
      final error = result['error']?.toString();
      if (error == null || error.isEmpty) return null;
      return RenderError.failed(error);
    }
    final message = result.toString();
    if (message.isEmpty) return null;
    // The shape the native halves used to return, kept readable rather than
    // demoted to a generic failure.
    const prefix = 'Unknown node type(s): ';
    if (message.startsWith(prefix)) {
      final types = message
          .substring(prefix.length)
          .split(',')
          .map((type) => type.trim())
          .where((type) => type.isNotEmpty)
          .toSet();
      if (types.isNotEmpty) return RenderError.unknownNodeTypes(types);
    }
    return RenderError.failed(message);
  }

  @override
  String toString() => message;
}
