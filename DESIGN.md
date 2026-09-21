---
name: Vendor360
description: A kirana shopkeeper's stock, sales and voice ledger, printed like the FMCG packets on the shelf.
colors:
  teal-band: "#0B7768"
  teal-text: "#075A4F"
  teal-wash: "#E1EFEB"
  teal-wash-strong: "#C6E3DC"
  on-band-muted: "#D9F0EA"
  bottle-green-band: "#16433C"
  ink: "#10201C"
  ink-muted: "#475853"
  ink-subtle: "#63726D"
  hairline: "#D5DEDA"
  board-white: "#FFFFFF"
  board-grey: "#EEF3F1"
  marigold-voice: "#F2A20C"
  marigold-voice-text: "#8A5300"
  marigold-voice-wash: "#FDF0D5"
  marigold-flash: "#F5B216"
  attention: "#E39A00"
  attention-text: "#7F4C00"
  attention-wash: "#FCF0D6"
  mrp-red: "#C62A1F"
  mrp-red-text: "#A3221A"
  mrp-red-wash: "#FBE9E7"
  heat-1: "#F9DE93"
  heat-2: "#F3BA45"
  heat-3: "#E88D1E"
  heat-4: "#D35A1C"
  heat-5: "#B02A1B"
typography:
  display:
    fontFamily: "Anek Latin, Anek Devanagari"
    fontSize: "56px"
    fontWeight: 700
    lineHeight: 1
    letterSpacing: "-0.5px"
    fontFeature: "\"tnum\""
    fontVariation: "\"wght\" 700, \"wdth\" 78"
  figure:
    fontFamily: "Anek Latin, Anek Devanagari"
    fontSize: "30px"
    fontWeight: 700
    lineHeight: "32px"
    fontFeature: "\"tnum\""
    fontVariation: "\"wght\" 700, \"wdth\" 82"
  title-l:
    fontFamily: "Anek Latin, Anek Devanagari"
    fontSize: "26px"
    fontWeight: 700
    lineHeight: "30px"
    fontFeature: "\"tnum\""
    fontVariation: "\"wght\" 700, \"wdth\" 88"
  title-m:
    fontFamily: "Anek Latin, Anek Devanagari"
    fontSize: "20px"
    fontWeight: 600
    lineHeight: "24px"
    fontFeature: "\"tnum\""
    fontVariation: "\"wght\" 600, \"wdth\" 94"
  title-s:
    fontFamily: "Anek Latin, Anek Devanagari"
    fontSize: "17px"
    fontWeight: 600
    lineHeight: "22px"
    fontFeature: "\"tnum\""
    fontVariation: "\"wght\" 600, \"wdth\" 100"
  body:
    fontFamily: "Anek Latin, Anek Devanagari"
    fontSize: "15px"
    fontWeight: 400
    lineHeight: "22px"
    fontFeature: "\"tnum\""
    fontVariation: "\"wght\" 430, \"wdth\" 100"
  body-strong:
    fontFamily: "Anek Latin, Anek Devanagari"
    fontSize: "15px"
    fontWeight: 600
    lineHeight: "22px"
    fontFeature: "\"tnum\""
    fontVariation: "\"wght\" 600, \"wdth\" 100"
  caption:
    fontFamily: "Anek Latin, Anek Devanagari"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: "18px"
    fontFeature: "\"tnum\""
    fontVariation: "\"wght\" 450, \"wdth\" 100"
  label:
    fontFamily: "Anek Latin, Anek Devanagari"
    fontSize: "12px"
    fontWeight: 500
    lineHeight: "16px"
    letterSpacing: "0.1px"
    fontFeature: "\"tnum\""
    fontVariation: "\"wght\" 500, \"wdth\" 100"
  code:
    fontFamily: "Anek Latin, Anek Devanagari"
    fontSize: "16px"
    fontWeight: 600
    lineHeight: "22px"
    letterSpacing: "1px"
    fontFeature: "\"tnum\""
    fontVariation: "\"wght\" 600, \"wdth\" 110"
rounded:
  sm: "4px"
  md: "6px"
  lg: "8px"
  xl: "12px"
  pill: "999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "20px"
  xxl: "24px"
  x3: "32px"
  x4: "40px"
  x5: "48px"
  gutter: "16px"
components:
  button-primary:
    backgroundColor: "{colors.teal-band}"
    textColor: "{colors.board-white}"
    typography: "{typography.body-strong}"
    rounded: "{rounded.md}"
    padding: "0 22px"
    height: "52px"
  button-primary-pressed:
    backgroundColor: "#0C6B5D"
  button-secondary:
    backgroundColor: "{colors.board-white}"
    textColor: "{colors.ink}"
    typography: "{typography.body-strong}"
    rounded: "{rounded.md}"
    padding: "0 22px"
    height: "52px"
  button-tonal:
    backgroundColor: "{colors.teal-wash}"
    textColor: "{colors.teal-text}"
    typography: "{typography.body-strong}"
    rounded: "{rounded.md}"
    padding: "0 18px"
    height: "48px"
  button-tonal-pressed:
    backgroundColor: "#C4D2CE"
  button-ghost:
    textColor: "{colors.teal-text}"
    typography: "{typography.body-strong}"
    rounded: "{rounded.md}"
    height: "48px"
  button-ghost-pressed:
    backgroundColor: "{colors.teal-wash}"
  button-danger:
    backgroundColor: "{colors.mrp-red}"
    textColor: "{colors.board-white}"
    typography: "{typography.body-strong}"
    rounded: "{rounded.md}"
    padding: "0 22px"
    height: "52px"
  button-disabled:
    backgroundColor: "{colors.board-grey}"
    textColor: "{colors.ink-subtle}"
  filter-tab:
    backgroundColor: "{colors.board-white}"
    textColor: "{colors.ink}"
    typography: "{typography.caption}"
    rounded: "{rounded.sm}"
    padding: "0 12px"
    height: "36px"
  filter-tab-active:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.board-white}"
  status-pill:
    backgroundColor: "{colors.board-white}"
    textColor: "{colors.ink}"
    typography: "{typography.caption}"
    rounded: "{rounded.sm}"
    padding: "4px 8px"
  panel:
    backgroundColor: "{colors.board-white}"
    rounded: "{rounded.lg}"
    padding: "16px"
  pack-header:
    backgroundColor: "{colors.teal-band}"
    textColor: "{colors.board-white}"
    typography: "{typography.display}"
    padding: "8px 4px 16px 16px"
  flash-band:
    backgroundColor: "{colors.marigold-flash}"
    textColor: "{colors.ink}"
    typography: "{typography.body-strong}"
    padding: "12px 8px 12px 16px"
  text-field:
    backgroundColor: "{colors.board-white}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.md}"
    padding: "14px"
  bottom-nav:
    backgroundColor: "{colors.board-white}"
    textColor: "{colors.ink-muted}"
    typography: "{typography.label}"
    height: "64px"
  mic-disc:
    backgroundColor: "{colors.marigold-voice}"
    textColor: "{colors.ink}"
    rounded: "{rounded.pill}"
    size: "58px"
  snackbar:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.board-white}"
    typography: "{typography.body}"
    rounded: "{rounded.md}"
---

# Design System: Vendor360

## Overview

**Creative North Star: "The Printed Pack"**

Vendor360 is printed, not lit. Every screen is set the way an FMCG packet on a kirana shelf is set: a few flat inks on white board, one brand colour owning the front of the pack, a dark ink for the small print, and a spot colour for the one thing that must be seen. The big figures (today's sales, a stock count, a score) are set narrow and heavy on Anek's width axis, the way a pack prints its product name and MRP, and the facts that qualify them sit in a ruled, value-first declaration strip like the MRP / Net qty / Best before box on the back panel.

The density is a shopkeeper's, not an analyst's: ruled lists instead of card grids, one teal band per screen, one marigold flash at most below it, and status printed as a small solid square beside an ink word. Colour carries meaning and nothing else. Hindi is the default language, so Latin and Devanagari are one design (Anek by Ek Type) and share one baseline.

The system refuses the SaaS vocabulary it replaced: gradient hero cards, stat-tile grids, glows, neon heatmaps, eyebrow labels, tinted pill chips, and entrance choreography.

**Key Characteristics:**
- Four inks on white board: teal band, green-black ink, marigold, MRP red; a cool board grey as the second neutral.
- One flat teal band per screen carrying the title, the actions and the screen's one figure.
- Figures narrow and heavy (width 78 to 86), running text at normal width; tabular figures everywhere.
- Rules, not shadows: hairlines between rows, hairline borders on panels, no panel elevation.
- Tight carton-dieline corners (4 to 12px); the microphone is the only round object.
- Motion carries state only: a rolling figure, bars growing to value, rings while listening, buttons darkening on press.

## Colors

A flat four-ink print on white board, with each ink holding exactly one meaning.

### Primary
- **Pack Teal** (teal-band): the brand. Owns the one flat band at the top of every screen, every AppBar, the primary button fill, the selected-tab rule in the bottom bar, focus rings, switches and chart lines. Teal is also the only ink that means *healthy / live* (in-stock squares, healthy expiry).
- **Deep Teal Text** (teal-text): teal when it must be read as text on white at 13px: tonal and ghost button labels, "See all" links, the selected nav label.
- **Teal Wash / Strong Wash** (teal-wash, teal-wash-strong): the tonal button fill, a pressed ghost button, a selected row, text selection. Never printed on the band.
- **Band Muted** (on-band-muted): secondary text on the band (locality, figure captions, strip labels), tinted from the teal rather than greyed so it holds in sunlight.
- **Bottle-Green Band** (bottle-green-band): the distributor shell's band, the same pack line printed in a second colour so a wholesaler screen can never be mistaken for a shop screen. Only the band changes; every other ink is shared.

### Secondary
- **Mic Marigold** (marigold-voice): reserved for the voice affordance: the raised mic disc in the bottom bar and the voice orb. It has its own token so a stock alert cannot borrow "the orange". Icons on it are ink (white on marigold fails contrast).
- **Flash Marigold** (marigold-flash): the "20% extra" flash, a single flat band with ink type carrying a heads-up worth acting on (a festival coming, a surge nearby). One per screen at most.
- **Marigold Text / Wash** (marigold-voice-text, marigold-voice-wash): readable marigold for voice-related text and the pale voice surface.

### Tertiary
- **Attention Amber** (attention): low stock, approaching expiry, pending sync. Used as a status square, a stock bar fill and a filter-tab marker, never as text. **Attention Text** (attention-text) carries readable amber where text must be amber; **Attention Wash** (attention-wash) is its pale surface.
- **MRP Red** (mrp-red): out of stock, expired, overdue, destructive actions, the unsynced-count badge. **MRP Red Text** (mrp-red-text) for red figures such as value at risk on an expired line; **MRP Red Wash** (mrp-red-wash) for its pale surface.
- **Heat Ramp** (heat-1 to heat-5): the demand map's five stepped classes, pale marigold to MRP red. One warm family, stepped not blended; teal is withheld from it because teal means live.

### Neutral
- **Board White** (board-white): canvas and panel surface alike. Panels separate from the page by a rule, not by a tone.
- **Board Grey** (board-grey): the second neutral layer: inset fields, steppers, disabled fills, bar tracks, skeletons. Cool, never cream.
- **Green-Black Ink** (ink): all primary text, every figure, the secondary button keyline, the active filter tab fill, snackbars and tooltips.
- **Ink Muted** (ink-muted): captions, meta lines, inactive nav labels.
- **Ink Subtle** (ink-subtle): placeholders, disabled labels, and text-field outlines (a field edge needs 3:1, which the hairline would not clear).
- **Hairline** (hairline): the rule between rows, panel borders, inactive filter-tab borders, the bottom bar's top rule.

Dark mode reprints the same roles on a near-black green board (canvas #0D1412, surface #131C1A); the teal lifts to #2DB39D for fills and text, and the band stays a deep printed teal (#0B5F54). Dark values live in the sidecar.

### Named Rules
**The One Meaning Rule.** A status ink means the same thing on every screen: teal is healthy or live, amber is low or attention, red is zero, expired, overdue or destructive. A colour is never used for decoration where it could be read as a status.

**The Marigold Reserve Rule.** Marigold belongs to the microphone, to attention, and to the one flash band. It is not a chart colour, a highlight colour, or a second brand colour.

**The Colour Lives in the Square Rule.** Status colour is printed in a small solid square (7 to 8px, 1px corner) beside a word set in ink. Tinted text on a tinted pill is what washes out first in sunlight, and the word guarantees colour is never the only signal.

**The One File Rule.** Colour literals exist only in `v360_colors.dart`; everything else reads `context.v360.colors`. Contrast is asserted in tests against WCAG ratios, not by pinning hex values.

## Typography

**Display Font:** Anek Latin (with Anek Devanagari)
**Body Font:** Anek Latin (with Anek Devanagari)

**Character:** One variable family by Ek Type that draws Latin and Devanagari as one design, bundled so it renders offline. Width does the work other systems give to a second typeface: figures and titles go narrow and heavy like pack print; running text stays at normal width where reading matters more than presence.

### Hierarchy
- **Display** (700, 56px, 56px, width 78): the one figure that owns a screen's teal band: today's sales, a stock count, a score. Scales down to fit, never wraps.
- **Figure** (700, 30px, 32px, width 82): a figure inside a panel.
- **Title L** (700, 26px, 30px, width 88): screen titles; the AppBar sets it at 22px on the band.
- **Title M** (600, 20px, 24px, width 94): section headings and the band's store name (at 700).
- **Title S** (600, 17px, 22px): row titles (an item, a shop, an order). At 700 and width 86 to 92 it becomes the declaration-strip value and the section heading.
- **Body** (400 on the wght axis at 430, 15px, 22px): running text; Anek's regular is drawn light, so the axis is lifted for daylight.
- **Body Strong** (600, 15px, 22px): button labels, emphasised inline figures.
- **Caption** (450 on the axis, 13px, 18px): meta lines, strip labels, filter-tab labels (at 600).
- **Label** (500, 12px, 16px, 0.1px tracking): nav labels and the pack's small print, set next to its value, sentence case.
- **Code** (600, 16px, 22px, width 110, 1px tracking): OTP digits, order numbers, batch codes.

### Named Rules
**The Narrow Figure Rule.** Key figures are narrowed on the `wdth` axis (78 to 86) and heavy; running text is never narrowed. Change weight or width only through the `weight()` and `narrow()` helpers so the `wght` axis moves with `fontWeight` and narrow figures are never synthetically emboldened.

**The Tabular Rule.** Tabular figures are on every style. A figure that updates live must not change width, and price columns must align.

**The One Baseline Rule.** Any label that may be set in either script carries the Latin strut (`v360Strut`), so Hindi and English beside each other sit on one baseline instead of the Devanagari riding about 3dp high.

**The Value-First Rule.** A figure is printed first and bold with its label small beneath or beside it ("16 entries"). No small grey label above a number, no tracked-out uppercase: section headings are real headings in ink, in the case they were written.

## Layout

A single-column phone layout on a 4pt scale (4, 8, 12, 16, 20, 24, 32, 40, 48) with a 16px horizontal gutter, Material's compact-width margin, so rows line up with system sheets and snackbars. Screens are stacked horizontal bands rather than grids: the teal band at the top (reaching under the status bar so the top of the phone reads as one printed field), then white board carrying ruled lists and bordered panels, then the flat ruled bottom bar.

Lists are ruled rows, not card grids: a row title, a status-mark meta line, the figure right-aligned, and its action beneath or at the end. Where a group needs an edge (Running out, a forecast), it sits in one hairline-bordered panel with rules between rows. Facts that qualify a figure go in a declaration strip of equal cells separated by 1px vertical rules and top/bottom rules. Filter tabs run in one horizontally scrolling row at 36px. The desktop/web build renders the same phone column inside a phone frame rather than reflowing into a dashboard.

## Elevation & Depth

Depth is the way print has it: almost none. Panels are flat in both themes and separated from the page by a 1px hairline; Material surface tint is switched off so a raised surface stays the colour it was printed in. AppBars, dialogs, bottom sheets, snackbars and the FAB all run at elevation 0. The bottom bar is a flat surface with a hairline top rule; the mic disc is lifted out of it by position and a 4px white ring, not by a shadow.

### Shadow Vocabulary
- **Floating** (`box-shadow: 0 6px 18px rgba(16, 32, 28, 0.14)`): only for something that genuinely floats over the page, such as a dragged row. None in dark mode, where a shadow on near-black reads as mud. Popup menus use a hairline border with minimal elevation.

### Named Rules
**The Rule-Not-Lift Rule.** A panel is separated by a rule, never by a shadow. If you reach for elevation on a card, draw a hairline instead.

## Shapes

Corners are cut tight like a carton dieline: 4px for markers, badges, status boxes, filter tabs and tooltips; 6px for buttons, fields, segmented options and snackbars; 8px for panels, stat tiles and popup menus; 12px for dialogs and the top of bottom sheets. The 999px pill is kept for the few things that are round in life, above all the microphone. Status squares have a 1px corner.

The flash band is the one irregular silhouette: a bevelled rectangle with the top-right corner cut away at 14px and 2px on the other three, the way a pack's "20% extra" flash is cut. On the demand map, shape separates layers: demand is a flat disc with a paper keyline, a distributor an ink square, a mandi an ink diamond, restock pressure a dashed ring.

## Components

Flutter widgets, not HTML. Every component reads tokens through `context.v360`; the sidecar's HTML/CSS snippets are approximations for preview only.

### Buttons
- **Shape:** printed blocks with tight corners (6px), never pills.
- **Sizes:** 40px (small, only inside a row whose row carries the rest of the target), 48px (medium), 52px (large, default). Horizontal padding 14 / 18 / 22px. Labels in Body Strong on the Latin strut, ellipsised rather than overflowing.
- **Primary:** Pack Teal fill, white label.
- **Secondary:** white fill, ink label, 1.5px ink keyline.
- **Tonal:** Teal Wash fill, Deep Teal Text label. For an action that repeats down a list (Reorder, 1-tap order, Mark % off), where a keyline on every row would print a column of black boxes.
- **Ghost:** no fill, Deep Teal Text label; Teal Wash on press.
- **Danger:** MRP Red fill, white label.
- **Pressed:** the fill darkens by 14% ink over 140ms, like a stamp pressing ink into paper. Buttons do not shrink.
- **Disabled:** Board Grey fill, Ink Subtle label, keyline dropped.

### Filter Tabs (V360Tab)
- **Style:** one component for every filter row (Stock categories, order filters, map categories): 36px high, 12px side padding, 4px corners, white with a hairline border, caption at 600 in ink.
- **State:** active prints solid ink with a white label. An optional status square (the amber square on "Running out") prints before the label while the tab is off.

### Status Mark and Status Box
- **Status Mark:** a 7 to 8px solid square in the status ink, 5 to 6px gap, then the word in ink (caption or label, 600). A Material outline icon in the status ink may replace the square where the kind of status matters more than its level.
- **Status Box:** a Status Mark inside a white box with a hairline border and 4px corners, for the end of a row. Not a tinted pill.

### Panels (V360Card)
- **Corner Style:** 8px.
- **Background:** Board White.
- **Shadow Strategy:** none (see Elevation & Depth).
- **Border:** 1px hairline.
- **Internal Padding:** 16px. Tappable panels acknowledge a finger with a very soft press scale (0.985) and highlight.

### Inputs / Fields
- **Style:** white fill, 1px Ink Subtle outline, 6px corners, 14px padding, Body text with Ink Subtle placeholder. On the band (Stock search) the field sits white on teal.
- **Focus:** 2px Pack Teal outline; floating label in Label style, Deep Teal Text.
- **Error / Disabled:** MRP Red outline (2px when focused); disabled outline drops to hairline.

### Navigation
- **Bottom bar:** flat white, hairline top rule, 64px, no shadow. Four plain destinations (Home, Stock, Forecast, Score) with a 24px outline icon and a Label word in Ink Muted; the selected one fills its icon, turns Deep Teal Text at 700, and gets a 28 x 3px teal rule printed on the bar's top edge.
- **Mic:** the centre slot is a 58px Mic Marigold disc raised 20px above the bar with a 4px white ring and an ink mic icon; on the Speak tab the ring prints 3px ink to say "you are here". Its label is ink at 700.
- **AppBar:** every secondary screen opens on the band: Pack Teal, white title in Title L at 22px, elevation 0, left-aligned.
- **Distributor shell:** identical structure on the Bottle-Green band.

### Pack Header (signature)
The front of the pack. A flat teal band, one per primary screen: a 48px title row (store or screen name in Title M 700, locality in Band Muted caption, actions at the end), then optionally the screen's one figure in Display white with a Body caption in Band Muted, then a Declaration Strip on the band, then optionally a search field. No gradient, glow or decorative shape.

### Declaration Strip (signature)
The ruled MRP box: equal cells separated by 1px rules, with top and bottom rules; value first in Title S 700 at width 86, label beneath in caption. On the band the rules are white at 32% and labels Band Muted; on white the rules are hairline and labels Ink Muted. Cells may be tappable.

### Flash Band (signature)
Flat Flash Marigold, ink content: a 22px icon, a Body Strong 700 title, a caption detail, optional chevron. Top-right corner cut at 14px. No border, no tinted icon square, no gradient. At most one per screen.

### Reason Line
Why a forecast moved, printed as a plain line rather than a chip: a small Ink Muted outline icon, the signed lift in bold, then the cause in ink.

### Demand Map
A printed district map drawn on canvas (so it works offline): flat discs sized by the square root of demand and filled from the five stepped heat classes, largest first, each with a paper keyline. Labels are set last and only where they fit, on a paper knock-out plate. Pins are reserved first and no label may overprint a pin or any disc but its own. The key shows five swatches, never a gradient bar.

### Voice Orb
The mic on the Speak screen: a Mic Marigold circle with an ink icon. While listening, two rings expand out of phase behind it; the button itself never scales, because the target must not move under the thumb.

## Do's and Don'ts

### Do:
- **Do** print exactly one flat teal band per screen and put the screen's one figure on it in Display (56px, width 78).
- **Do** keep status inks consistent everywhere: teal for healthy/live, amber for low/attention, MRP Red only for zero, expired, overdue or destructive.
- **Do** print status as a solid 7 to 8px square beside an ink word.
- **Do** set qualifying facts value-first in a ruled Declaration Strip.
- **Do** use ruled rows inside at most one hairline-bordered panel for lists.
- **Do** make primary row actions at least 48px (tonal medium button); reserve the 40px size for secondary actions inside a row.
- **Do** derive a header count from the same read as the rows beneath it ("Running out · 6" lists six).
- **Do** name every window in the copy: "in 3 days", "next 7 days".
- **Do** use V360Tab for every filter row.
- **Do** put the Latin strut on any label that may render in Devanagari.
- **Do** change weight and width through `weight()` and `narrow()`.
- **Do** keep colour literals in `v360_colors.dart` and assert contrast ratios in tests.
- **Do** let motion carry state only: a rolling figure when a sale lands, factor bars growing to value, pulsing rings while listening, a darkening press.

### Don't:
- **Don't** use gradients, glows or coloured halos on any surface, including charts and the map.
- **Don't** put shadows on panels; use a hairline.
- **Don't** lay out key figures as a grid of stat tiles or a gradient hero card.
- **Don't** set small grey or uppercase letterspaced labels above headings or figures.
- **Don't** use tinted pill chips or coloured status text; the colour goes in the square.
- **Don't** use marigold for chart decoration, highlights or anything other than the mic, attention and the one flash band.
- **Don't** print more than one flash band on a screen.
- **Don't** let a map label overprint another zone or a pin; leave it off instead.
- **Don't** round panels beyond 12px or make buttons pills; the pill radius is for things round in life.
- **Don't** add staggered or orchestrated entrance animations.
- **Don't** shrink buttons on press.
- **Don't** use cream or warm off-white as the second neutral; the board grey is cool.
