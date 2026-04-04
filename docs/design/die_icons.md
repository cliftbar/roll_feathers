# Die Icons — Design Notes

## Current implementation (Option B)

All icons live in `lib/ui/die_screen/die_list_tile.dart` as a private `_DieIconPainter`
(`CustomPainter`). The rolling state wraps the same icon in a `RotationTransition` using
the die's own color — no separate "rolling" icon.

### Visual language: filled shape + contrast overlay

Every icon is a solid-filled polygon with a contrast-color overlay that identifies the
die type. Simpler dice (d4, d6) have no overlay — they rely on shape alone.

| Die | Outer shape | Overlay | Notes |
|-----|-------------|---------|-------|
| d4  | Triangle (3-gon, apex up) | — | Plain fill |
| d6  | Square (4-gon, flat sides) | — | Plain fill |
| d8  | Diamond (4-gon, apex up/down) | Horizontal equator line | Evokes octahedron equator |
| d10 | Pentagon (5-gon, apex up) | Pentagram (5 crossing lines) | Classic d10 symbol |
| d12 | Dodecagon (12-gon) | Pentagon outline (apex up) | Pentagon = dodecahedron face |
| d20 | Hexagon (6-gon) | Triangle outline (apex up) | Triangle = icosahedron face |
| custom | Square (axis-aligned) | Face count number | `?` when faces ≤ 0 |

### Key parameters

```dart
// Outer shape radius multipliers
d4  triangle : r * 0.85   // tighter — high circumradius/inradius ratio
others       : r * 0.90

// Inner overlay sizes
d8  equator  : strokeWidth = size * 0.10, spans full diamond width
d10 pentagram: strokeWidth = size * 0.08, connects vertex[i] → vertex[(i+2)%5]
d12 pentagon : r * 0.60,  strokeWidth = size * 0.09
d20 triangle : r * 0.65,  strokeWidth = size * 0.09
```

All contrast overlays use `_contrastColor(color)`:
```dart
Color _contrastColor(Color bg) =>
    bg.computeLuminance() > 0.4 ? Colors.black : Colors.white;
```

---

## Alternatives considered

### Option A — "Outline + inner shape" for everything

Every icon uses a semi-transparent stroke outline (die silhouette, 40% opacity) with a
solid inner fill (die face shape). Mirrors how d12 and d20 were originally implemented
before switching to Option B.

| Die | Outer (outline, 40% opacity) | Inner (solid fill) |
|-----|------------------------------|--------------------|
| d4  | Triangle outline | Smaller triangle |
| d6  | Square outline | Smaller square |
| d8  | Diamond outline | Triangle (octahedron face) |
| d10 | Pentagon outline | Pentagram fill or pentagon |
| d12 | 12-gon outline | Pentagon |
| d20 | Hexagon outline | Triangle |

Pros: consistent depth/layering feel, every icon has a secondary element.
Cons: d4/d6 feel forced (nested same-shape), less bold at small sizes.

### 3D polyhedra projection style

The image below (saved from conversation) shows the classic RPG dice icon style used
in many tabletop apps and print resources — a 2D perspective projection of each
polyhedron, rendered as either wireframe or filled silhouette with white edge lines.

Reference image: `docs/design/assets/polyhedra_reference.png` *(copy manually if needed)*

This style shows the actual 3D shape of each die:

| Die | Shape | Internal lines |
|-----|-------|----------------|
| d4  | Triangular pyramid | 3 face divisions from base corners |
| d6  | Isometric cube | 2 face dividing lines (3 visible faces) |
| d8  | Double pyramid (diamond) | Equator + diagonal face lines |
| d10 | Kite/trapezohedron | Kite outline + face divisions |
| d12 | Rounded pentagon solid | Internal pentagonal face lines |
| d20 | Rounded triangle solid | Internal triangular face lines |

**Feasibility notes:**
- Implementable with `CustomPainter` — each shape is a 2D projection of fixed
  3D geometry, so vertex coordinates can be hard-coded in normalized `[-1, 1]` space
  and scaled at paint time.
- d6 (cube) is the most complex — requires isometric projection of 3 parallelogram faces,
  not a regular polygon.
- d10 face is a kite/deltoid — also non-trivial to project.
- **Recommended minimum icon size: 36–40px.** At 24px the internal edge lines collapse
  into noise. Would require changing `_DieIcon._size` and the `ListTile.leading` sizing.
- Filled silhouette style (white edge lines on solid fill) reads better at small sizes
  than the wireframe style.
- Implementation cost: high — each die needs individually crafted vertex data rather than
  the formula-driven regular polygon approach currently used.

**When to revisit:** If icon size is bumped to 36px+ or if a dedicated icon asset pipeline
is introduced (e.g. SVG assets loaded via `flutter_svg`).

---

## Icon size

Current: `_DieIcon._size = 24` (matches Flutter's default `Icon` size in `ListTile.leading`).

Increasing to 36–40px would require:
1. Changing `_DieIcon._size`
2. Wrapping the `ListTile` leading in a `SizedBox` of the same size (ListTile constrains
   leading to its own layout, so a larger `CustomPaint` may need explicit sizing)
