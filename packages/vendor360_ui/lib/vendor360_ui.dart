/// Vendor360 design system.
///
/// Tokens, theme, motion and components for the Vendor360 vendor app.
///
/// Forked from the CarryO design system, which established the structure this
/// package keeps: semantic colour tokens with a single file permitted to hold
/// literals, Inter with tabular figures on every style, a 4pt spacing scale,
/// motion resolved through `MotionScope` against the platform's reduce-motion
/// setting, and a soft shadow in light mode against a hairline border in dark.
/// The palette is Vendor360's own (teal and saffron, per the UI/UX guide);
/// everything else is inherited deliberately.
///
/// This package must never depend on app models, Riverpod or networking — the
/// package boundary is what keeps the design system reusable and testable in
/// isolation.
library;

export 'src/tokens/v360_colors.dart';
export 'src/tokens/v360_elevation.dart';
export 'src/tokens/v360_motion.dart';
export 'src/tokens/v360_spacing.dart';
export 'src/tokens/v360_typography.dart';
export 'src/tokens/v360_theme.dart';

export 'src/motion/motion_scope.dart';
export 'src/motion/v360_transitions.dart';
export 'src/motion/v360_reveal.dart';

export 'src/components/buttons/v360_button.dart';
export 'src/components/buttons/v360_icon_button.dart';
export 'src/components/surfaces/v360_card.dart';
export 'src/components/surfaces/v360_stack_card.dart';
export 'src/components/surfaces/v360_phone_frame.dart';
export 'src/components/surfaces/section_label.dart';
export 'src/components/controls/v360_segmented.dart';
export 'src/components/controls/v360_pressable.dart';
export 'src/components/data/capacity_bar.dart';
export 'src/components/data/rolling_number.dart';
export 'src/components/data/otp_boxes.dart';
export 'src/components/feedback/v360_banner.dart';
export 'src/components/feedback/v360_skeleton.dart';
export 'src/components/feedback/sync_badge.dart';
export 'src/components/nav/v360_bottom_nav.dart';

// Vendor360-specific components, built on the same tokens.
export 'src/components/vendor/voice_orb.dart';
export 'src/components/vendor/health_dial.dart';
export 'src/components/vendor/stat_tile.dart';
export 'src/components/vendor/forecast_spark.dart';
export 'src/components/vendor/expiry_chip.dart';
export 'src/components/vendor/confidence_row.dart';
export 'src/components/vendor/driver_badge.dart';
export 'src/components/vendor/demand_heatmap.dart';
