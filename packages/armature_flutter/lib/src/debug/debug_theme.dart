// Design tokens (colors, sizes, strokes) for the debug overlay —
// `FeatureGraphOverlay` and its subcomponents consume these. The whole
// file is framework-internal: it lives under `src/` and isn't exported
// from `package:armature_flutter/armature_flutter.dart`, so user code
// shouldn't reach into it.

import 'package:flutter/widgets.dart' show Color, TextDecoration, TextStyle;

// --- Status colors ---
const kEnabledColor = Color(0xFF66BB6A);
const kDisabledColor = Color(0xFFEF5350);
const kPendingColor = Color(0xFFFFA726);

const kNodeBgEnabled = Color(0xFF1B3A1B);
const kNodeBgDisabled = Color(0xFF3A1B1B);
const kNodeBgPending = Color(0xFF3A3A1B);

// --- Text colors ---
const kTextWhite = Color(0xFFFFFFFF);
const kTextGrey = Color(0xFF9E9E9E);
const kTextBlue = Color(0xFF64B5F6);
const kTextPurple = Color(0xFFCE93D8);
const kTextAmber = Color(0xFFFFD54F);

// --- Edge colors ---
const kRequiredEdgeColor = Color(0xAAFFFFFF);
const kOptionalEdgeColor = Color(0x55FFFFFF);

// --- Overlay colors ---
const kOverlayBg = Color(0xEE111111);
const kPanelBg = Color(0xFF1E1E1E);
const kTabActiveBg = Color(0xFF333333);
const kTabInactiveBg = Color(0xFF1E1E1E);
const kAccentColor = Color(0xFF6200EA);
const kFabBgOpen = Color(0x6637474F);
const kFabBgClose = Color(0x66424242);

// --- Minimap ---
const kMinimapBg = Color(0xCC111111);
const kMinimapBorder = Color(0x33FFFFFF);
const kMinimapEdge = Color(0x40FFFFFF);
const kMinimapViewport = Color(0x55FFFFFF);

// --- Detail / state cards ---
const kDetailPanelBg = Color(0xBB1E1E1E);
const kStoreCardBg = Color(0xFF252525);
const kStoreCardBorder = Color(0xFF333333);

// --- Drag highlight glow ---
const kDragGlowOuter = Color(0x44FFFFFF);
const kDragGlowInner = Color(0xAAFFFFFF);

// --- Node sizes ---
const kNodeWidth = 200.0;
const kNodeBaseHeight = 40.0;
const kLineHeight = 14.0;
const kLevelGap = 200.0;
const kSiblingGap = 40.0;
const kNodeRadius = 8.0;
const kStatusDotRadius = 4.0;

// --- Arrow ---
const kArrowSize = 5.0;
const kEdgeStrokeWidth = 1.5;
const kDashLength = 6.0;
const kDashGap = 4.0;

// --- Text styles ---
const kLegendTextStyle = TextStyle(
  color: kTextGrey,
  fontSize: 9,
  decoration: TextDecoration.none,
);
