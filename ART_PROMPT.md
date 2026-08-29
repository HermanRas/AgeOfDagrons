# ART_PROMPT.md — the UI overhaul, batched into sprite sheets

Gemini prompts for the whole UI art set (`asset_request.md` [P8]). One `##` section
per sheet. Generate a section, save it as `<section heading>.png` into
**`assets/UI_Gen/`**, and we review and slice from there.

Written 2026-08-30 by the asset agent. Every count below was read off the code, not
off [P8]'s summary — where the two differ, this file is the measured one.

---

## How to use this file

1. Copy the fenced prompt block of one `##` section — the whole block, it is
   self-contained on purpose (Gemini keeps nothing between prompts).
2. Save Gemini's output as `assets/UI_Gen/<the section's heading>.png`.
3. We review it together, regenerate if a cell is malformed, then slice.

**Regenerate the whole sheet, never one cell.** A single-cell re-roll comes back in a
slightly different light and gloss, and a sheet where one icon is lit from the right
is worse than a sheet with one weak icon.

### The canvas contract, identical for every sheet

- **1024 × 1024 px**, no exceptions.
- **The bottom-right 256 × 256 is left empty**, flat background, no artwork. That is
  where Gemini stamps its watermark, and it is why every icon sheet has 15 usable
  cells rather than 16.
- **Flat pure black background (#000000)** everywhere the artwork is not. Not a
  gradient, not a vignette, not a texture. We key it out to alpha when slicing, and
  a gradient background cannot be keyed cleanly.
- **No text anywhere in the image.** No labels, no captions, no numbers, no
  watermark of its own, no grid lines, no cell borders. Gemini adds these unasked on
  any prompt that reads like a chart; each prompt below says so twice for that
  reason.

### The two decisions that shape every prompt (owner, 2026-08-30)

**Smooth painted, not pixel art.** The reference image is smooth-rendered and that is
the target. This retires the existing 20 icons' pixel-art look entirely.
`UI_Design.md` and its mockups said "pixel art"; they have been deleted as outdated
on the same instruction.

**Icons are BARE GLYPHS. The frame is chrome.** Today every icon carries its own gold
dragon frame *and* `ActionSlot` draws `panel_background.png` behind it — so every
action tile in the running game is double-framed. In the new set the dragon tile
frame is **one reusable asset** (`sheet_widgets`, cells 1–3), and the 103 glyphs sit
inside it. That is exactly what the reference image is: an empty frame waiting for a
glyph.

Consequences worth knowing before generation starts:

- A glyph gets the full 52 px of the tile instead of ~30 px inside a border.
- Normal / selected / disabled states cost three frame assets, not 315 icons.
- **The glyph must read with no frame to help it.** Every prompt therefore asks for a
  bold silhouette and a dark contact shadow — a thin gold outline on a gold-rimmed
  tile disappears.

### Palette, quoted in every prompt

| role | hex |
|---|---|
| gold highlight | `#F2D06B` |
| gold mid | `#E5B842` |
| gold shadow | `#8A6A1E` |
| panel field | `#2B1D14` |
| cream / parchment | `#F0E2C0` |
| button red | `#7A1F1F` |
| health red | `#C4342E` |

`#E5B842` and `#2B1D14` are `HudStyle.GOLD` and `HudStyle.DARK_BG`, which the running
HUD already draws with. The other five are new and are ours to set.

---

## The batching, and why these groupings

**Seven icon sheets, 4 × 4 at 256 px, 15 usable cells each = 103 glyphs** — 15 on six
of them and 13 on `sheet_e_economy_techs`, whose last two cells are reserved. Sheets are
grouped by *when a player sees them together*, not alphabetically — every icon on one
sheet is generated in one pass, so a sheet is the unit of style consistency, and the
icons that must match are the ones that share a screen.

| sheet | cells | what it covers | wired today? |
|---|---|---|---|
| `sheet_a_command_verbs` | 15 | the selection panel's action column | 13 of 15 |
| `sheet_b_resources_and_hud` | 15 | resource column, HUD corner buttons | 11 of 15 |
| `sheet_c_formations_stances_ages` | 15 | formations, stances, abilities, age medallions | 10 of 15 |
| `sheet_d_military_techs` | 15 | the blacksmith's 12 + university 2 + a fallback | 14 of 15 |
| `sheet_e_economy_techs` | 13 | town centre, mill, lumber, mining, monastery | 13 of 13 |
| `sheet_f_multiplayer_and_voice` | 15 | chat, voice, server browser, lobby | 0 of 15 |
| `sheet_g_system_and_modes` | 15 | save/load, replay, packs, victory, transport, siege | 2 of 15 |

**Five chrome pieces, one full 1024 canvas each.** A panel border rendered as a 256 px
cell on a shared sheet comes back with the corner ornament not lining up with the
edge run beside it, and a seam at every panel corner is not fixable by hand. One
panel per canvas also gives the border enough pixels to survive being sliced.

**Two widget sheets**, because the widgets genuinely are small and independent.

Total: **14 prompts**.

### What is deliberately NOT in here

- **Page arrows for the detail grid.** `SelectionActions` uses the characters `<` and
  `>` and its header records why: at 72 px a caret reads as navigation in a way no
  glyph does. `sheet_widgets` has arrows for **scrollbars and dropdowns** — do not
  wire those into the detail grid against a decision that was already made and
  written down.
- **Train / place / queue / roster tiles.** Those crop the entity's own baked sprite,
  which beats any icon.
- **A font.** Gemini does not produce a `.ttf`. [P8] §4b was right that the typeface
  was unchosen and touches every screen — **the owner has since chosen, 2026-08-30**;
  see the fonts section at the end of this file.

---

## sheet_a_command_verbs

**15 glyphs. `assets/UI_Gen/sheet_a_command_verbs.png`.**

The selection panel's action column. Thirteen of these have a live command behind
them today; `leave` has art and no consumer (PLAN.md 13.2 item 4b asks whether
enter/garrison and exit/leave are two pairs covering one concept — drawing it does not
answer that, it keeps the option open), and `close` replaces the ring-and-two-strokes
that `ClearSelectionButton` draws by hand.

| cell | id | replaces |
|---|---|---|
| 1 | `act_move` | `act_move.png` |
| 2 | `act_stop` | `act_stop.png` |
| 3 | `act_attack` | `act_attack.png` |
| 4 | `act_build` | `act_build.png` |
| 5 | `act_repair` | **stand-in today** — draws `act_guard.png`, a shield |
| 6 | `act_harvest` | **stand-in today** — draws `res_wood.png`, a resource not a verb |
| 7 | `act_destroy` | `act_destroy.png` |
| 8 | `act_garrison` | `act_garrison.png` |
| 9 | `act_enter` | `act_enter.png` (also the gate's "close") |
| 10 | `act_exit` | `act_exit.png` (also the gate's "open", and garrison "empty") |
| 11 | `act_leave` | `act_leave.png` — **wired to nothing** |
| 12 | `act_upgrade` | **stand-in today** — draws `hud_techtree.png` |
| 13 | `act_research` | **stand-in today** — shares Upgrade's file |
| 14 | `act_stance` | shares Repair's `act_guard.png`; the shield is stance's claim |
| 15 | `ui_close` | nothing — drawn by hand in `clear_selection_button.gd` |

```
A 1024x1024 sprite sheet of 15 medieval-fantasy game UI symbols, arranged on a
strict 4x4 grid of 256x256 cells with no gutters. The bottom-right cell is
completely empty.

STYLE: richly rendered semi-realistic mobile-game icon art. Smooth gradients, soft
studio lighting from the upper left, bevelled three-dimensional depth, subtle
ambient occlusion, crisp anti-aliased edges, a slight warm specular sheen on metal.
NOT pixel art. NOT flat vector. NOT cel-shaded outline art. NOT isometric.

PALETTE: burnished gold, highlight #F2D06B through mid #E5B842 to shadow #8A6A1E;
aged steel; warm oak brown; cream parchment #F0E2C0. Accents in deep red #7A1F1F
only where noted.

COMPOSITION: each symbol floats alone, centred in its cell, filling about 76% of the
cell with clear empty margin around it. Each symbol has a bold, instantly readable
silhouette and a soft dark contact shadow beneath it so it reads without any frame
around it. Symbols are consistent in scale, lighting direction and level of detail
across all 15 cells.

BACKGROUND: flat pure black #000000 everywhere. No gradient, no vignette, no
texture, no glow. No grid lines. No borders or frames around the cells or the
symbols.

ABSOLUTELY NO TEXT of any kind: no labels, no captions, no numbers, no letters.

The 15 symbols, left to right, top to bottom:
1. A brown leather marching boot in mid-stride with a gold arrow sweeping forward
   from its heel.
2. An open human palm facing the viewer, gold-rimmed, in a halt gesture.
3. Two crossed swords, aged steel blades, gold hilts and pommels.
4. A mason's hammer crossed with a chisel over a freshly cut stone block.
5. A gold-headed hammer striking a black anvil, three bright sparks flying.
6. A curved harvesting sickle crossed with a miner's pickaxe.
7. A weathered skull with a bold deep-red #7A1F1F cross struck through it.
8. A stone archway with a small armoured figure stepping inward through it.
9. An open wooden door with a gold arrow curving inward through the opening.
10. An open wooden door with a gold arrow curving outward through the opening.
11. A small cloaked figure walking away from a doorway, a gold motion trail behind.
12. A broad gold chevron pointing upward, rising above a small black anvil.
13. An unrolled parchment scroll with a quill laid across it and a small glass
    flask standing beside it.
14. A heater shield, gold-rimmed with a dark field, a spear crossed behind it.
15. A bold X of two thick bevelled gold bars.
```

---

## sheet_b_resources_and_hud

**15 glyphs. `assets/UI_Gen/sheet_b_resources_and_hud.png`.**

The resource column (`ResourceHUD`, which draws these at 24 px) and the four corner
buttons around the minimap. Note the existing resource icons are **green circles**
where the actions are gold squares — that distinction was carrying real meaning and
it moves into the chrome: resources get `badge_round` from `sheet_widgets`, actions
get `tile_frame`. The glyphs themselves stay bare.

`res_idle` is new and replaces the ring `IdleVillagerBadge` draws by hand.
`hud_volume` is game audio; the headset on `sheet_f` is voice chat, and they are
deliberately different pictures.

| cell | id | wired |
|---|---|---|
| 1–5 | `res_food` `res_wood` `res_gold` `res_stone` `res_villagers` | yes, all five |
| 6 | `res_idle` | no — hand-drawn ring today |
| 7–11 | `hud_chat` `hud_trade` `hud_techtree` `hud_settings` `hud_score` | `hud_score` is referenced by **nothing** |
| 12–15 | `hud_menu` `hud_pause` `hud_alert` `hud_volume` | pause exists as `menu/pause_icon.png`; the rest are new |

```
A 1024x1024 sprite sheet of 15 medieval-fantasy game UI symbols, arranged on a
strict 4x4 grid of 256x256 cells with no gutters. The bottom-right cell is
completely empty.

STYLE: richly rendered semi-realistic mobile-game icon art. Smooth gradients, soft
studio lighting from the upper left, bevelled three-dimensional depth, subtle
ambient occlusion, crisp anti-aliased edges, a slight warm specular sheen on metal.
NOT pixel art. NOT flat vector. NOT cel-shaded outline art.

PALETTE: burnished gold, highlight #F2D06B through mid #E5B842 to shadow #8A6A1E;
aged steel; warm oak brown; cream parchment #F0E2C0.

COMPOSITION: each symbol floats alone, centred in its cell, filling about 76% of the
cell with clear empty margin around it. Bold readable silhouette, soft dark contact
shadow beneath. Consistent scale, lighting direction and detail across all 15 cells.

BACKGROUND: flat pure black #000000 everywhere. No gradient, no vignette, no
texture, no glow. No grid lines. No borders or frames around cells or symbols.

ABSOLUTELY NO TEXT of any kind: no labels, no captions, no numbers, no letters.

The 15 symbols, left to right, top to bottom:
1. A golden wheat sheaf tied with cord, a red apple resting against it.
2. Three freshly cut oak logs stacked in a pyramid, pale end-grain facing the viewer.
3. A small stack of gleaming gold coins, the top one tilted.
4. Three cut grey granite blocks stacked, chisel marks visible.
5. A villager's head-and-shoulders bust in a simple blue tunic, three-quarter view.
6. The same villager bust, head tipped and eyes closed, a small brass hourglass
   standing beside it.
7. A rounded speech bubble in cream #F0E2C0 with a gold rim.
8. A merchant's brass balance scale, both pans level.
9. Three linked circular nodes branching upward like a tree diagram, gold, joined by
   gold connecting bars.
10. A single ornate brass cogwheel, eight teeth.
11. A laurel wreath of gold leaves enclosing three rising bars of different heights.
12. Three thick horizontal gold bars stacked with even gaps, like ingots.
13. Two thick vertical gold bars, rounded ends, side by side.
14. A brass hand bell, tilted mid-ring, two small motion arcs beside it.
15. A brass speaker horn facing right with three concentric sound arcs.
```

---

## sheet_c_formations_stances_ages

**15 glyphs. `assets/UI_Gen/sheet_c_formations_stances_ages.png`.**

Formations 1–4 are `Formation.SHAPES` in enum order. Stances 5–8 are
`SimUnit.Stance` in `STANCE_LABELS` order. Abilities 9–10 are keyed by
`UnitDef.ability_id` — `heal` (monk) and `fire_breath` (dragon), verified in
`units.json`. 11–15 are the age medallions, which `AgeBadge` draws by hand today.

**Formations are pips, not pictures.** `SelectionActions._formation_details` records
that a formation is a shape and the label already is the picture; a literal drawing of
soldiers at 52 px is mush, an arrangement of pips is not.

| cell | id |
|---|---|
| 1–4 | `form_line` `form_grid` `form_vee` `form_box` |
| 5–8 | `stance_aggressive` `stance_defensive` `stance_stand_ground` `stance_passive` |
| 9–10 | `abil_heal` `abil_fire_breath` |
| 11–15 | `age_1` `age_2` `age_3` `age_4` `age_advance` |

```
A 1024x1024 sprite sheet of 15 medieval-fantasy game UI symbols, arranged on a
strict 4x4 grid of 256x256 cells with no gutters. The bottom-right cell is
completely empty.

STYLE: richly rendered semi-realistic mobile-game icon art. Smooth gradients, soft
studio lighting from the upper left, bevelled three-dimensional depth, subtle
ambient occlusion, crisp anti-aliased edges. NOT pixel art. NOT flat vector.

PALETTE: burnished gold, highlight #F2D06B through mid #E5B842 to shadow #8A6A1E;
aged steel; deep red #7A1F1F; cream parchment #F0E2C0.

COMPOSITION: each symbol floats alone, centred in its cell, filling about 76% of the
cell. Bold readable silhouette, soft dark contact shadow. Consistent scale, lighting
and detail across all 15 cells.

BACKGROUND: flat pure black #000000. No gradient, no vignette, no texture, no glow,
no grid lines, no borders around cells or symbols.

ABSOLUTELY NO TEXT of any kind: no labels, no captions, no numbers, no letters,
no Roman numerals.

The 15 symbols, left to right, top to bottom:
1. Five identical polished gold spheres in one straight horizontal row, evenly spaced.
2. Nine identical polished gold spheres in a tidy 3 by 3 square block.
3. Seven identical polished gold spheres arranged in a wide V, point downward.
4. Twelve identical polished gold spheres arranged as a hollow square outline.
5. A steel sword raised and angled forward, wreathed in a faint deep-red #7A1F1F aura.
6. A gold-rimmed heater shield facing the viewer, a sword held upright behind it.
7. A spear planted upright into a stone slab, an armoured boot braced at its base.
8. A gold-rimmed shield lowered and tilted downward, muted and pale, no weapon.
9. A radiant gold cross with a soft warm white glow blooming behind it.
10. A stylised golden dragon head in profile, jaws open, exhaling a cone of orange
    and gold flame.
11. A circular gold medallion containing a small thatched hut in relief.
12. A circular gold medallion containing a wooden watchtower in relief.
13. A circular gold medallion containing a stone castle turret in relief.
14. A circular gold medallion containing a crown above a castle in relief.
15. A broad gold chevron pointing upward with a bright starburst behind its point.
```

---

## sheet_d_military_techs

**15 glyphs. `assets/UI_Gen/sheet_d_military_techs.png`.**

The blacksmith's twelve, plus the university's two, plus a fallback.

**The grid layout IS the design.** At age 4 all twelve blacksmith technologies are on
screen at once in a 4 × 3 grid, one ladder per column — so this sheet's rows 1–3 are
laid out *exactly as the player will see them*: **one ladder per column, tier
ascending down the rows**. Generating them in that arrangement is what makes Gemini
keep a shared motif down each column instead of drawing twelve unrelated objects.

Each glyph also carries **1, 2 or 3 small gold pips** in its lower right for its tier.
That is the tier mark [P8] asked for; the ladder is the column, the tier is the pips.

|  | col 1 — melee attack | col 2 — ranged attack | col 3 — melee armour | col 4 — ranged armour |
|---|---|---|---|---|
| **row 1** | `tech.forging` | `tech.fletching` | `tech.scale_mail` | `tech.padded_armour` |
| **row 2** | `tech.iron_casting` | `tech.bodkin_arrow` | `tech.chain_mail` | `tech.leather_armour` |
| **row 3** | `tech.blast_furnace` | `tech.bracer` | `tech.plate_mail` | `tech.ring_armour` |

Row 4: `tech.ballistics`, `tech.chemistry`, `tech_generic`, empty.

`tech_generic` is a fallback for any technology added later —
`_research_details` asks `ICONS.get(t.id, "")` and a new tech otherwise draws its
label until somebody bakes art. One spare cell buys that.

```
A 1024x1024 sprite sheet of 15 medieval-fantasy game technology-upgrade symbols,
arranged on a strict 4x4 grid of 256x256 cells with no gutters. The bottom-right
cell is completely empty.

STYLE: richly rendered semi-realistic mobile-game icon art. Smooth gradients, soft
studio lighting from the upper left, bevelled three-dimensional depth, subtle
ambient occlusion, crisp anti-aliased edges, warm specular sheen on metal.
NOT pixel art. NOT flat vector.

PALETTE: burnished gold, highlight #F2D06B through mid #E5B842 to shadow #8A6A1E;
aged blued steel; warm oak; tan leather; forge-orange embers.

IMPORTANT STRUCTURE: the first three rows are four UPGRADE LADDERS read down the
columns. Every symbol in a column shares one motif and one material family, and gets
visibly richer and more refined as it goes down the rows. Column 1 is forging
weapons, column 2 is archery, column 3 is metal body armour, column 4 is soft and
studded body armour.

TIER MARKS: each of the twelve symbols in rows 1 to 3 carries small polished gold
pips in its lower right corner - ONE pip in row 1, TWO pips in row 2, THREE pips in
row 3. The pips are small, plain spheres, clearly separate from the symbol itself.

COMPOSITION: each symbol floats alone, centred in its cell, filling about 76% of the
cell. Bold readable silhouette, soft dark contact shadow. Consistent scale, lighting
and detail across all cells.

BACKGROUND: flat pure black #000000. No gradient, no vignette, no texture, no glow,
no grid lines, no borders around cells or symbols.

ABSOLUTELY NO TEXT of any kind: no labels, no captions, no numbers, no letters.

The 15 symbols, left to right, top to bottom:
1. A glowing orange sword blank resting on a black anvil. One gold pip.
2. Three white goose-feather arrow fletches fanned out. One gold pip.
3. A patch of overlapping steel scales, like fish scales. One gold pip.
4. A patch of quilted tan linen armour, diamond stitching. One gold pip.
5. A stone crucible pouring molten metal into a sword mould. Two gold pips.
6. A single narrow four-sided bodkin arrowhead, polished steel. Two gold pips.
7. A patch of interlocking steel chain rings. Two gold pips.
8. A brown leather cuirass, plain, laced at the side. Two gold pips.
9. A stone blast furnace with leather bellows, flames at its mouth. Three gold pips.
10. A brown leather archer's arm bracer with gold buckles. Three gold pips.
11. A polished steel breastplate, fluted, catching the light. Three gold pips.
12. A brown leather jerkin studded with rows of small steel rings. Three gold pips.
13. A ballista bolt flying along a curving gold trajectory arc toward a small ring
    sight. No pips.
14. A glass alembic on a stand with pale green vapour curling from its spout and a
    single bright spark. No pips.
15. A plain gold cogwheel resting on an open book. No pips.
```

---

## sheet_e_economy_techs

**13 glyphs, cells 14 and 15 reserved. `assets/UI_Gen/sheet_e_economy_techs.png`.**

The remaining thirteen of the twenty-seven, by the building that sells them. All
thirteen are live in `techs.json` today and all thirteen draw their label.

Two cells are deliberately left blank rather than padded with something unwanted —
`techs.json`'s own note says its numbers are starting values tuned by playtest, and a
tuning pass that adds a fourteenth economy tech should not need a whole new sheet.

| cell | id | building |
|---|---|---|
| 1–2 | `tech.wheelbarrow` `tech.hand_cart` | Town Centre |
| 3–5 | `tech.horse_collar` `tech.heavy_plough` `tech.crop_rotation` | Mill |
| 6–7 | `tech.double_bit_axe` `tech.bow_saw` | Lumber Camp |
| 8–11 | `tech.gold_mining` `tech.stone_mining` `tech.gold_shaft_mining` `tech.stone_shaft_mining` | Mining Camp |
| 12–13 | `tech.sanctity` `tech.fervour` | Monastery |
| 14–15 | reserved, empty | — |

The two mining pairs differ by **material** (gold vs grey stone) and the two shaft
technologies add a **pithead frame**. That is the whole visual grammar; four
unrelated pickaxes would be unreadable in one 4-wide row.

```
A 1024x1024 sprite sheet of 13 medieval-fantasy economic technology symbols,
arranged on a strict 4x4 grid of 256x256 cells with no gutters. Cells are filled left
to right, top to bottom; the LAST THREE cells of the bottom row are completely empty.

STYLE: richly rendered semi-realistic mobile-game icon art. Smooth gradients, soft
studio lighting from the upper left, bevelled three-dimensional depth, subtle
ambient occlusion, crisp anti-aliased edges. NOT pixel art. NOT flat vector.

PALETTE: burnished gold, highlight #F2D06B through mid #E5B842 to shadow #8A6A1E;
aged steel; warm oak and weathered timber; tan leather; grey granite; wheat gold.

COMPOSITION: each symbol floats alone, centred in its cell, filling about 76% of the
cell. Bold readable silhouette, soft dark contact shadow. Consistent scale, lighting
and detail across all cells.

BACKGROUND: flat pure black #000000. No gradient, no vignette, no texture, no glow,
no grid lines, no borders around cells or symbols.

ABSOLUTELY NO TEXT of any kind: no labels, no captions, no numbers, no letters.

The 13 symbols, left to right, top to bottom:
1. A single-wheeled wooden barrow with worn oak handles, seen three-quarter.
2. A two-wheeled wooden handcart loaded with sacks.
3. A padded brown leather horse collar with brass fittings.
4. An iron ploughshare biting into a turned furrow of dark earth.
5. Three different crops - wheat, a root vegetable and a green leaf - encircled by
   three gold arrows chasing each other in a ring.
6. A double-headed felling axe with an oak haft.
7. A bow saw: a curved timber frame under tension holding a fine steel blade.
8. A steel pickaxe crossed over a scatter of raw gold nuggets.
9. A steel pickaxe crossed over three cut grey granite blocks.
10. A timber mine pithead frame with a pulley wheel, a cart of gold ore below it.
11. A timber mine pithead frame with a pulley wheel, a cart of grey stone below it.
12. A white dove with a soft gold halo descending toward a small stone altar.
13. A brass brazier with a tall bright flame rising from it.
```

---

## sheet_f_multiplayer_and_voice

**15 glyphs. `assets/UI_Gen/sheet_f_multiplayer_and_voice.png`.**

⚠️ **Not one of these has a feature behind it.** [P8] §5 files them on the owner's
instruction so one bake covers them, and drawing them commits nobody to building any
of it. Chat exists as a wireframe with deliberately disabled buttons; the server
browser, the lobby and voice chat do not exist at all.

**On voice chat**: `asset_request.md` records that it appears in no plan document. It
does appear in a mockup — `UI_Design_Chat_Voice.jpg` showed a per-player tab row with
a microphone or a speaker beside each name, which is where cells 1–4 come from. That
mockup has now been deleted as outdated, so **this file is the only surviving record
of that design**, and it is worth saying that the art is cheap and the feature is not:
voice needs a capture device, a codec, a transport that is *not* the command channel,
and an Android permissions prompt.

| cell | id | for |
|---|---|---|
| 1–4 | `mic_on` `mic_muted` `voice_on` `voice_muted` | voice chat |
| 5–6 | `chat_send` `chat_clear` | text chat (8.6) |
| 7–10 | `net_refresh` `net_join` `net_host` `net_filter` | server browser (12.1b) |
| 11–15 | `lobby_faction` `lobby_team` `lobby_gametype` `lobby_victory` `lobby_mapsize` | lobby |

```
A 1024x1024 sprite sheet of 15 medieval-fantasy game UI symbols for multiplayer,
chat and voice, arranged on a strict 4x4 grid of 256x256 cells with no gutters. The
bottom-right cell is completely empty.

STYLE: richly rendered semi-realistic mobile-game icon art. Smooth gradients, soft
studio lighting from the upper left, bevelled three-dimensional depth, subtle
ambient occlusion, crisp anti-aliased edges. NOT pixel art. NOT flat vector.

PALETTE: burnished gold, highlight #F2D06B through mid #E5B842 to shadow #8A6A1E;
aged brass; cream parchment #F0E2C0; deep red #7A1F1F for the two "muted" slashes.

DESIGN NOTE: these are modern functions rendered as medieval objects wherever
possible - parchment and seals rather than envelopes, brass horns rather than
loudspeakers - but they must stay instantly readable as their modern function.

COMPOSITION: each symbol floats alone, centred in its cell, filling about 76% of the
cell. Bold readable silhouette, soft dark contact shadow. Consistent scale, lighting
and detail across all 15 cells.

BACKGROUND: flat pure black #000000. No gradient, no vignette, no texture, no glow,
no grid lines, no borders around cells or symbols.

ABSOLUTELY NO TEXT of any kind: no labels, no captions, no numbers, no letters.

The 15 symbols, left to right, top to bottom:
1. A handheld microphone with an ornate gold cage head and a leather-wrapped grip,
   two small sound arcs beside it.
2. The identical microphone with a bold deep-red #7A1F1F diagonal slash across it.
3. A pair of over-ear listening cups on a gold headband, three sound arcs beside them.
4. The identical headset with a bold deep-red #7A1F1F diagonal slash across it.
5. A rolled parchment scroll with a gold arrow sweeping forward to the right.
6. An unrolled parchment scroll with a soft brush sweeping it blank, faint dust
   curling off the swept edge.
7. Two gold arrows chasing each other in a closed circle.
8. A brass plug entering a brass socket, a small spark where they meet.
9. A small stone keep with a bright beacon flame on its roof and two broadcast arcs
   rising from it.
10. A brass funnel, wide mouth up, with three gold grains falling through it.
11. A heraldic shield quartered in gold and deep red, with a small rampant device.
12. Three small overlapping heraldic shields in three different colours.
13. An unrolled map with two crossed swords laid across it.
14. A laurel wreath of gold leaves enclosing a small crown.
15. A framed map with four gold expansion arrows pushing outward from its corners.
```

---

## sheet_g_system_and_modes

**15 glyphs. `assets/UI_Gen/sheet_g_system_and_modes.png`.**

Save/load, replay transport, asset packs, victory modes, naval transport, and the two
siege pack states. Two of the fifteen have live systems behind them (`act_pack` /
`act_unpack` — `SiegeSystem` swaps the actor automatically today, with no button;
`icons.txt` asked for "unpack, repack" in the owner's original sheet brief, so they are
drawn and it stays the owner's call whether a button ever appears).

| cell | id | for |
|---|---|---|
| 1–3 | `file_save` `file_load` `file_delete` | save/load (12.4) |
| 4–6 | `replay_play` `replay_pause` `replay_step` | replay playback (12.4) |
| 7–8 | `pack_download` `pack_retry` | asset packs (0.3) |
| 9–10 | `victory_regicide` `victory_trophy` | victory modes (11.2) |
| 11–12 | `transport_load` `transport_unload` | naval transport |
| 13–14 | `act_pack` `act_unpack` | siege engines — **live system, no button** |
| 15 | `ui_confirm` | generic |

`replay_pause` and `hud_pause` (sheet B, cell 13) are the same two bars on purpose —
one file can serve both, and drawing them on separate sheets simply means neither
screen waits on the other.

```
A 1024x1024 sprite sheet of 15 medieval-fantasy game UI symbols, arranged on a
strict 4x4 grid of 256x256 cells with no gutters. The bottom-right cell is
completely empty.

STYLE: richly rendered semi-realistic mobile-game icon art. Smooth gradients, soft
studio lighting from the upper left, bevelled three-dimensional depth, subtle
ambient occlusion, crisp anti-aliased edges. NOT pixel art. NOT flat vector.

PALETTE: burnished gold, highlight #F2D06B through mid #E5B842 to shadow #8A6A1E;
aged steel; warm oak; deep red #7A1F1F for the delete mark.

COMPOSITION: each symbol floats alone, centred in its cell, filling about 76% of the
cell. Bold readable silhouette, soft dark contact shadow. Consistent scale, lighting
and detail across all 15 cells. The three flat geometric playback symbols in cells 4,
5 and 6 are still bevelled and lit like polished gold castings, matching the rest.

BACKGROUND: flat pure black #000000. No gradient, no vignette, no texture, no glow,
no grid lines, no borders around cells or symbols.

ABSOLUTELY NO TEXT of any kind: no labels, no captions, no numbers, no letters.

The 15 symbols, left to right, top to bottom:
1. A closed oak chest with gold banding and a gold clasp, a gold arrow curving down
   into its lid.
2. The same oak chest with its lid open, a gold arrow curving up out of it.
3. The same oak chest closed, with a bold deep-red #7A1F1F X across its lid.
4. A polished gold triangle pointing right, bevelled edges.
5. Two thick vertical gold bars with rounded ends, side by side.
6. A polished gold triangle pointing right with a thick vertical gold bar hard
   against its right side.
7. A gold arrow pointing down into an open-topped wooden crate.
8. Two gold arrows chasing each other in a circle around a small broken chain link.
9. A fallen gold crown lying on its side with a steel sword driven through it.
10. A two-handled gold victory chalice on a stepped base.
11. A wooden ship's hull with a lowered gangplank and a gold arrow curving up the
    plank into the ship.
12. The same ship and gangplank with the gold arrow curving down the plank away from
    the ship.
13. A wooden siege catapult folded flat onto a transport cart, four small gold arrows
    pointing inward toward it.
14. The same wooden siege catapult erected and braced for firing, four small gold
    arrows pointing outward away from it.
15. A bold, thick, bevelled gold check mark.
```

---

## panel_ornate

**One full 1024 × 1024 canvas. `assets/UI_Gen/panel_ornate.png`.**

The main menu, the lobby, dialogs, the pause menu — anywhere a panel owns the screen
and can afford ornament. This is the piece the reference image is of.

**⚠️ THE NINE-PATCH RULE, AND IT IS THE WHOLE POINT OF THIS PROMPT.** A nine-patch
stretches the four straight edge runs and holds the four corners fixed. So:

- **All ornament lives in the corners.** Dragon heads at the top two corners, tails at
  the bottom two.
- **The four straight runs between the corners are plain, uniform, repeating
  moulding.** No unique feature anywhere along them. A dragon coiling *along* the left
  edge — which is what the old mockups drew — smears the instant the panel is drawn
  at any height but the authored one, and the panel is drawn at a dozen sizes.
- Stretch margins: **256 px on all four sides** of the 1024 canvas, so the ornament
  must fit entirely inside a 256 × 256 corner square and the runs must be clean from
  256 px to 768 px along each edge.
- The centre field must be **flat and even** — it is the region that stretches most.

`main_menu.gd` records that today's panel carries transparent padding, so its gold
edge sits inside its own rect. Ours should not: the gold border runs to the canvas
edge, and any drop shadow is inside the border, not outside it.

```
A single ornate rectangular medieval-fantasy game UI panel, filling the entire
1024x1024 canvas edge to edge.

STRUCTURE, and this is the most important requirement: the panel is designed to be
cut into a nine-slice. ALL ornament is concentrated in the four CORNERS, each fitting
entirely within a 256x256 corner square. The four straight edge runs BETWEEN the
corners are plain, uniform, evenly repeating gold moulding with absolutely no unique
feature, no creature, no crest, no break in the pattern anywhere along their length.
The centre is a large flat even field.

THE CORNERS: two golden dragon heads, one at the top-left corner and one at the
top-right corner, mirrored, jaws forward, coiling into the border. Two golden dragon
tails, one at the bottom-left and one at the bottom-right corner, mirrored, curling
into the border. They do not extend along the edges.

THE EDGE RUNS: a simple raised gold bead-and-reel moulding, the same profile
repeating steadily, identical along all four runs.

THE FIELD: deep chocolate brown #2B1D14 with a very subtle even leather grain, no
vignette, no highlight, no gradient, no pattern, nothing that would look wrong when
stretched.

STYLE: richly rendered semi-realistic game art. Smooth gradients, soft studio
lighting from the upper left, bevelled depth, subtle ambient occlusion, warm
specular sheen on the gold. NOT pixel art. NOT flat vector.

PALETTE: burnished gold, highlight #F2D06B through mid #E5B842 to shadow #8A6A1E,
against deep chocolate brown #2B1D14.

The gold border runs right to the edge of the canvas on all four sides, with no
transparent margin and no drop shadow outside it.

ABSOLUTELY NO TEXT of any kind: no title, no labels, no letters, no numbers. The
panel is completely empty inside.
```

---

## panel_hud

**One full 1024 × 1024 canvas. `assets/UI_Gen/panel_hud.png`.**

The in-game panels — selection panel, resource column, and the backdrop `HudStyle`
adds behind `ResourceHUD` and `Minimap`. **Deliberately plainer than `panel_ornate`.**

Two recorded reasons it must be restrained. `HudPanel` refuses to use today's panel
texture at full-page size because a filled panel at that scale "reads as a smear" —
the pages hand-roll a flat fill with a double gold border instead, and their header
says the texture goes back the moment art exists at that shape. And the selection
panel is a grid of 72 px tiles: a border thick enough to be handsome at 1024 eats a
whole tile at HUD scale.

Stretch margins: **160 px on all four sides.**

```
A single restrained rectangular medieval-fantasy game UI panel, filling the entire
1024x1024 canvas edge to edge.

STRUCTURE, and this is the most important requirement: the panel is designed to be
cut into a nine-slice. The border is a SLIM double gold rule - an outer band and a
thinner inner line with a narrow dark channel between them - running uniformly around
all four sides. The four straight runs are perfectly plain and even. The only
ornament is a small gold corner boss at each of the four corners, each fitting
entirely within a 160x160 corner square.

THE FIELD: deep chocolate brown #2B1D14, flat and even, with a very subtle leather
grain. No vignette, no gradient, no highlight, no pattern, nothing that would look
wrong when stretched to any size.

RESTRAINT IS THE POINT: this panel sits behind dense grids of small buttons. The
border must be thin, quiet and legible, never heavy or busy. No dragons, no
creatures, no filigree, no scrollwork.

STYLE: richly rendered semi-realistic game art. Smooth gradients, soft lighting from
the upper left, gentle bevelled depth on the gold rules, subtle ambient occlusion.
NOT pixel art. NOT flat vector.

PALETTE: burnished gold, highlight #F2D06B through mid #E5B842 to shadow #8A6A1E,
against deep chocolate brown #2B1D14.

The border runs right to the edge of the canvas on all four sides, with no
transparent margin and no drop shadow outside it.

ABSOLUTELY NO TEXT of any kind, and nothing at all inside the panel.
```

---

## banner_alert

**One full 1024 × 1024 canvas, art in a centre band.
`assets/UI_Gen/banner_alert.png`.**

Replaces `toast_banner.png` (184 × 80, roughly 2.3 : 1), which `NoticeToast` draws
messages on. Stretches **horizontally only** — a toast is one line of text at a
variable width — so the left and right ends are fixed caps and the middle run
repeats. Vertically it does not stretch at all.

Horizontal stretch margins: **200 px** from each end of the banner.

```
A single ornate horizontal medieval-fantasy game UI banner ribbon, centred on a
1024x1024 canvas. The banner spans the full width of the canvas and occupies a
horizontal band roughly 440 pixels tall through the vertical centre. Everything
above and below that band is flat pure black #000000.

STRUCTURE, and this is the most important requirement: the banner is designed to
stretch HORIZONTALLY as a nine-slice. Both END CAPS - the leftmost 200 pixels and the
rightmost 200 pixels - carry all the ornament: a small mirrored golden dragon head at
each end, facing inward. The long middle run between them is plain, uniform,
evenly repeating gold moulding above and below a flat field, with no unique feature
anywhere along its length.

THE FIELD: deep chocolate brown #2B1D14, flat and even, framed above and below by a
slim gold rule that runs unbroken from cap to cap.

STYLE: richly rendered semi-realistic game art. Smooth gradients, soft studio
lighting from the upper left, bevelled depth, subtle ambient occlusion, warm specular
sheen on the gold. NOT pixel art. NOT flat vector.

PALETTE: burnished gold, highlight #F2D06B through mid #E5B842 to shadow #8A6A1E,
against deep chocolate brown #2B1D14.

BACKGROUND above and below the banner: flat pure black #000000, no glow, no shadow,
no gradient.

ABSOLUTELY NO TEXT of any kind: no title, no labels, no letters, no numbers. The
banner is completely empty.
```

---

## banner_age

**One full 1024 × 1024 canvas, art in a centre band.
`assets/UI_Gen/banner_age.png`.**

The age advancement header — the top-centre piece that carries "AGE IV: Imperial Age"
and its progress bar. Two things share this asset: a title bar above and a **recessed
empty groove** below it that the progress fill (`sheet_bars`, rows 5–6) draws inside.

The groove must be **empty and unfilled** in the art. If Gemini paints a half-full red
bar into it we cannot draw progress on top without the painted bar showing through.

Horizontal stretch margins: **240 px** from each end.

```
A single ornate horizontal medieval-fantasy game UI header banner, centred on a
1024x1024 canvas. The banner spans the full width and occupies a horizontal band
roughly 520 pixels tall through the vertical centre. Everything above and below that
band is flat pure black #000000.

STRUCTURE: the banner has two stacked parts. The UPPER part is a wide flat title
plate of deep chocolate brown #2B1D14 framed in gold. The LOWER part, directly
beneath it and slightly narrower, is a long EMPTY RECESSED CHANNEL with a polished
gold rim and a dark shadowed interior - an empty progress-bar groove.

CRITICAL: the recessed channel is COMPLETELY EMPTY. It contains no fill, no coloured
bar, no red, no marker, no segments, no progress of any kind. Just an empty dark
shadowed trough with a gold rim.

ORNAMENT: two large mirrored golden dragons, one at each end of the banner, coiling
around the end caps with their heads turned inward over the title plate. All ornament
stays within 240 pixels of each end; the long middle runs of both the title plate and
the groove are plain and uniform.

STYLE: richly rendered semi-realistic game art. Smooth gradients, soft studio
lighting from the upper left, bevelled depth, subtle ambient occlusion, rich warm
specular sheen on the gold. NOT pixel art. NOT flat vector.

PALETTE: burnished gold, highlight #F2D06B through mid #E5B842 to shadow #8A6A1E,
against deep chocolate brown #2B1D14.

BACKGROUND above and below the banner: flat pure black #000000.

ABSOLUTELY NO TEXT of any kind: no title, no age name, no Roman numerals, no letters,
no numbers, no percentage.
```

---

## frame_minimap

**One full 1024 × 1024 canvas. `assets/UI_Gen/frame_minimap.png`.**

`Minimap` draws a 150 px square rotated 45° into a diamond inside a 200 px footprint,
and its own header says the gold frame it draws by hand "approximates an ornate
diamond frame" it never had. This is that frame.

**Does not stretch.** It is drawn at one size, so it can be as ornate as it likes.

The four circular mounts at the corners are where `hud_techtree`, `hud_score`,
`hud_trade` and `hud_chat` sit — `map_icons.txt` fixes their positions: tech tree top
left, score top right, trade bottom left, chat bottom right.

```
A single ornate medieval-fantasy game minimap frame, centred on a 1024x1024 canvas
and filling most of it.

STRUCTURE: a large diamond aperture in the centre - a square rotated 45 degrees -
with its interior completely EMPTY and flat pure black #000000, because a live map is
drawn inside it. The diamond is bordered by a thick ornate gold frame with two
golden dragons coiling along its upper-left and lower-right runs.

At each of the four outer corners of the canvas sits a separate small circular gold
medallion mount - an empty gold ring with a dark recessed interior, sized to hold a
round button. Four identical mounts, one per corner, connected to the diamond frame
by short gold brackets.

CRITICAL: both the diamond interior and all four circular mount interiors are
COMPLETELY EMPTY - flat pure black, no map, no terrain, no symbol, no artwork inside
any of them.

STYLE: richly rendered semi-realistic game art. Smooth gradients, soft studio
lighting from the upper left, bevelled depth, subtle ambient occlusion, rich warm
specular sheen on the gold. NOT pixel art. NOT flat vector.

PALETTE: burnished gold, highlight #F2D06B through mid #E5B842 to shadow #8A6A1E,
against deep chocolate brown #2B1D14.

BACKGROUND everywhere outside the frame: flat pure black #000000.

ABSOLUTELY NO TEXT of any kind.
```

---

## sheet_widgets

**15 pieces, 4 × 4 at 256 px. `assets/UI_Gen/sheet_widgets.png`.**

The small chrome. **Cell 1 is the single most important asset in this whole file** —
it is the tile frame every one of the 103 glyphs is drawn inside, and it is what the
reference image shows.

| cell | id | notes |
|---|---|---|
| 1 | `tile_frame` | the action-tile frame. `ActionSlot` is 72 px |
| 2 | `tile_frame_selected` | `HudAction.selected` — the live stance, the active formation, a researched tech |
| 3 | `tile_frame_disabled` | unimplemented verbs, cooling abilities, unaffordable techs |
| 4 | `portrait_frame` | replaces `hud/portrait_frame.png`, 80 × 80 |
| 5 | `group_slot_ring` | replaces `control_groups/group_slot_ring.png`, 69 × 85 |
| 6 | `badge_round` | the circular resource badge — the green circles in today's set |
| 7–8 | `checkbox_off` `checkbox_on` | settings |
| 9–10 | `radio_off` `radio_on` | lobby options |
| 11–14 | `arrow_down` `arrow_up` `arrow_left` `arrow_right` | **scrollbars and dropdowns only** — see below |
| 15 | `tab_plate` | the per-player chat tabs |

⚠️ **Cells 11–14 are not the detail grid's page arrows.** `SelectionActions` uses the
characters `<` and `>` there and its header records why: at 72 px a caret reads as
navigation in a way no glyph in the pack does. That decision was made once already.

```
A 1024x1024 sprite sheet of 15 medieval-fantasy game UI frames and widgets, arranged
on a strict 4x4 grid of 256x256 cells with no gutters. The bottom-right cell is
completely empty.

STYLE: richly rendered semi-realistic game art. Smooth gradients, soft studio
lighting from the upper left, bevelled depth, subtle ambient occlusion, rich warm
specular sheen on the gold. NOT pixel art. NOT flat vector.

PALETTE: burnished gold, highlight #F2D06B through mid #E5B842 to shadow #8A6A1E,
against deep chocolate brown #2B1D14.

CRITICAL: every frame, ring and box below is EMPTY inside. No symbol, no picture, no
portrait, no content of any kind sits within any of them - they are containers that
will have artwork placed inside them later.

COMPOSITION: each piece centred in its cell, filling about 88% of the cell.
Consistent lighting direction and material across all 15 cells.

BACKGROUND: flat pure black #000000. No grid lines, no cell borders.

ABSOLUTELY NO TEXT of any kind: no labels, no letters, no numbers.

The 15 pieces, left to right, top to bottom:
1. A square tile frame with softly cut corners: a thick burnished gold border around
   an empty deep chocolate brown #2B1D14 field, with a slender golden dragon coiled
   around the border, its head at the top and its tail meeting it at the bottom.
   Ornate but compact. The interior is completely empty.
2. The identical tile frame, but the gold is brighter and hotter with a warm glow
   blooming around the whole border, clearly selected and active.
3. The identical tile frame, but desaturated to dull grey-brown, dimmed and flat with
   no sheen, clearly disabled.
4. A square portrait frame with softly cut corners, a heavier and more ornate gold
   border than piece 1, small gold corner bosses, empty dark interior.
5. A circular ring frame: a thick burnished gold ring with a slender dragon coiled
   around it, empty dark interior.
6. A plain circular badge: a simple polished gold ring around an empty deep chocolate
   brown field, no ornament at all.
7. A small empty square box with a gold rim and a dark recessed interior.
8. The identical box with a bold bevelled gold check mark inside it.
9. A small empty circle with a gold rim and a dark recessed interior.
10. The identical circle with a polished gold sphere filling its centre.
11. A bevelled polished gold triangle pointing down.
12. A bevelled polished gold triangle pointing up.
13. A bevelled polished gold triangle pointing left.
14. A bevelled polished gold triangle pointing right.
15. A small wide tab plate: a shallow rectangle with a gold rim and a deep chocolate
    brown face, its bottom edge open, empty inside.
```

---

## sheet_bars

**7 full-width horizontal pieces. `assets/UI_Gen/sheet_bars.png`.**

Buttons and bars, laid out as **seven stacked rows of 128 px** across the full 1024
width, with the **bottom 128 px band left entirely empty** — that band is this sheet's
watermark reservation, and it is why there are seven rows and not eight.

Every row stretches **horizontally only**, with fixed left and right caps.
Suggested horizontal stretch margin: **80 px** each end.

| row | y range | id | replaces |
|---|---|---|---|
| 1 | 0–128 | `button_normal` | `menu/*_button.png` (nine of them, 94 × 31) |
| 2 | 128–256 | `button_pressed` | — |
| 3 | 256–384 | `button_disabled` | — |
| 4 | 384–512 | `bar_groove` | the empty half of `hud/health_bar.png` |
| 5 | 512–640 | `bar_fill_health` | the filled half |
| 6 | 640–768 | `bar_fill_progress` | the age bar's fill, sits in `banner_age`'s groove |
| 7 | 768–896 | `field_input` | nothing — `TouchLineEdit` has no frame today |
| — | 896–1024 | empty | watermark |

**Nine menu buttons become one.** `play`, `multiplayer`, `settings`, `credits`,
`quit`, `resume`, `main_menu`, `back` and `inventory` are nine separate 94 × 31 PNGs
today, differing only in the word printed on them. One stretchable blank plate plus a
text label replaces all nine — and `inventory_button.png`, which is referenced by
nothing, simply stops existing.

```
A 1024x1024 sprite sheet of 7 wide horizontal medieval-fantasy game UI bars, stacked
in 7 rows across the full width of the canvas. Each row is 128 pixels tall and spans
the entire 1024 pixel width. The bottom 128 pixels of the canvas is completely empty
flat black.

STYLE: richly rendered semi-realistic game art. Smooth gradients, soft studio
lighting from the upper left, bevelled depth, subtle ambient occlusion, warm specular
sheen on gold and a glossy highlight along the top of the filled bars. NOT pixel art.
NOT flat vector.

PALETTE: burnished gold, highlight #F2D06B through mid #E5B842 to shadow #8A6A1E;
deep chocolate brown #2B1D14; deep red #7A1F1F; health red #C4342E.

STRUCTURE, and this is the most important requirement: every bar is designed to
stretch HORIZONTALLY. Each one is perfectly uniform along its length - the same
profile repeating from end to end, with no ornament, no crest, no creature, no break
in the pattern anywhere. Only the extreme left and right ends are capped.

CRITICAL: every bar is completely EMPTY of content. No text, no icon, no marker, no
segment divisions, no percentage.

BACKGROUND: flat pure black #000000 in the gaps between rows and in the bottom band.

ABSOLUTELY NO TEXT of any kind: no labels, no letters, no numbers.

The 7 bars, top to bottom:
1. A wide button plate: a deep red #7A1F1F face with a rounded rectangular shape,
   framed by a slim burnished gold border, lit from above, slightly domed.
2. The identical button plate pressed in: darker, the dome inverted to a shallow
   concave, the highlight moved to the bottom edge.
3. The identical button plate disabled: desaturated to flat grey-brown, no gold sheen,
   dull and lifeless.
4. An empty recessed channel: a long dark shadowed trough with a polished gold rim,
   completely unfilled.
5. A glossy filled bar in health red #C4342E, brightest along the top edge, running
   the full width with slim gold end caps.
6. A glossy filled bar in warm gold, highlight #F2D06B through mid #E5B842, brightest
   along the top edge, running the full width with slim gold end caps.
7. A recessed text field: a long dark chocolate brown #2B1D14 trough with a slim gold
   rim and a soft inner shadow along its top edge, completely empty.
```

---

## After the sheets come back

**What to check before slicing**, in the order the failures actually happen:

1. **Cell alignment.** Gemini drifts off a strict grid. Overlay a 256 px lattice
   before anything else — if symbols are not centred in their cells the sheet is a
   re-roll, not a crop-by-hand job.
2. **The reserved corner is empty**, and the watermark is inside it.
3. **Style drift down the sheet.** Cells 1–4 and cells 12–15 should be lit from the
   same direction with the same gloss. Drift is the usual failure on a 15-cell ask and
   it is only visible when you look at the first row against the last.
4. **No text crept in.** Gemini adds labels to anything grid-shaped.
5. **The empty things are empty** — `banner_age`'s groove, `frame_minimap`'s diamond,
   every frame on `sheet_widgets`.

**Then**: key the black to alpha, slice on the lattice, and downscale. Icons ship as
**100 × 100 RGBA PNG** in `game/assets/ui/icons/` to match the twenty already there —
`ResourceHUD`'s own comment records that a TextureRect's minimum size comes from the
texture's real pixels, so the size is not cosmetic. 256 px sources downscale to that
with room to spare, and keeping the 256 masters means a future HUD at a larger tile
size does not need a re-bake.

**Nothing lands in `game/` until the whole set is ready.** [P8] §4a is explicit: the
Kibyra packs are still required to run the game today, so `UI_Sprites/README.md`, the
`.gitignore` entries and `LICENCES.md` rows 503–510 all stay exactly as they are until
there is something to swap in. Retire them in the same commit that lands the art, or
the next clone gets a game with no panels and a README that says the packs are no
longer needed.

**One consequence worth naming now**: this art is project-owned, so it **commits**.
That retires the download-two-packs-by-hand step, gives a clean checkout a working
HUD for the first time, and makes `licence_audit.py`'s undeclared-UI-files complaint
disappear by construction rather than by declaration.

---

# GENERATED AND SLICED — 2026-08-30

All 14 sheets came back and all 14 are in. **130 pieces cut, 0 flagged.**

```powershell
<venv>\python.exe tools\slice_ui_sheets.py      # -> assets/UI_Gen/sliced/
<venv>\python.exe tools\measure_ninepatch.py    # -> sliced/ninepatch.json
<venv>\python.exe tools\preview_ninepatch.py    # -> sliced/review/ninepatch_*.png
```

The Gemini masters in `assets/UI_Gen/*.jpg` are **committed** — they cannot be
regenerated identically. `sliced/` is derived and gitignored.

## The `.jpg` question, settled

The sheets came back JPEG rather than PNG. **It does not matter here, and the
reason is worth keeping** so it is not re-litigated: JPEG's failure mode is
ringing at hard edges between flat colours — that is pixel art, and this is not.
Smooth gradients on a flat ground are the case it handles best. Measured border
noise is **≤ 6/255 on twelve of the fourteen sheets**, and every icon is
downsampled 256 → 100 on the way out, which averages what ringing there is below
visibility.

The one real rule: **no second JPEG round trip.** Everything the slicer writes is
PNG and the masters are kept.

`sheet_a_command_verbs` is the exception worth knowing about — it came back on a
uniform `#111111` ground (border p99.5 = 18) where the others are true black
(p99.5 = 2). That is Gemini, not JPEG, and it is why the key threshold is derived
per sheet instead of fixed.

## Three things the plan got wrong, found by doing it

**The lattice does not survive contact.** Gemini does not centre cells on a strict
256 px grid and does not keep art inside them — `sheet_widgets` cell 1's dragon
runs off the top of the canvas. A blind `crop(c*256, r*256)` decapitates three of
the four tile frames. The lattice now only **assigns** a piece to a slot; the crop
is the piece's own content bbox grown out of that slot.

**`sheet_bars` is not a lattice at all.** Seven bars of unequal height with unequal
gaps, and the empty band at the bottom put `h // 7`'s last row inside it — so
`field_input` came back EMPTY and four neighbours BLED. It is cut by row
projection now, which needs no guess about bar heights.

**A threshold key punches holes in the artwork.** Half these icons contain large
genuinely dark regions — `act_repair`'s black anvil, `act_garrison`'s shadowed
archway. The background is not "the dark pixels", it is "the dark pixels
**reachable from the border**", so it comes out by flood fill. The anvil survives
intact; verify it in `sliced/review/sheet_a_command_verbs.png`, which composites
every icon over a checkerboard for exactly this reason.

## Measured nine-patch margins

Off the art, not off this file's original guesses. Full table in
`sliced/ninepatch.json`.

| piece | size | margin (L/R/T/B) | use |
|---|---|---|---|
| `panel_hud` | 1024² | 46/46/46/46 → **use 64** | stretch, **verified clean at every size** |
| `panel_ornate` | 1024² | 183/241/178/92 → **use 256** | **tile the edges, do not stretch** |
| `portrait_frame` | 254² | 53/53/52/53 → **use 56** | stretch |
| `tile_frame` | 256×262 | 110/52/126/51 → **use 128** | stretch |
| buttons, bars, `field_input` | ~1010×110 | 23–35 → **use 40** | stretch horizontally only |
| `banner_age` | 1003×344 | 235/229 → **use 240** | stretch horizontally only |
| `banner_alert` | 1024×308 | period 37 → **use 200** | **tile horizontally** |
| `frame_minimap` | 1014² | — | fixed size, no margins |

**⚠️ `panel_ornate`'s bead-and-reel run must be TILED, not stretched**
(`StyleBoxTexture`, `axis_stretch_horizontal/vertical = AXIS_STRETCH_MODE_TILE`).
`preview_ninepatch.py` renders it at 620 × 620, where the 512 px middle is
*compressed* 4.7× and the round beads squash into flat vertical ribbing. It is
obvious in `sliced/review/ninepatch_panel_ornate.png` and invisible in any table —
which is the point of that script existing. `panel_hud` has no repeating element
and stretches perfectly, which is why it is the one that belongs behind dense HUD
grids.

**How the margin numbers were arrived at matters more than the numbers.** Two
earlier versions of `measure_ninepatch.py` produced confident, symmetric, wrong
answers. The first averaged each column over the full height and put
`panel_ornate`'s left margin at **75 px** — its dragons reach ~250 px in, but a
column through one also crosses 700 px of flat field, which dilutes it below any
cut. The second took p99.5 of the same difference *including alpha*, and the
alpha edge's 0 → 255 step drove the noise floor to 255 and collapsed every margin
to zero. The working version compares each column to the one **one period away**,
on RGB only — because these edges are periodic rather than uniform, which is the
same fact that makes them need tiling. **The render test is the ground truth; the
table is a hypothesis.**

## What is left, and it is not mine

The art is cut and keyed. Landing it is game-side work behind the fence:

- **`ActionSlot._FRAME_PATH` must point at `tile_frame.png`**, not at
  `panel_background.png`. Until it does, the new bare glyphs draw on the old
  Kibyra plate and the double-frame is merely inverted rather than fixed.
- The 100 × 100 icons in `sliced/icons/` drop into `game/assets/ui/icons/`.
- `sliced/chrome/` replaces `hud/`, `menu/` and `control_groups/`.
- **In one commit with the licence retirement**, per §4a above — `.gitignore`,
  `assets/UI_Sprites/README.md` and `LICENCES.md` rows 503–510 all move together,
  or a fresh clone gets a HUD with no panels.

## The fonts — chosen 2026-08-30, and they are the easy half of §4b

The owner dropped two families into `assets/UI_Gen/`, extracted to
`assets/UI_Gen/fonts/`:

| role | family | files |
|---|---|---|
| titles | **Cinzel Decorative** | Regular, Bold, Black |
| body / general | **MedievalSharp** | Regular |

**Both are SIL Open Font License 1.1**, verified by reading the `OFL.txt` in each
archive rather than by recognising the names. That matters more than it sounds:
OFL is *redistributable*, which is exactly what Kibyra's terms were not, so the
fonts commit with the art and a clean checkout gets them. `LICENCES.md` needs one
row per family and **the `OFL.txt` files must ship alongside the `.ttf`s** — the
licence requires its own text be included, and it is the one condition here that
is easy to drop by accident.

The other OFL condition worth knowing: both carry a **Reserved Font Name**
(`MedievalSharp`, `Cinzel`). Shipping them unmodified is fine; shipping a
*modified* build still called by that name is not. Nothing in this project
modifies a font, so this is a note rather than a task.

**Still game-side, and still §4b's real content**: nothing loads a font today —
there is no `.ttf` under `game/` and every label draws in Godot's built-in
default. A `Theme` with these two set as the default and title fonts is the
change, and it touches every screen at once, which is why it wants doing in the
same pass as the chrome rather than after it.
