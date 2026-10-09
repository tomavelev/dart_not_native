/// The icon an app names, as a codepoint in the Material Icons font.
///
/// Flutter's own `IconData` carries a font family and package as well; the
/// renderers here all draw from one font (Flutter's `MaterialIcons-Regular`,
/// which the web shell ships too), so the codepoint and the name are all that
/// travel.
library;

class IconData {
  const IconData(this.codePoint, {this.name});
  final int codePoint;
  final String? name;
}
