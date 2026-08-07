## One entry from data/ages.json (PLAN.md 9). Phase 0.4.
##
## Ages are indexed from 1 (SimPlayer.age starts at 1), and `ages.json` is a
## LIST rather than an ID-keyed object because age order is the whole meaning of
## the data -- keying it by name would let the file be reordered without anything
## noticing. Advancement is phase 9.2; MVP ships age 1 only.
class_name AgeDef
extends RefCounted

var index: int = 1
var name: String = ""
## Roman numeral for the age header (PLAN.md 9.1 of the roadmap, phase 9.1).
var numeral: String = "I"
var cost: Dictionary = {}
var advance_time_ticks: int = 0


static func from_dict(p_index: int, d: Dictionary) -> AgeDef:
	var a := AgeDef.new()
	a.index = p_index
	a.name = str(d.get("name", "Age %d" % p_index))
	a.numeral = str(d.get("numeral", "I"))
	a.cost = GameDefs.int_map(d.get("cost", {}))
	a.advance_time_ticks = int(d.get("advance_time_ticks", 0))
	return a
