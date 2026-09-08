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

**One title card**, `splash_screen`, added 2026-08-30 to replace `Splash_h.jpg`.
It is the only prompt in this file that asks for text, and its section says why.

Total: **15 prompts** — 14 generated and sliced on 2026-08-30, plus the splash.

> **Two more sheets were added 2026-09-08 for the MapMaker** — `sheet_h_mapmaker_tools`
> and `sheet_i_mapmaker_cursors`, in **Part two** at the end of this file. They are
> counted separately but they are **the same art**: same canvas contract, same palette,
> same 256 px cells, same 100 × 100 delivery. The MapMaker's grey chrome is alpha
> scaffolding and it is going to be reskinned to the game's panels and fonts, so its
> icons are game icons that happen to live in the editor. Part two opens with the one
> consequence that has for the code.

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

## splash_screen

**One full 1024 × 1024 canvas. `assets/UI_Gen/splash_screen.png`.**

Replaces the repo-root **`Splash_h.jpg`** (1024 × 572), which becomes
`game/assets/ui/boot_splash.png`. **Delete `Splash_h.jpg` only once the coder
agent has the new one in-game**, not before — it is the splash that ships today.

**Composed square, cropped to 16:9.** `BootScreen` uses
`STRETCH_KEEP_ASPECT_CENTERED` over a `#0E0A06` ground, so any aspect *works* and
is letterboxed — but the game is landscape (`handheld/orientation=4`) and the art
it replaces is 1.79:1. Asking for a full 1024 canvas rather than a centred band
costs nothing and gains everything: the crop is 1024 px wide either way, and a
square master survives a future portrait or tall-tablet layout. **The essential
content must sit inside the centre 16:9 band (y 224–800); everything outside it
is extendable background that we crop away.**

**Leave the lower band clear.** The owner asked for "splash screen / loading
screen" — `BootScreen` is a 2-second hold with tap-to-skip and has no progress
bar today, but asset packs (0.3) will want one, and a "tap to continue" line has
nowhere to go on the current art. One clear strip costs nothing now and is
impossible to add later.

### ⚠️ This is the one prompt that asks for TEXT, and text is Gemini's worst failure

Every other prompt in this file forbids it. A title card is the exception, because
a bevelled gold title with fire behind it is beyond what a font can do — but
**Gemini misspells, doubles letters, and invents glyphs**, and it does it more the
more words you give it. So:

- **Check the spelling letter by letter** before accepting a render. "AGE OF
  DRAGON" is three words and it will still get them wrong sometimes.
- **If three attempts fail, use the text-free variant below** and set the type in
  engine with **Cinzel Decorative**, which was chosen for titles on 2026-08-30 and
  is sitting in `assets/UI_Gen/fonts/` unused. That route is strictly more robust
  and loses only the fire treatment on the letterforms.

```
A landscape title card for a medieval-fantasy real-time strategy game, filling
the entire 1024x1024 canvas.

CRITICAL COMPOSITION RULE: every important element - the dragon, the castle, the
title, the shields - must sit within the horizontal centre band of the image,
between 22% and 78% of the height. The areas above and below that band are
plain extended background only, because they will be cropped away. Nothing that
matters may touch the top or bottom edge of the canvas.

THE SCENE, from back to front:
A weathered parchment field, warm cream and tan, framed by a border of dark
mortared castle stone that runs around all four edges of the canvas. Fine gold
filigree traces the inner edge of the stone border, with a small gold corner
flourish at each corner.

Centred on the parchment, a grey stone castle with four round towers and conical
red-tiled roofs, a portcullis gate, and small pennants flying. Coiled around and
behind the castle, a large ornate GOLDEN DRAGON, serpentine, with outspread
feathered-scale wings framing the castle on both sides, its head in profile on
the left breathing a plume of orange fire that curls across the lower right of
the castle. Embers and sparks drift through the scene.

Flanking the castle at mid height, two heraldic shields: on the left a red shield
bearing a gold rampant lion, on the right a blue shield bearing a silver crescent
moon over crossed swords. Both shields have polished gold rims.

Across the upper part of the scene, a furled gold-edged parchment ribbon banner.
Below the castle, a second smaller gold-edged parchment banner bearing a small
blue shield with a gold cross.

THE TEXT, and it must be spelled EXACTLY as written here:
- On the upper ribbon banner, in small gold capitals: A RENAISSANCE OF FIRE
- Across the centre, as the main title, very large bold gold capitals with a
  strong bevelled three-dimensional edge, a bright specular highlight and a
  faint fire glow behind the letters: AGE OF DRAGON
- Along the lower area, in small gold capitals: A REAL-TIME STRATEGY EPIC
Use no other text anywhere. Do not add a subtitle, a studio name, a version
number, a date or any decorative lettering.

LEAVE THE LOWER STRIP CLEAR: the bottom 12% of the centre band must be plain
parchment with no artwork, no text and no ornament, so a loading bar can be drawn
over it later.

STYLE: richly rendered semi-realistic painted game art. Smooth gradients, warm
cinematic lighting, bevelled three-dimensional depth on the gold, subtle ambient
occlusion, crisp anti-aliased edges, rich specular sheen on metal. NOT pixel art.
NOT flat vector. NOT cel-shaded outline art.

PALETTE: burnished gold, highlight #F2D06B through mid #E5B842 to shadow #8A6A1E;
warm parchment cream #F0E2C0; deep chocolate brown #2B1D14; slate grey castle
stone; ember orange and deep red #7A1F1F for the fire.
```

### The text-free variant, if the title will not come out

Identical prompt with the TEXT block replaced by this, then set the three lines in
engine over the empty banners using Cinzel Decorative:

```
NO TEXT ANYWHERE IN THE IMAGE. No title, no letters, no numbers, no lettering of
any kind. The upper ribbon banner and the lower banner are both COMPLETELY EMPTY
- blank parchment with gold edges, waiting for type to be placed on them later.
Leave a clear horizontal space across the centre of the scene, between the two
shields and above the lower banner, empty of artwork, where a title will be set.
```

### Slicing it

Not a sheet, so `slice_ui_sheets.py` does not touch it. Crop and convert by hand:

```powershell
<venv>\python.exe -c "from PIL import Image; im=Image.open('assets/UI_Gen/splash_screen.png'); im.crop((0,224,1024,800)).save('assets/UI_Gen/sliced/chrome/boot_splash.png')"
```

That yields **1024 × 576**, four pixels taller than the art it replaces and the
same aspect. No alpha — a splash is opaque, and `BootScreen` puts `#0E0A06`
behind it anyway.

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

## Five icon bugs the owner found, and what they were

Reported 2026-08-30: edge artefacts on `abil_heal`, `age_1`, `net_join` and
`tech_blast_furnace`; `tech_bracer` cut off. **Two root causes, both mine, and
neither was in the slicing code the way I expected.**

### The bounding box was being treated as the icon

`grow_within` finds the blob at the centre of a cell. The crop then took a
**rectangle** around it — and a rectangle keeps whatever is inside it.

**THE TIER PIPS ARE A SEPARATE CONNECTED COMPONENT**, which this file caused: it
asked for "small gold pips in the lower right", and Gemini drew several detached
from the glyph. So `tech_bracer`'s bbox found the bracer and not its three pips,
came out at **77% of its cell against its siblings' 90–99%**, and the square crop
around that undersized box sliced the pips in half — which reads exactly like the
icon being cut off, because it is. The same defect from the other side put a
*neighbour's* pips inside `tech_blast_furnace`'s crop.

Fixed by deciding ownership **per blob, by centroid**, and masking alpha to the
blobs a cell owns. A detached pip inside the cell is kept; a neighbour's pip
overlapping the crop is dropped. `tech_bracer` went 77% → 84%,
`tech_blast_furnace` 85% → 92%.

### A glow on black cannot be keyed, and this file asked for one

`abil_heal` was specified with "a soft warm white glow blooming behind it". **A
glow IS partial transparency**, and compositing it over black already destroyed
the information that says so. A flood fill can only answer background-or-not, so
it kept the entire falloff as opaque and the icon shipped with a black disc.

**Two automatic discriminators were tried and both failed on measurement**, which
is why the fix is an explicit list rather than a heuristic:

| discriminator | glow halo | `act_repair`'s black anvil | verdict |
|---|---|---|---|
| luma p25 / p50 | 20 / 29 | 38 / 45 | overlaps — a ramp that feathers the glow makes the anvil half transparent |
| edge energy p10 / p90 | 2.6 / 5.2 | 1.0 / 35.3 | the anvil's *flattest* pixels are flatter than the glow's — a per-pixel cut punches holes in it |

The list wins because it uses information the image does not carry: **this file
specified which cells get a glow.** `GLOW_ICONS` in the slicer is read off the
prompts. For those, alpha ramps with luminance **and the colour is
un-premultiplied against the new alpha** — without that second half a luma-29
pixel at alpha 0.19 renders at 5 and the bloom vanishes instead of blooming.

### A checkerboard is the wrong background for judging this art

It caused two false alarms. `tech_blast_furnace`'s chimney smoke and `abil_heal`'s
bloom are dark, soft-edged art whose alpha is genuinely ambiguous — against grey
squares they read as blobs, against the dark brown field they are drawn on they
are nearly invisible. **The checkerboard's job is finding holes punched in
artwork; it is actively misleading about anything dark and soft.**

`tools/preview_icons_in_tile.py` is the check that settles it — every icon
composited into `tile_frame` at `ActionSlot`'s real geometry, 52 px inside a
72 px tile, at 3× for inspection with a 1× strip alongside so an icon that reads
at 3× and turns to mush at 1× is caught. **Review there, not on the
checkerboard.**

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

### ⚠️ `TEXTURE_FILTER_NEAREST` IS SET IN 15 PLACES AND IS NOW WRONG

Every one of these was correct for the pixel art it was written against, and every
one of them will make the replacement art look crunchy and aliased the moment it is
drawn at any size but 1:1 — which is most of them, since `ActionSlot` draws a
100 px icon at 52 px and `BootScreen` scales the splash to fill a phone.

```
action_slot.gd:102,112   boot_screen.gd:26      game_scene.gd:564
health_bar_view.gd:40,48 hud_panel.gd:257       hud_style.gd:28
main_menu.gd:170         map_preview.gd:39      notice_toast.gd:47
pause_menu.gd:76,147     resource_hud.gd:151    result_screen.gd:167
```

**`map_preview.gd` is the one to think about rather than sweep**: a minimap
preview of discrete tiles may genuinely want nearest. The other fourteen are
photographic-style art being scaled and want `TEXTURE_FILTER_LINEAR`. This is
listed rather than changed because every file in it is behind the fence.

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

---
---

# Part two — the MapMaker (2026-09-08)

Everything above is the **game's** UI, batched for [P8] on 2026-08-30. These two
sheets are for the **MapMaker**, a separate Godot project and a separate program,
requested by the owner on 2026-09-08.

## THESE FOLLOW THE HOUSE STYLE, AND THE SIZE IS THE GAME'S SIZE

**Owner's ruling, 2026-09-08:** *"the map maker as it stands is in alpha / design
phase, it will look like the game, same panels same fonts, render the icons and
cursors the same size as game icons (tech tree) we will scale them in game."*

So Part two is not a second art style. **Same canvas contract, same palette, same
smooth-painted burnished gold, same 4 × 4 grid of 256 px cells, same 100 × 100 RGBA
delivery** as `sheet_d_military_techs` and every other sheet above. Read §"The canvas
contract" and §"Palette" as binding here too — the prompts below quote them in full
because Gemini keeps nothing between prompts, not because anything differs.

**Author for the target, not for today's scaffolding.** The MapMaker's `#212129`
panels and default font are placeholder chrome from PLAN.md §16; the icons outlive
them. Authoring flat grey glyphs to match scaffolding would mean re-rolling both
sheets the day the reskin lands — and a sheet is regenerated whole.

### ⚠️ ONE CONSEQUENCE FOR THE CODE, AND IT IS THE GAME SIDE'S CALL

`ToolIcons.SIZE` is **16 px** today — the toolbar draws icons at the label's font
size, deliberately, because *"an icon taller than the text makes the row grow, and the
toolbar is already four rows of chrome above a canvas that wants every pixel."*

**A bevelled gold glyph does not survive 100 → 16.** A bevel, a gradient and a contact
shadow are all sub-pixel at that reduction; they do not become subtle, they become
grey mud that eats the silhouette. Part one's glyphs are authored at 256 for a
**52–72 px** tile and that ratio is why they read.

That is not a reason to change this art — it is a number the reskin has to move.
**When these land, the toolbar wants icons at 24–32 px minimum**, which means either a
larger font on that row or icons allowed to exceed the label height. Both are choices
the game side owns; naming it here so it is not discovered as "the new icons look
worse than the drawn ones".

Until then `tool_icons.gd`'s code-drawn 16 px glyphs remain correct for the alpha, and
these sheets are the thing that replaces them at the reskin, not before.

## Two corrections to the request, both from the code

**There is no `Place start` button any more, so it needs no icon.** The owner's
screenshot still shows one; `Tool.START` was removed on 2026-09-08 on the owner's own
ruling (*"can we add the start location as a building option … we can use the same
select and erase as normal buildings and remove duplicates"*). The start is now
`ObjectPalette.START_ID`, a palette entry — so it is covered by the **Buildings**
category tile and the ordinary Place/Erase tools. Five tools, not six.

**There is a fifth category coming and it gets a cell.** `object_palette.gd`'s
`CATEGORIES` holds four today with a comment reserving the fifth: *"16.5 adds
`{"id": Category.AREA, "label": "Areas"}` here."* A sheet is regenerated whole, never
one cell (§"How to use this file"), so drawing Areas now costs one of three spare
cells and drawing it later costs the whole sheet.

**One thing being overridden, said out loud so the reasoning is not lost.** `Place`
has no glyph today and that was deliberate: *"the palette's own tile is the picture of
what a place-click will do, and a generic icon beside it would say less than the town
centre already showing in the panel."* The owner has asked for one anyway, which is
their call — but if the toolbar ever looks busy, that is the icon to drop first.

## Where they land, and the one seam

`ToolIcons.for_tool()` is the whole seam — *"nothing else in the tool knows how a
button gets its picture."* The file's own header says so and names itself the place to
change if the owner wants supplied files used instead of drawn ones.

⚠️ **A PNG under `MapMaker/` NEEDS `--import` BEFORE `load()` CAN OPEN IT**, and
`ResourceLoader.exists()` answers **true** for a staged file `load()` cannot open — so a
missing import is a null plus three engine errors rather than an honest failure. That
is 16.3's recorded finding and it is the trap these files walk into. Import once after
adding them.

⚠️ **THE THEME MUST NOT TINT THESE.** `tool_icons.gd` drew one near-white ink partly
because *"a `Button`'s icon is tinted by the theme's `icon_normal_color` in some themes
and left alone in others, and this tool sets neither."* A monochrome glyph survived
that; **full-colour gold art does not** — a theme that tints would recolour the
buildings, the plume and the grass tile alike. When the reskin lands, set
`icon_normal_color` to opaque white explicitly on the toolbar and palette buttons
rather than leaving it to the theme's default.

---

## sheet_h_mapmaker_tools

**12 glyphs, 3 spare cells. `assets/UI_Gen/sheet_h_mapmaker_tools.png`.**

Seven toolbar buttons and five palette categories. **Delivered at 100 × 100 RGBA,
identical to the game's icons**, and the MapMaker scales them down at load — the
owner's ruling, and the reason is that the reskin will want them at tile size, not at
today's 16 px.

| cell | id | for | today |
|---|---|---|---|
| 1 | `mm_undo` | Undo button | no glyph |
| 2 | `mm_redo` | Redo button | no glyph |
| 3 | `mm_brush` | `Tool.PAINT` | drawn in code — pointer + dotted ring |
| 4 | `mm_place` | `Tool.PLACE` | **no glyph on purpose** — see above |
| 5 | `mm_erase` | `Tool.ERASE` | drawn in code — pointer + minus badge |
| 6 | `mm_select` | `Tool.SELECT` | drawn in code — dashed marquee |
| 7 | `mm_move` | `Tool.MOVE` | drawn in code — four-way arrow |
| 8 | `cat_buildings` | palette tab | text only |
| 9 | `cat_units` | palette tab | text only |
| 10 | `cat_resources` | palette tab | text only |
| 11 | `cat_terrain` | palette tab | text only |
| 12 | `cat_areas` | palette tab — **16.5, not built yet** | does not exist |
| 13–15 | — | empty | — |

Cells 3, 5, 6 and 7 replace shapes that already exist in `tool_icons.gd`. **Keep the
same shape language** — a marquee for Select, a four-way for Move, a minus badge for
Erase — because an author who has used the tool for a week has learned those, and the
code's own note explains the minus: *"an X on a cursor means 'cannot' in every other
tool an author has used, and this button removes rather than refuses."* The rendering
changes; the reading does not.

**The four category glyphs are the sheet's one internal grammar.** Cells 8–12 sit
side by side as tabs, so they are asked for as *one object each on a matching gold
plinth* rather than four unrelated illustrations — the same trick `sheet_d` uses down
its columns.

```
A 1024x1024 sprite sheet of 12 medieval-fantasy game UI symbols for a map editor's
toolbar, arranged on a strict 4x4 grid of 256x256 cells with no gutters. The last
three cells of the bottom row are completely empty.

STYLE: richly rendered semi-realistic mobile-game icon art. Smooth gradients, soft
studio lighting from the upper left, bevelled three-dimensional depth, subtle
ambient occlusion, crisp anti-aliased edges, warm specular sheen on metal.
NOT pixel art. NOT flat vector.

PALETTE: burnished gold, highlight #F2D06B through mid #E5B842 to shadow #8A6A1E;
aged blued steel; warm oak; tan leather; cream parchment #F0E2C0.

BOLD SILHOUETTE, NO FRAME: each symbol is a bare object with no border, ring, badge
or plate around it - a reusable frame is drawn separately by the game. The shape must
read on its own, so favour one big blunt form over fine detail, and keep every stroke
and gap generous.

CONSISTENCY: the last five symbols are category tabs seen side by side, so give each
of them the same small polished gold plinth or base to stand on, at the same scale
and the same angle. The first seven are toolbar tools and stand alone with no plinth.

COMPOSITION: each symbol floats alone, centred in its cell, filling about 76% of the
cell. Soft dark contact shadow. Consistent scale, lighting and detail across all 12
cells.

BACKGROUND: flat pure black #000000. No gradient, no vignette, no texture, no glow,
no grid lines, no borders around cells or symbols.

ABSOLUTELY NO TEXT of any kind: no labels, no captions, no numbers, no letters.

The 12 symbols, left to right, top to bottom:
1. A broad polished gold arrow curving anticlockwise back on itself to the left, thick
   and three-dimensional, blunt head.
2. The mirror image of symbol 1: a broad polished gold arrow curving clockwise back on
   itself to the right.
3. A decorator's paintbrush at a diagonal, warm oak handle, gold ferrule, broad dark
   bristle block, tip pointing to the lower left, a smear of green paint at the tip.
4. A polished gold mouse pointer arrow in the lower left with a bold gold plus sign
   floating clear of it in the upper right.
5. A polished gold mouse pointer arrow in the lower left with a bold gold minus bar
   floating clear of it in the upper right.
6. A selection marquee: a gold dashed square outline with a small solid polished gold
   cube handle at each of its four corners.
7. A four-way arrow cross in polished gold: four thick arms with blunt heads pointing
   up, down, left and right from a common boss.
8. A small stone keep with a tiled roof and one dark arched door, standing on a
   polished gold plinth.
9. A helmed soldier's head and shoulders in blued steel with a red plume, standing on
   a matching polished gold plinth.
10. A heap of three oak logs and one gold nugget together, on a matching polished gold
    plinth.
11. An isometric diamond ground tile, grass green on top with a band of brown earth
    below it, on a matching polished gold plinth.
12. A closed loop of gold surveyor's rope pegged out over bare ground into a rounded
    rectangle, empty inside, on a matching polished gold plinth.
```

---

## sheet_i_mapmaker_cursors

**5 cursors, cells 1–5 of the standard 4 × 4 at 256 px.
`assets/UI_Gen/sheet_i_mapmaker_cursors.png`.**

Same grid as every other sheet, so `slice_ui_sheets.py` needs no special case for the
lattice. **Delivered at 100 × 100 like the icons**, and the game scales at load — the
owner's ruling, and it is the right one here for a second reason: a cursor is the one
asset whose display size the OS and the window scale factor argue over, so keeping a
generous master and resizing in code beats baking a 32 px file we cannot re-derive.

⚠️ **A CURSOR IS THE ONE PLACE IN THIS DOCUMENT WHERE AN OUTLINE IS REQUIRED RATHER
THAN FORBIDDEN.** Every glyph above sits in a panel of known colour and gets a *dark
contact shadow*; a cursor floats over grass, water, dark rock and bright sand, and
burnished gold on bright sand is invisible. So these keep the house rendering and add
**a hard dark keyline all the way round** — the gold body reads on the dark half of
the map, the keyline reads on the light half. Losing the keyline is the failure that
makes the whole sheet a re-roll.

**Hotspots, because nobody else will decide them and `Input.set_custom_mouse_cursor`
demands one.** Given as **fractions of the texture**, since the game resizes these and
an absolute pixel hotspot would drift with whatever size it picks:

| id | shape | hotspot | at 100 px | at 32 px |
|---|---|---|---|---|
| `cur_brush` | pointer + ring badge | **(0.02, 0.02)** | (2, 2) | (1, 1) |
| `cur_place` | pointer + plus badge | **(0.02, 0.02)** | (2, 2) | (1, 1) |
| `cur_erase` | pointer + minus badge | **(0.02, 0.02)** | (2, 2) | (1, 1) |
| `cur_select` | crosshair + corner ticks | **(0.5, 0.5)** | (50, 50) | (16, 16) |
| `cur_move` | four-way arrow | **(0.5, 0.5)** | (50, 50) | (16, 16) |

Three share the pointer so the arm reads the same in every mode and only the badge
changes; two are centred because a crosshair or a grab handle that aims from its
corner is simply wrong. **The three pointers must have their tip in the cell's extreme
top-left corner** or the fraction above points at empty pixels — that is the single
thing to check on this sheet before slicing.

⚠️ **STOP RULE, KEPT FROM THE FLAT VERSION OF THIS PROMPT.** A cursor is still the
hardest thing in this file to generate — it needs a hard even keyline that diffusion
models soften, and it needs the tip pinned to a corner rather than composed nicely in
the middle. **If three rolls come back with a soft rim or a floating tip, code-draw
them instead.** `tool_icons.gd` already proves that route works and its header gives
the three reasons. A fourth roll is the expensive outcome, not the code.

```
A 1024x1024 sprite sheet of 5 medieval-fantasy game mouse-cursor symbols, arranged on
a strict 4x4 grid of 256x256 cells with no gutters. Only the first five cells are
used, filled left to right along the top row and then the first cell of the second
row. ALL ELEVEN REMAINING CELLS ARE COMPLETELY EMPTY.

STYLE: richly rendered semi-realistic mobile-game icon art. Smooth gradients, soft
studio lighting from the upper left, bevelled three-dimensional depth, crisp
anti-aliased edges, warm specular sheen on metal. NOT pixel art. NOT flat vector.

PALETTE: burnished gold, highlight #F2D06B through mid #E5B842 to shadow #8A6A1E,
with cream #F0E2C0 catching the brightest faces.

CRITICAL - EVERY SHAPE HAS A HARD DARK KEYLINE: a clean, even, very dark brown-black
outline follows the whole outer edge of every cursor, at least 10 pixels thick and
the same thickness all the way round. Hard edged, not a glow, not a soft shadow, not
a blur. WHY: these float over grass, water, dark rock and bright sand, so the gold
body reads on dark ground and the dark keyline reads on light ground. Without the
keyline the cursor vanishes over half the map.

CRITICAL - CHUNKY AND BLUNT: every arm, stroke and gap must be at least 40 pixels
thick in this 1024 image. These get shrunk hard, so favour one big simple form and
no fine detail.

COMPOSITION: the three pointer-arrow cursors have their sharp tip touching the
EXTREME TOP-LEFT CORNER of their own cell, with the arrow running down and to the
right from it. The two symmetrical cursors are centred exactly in the middle of their
cell. Consistent keyline thickness, scale and lighting across all five.

BACKGROUND: flat mid grey #808080 across the whole canvas - NOT black, because the
dark keylines must be visible against it. No gradient, no vignette, no texture, no
grid lines, no cell borders.

ABSOLUTELY NO TEXT of any kind: no labels, no captions, no numbers, no letters.

The 5 cursors, left to right along the top row then the start of the second row:
1. A classic slanted mouse pointer arrow in polished gold, tip at the extreme
   top-left of the cell, with a small gold ring floating clear of its upper right -
   a paint radius.
2. The identical gold pointer arrow, tip at the extreme top-left, with a bold gold
   plus sign floating clear of its upper right.
3. The identical gold pointer arrow, tip at the extreme top-left, with a bold gold
   minus bar floating clear of its upper right.
4. A large symmetrical crosshair in polished gold, centred exactly in the middle of
   the cell: two thick bars crossing at right angles with a small open square gap at
   their centre, and four short right-angled corner ticks set out from it like
   selection handles.
5. A large symmetrical four-way arrow in polished gold, centred exactly in the middle
   of the cell: four thick arms with blunt heads pointing up, down, left and right
   from a common boss.
```

---

# PART TWO GENERATED AND SLICED — 2026-09-08

Both sheets came back on the first roll and both are in. **18 pieces cut, 0 flagged**,
which takes the whole document to 148. Masters committed as `.jpg`; `sliced/` is
derived and gitignored, so re-cut with:

```powershell
<venv>\python.exe tools\slice_ui_sheets.py      # -> assets/UI_Gen/sliced/
```

`sheet_h`'s 13 land in `sliced/icons/` at 100 × 100 with 256 px masters beside them,
exactly like the game's. `sheet_i`'s 5 land in `sliced/cursors/` with
**`hotspots.json`**, and the review strip for that sheet composites each cursor over
**dark grass and pale sand** rather than the usual checkerboard — a checker is two
light greys and can only answer half the question a keyline exists to answer.

## Three things came back different from the ask, and all three were kept

**`sheet_h` has THIRTEEN glyphs, not twelve.** Gemini drew two buildings — a
crenellated keep and a tiled house — which pushed the categories along by one and put
terrain ahead of resources. The reading order in `slice_ui_sheets.py` is what is *on
the sheet*, not what was asked for. The house is `cat_buildings` because a dwelling is
what a Buildings tab means; the keep ships as **`cat_buildings_keep`, unwired** — a
spare fortification glyph in the house style costs nothing to keep and cannot be
re-rolled identically.

**`sheet_h`'s reserved corner came back WHITE, not empty.** The watermark block fills
cells 15–16 solid white instead of leaving flat black. It does not matter: white is
not background to a flood that keys *dark reachable from the border*, so it stays
opaque and is simply never sliced — no id points at it. It sits 8 px below cell 12's
boundary and did not contaminate it, because `own_components` assigns a blob by its
centroid and that block's centroid is in row 4.

⚠️ **`sheet_i` came back WITH THE CELL GRID DRAWN**, which the prompt forbade twice.
Measured, the lines sit at x,y = 0–1, 254–257, 510–513, 766–769, 1022–1023 — a true
4 px lattice with no drift — and **no artwork pixel comes within 8 px of one**. So a
10 px inset removes them exactly. That is a better outcome than the re-roll the
checklist would otherwise call for, because a re-roll would have to reproduce five
cursors *and* a keyline; but it is only safe because it was measured first, and a
sheet whose art touched a grid line would still be a re-roll.

## What the cursor sheet needed that no other sheet has needed

**The key is inverted, and it is its own cutter** (`slice_grey_grid`). The ground is
flat `#7C7C7C` and the artwork owns every dark pixel, so `key_background`'s "dark
reachable from the border" would have keyed out the keylines and kept the ground —
exactly backwards. Ground is found by colour distance instead.

**Enclosed ground is ground here, which reverses this file's oldest rule.** A dark
pixel surrounded by artwork is artwork — that is `act_repair`'s black anvil, and it is
why the fill exists. It holds because those sheets contain black *subject matter*.
This one contains no grey subject matter: measured, every ground-coloured pixel on the
sheet is neutral (saturation p99.9 = **9**, against the gold's 40+). The 1,492 enclosed
pixels are holes — the brush ring's interior, the crosshair's centre gap, the slots
between its corner ticks — and the first cut shipped them as **a grey disc inside the
ring that read as a blob over grass**. A saturation guard keeps that safe rather than
merely true today.

**Edges are un-composited against grey, not black.** Every other sheet was painted
over black, so the slicer divides colour back out by coverage. Doing that here would
count a half-covered pixel's grey contribution as artwork and put a pale halo round
every cursor, so the ground is subtracted first: `fg = (seen − ground·(1−a)) / a`.

## The hotspots are MEASURED, and they are not the numbers above

The table earlier in this section gives `(0.02, 0.02)` for the three pointers on the
assumption their tip sits in the cell's corner. **Gemini inset them, and the crop is
taken from the content bounding box anyway**, so the fraction has to come off the
pixels that shipped. `hotspots.json` holds what was measured — the foreground pixel
minimising *x + y*, which is the outer corner of the keyline:

| id | fraction | at 100 px | at 32 px |
|---|---|---|---|
| `cur_brush` | (0.10, 0.07) | (10, 7) | (3, 2) |
| `cur_place` | (0.08, 0.09) | (8, 9) | (3, 3) |
| `cur_erase` | (0.07, 0.05) | (7, 5) | (2, 2) |
| `cur_select` | (0.50, 0.50) | (50, 50) | (16, 16) |
| `cur_move` | (0.50, 0.50) | (50, 50) | (16, 16) |

**The three pointers differ from each other and that is correct, not drift.** Each
hotspot is measured on its own image, so each aims at its own tip; the picture shifts a
pixel or two under the pointer when the tool changes, and the aim does not move. Read
these from the JSON rather than copying them — a re-cut re-measures.

### The two slicing notes this section was written against, both now settled

`sheet_h_mapmaker_tools` slices exactly like `sheet_d` — same lattice, same black key,
same 256 → 100 resample. Neither note below applies to it.

- **"The grey ground breaks the key threshold."** It did, and worse than predicted:
  the derived threshold clamps at 40, a `#7C7C7C` border is nowhere near it, so the
  flood found nothing and the whole canvas came out opaque. Fixed by giving the sheet
  its own cutter rather than a threshold override, for the reasons above.
- **"Keep the keyline through the downsample."** Settled at the slicer: the 236 px
  inset cell goes to 100 through LANCZOS, because a hard decimation drops whole pixels
  out of a 10 px rim. **The second resize is still the game side's**, and it is the one
  that matters — going 100 → 32 at load, prefer `INTERPOLATE_LANCZOS` and check the
  rim, or accept `INTERPOLATE_NEAREST` and a slightly ragged edge over a soft one.

### Still open, and it belongs to the game side

Nothing in the art is blocked. What is left is wiring, and the three things it has to
get right are recorded above rather than here: `--import` before `load()`,
`icon_normal_color` set to white so the theme cannot tint gold art, and
`ToolIcons.SIZE` growing past 16 px at the reskin. `ToolIcons.for_tool()` is the whole
seam.
