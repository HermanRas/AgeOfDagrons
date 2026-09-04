## ⚠️ **NOT THE GAME'S `MapGenerator`. A ONE-ENUM STAND-IN, AND THE SECOND FILE IN `format/`
## THAT IS NOT A VERBATIM COPY** — see `format/sim_world.gd`, which is the same trick for the
## same reason.
##
## `format/map_validator.gd` IS verbatim, and one line of it reads
## `MapGenerator.Type.ARCHIPELAGO` (`MapValidator._is_sea_map`). That is the whole dependency:
## the validator asks a map what TYPE it is, because the archipelago's connectivity claim is
## different by intent rather than relaxed. The game's real `map_generator.gd` is ~1,500 lines
## of noise fields, veins, herds and copses that this tool has no use for and must not carry —
## **authoring a map by hand and generating one are opposite jobs.**
##
## **The shim wins because it keeps `map_validator.gd` HASHABLE.** An edited copy can never be
## checked against its original: the check would fail by design and therefore be turned off,
## which would leave the tool's opinion about a map free to drift from the game's — the exact
## failure PLAN.md §16 decision 3 exists to prevent, and the reason `MapDocument.seats()`
## records that its own duplication is the *one* duplication in this tool.
##
## ## HOW THIS FILE IS KEPT HONEST, SINCE IT CANNOT BE HASHED
##
## `FormatGuard` checks it by **declaration**: it reads the game's `map_generator.gd` as text,
## pulls out the `enum Type { ... }` line, and compares it to the one below. So the day a map
## type is added or — much worse — inserted in the MIDDLE, this tool says so and refuses to
## save.
##
## ⚠️ **THAT MIDDLE CASE IS WHY THE WHOLE ENUM IS CHECKED AND NOT JUST THE ONE NAME THE
## VALIDATOR USES.** The game's own header spells out the hazard: *"`MatchConfig.map_type` is
## stored as an int and a saved map records it (2.4c), so inserting a type in the middle would
## silently turn every recorded Desert into a Forest."* A tool that only knew
## `ARCHIPELAGO` existed would go on comparing against the wrong number and calling sea maps
## land maps, with nothing failing anywhere.
##
## ⚠️ **DO NOT GROW THIS FILE.** If something here starts needing the generator itself, that is
## the tool reaching into content generation. Raise it rather than adding a second stub.
class_name MapGenerator
extends RefCounted

## The map types a generated map can be.
##
## **MUST MATCH the game's `src/sim/map_generator.gd`, ORDER INCLUDED.** Checked at startup by
## declaration, not by hash — see the class comment.
enum Type { RANDOM, ISLAND, RIVER, DESERT, FOREST, ARCHIPELAGO }
