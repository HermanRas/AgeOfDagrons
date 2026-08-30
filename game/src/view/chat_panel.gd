## The CHAT page behind the minimap's top-left corner button (PLAN.md 8.4b).
##
## THE PAGE, NOT THE WIDGET. Everything that was in here -- the voice bar, the player
## tabs, the log, the composer -- moved to `ChatBoard` on 2026-08-30, when the project
## owner asked the lobby to *"duplicate chat panel from mini map button"*. What is left
## is the dimmed full-screen chrome, a title and the two footer buttons; the insides are
## one `ChatBoard`, and `SkirmishScreen` holds another.
##
## Duplicating it was the alternative and would have been two layouts to keep in step --
## and, the day chat gets a transport, two places to wire it into, with the lobby's copy
## the one nobody remembers. `ChatBoard`'s header carries what that transport needs.
##
## The wireframe rules live with the widget: everything is disabled, on purpose, and the
## page says so on its own face because the owner reviews by screenshot.
class_name ChatPanel
extends HudPanel

## The widget this page wraps. Public because it is the whole content: a caller with a
## `ChatPanel` in hand wants `board.show_players(...)`, and hiding it behind forwarding
## methods would mean adding one per feature the board grows.
var board: ChatBoard

var _clear_button: Button


func _init() -> void:
	# The chrome, and it is not optional -- see `HudPanel._init`.
	super()
	set_title("CHAT")

	board = ChatBoard.new()
	board.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.add_child(board)

	# CLEAR / CLOSE. SEND lives in the board's composer row, where a send button belongs
	# -- it sends the thing in the field beside it, and a page-wide footer button is too
	# far from what it acts on to read as one.
	_clear_button = add_button("CLEAR CHAT", Callable())
	_clear_button.disabled = true
	add_close_button()


## Forwarded, because `GameScene` calls this once a tick while the page is open and
## `_chat.board.show_players(...)` at the call site would be reaching through this class
## to do the one thing it exists to do. Everything else goes through `board`.
func show_players(player_state: Dictionary, local_id: int) -> void:
	board.show_players(player_state, local_id)
