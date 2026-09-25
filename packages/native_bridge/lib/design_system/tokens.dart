/// Design System Tokens
///
/// Core design tokens for typography, colors, spacing, and other design properties.
/// These tokens form the foundation of the entire design system.

// ============================================================================
// SPACING TOKENS (8px base scale)
// ============================================================================

const double SPACING_XS = 4.0; // xs: minimal spacing
const double SPACING_SM = 8.0; // sm: small spacing
const double SPACING_MD = 16.0; // md: standard spacing
const double SPACING_LG = 24.0; // lg: large spacing
const double SPACING_XL = 32.0; // xl: extra large
const double SPACING_XXL = 48.0; // xxl: extra extra large
const double SPACING_XXXL = 64.0; // xxxl: massive

// ============================================================================
// TYPOGRAPHY - FONT SIZES
// ============================================================================

const double FONT_SIZE_H1 = 32.0; // Heading 1 - page titles
const double FONT_SIZE_H2 = 28.0; // Heading 2 - section titles
const double FONT_SIZE_H3 = 24.0; // Heading 3 - subsections
const double FONT_SIZE_H4 = 20.0; // Heading 4
const double FONT_SIZE_H5 = 16.0; // Heading 5
const double FONT_SIZE_H6 = 14.0; // Heading 6
const double FONT_SIZE_BODY_LG = 18.0; // Large body text
const double FONT_SIZE_BODY_MD = 16.0; // Default body text
const double FONT_SIZE_BODY_SM = 14.0; // Secondary body text
const double FONT_SIZE_CAPTION = 12.0; // Small captions, labels
const double FONT_SIZE_LABEL = 13.0; // Form labels

// ============================================================================
// TYPOGRAPHY - FONT WEIGHTS
// ============================================================================

const int FONT_WEIGHT_LIGHT = 300;
const int FONT_WEIGHT_REGULAR = 400;
const int FONT_WEIGHT_MEDIUM = 500;
const int FONT_WEIGHT_SEMIBOLD = 600;
const int FONT_WEIGHT_BOLD = 700;

// ============================================================================
// TYPOGRAPHY - LINE HEIGHT
// ============================================================================

const double LINE_HEIGHT_TIGHT = 1.2; // For headings
const double LINE_HEIGHT_NORMAL = 1.5; // For body text
const double LINE_HEIGHT_RELAXED = 1.8; // For long-form content

// ============================================================================
// TYPOGRAPHY - LETTER SPACING
// ============================================================================

const double LETTER_SPACING_TIGHT = -0.5;
const double LETTER_SPACING_NORMAL = 0.0;
const double LETTER_SPACING_WIDE = 0.5;

// ============================================================================
// COLORS - SEMANTIC
// ============================================================================

const String COLOR_PRIMARY = '#1976d2'; // Blue - main brand color
const String COLOR_SECONDARY = '#f57c00'; // Orange - secondary actions
const String COLOR_SUCCESS = '#388e3c'; // Green - success states
const String COLOR_ERROR = '#d32f2f'; // Red - errors, dangers
const String COLOR_WARNING = '#fbc02d'; // Yellow - warnings
const String COLOR_INFO = '#0288d1'; // Light blue - informational

// ============================================================================
// COLORS - NEUTRAL / GRAYSCALE
// ============================================================================

const String COLOR_WHITE = '#ffffff'; // Backgrounds
const String COLOR_GRAY_50 = '#fafafa'; // Very light backgrounds
const String COLOR_GRAY_100 = '#f5f5f5'; // Light backgrounds
const String COLOR_GRAY_200 = '#eeeeee'; // Borders, dividers
const String COLOR_GRAY_300 = '#e0e0e0'; // Subtle borders
const String COLOR_GRAY_400 = '#bdbdbd'; // Secondary text
const String COLOR_GRAY_500 = '#9e9e9e'; // Disabled text
const String COLOR_GRAY_600 = '#757575'; // Secondary text
const String COLOR_GRAY_700 = '#616161'; // Body text
const String COLOR_GRAY_800 = '#424242'; // Strong text
const String COLOR_GRAY_900 = '#212121'; // Very dark text
const String COLOR_BLACK = '#000000'; // Pure black

// ============================================================================
// COLORS - TEXT
// ============================================================================

const String COLOR_TEXT_PRIMARY = '#212121'; // Main text
const String COLOR_TEXT_SECONDARY = '#757575'; // Secondary text
const String COLOR_TEXT_DISABLED = '#bdbdbd'; // Disabled text
const String COLOR_TEXT_HINT = '#9e9e9e'; // Hint/placeholder

// ============================================================================
// COLORS - DARK MODE
// ============================================================================

const String COLOR_DARK_BG = '#121212';
const String COLOR_DARK_SURFACE = '#1e1e1e';
const String COLOR_DARK_TEXT = '#ffffff';
const String COLOR_DARK_SECONDARY = '#b0bec5';

// ============================================================================
// BORDER RADIUS
// ============================================================================

const double BORDER_RADIUS_NONE = 0.0;
const double BORDER_RADIUS_SM = 4.0;
const double BORDER_RADIUS_MD = 8.0;
const double BORDER_RADIUS_LG = 16.0;
const double BORDER_RADIUS_FULL = 9999.0; // Fully rounded (pills)

// ============================================================================
// SHADOW ELEVATION
// ============================================================================

const double ELEVATION_NONE = 0.0;
const double ELEVATION_SM = 2.0;
const double ELEVATION_MD = 4.0;
const double ELEVATION_LG = 8.0;
const double ELEVATION_XL = 16.0;
const double ELEVATION_XXL = 24.0;

// ============================================================================
// BUTTON SIZES
// ============================================================================

const double BUTTON_HEIGHT_SM = 32.0; // Small button
const double BUTTON_HEIGHT_MD = 40.0; // Medium/default button
const double BUTTON_HEIGHT_LG = 48.0; // Large/prominent button

const double BUTTON_PADDING_H_SM = 12.0; // Horizontal padding small
const double BUTTON_PADDING_H_MD = 16.0; // Horizontal padding medium
const double BUTTON_PADDING_H_LG = 20.0; // Horizontal padding large

// ============================================================================
// INPUT SIZES
// ============================================================================

const double INPUT_HEIGHT_SM = 32.0;
const double INPUT_HEIGHT_MD = 40.0;
const double INPUT_HEIGHT_LG = 48.0;

// ============================================================================
// BREAKPOINTS (For responsive design)
// ============================================================================

const double BREAKPOINT_SM = 480.0; // Small devices
const double BREAKPOINT_MD = 768.0; // Medium devices (tablets)
const double BREAKPOINT_LG = 1024.0; // Large devices (desktops)
const double BREAKPOINT_XL = 1280.0; // Extra large devices

// ============================================================================
// ANIMATION & TRANSITION
// ============================================================================

const Duration ANIMATION_FAST = Duration(milliseconds: 150);
const Duration ANIMATION_NORMAL = Duration(milliseconds: 300);
const Duration ANIMATION_SLOW = Duration(milliseconds: 500);

// ============================================================================
// OPACITY / ALPHA
// ============================================================================

const double OPACITY_DISABLED = 0.38; // Disabled state
const double OPACITY_HOVER = 0.08; // Hover state
const double OPACITY_FOCUS = 0.12; // Focus state
const double OPACITY_ACTIVE = 0.12; // Active state
const double OPACITY_PLACEHOLDER = 0.6; // Placeholder text

// ============================================================================
// Typography Styles (as text descriptions for reference)
// ============================================================================

class TypographyTokens {
  // Headings
  static const String h1 = 'h1: 32px, bold (700), line-height 1.2';
  static const String h2 = 'h2: 28px, semibold (600), line-height 1.2';
  static const String h3 = 'h3: 24px, semibold (600), line-height 1.2';
  static const String h4 = 'h4: 20px, semibold (600), line-height 1.3';
  static const String h5 = 'h5: 16px, semibold (600), line-height 1.4';
  static const String h6 = 'h6: 14px, semibold (600), line-height 1.4';

  // Body
  static const String bodyLarge =
      'body-lg: 18px, regular (400), line-height 1.5';
  static const String bodyMedium =
      'body-md: 16px, regular (400), line-height 1.5';
  static const String bodySmall =
      'body-sm: 14px, regular (400), line-height 1.5';

  // Special
  static const String caption = 'caption: 12px, regular (400), line-height 1.4';
  static const String label = 'label: 13px, medium (500), line-height 1.4';
  static const String mono = 'mono: 14px, monospace, line-height 1.5';
}

// ============================================================================
// Color Palette (organized by purpose)
// ============================================================================

class ColorPalette {
  // Semantic colors
  static const String primary = COLOR_PRIMARY;
  static const String secondary = COLOR_SECONDARY;
  static const String success = COLOR_SUCCESS;
  static const String error = COLOR_ERROR;
  static const String warning = COLOR_WARNING;
  static const String info = COLOR_INFO;

  // Neutral/Grayscale
  static const String white = COLOR_WHITE;
  static const List<String> gray = [
    COLOR_GRAY_50,
    COLOR_GRAY_100,
    COLOR_GRAY_200,
    COLOR_GRAY_300,
    COLOR_GRAY_400,
    COLOR_GRAY_500,
    COLOR_GRAY_600,
    COLOR_GRAY_700,
    COLOR_GRAY_800,
    COLOR_GRAY_900,
  ];
  static const String black = COLOR_BLACK;

  // Text colors
  static const String textPrimary = COLOR_TEXT_PRIMARY;
  static const String textSecondary = COLOR_TEXT_SECONDARY;
  static const String textDisabled = COLOR_TEXT_DISABLED;
  static const String textHint = COLOR_TEXT_HINT;

  // Dark mode
  static const String darkBg = COLOR_DARK_BG;
  static const String darkSurface = COLOR_DARK_SURFACE;
  static const String darkText = COLOR_DARK_TEXT;
  static const String darkSecondary = COLOR_DARK_SECONDARY;
}

// ============================================================================
// Spacing Scale
// ============================================================================

class SpacingScale {
  static const double xs = SPACING_XS; // 4px
  static const double sm = SPACING_SM; // 8px
  static const double md = SPACING_MD; // 16px
  static const double lg = SPACING_LG; // 24px
  static const double xl = SPACING_XL; // 32px
  static const double xxl = SPACING_XXL; // 48px
  static const double xxxl = SPACING_XXXL; // 64px

  static const List<double> all = [xs, sm, md, lg, xl, xxl, xxxl];
  static const Map<String, double> named = {
    'xs': xs,
    'sm': sm,
    'md': md,
    'lg': lg,
    'xl': xl,
    'xxl': xxl,
    'xxxl': xxxl,
  };
}

// ============================================================================
// Font Sizes
// ============================================================================

class FontSizeScale {
  static const double h1 = FONT_SIZE_H1;
  static const double h2 = FONT_SIZE_H2;
  static const double h3 = FONT_SIZE_H3;
  static const double h4 = FONT_SIZE_H4;
  static const double h5 = FONT_SIZE_H5;
  static const double h6 = FONT_SIZE_H6;
  static const double bodyLg = FONT_SIZE_BODY_LG;
  static const double bodyMd = FONT_SIZE_BODY_MD;
  static const double bodySm = FONT_SIZE_BODY_SM;
  static const double caption = FONT_SIZE_CAPTION;
  static const double label = FONT_SIZE_LABEL;
}

// ============================================================================
// Font Weights
// ============================================================================

class FontWeightScale {
  static const int light = FONT_WEIGHT_LIGHT;
  static const int regular = FONT_WEIGHT_REGULAR;
  static const int medium = FONT_WEIGHT_MEDIUM;
  static const int semibold = FONT_WEIGHT_SEMIBOLD;
  static const int bold = FONT_WEIGHT_BOLD;
}
