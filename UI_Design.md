# Mobile RTS Game UI Concept & Architecture Document

## Overview & Visual Theme
This document outlines the layout, user interface (UI) architecture, and user experience (UX) specifications for a mobile Real-Time Strategy (RTS) game heavily inspired by classics like *Age of Empires*.

* **Visual Style:** Pixel art / Medieval fantasy featuring dragon-adorned gold borders with deep dark-brown background panels (`#2B1D14` fill with `#E5B842` gold accents).
* **Target Platform:** Mobile (Landscape orientation, optimized for thumb controls).

---

## Screen Layout Wireframe

```
+---------------------------------------------------------------------------------+
| [Archer] (•)                 [ AGE IV: Imperial Age ]                (Stone)    |
| [Knight] (•)            [==== Progress Bar: 65% ====]                (Gold)     |
| [Pike]   (•)                                                         (Wood)     |
| [Villager](•)                                                        (food)     |
| [Treb]   (•)                                                         (Villager) |
|                                                                                 |
|                                     GAMEPLAY                                    |
|                                       VIEW                                      |
|                                                                      +----------+
| +-----------------------------------------------+                    |          |
| |               SELECTION PANEL                 |                    | MINIMAP  |
| |  [Icon] [Icon] [Icon]   Unit / Building Stats  |                    | PANEL    |
| +-----------------------------------------------+--------------------+----------+
```

---

## UI Component Specifications

### 1. Control Group Quick-Selects (Top-Left, Vertical Stack)
Situated above the selection panel along the left edge for fast left-thumb access.
* **Format:** 5 circular gold-framed icons stacked vertically.
* **Groups Included:**
  1. **Archer** (Ranged units)
  2. **Knight** (Cavalry / Mobile units)
  3. **Pike-man** (Anti-cavalry / Frontline)
  4. **Villager** (Economy / Workers)
  5. **Trebuchet** (Siege machinery)
* **Function:** Single tap selects the active control group; double tap centers the camera on the group.

### 2. Age Advancement Header (Top Center)
Displays current technological age and active transition progress.
* **Frame:** Gold-embossed banner with ornamental dragon framing.
* **Components:**
  * **Age Title:** e.g., `AGE IV: Imperial Age`
  * **Progress Bar:** Red-to-gold filling progress bar indicating upgrade percentage during age transitions.

### 3. Resource Counter Column (Top-Right, Vertical Stack)
Stacked vertically along the right side directly above the bottom minimap to conserve horizontal viewport space.
* **Layout (Top to Bottom):**
  1. **Stone** (e.g., 🪙 150)
  2. **Gold** (e.g., 🟡 500)
  3. **Wood** (e.g., 🪵 350)
  3. **Food** (e.g., 🍎 350)
  4. **Villager Count** (e.g., 👨‍🌾 18/50 Idle/Total)
* **Styling:** Compact dark-brown badges with gold outline and high-contrast numerical indicators.

### 4. Selected Unit / Building Panel (Bottom-Left)
Occupies the bottom-left corner with a dark brown background panel framed by pixel-art dragon accents.
* **Dynamic Views:**
  * **Single Unit Selected:** Displays unit portrait, HP bar, attack/armor statistics, stance commands (Aggressive, Defensive, Stand Ground), and special actions.
  * **Building Selected:** Displays building hit points, production queue slots, available unit creation icons (e.g., Villager creation at Town Center), and technology research upgrades.
  * **Multi-Selection / Army:** Displays a grid of unit micro-portraits (up to 15-20 units) with miniature health status overlays.

### 5. Minimap Panel (Bottom-Right, Flush Bottom)
Anchored flush against the bottom-right corner of the screen.
* **Frame:** Golden dragon-wrapped border.
* **Features:**
  * Isometric / Top-down fog-of-war minimap rendering.
  * Camera viewport rectangle overlay.
  * Quick-ping gesture support for mini-map communication and movement dispatch.

---

## Mobile UX & Design Principles
1. **Dual-Thumb Ergonomics:** Key interactive zones (Control Groups on the left, Minimap and Resources on the right) align with comfortable thumb reach during horizontal mobile holding.
2. **Clear Center Viewport:** Uncluttered middle arena ensures maximum visibility for battlefield micro-management and terrain navigation.
3. **Contrast & Hierarchy:** Dark brown fill behind command interfaces provides high readability over bright grass, stone, and water textures on the map.