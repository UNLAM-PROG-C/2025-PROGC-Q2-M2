extends Node

@onready var grid_player_1 = $Player1Panel/Player1Board
@onready var grid_player_2 = $Player2Panel/Player2Board

const GRID_SIZE := 10
const CELL_PIXEL_SIZE := 60
const TILE_ATLAS := preload("res://assets/cells.png")
const TILE_RECTS := {
	"base": Rect2i(Vector2i(73, 98), Vector2i(428, 393)),
	"hit": Rect2i(Vector2i(535, 98), Vector2i(415, 393)),
	"miss": Rect2i(Vector2i(73, 525), Vector2i(428, 393)),
	"hover": Rect2i(Vector2i(535, 525), Vector2i(415, 393)),
}

const CellButton = preload("res://scenes/game/cell_button.tscn")

enum CellVisualState {
	BASE,
	HIT,
	MISS,
}

# This will be the grid for the current player
var button_grid_player_1 := []
# This will be the grid for the oponent
var button_grid_player_2 := []
var player_cell_states := []
var opponent_cell_states := []
var pre_start_mode := true
var current_ship_size := 0
var current_orientation := "horizontal" 
var highlighted_cells: Array[Vector2i] = []
var last_hover_start := Vector2i(-1, -1)
var last_hover_end := Vector2i(-1, -1)
var cell_styles := {}
var hover_style: StyleBoxTexture

func _input(event):
	if event.is_action_released("rotate"):
		if current_orientation == "horizontal":
			current_orientation = "vertical"
		else:
			current_orientation = "horizontal"
		_on_cell_hover_enter(last_hover_start.x, last_hover_start.y)

func _ready() -> void:
	_init_styles()
	for row in range(GRID_SIZE):
		var row_array := []
		var state_row := []
		for col in range(GRID_SIZE):
			var btn = CellButton.instantiate()
			btn.name = "Cell_%d_%d" % [row, col]
			btn.text = ""
			btn.custom_minimum_size = Vector2(CELL_PIXEL_SIZE, CELL_PIXEL_SIZE)
			btn.focus_mode = Control.FOCUS_NONE
			btn.pressed.connect(_on_cell_pressed.bind(row, col))
			btn.mouse_entered.connect(_on_cell_hover_enter.bind(row, col))
			btn.mouse_exited.connect(_on_cell_hover_exit)
			_apply_style(btn, CellVisualState.BASE, false, true)
			grid_player_1.add_child(btn)
			row_array.append(btn)
			state_row.append(CellVisualState.BASE)
		button_grid_player_1.append(row_array)
		player_cell_states.append(state_row)
	
	for row in range(GRID_SIZE):
		var row_array := []
		var state_row := []
		for col in range(GRID_SIZE):
			var btn = CellButton.instantiate()
			btn.name = "Cell_%d_%d" % [row, col]
			btn.text = ""
			btn.custom_minimum_size = Vector2(CELL_PIXEL_SIZE, CELL_PIXEL_SIZE)
			btn.focus_mode = Control.FOCUS_NONE
			btn.pressed.connect(_hit_boat.bind(row, col))
			btn.disabled = true
			_apply_style(btn, CellVisualState.BASE, true, false)
			grid_player_2.add_child(btn)
			row_array.append(btn)
			state_row.append(CellVisualState.BASE)
		button_grid_player_2.append(row_array)
		opponent_cell_states.append(state_row)


func _hit_boat(x: int, y: int):
	if pre_start_mode:
		return

	var payload := PackedByteArray([x, y])
	ConnectionState.send_message(ConnectionState.ClientMessageType.HIT, payload)


func _on_cell_pressed(row: int, col: int):
	print("Button at [%d %d] pressed!" % [row,col])
	if last_hover_start.x == -1:
		return
	var payload := PackedByteArray([
		last_hover_start.x,
		last_hover_start.y,
		last_hover_end.x,
		last_hover_end.y,
	])
	ConnectionState.send_message(ConnectionState.ClientMessageType.PLACE_BOAT, payload)
	

func _on_cell_hover_enter(row: int, col: int):
	clear_highlight()
	
	last_hover_start = Vector2i(row, col)
	var cells_to_highlight: Array[Vector2i] = []
	var r := row
	var c := col
	
	for i in range(current_ship_size):
		if current_orientation == "horizontal":
			c = col + i
			r = row
		else:
			c = col
			r = row + i

		# Stop if outside the grid
		if r >= GRID_SIZE or c >= GRID_SIZE:
			return

		var button: Button = button_grid_player_1[r][c]
		if button.disabled or player_cell_states[r][c] != CellVisualState.BASE:
			return

		cells_to_highlight.append(Vector2i(r, c))

	# The last valid cell is your "end"
	last_hover_end = Vector2i(r, c)

	# Highlight
	for coords in cells_to_highlight:
		var row_idx: int = coords.x
		var col_idx: int = coords.y
		var button: Button = button_grid_player_1[row_idx][col_idx]
		if button.disabled or player_cell_states[row_idx][col_idx] != CellVisualState.BASE:
			continue
		_apply_hover_override(button)
		highlighted_cells.append(Vector2i(row_idx, col_idx))

func _on_cell_hover_exit():
	clear_highlight()

func clear_highlight():
	for coords in highlighted_cells:
		var row_idx: int = coords.x
		var col_idx: int = coords.y
		var button: Button = button_grid_player_1[row_idx][col_idx]
		_apply_style(button, player_cell_states[row_idx][col_idx], button.disabled, true)
	highlighted_cells.clear()
	last_hover_start = Vector2i(-1, -1)
	last_hover_end = Vector2i(-1, -1)

func switch_to_start():
	if not pre_start_mode:
		return
	else:
		switch_to_waiting_for_other_player()
		for row in button_grid_player_2:
			for button in row:
				button.disabled = false
		_refresh_opponent_styles()
	pre_start_mode = false

func switch_to_waiting_for_other_player():
	clear_highlight()
	for row_idx in range(GRID_SIZE):
		for col_idx in range(GRID_SIZE):
			var button: Button = button_grid_player_1[row_idx][col_idx]
			_apply_style(button, player_cell_states[row_idx][col_idx], true, true)

func update_player_cell_from_value(row: int, col: int, value: int) -> void:
	match value:
		2:
			set_player_cell_state(row, col, CellVisualState.HIT, true)
		3:
			set_player_cell_state(row, col, CellVisualState.MISS, true)
		1:
			set_player_cell_state(row, col, CellVisualState.BASE, true)
		_:
			var button: Button = button_grid_player_1[row][col]
			var should_disable := button.disabled
			if pre_start_mode:
				should_disable = false
			set_player_cell_state(row, col, CellVisualState.BASE, should_disable)

func update_opponent_cell_from_value(row: int, col: int, value: int, disabled: bool) -> void:
	match value:
		2:
			set_opponent_cell_state(row, col, CellVisualState.HIT, disabled)
		3:
			set_opponent_cell_state(row, col, CellVisualState.MISS, disabled)
		_:
			set_opponent_cell_state(row, col, CellVisualState.BASE, disabled)

func set_player_cell_state(row: int, col: int, state: int, disabled_override: Variant = null) -> void:
	player_cell_states[row][col] = state
	var button: Button = button_grid_player_1[row][col]
	var disabled_state := button.disabled
	if disabled_override != null:
		disabled_state = disabled_override
	_apply_style(button, state, disabled_state, true)
	if state == CellVisualState.BASE and not disabled_state and highlighted_cells.has(Vector2i(row, col)):
		_apply_hover_override(button)

func set_opponent_cell_state(row: int, col: int, state: int, disabled: bool) -> void:
	opponent_cell_states[row][col] = state
	var button: Button = button_grid_player_2[row][col]
	_apply_style(button, state, disabled, false)

func _refresh_opponent_styles() -> void:
	for row_idx in range(GRID_SIZE):
		for col_idx in range(GRID_SIZE):
			var button: Button = button_grid_player_2[row_idx][col_idx]
			_apply_style(button, opponent_cell_states[row_idx][col_idx], button.disabled, false)

func _apply_hover_override(button: Button) -> void:
	button.add_theme_stylebox_override("normal", hover_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", hover_style)

func _init_styles() -> void:
	if not cell_styles.is_empty():
		return
	cell_styles[CellVisualState.BASE] = _create_style(TILE_RECTS["base"])
	cell_styles[CellVisualState.HIT] = _create_style(TILE_RECTS["hit"])
	cell_styles[CellVisualState.MISS] = _create_style(TILE_RECTS["miss"])
	hover_style = _create_style(TILE_RECTS["hover"])

func _create_style(region: Rect2i) -> StyleBoxTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = TILE_ATLAS
	atlas.region = region
	var style := StyleBoxTexture.new()
	style.texture = atlas
	style.draw_center = true
	style.set_expand_margin_all(0)
	return style

func _apply_style(button: Button, state: int, disabled: bool, allow_hover: bool) -> void:
	var style: StyleBoxTexture = cell_styles.get(state, cell_styles[CellVisualState.BASE])
	button.disabled = disabled
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("disabled", style)
	button.add_theme_stylebox_override("pressed", style)
	if allow_hover and not disabled and state == CellVisualState.BASE:
		button.add_theme_stylebox_override("hover", hover_style)
	else:
		button.add_theme_stylebox_override("hover", style)
