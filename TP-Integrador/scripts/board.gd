extends Node

@onready var grid_player_1 = $Player1Panel/Player1Board
@onready var grid_player_2 = $Player2Panel/Player2Board
@onready var player_ships_overlay: Node2D = $Player1Panel/Player1Overlay
@onready var player_effects_overlay: Node2D = $Player1Panel/Player1Effects
@onready var opponent_effects_overlay: Node2D = $Player2Panel/Player2Effects
@onready var preview_overlay: Node2D = $Player1Panel/Player1Preview
@onready var status_panel: Panel = get_parent().get_node("StatusPanel")
@onready var phase_label: Label = status_panel.get_node("MarginContainer/VBoxContainer/PhaseLabel")
@onready var turn_label: Label = status_panel.get_node("MarginContainer/VBoxContainer/TurnLabel")
@onready var placement_container: HBoxContainer = status_panel.get_node("MarginContainer/VBoxContainer/PlacementContainer")
@onready var player_name_label: Label = status_panel.get_node("MarginContainer/VBoxContainer/PlayerNameLabel")
@onready var opponent_name_label: Label = status_panel.get_node("MarginContainer/VBoxContainer/OpponentNameLabel")

const GRID_SIZE := 10
const CELL_PIXEL_SIZE := 60
const TILE_ATLAS := preload("res://assets/cells.png")
const TILE_RECTS := {
	"base": Rect2i(Vector2i(73, 98), Vector2i(428, 393)),
	"hit": Rect2i(Vector2i(535, 98), Vector2i(415, 393)),
	"miss": Rect2i(Vector2i(73, 525), Vector2i(428, 393)),
	"hover": Rect2i(Vector2i(535, 525), Vector2i(415, 393)),
}

const HIT_ANIMATION_ATLAS := preload("res://assets/hit_animation.png")
const HIT_ANIMATION_BOUNDS := [
	Vector4i(84, 287, 134, 388),
	Vector4i(330, 602, 109, 388),
	Vector4i(642, 932, 91, 411),
]
const HIT_ANIMATION_PHASE_TIME := 0.2
const HIT_ANIMATION_TILE_DELAY := 0.5

const SHIP_ATLAS := preload("res://assets/ships_sheet.png")
const SHIP_RECTS := {
	"portaaviones": Rect2i(Vector2i(47, 150), Vector2i(867, 160)),
	"acorazado": Rect2i(Vector2i(84, 394), Vector2i(756, 142)),
	"crucero": Rect2i(Vector2i(202, 567), Vector2i(563, 117)),
	"destructor": Rect2i(Vector2i(51, 726), Vector2i(338, 93)),
	"submarino": Rect2i(Vector2i(493, 730), Vector2i(442, 89)),
}

const SHIP_ORDER_BY_LENGTH := {
	5: ["portaaviones"],
	4: ["acorazado"],
	3: ["crucero", "submarino"],
	2: ["destructor"],
}

const PLACEMENT_SEQUENCE :Array[int]= [5, 4, 3, 3, 2, 2]
const PLACEMENT_NAMES := [
	"Portaaviones",
	"Acorazado",
	"Crucero",
	"Submarino",
	"Destructor 1",
	"Destructor 2",
]

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
var player_raw_values := []
var opponent_raw_values := []
var pre_start_mode := true
var current_ship_size := 0
var current_orientation := "horizontal" 
var highlighted_cells: Array[Vector2i] = []
var last_hover_start := Vector2i(-1, -1)
var last_hover_end := Vector2i(-1, -1)
var cell_styles := {}
var hover_style: StyleBoxTexture
var ship_textures_by_length := {}
var placement_icon_nodes: Array = []
var placed_ship_counts := {2: 0, 3: 0, 4: 0, 5: 0}
var placement_progress := 0
var preview_sprite: Sprite2D
var explosion_textures: Array[Texture2D] = []
var player_explosions := {}
var opponent_explosions := {}
var opponent_destroyed_ship_keys := {}
var player_ship_layout: Array = []
var player_display_name: String = ""
var opponent_display_name: String = ""
var last_status_header: int = -1
var last_status_is_player_turn: bool = false
var interactions_enabled: bool = false
var player_destroyed_ship_keys := {}


func _input(event):
	if not (event is InputEventKey):
		return

	# Solo nos interesa cuando se presiona (no cuando se mantiene apretada)
	if not event.pressed or event.echo:
		return

	# Solo permitir rotar mientras estamos en la fase de colocación
	if not pre_start_mode or current_ship_size <= 0:
		return

	# Flechas izquierda / derecha → orientación horizontal
	if event.keycode == KEY_LEFT or event.keycode == KEY_RIGHT:
		if current_orientation != "horizontal":
			current_orientation = "horizontal"
			if last_hover_start.x >= 0:
				_on_cell_hover_enter(last_hover_start.x, last_hover_start.y)

	# Flechas arriba / abajo → orientación vertical
	elif event.keycode == KEY_UP or event.keycode == KEY_DOWN:
		if current_orientation != "vertical":
			current_orientation = "vertical"
			if last_hover_start.x >= 0:
				_on_cell_hover_enter(last_hover_start.x, last_hover_start.y)


func _ready() -> void:
	_init_styles()
	_init_ship_textures()
	_init_explosion_textures()
	_init_status_ui()
	_refresh_name_labels()
	_update_placement_icons(0)
	for row in range(GRID_SIZE):
		var row_array := []
		var state_row := []
		var raw_row := []
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
			raw_row.append(0)
		button_grid_player_1.append(row_array)
		player_cell_states.append(state_row)
		player_raw_values.append(raw_row)
	
	for row in range(GRID_SIZE):
		var row_array := []
		var state_row := []
		var raw_row := []
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
			raw_row.append(0)
		button_grid_player_2.append(row_array)
		opponent_cell_states.append(state_row)
		opponent_raw_values.append(raw_row)


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
	_remember_player_ship(last_hover_start, last_hover_end)
	clear_highlight()
	

func _on_cell_hover_enter(row: int, col: int):
	clear_highlight()
	if current_ship_size <= 0 or placement_progress >= PLACEMENT_SEQUENCE.size():
		return
	_hide_preview()

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
			_hide_preview()
			return

		var button: Button = button_grid_player_1[r][c]
		if button.disabled or player_cell_states[r][c] != CellVisualState.BASE:
			_hide_preview()
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

	_show_preview_for_cells(cells_to_highlight)

func _on_cell_hover_exit():
	clear_highlight()

func clear_highlight():
	_hide_preview()
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
	_clear_all_explosions(false)
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

func handle_state_payload(_payload: PackedByteArray) -> void:
	_process_destroyed_opponent_ships()

func update_player_cell_from_value(row: int, col: int, value: int) -> void:
	player_raw_values[row][col] = value
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
			
	_process_destroyed_player_ships()

func update_opponent_cell_from_value(row: int, col: int, value: int, disabled: bool) -> void:
	opponent_raw_values[row][col] = value
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
	if state == CellVisualState.HIT:
		_trigger_player_explosion(row, col)
	else:
		_clear_cell_explosion(row, col, player_explosions)
	if state == CellVisualState.BASE and not disabled_state and highlighted_cells.has(Vector2i(row, col)):
		_apply_hover_override(button)

func set_opponent_cell_state(row: int, col: int, state: int, disabled: bool) -> void:
	opponent_cell_states[row][col] = state
	var button: Button = button_grid_player_2[row][col]
	_apply_style(button, state, disabled, interactions_enabled)

func _refresh_opponent_styles() -> void:
	for row_idx in range(GRID_SIZE):
		for col_idx in range(GRID_SIZE):
			var button: Button = button_grid_player_2[row_idx][col_idx]
			_apply_style(button, opponent_cell_states[row_idx][col_idx], button.disabled, interactions_enabled)

func _apply_hover_override(button: Button) -> void:
	button.add_theme_stylebox_override("normal", hover_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", hover_style)

func _hide_preview() -> void:
	if preview_sprite and is_instance_valid(preview_sprite):
		preview_sprite.visible = false

func _show_preview_for_cells(cells: Array[Vector2i]) -> void:
	if placement_progress >= PLACEMENT_SEQUENCE.size():
		_hide_preview()
		return
	if current_ship_size <= 0:
		_hide_preview()
		return
	if cells.is_empty():
		_hide_preview()
		return
	if preview_overlay == null:
		return
	var texture := _get_sequence_texture_for_index(placement_progress)
	if texture == null:
		_hide_preview()
		return
	if preview_sprite == null or !is_instance_valid(preview_sprite):
		preview_sprite = Sprite2D.new()
		preview_sprite.centered = true
		preview_sprite.z_index = 3
		preview_overlay.add_child(preview_sprite)
	preview_sprite.texture = texture
	var horizontal := true
	if cells.size() > 1 and cells[0].x != cells[1].x:
		horizontal = false
	var min_row := cells[0].x
	var min_col := cells[0].y
	for coords in cells:
		min_row = min(min_row, coords.x)
		min_col = min(min_col, coords.y)
	var target_size: Vector2
	var tex_size := texture.get_size()
	target_size = Vector2(cells.size() * CELL_PIXEL_SIZE, CELL_PIXEL_SIZE)

	preview_sprite.scale = Vector2(target_size.x / tex_size.x, target_size.y / tex_size.y)
		

	if horizontal:
		preview_sprite.rotation = 0.0
	else:
		target_size = Vector2(target_size.y, target_size.x)
		preview_sprite.rotation = -PI / 2.0
	preview_sprite.position = Vector2(min_col, min_row) * CELL_PIXEL_SIZE + target_size / 2.0
		
	
	preview_sprite.visible = true

func rebuild_player_ships(payload: PackedByteArray) -> void:
	if not player_ships_overlay:
		return
	for child in player_ships_overlay.get_children():
		child.queue_free()

	var any_ship := false
	for value in payload.slice(2, 2 + GRID_SIZE * GRID_SIZE):
		if _is_ship_value(value):
			any_ship = true
			break
	if not any_ship:
		player_ship_layout.clear()

	var visited := []
	for _row in range(GRID_SIZE):
		var row_flags: Array[bool] = []
		for _col in range(GRID_SIZE):
			row_flags.append(false)
		visited.append(row_flags)

	var ships_found: Array = []
	var valid_layout: Array = []

	for ship_data in player_ship_layout:
		var stored_ship: Dictionary = ship_data
		if _ship_layout_matches_board(payload, stored_ship):
			var cells: Array[Vector2i] = _get_ship_cells(stored_ship)
			_mark_cells_visited(visited, cells)
			var ship_dict := {
				"length": int(stored_ship.get("length", 0)),
				"horizontal": bool(stored_ship.get("horizontal", true)),
				"start_row": stored_ship.get("start_row", 0),
				"start_col": stored_ship.get("start_col", 0),
				"used": false,
			}
			ships_found.append(ship_dict)
			valid_layout.append(stored_ship)
	player_ship_layout = valid_layout

	for row in range(GRID_SIZE):
		for col in range(GRID_SIZE):
			var visited_row: Array[bool] = visited[row] as Array[bool]
			if visited_row[col]:
				continue
			var value := _get_player_cell_value(payload, row, col)
			if not _is_ship_value(value):
				continue
			var ship_info := _collect_ship(payload, row, col, visited)
			var length: int = ship_info.get("length", 0)
			if length < 2:
				continue
			ship_info["used"] = false
			ships_found.append(ship_info)
			_store_layout_entry(
				ship_info.get("start_row", 0),
				ship_info.get("start_col", 0),
				length,
				bool(ship_info.get("horizontal", true))
			)

	placed_ship_counts = {2: 0, 3: 0, 4: 0, 5: 0}
	for ship_dict in ships_found:
		var length: int = ship_dict.get("length", 0)
		if placed_ship_counts.has(length):
			placed_ship_counts[length] = placed_ship_counts[length] + 1
		ship_dict["used"] = false

	placement_progress = min(ships_found.size(), PLACEMENT_SEQUENCE.size())
	for i in range(min(PLACEMENT_SEQUENCE.size(), ships_found.size())):
		var expected_length: int = PLACEMENT_SEQUENCE[i]
		var idx := _find_unassigned_ship(ships_found, expected_length)
		if idx == -1:
			continue
		var ship_data: Dictionary = ships_found[idx]
		ship_data["used"] = true
		var texture := _get_sequence_texture_for_index(i)
		if texture == null:
			continue
		_spawn_ship_sprite(
			texture,
			expected_length,
			ship_data.get("start_row", 0),
			ship_data.get("start_col", 0),
			ship_data.get("horizontal", true)
		)

	_update_placement_icons(current_ship_size)

func _get_player_cell_value(payload: PackedByteArray, row: int, col: int) -> int:
	return payload[2 + row * GRID_SIZE + col]

func _is_ship_value(value: int) -> bool:
	return value == 1 or value == 2

func _ship_layout_matches_board(payload: PackedByteArray, ship_data: Dictionary) -> bool:
	var cells: Array[Vector2i] = _get_ship_cells(ship_data)
	if cells.is_empty():
		return false
	for coord in cells:
		var value := _get_player_cell_value(payload, coord.x, coord.y)
		if not _is_ship_value(value):
			return false
	return true

func _get_ship_cells(ship_data: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var length: int = ship_data.get("length", 0)
	if length <= 0:
		return cells
	var horizontal := bool(ship_data.get("horizontal", true))
	var start_row: int = ship_data.get("start_row", 0)
	var start_col: int = ship_data.get("start_col", 0)
	for i in range(length):
		var row: int
		var col: int
		if horizontal:
			row = start_row
			col = start_col + i
		else:
			row = start_row + i
			col = start_col
		if row < 0 or row >= GRID_SIZE or col < 0 or col >= GRID_SIZE:
			continue
		cells.append(Vector2i(row, col))
	return cells

func _mark_cells_visited(visited: Array, cells: Array[Vector2i]) -> void:
	for coord in cells:
		var visited_row: Array[bool] = visited[coord.x] as Array[bool]
		if coord.y >= 0 and coord.y < visited_row.size():
			visited_row[coord.y] = true

func _collect_ship(payload: PackedByteArray, row: int, col: int, visited: Array) -> Dictionary:
	visited[row][col] = true
	var coords: Array[Vector2i] = [Vector2i(row, col)]
	var horizontal := false
	if col + 1 < GRID_SIZE and _is_ship_value(_get_player_cell_value(payload, row, col + 1)):
		horizontal = true
	elif col - 1 >= 0 and _is_ship_value(_get_player_cell_value(payload, row, col - 1)):
		horizontal = true
	elif row + 1 < GRID_SIZE and _is_ship_value(_get_player_cell_value(payload, row + 1, col)):
		horizontal = false
	elif row - 1 >= 0 and _is_ship_value(_get_player_cell_value(payload, row - 1, col)):
		horizontal = false
	else:
		horizontal = true

	if horizontal:
		var cc := col + 1
		while cc < GRID_SIZE and _is_ship_value(_get_player_cell_value(payload, row, cc)):
			if not visited[row][cc]:
				visited[row][cc] = true
				coords.append(Vector2i(row, cc))
			cc += 1
		cc = col - 1
		while cc >= 0 and _is_ship_value(_get_player_cell_value(payload, row, cc)):
			if not visited[row][cc]:
				visited[row][cc] = true
				coords.append(Vector2i(row, cc))
			cc -= 1
	else:
		var rr := row + 1
		while rr < GRID_SIZE and _is_ship_value(_get_player_cell_value(payload, rr, col)):
			if not visited[rr][col]:
				visited[rr][col] = true
				coords.append(Vector2i(rr, col))
			rr += 1
		rr = row - 1
		while rr >= 0 and _is_ship_value(_get_player_cell_value(payload, rr, col)):
			if not visited[rr][col]:
				visited[rr][col] = true
				coords.append(Vector2i(rr, col))
			rr -= 1

	var start_row := coords[0].x
	var start_col := coords[0].y
	for pos in coords:
		start_row = min(start_row, pos.x)
		start_col = min(start_col, pos.y)

	return {
		"length": coords.size(),
		"horizontal": horizontal,
		"start_row": start_row,
		"start_col": start_col,
		"used": false,
	}

func _find_unassigned_ship(ships: Array, length: int) -> int:
	for i in range(ships.size()):
		var ship: Dictionary = ships[i]
		if int(ship.get("length", 0)) == length and ship.get("used", false) == false:
			return i
	return -1

func _remember_player_ship(start: Vector2i, end: Vector2i) -> void:
	if start.x < 0 or end.x < 0:
		return
	var horizontal := start.x == end.x
	var length := 1
	if horizontal:
		length = abs(end.y - start.y) + 1
	else:
		length = abs(end.x - start.x) + 1
	var start_row :int = min(start.x, end.x)
	var start_col :int = min(start.y, end.y)
	_store_layout_entry(start_row, start_col, length, horizontal)

func _store_layout_entry(start_row: int, start_col: int, length: int, horizontal: bool) -> void:
	if length < 2:
		return
	for existing in player_ship_layout:
		if existing.get("start_row", -1) == start_row \
				and existing.get("start_col", -1) == start_col \
				and int(existing.get("length", 0)) == length \
				and bool(existing.get("horizontal", false)) == horizontal:
			return
	player_ship_layout.append({
		"start_row": start_row,
		"start_col": start_col,
		"length": length,
		"horizontal": horizontal,
	})

func update_player_names(player_name: String, opponent_name: String) -> void:
	player_display_name = player_name.strip_edges()
	opponent_display_name = opponent_name.strip_edges()
	_refresh_name_labels()
	if last_status_header != -1:
		update_status(last_status_header, last_status_is_player_turn)

func _refresh_name_labels() -> void:
	if player_name_label:
		var label := player_display_name if _has_player_name() else "Vos"
		player_name_label.text = "Jugador:   %s" % label
	if opponent_name_label:
		var label := opponent_display_name if _has_opponent_name() else "Desconocido"
		opponent_name_label.text = "Oponente:   %s" % label

func _has_player_name() -> bool:
	return player_display_name != ""

func _has_opponent_name() -> bool:
	return opponent_display_name != ""

func _spawn_ship_sprite(texture: Texture2D, length: int, start_row: int, start_col: int, horizontal: bool) -> void:
	var sprite := _create_ship_sprite(texture, length, start_row, start_col, horizontal, 2)
	if sprite == null:
		return
	player_ships_overlay.add_child(sprite)

func _create_ship_sprite(texture: Texture2D, length: int, start_row: int, start_col: int, horizontal: bool, z_value: int) -> Sprite2D:
	if texture == null:
		return null
	var tex_size: Vector2 = texture.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return null
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = true
	var target_size := Vector2(length * CELL_PIXEL_SIZE, CELL_PIXEL_SIZE)
	sprite.scale = Vector2(target_size.x / tex_size.x, target_size.y / tex_size.y)
	var top_left := Vector2(start_col, start_row) * CELL_PIXEL_SIZE
	sprite.position = top_left + target_size / 2.0
	if not horizontal:
		target_size = Vector2(target_size.y, target_size.x)
		sprite.position = top_left + target_size / 2.0
		sprite.rotation = -PI / 2.0
	sprite.z_index = z_value
	return sprite

func update_status(header: int, is_player_turn: bool) -> void:
	last_status_header = header
	last_status_is_player_turn = is_player_turn
	var active_length: int = 0
	var phase_text: String = ""
	var info_text: String = ""
	var has_player_name := _has_player_name()
	var has_opponent_name := _has_opponent_name()
	var player_name := player_display_name
	var opponent_name := opponent_display_name

	# Por defecto, deshabilitamos interacciones (hover en tablero derecho)
	interactions_enabled = false

	match header:
		254:
			phase_text = "¡Ganaste!"
			info_text = ""
			current_ship_size = 0
			placement_progress = PLACEMENT_SEQUENCE.size()
		255:
			phase_text = "Has sido derrotado."
			info_text = ""
			current_ship_size = 0
		2, 3, 4, 5:
			current_ship_size = header
			active_length = header
			var seq_index: int = min(placement_progress, PLACEMENT_SEQUENCE.size() - 1)
			var ship_name: String = _get_sequence_name(seq_index)
			phase_text = "Coloca tu %s (%d casillas)" % [ship_name, header]
			var remaining: Array[String] = []
			for i in range(seq_index + 1, PLACEMENT_SEQUENCE.size()):
				remaining.append(_get_sequence_name(i))
			if remaining.is_empty():
				info_text = ""
			else:
				info_text = "Faltan: %s" % String(", ").join(remaining)
		1:
			current_ship_size = 0
			if has_opponent_name:
				phase_text = "Esperando a que %s coloque sus barcos..." % opponent_name
			else:
				phase_text = "Esperando a que el oponente coloque sus barcos..."
			info_text = "Barcos listos: %d / %d" % [placement_progress, PLACEMENT_SEQUENCE.size()]
		0:
			# PARTIDA EN CURSO → solo permitimos hover en tablero derecho
			# cuando es tu turno (para que apuntes donde disparar).
			current_ship_size = 0
			interactions_enabled = is_player_turn

			if is_player_turn:
				if has_player_name:
					phase_text = "¡Tu turno, %s!" % player_name
					info_text = "Seleccioná una celda del tablero enemigo de %s." % (opponent_name if has_opponent_name else "tu oponente")
				else:
					phase_text = "¡Tu turno para atacar!"
					info_text = "Seleccioná una celda del tablero enemigo."
			else:
				if has_opponent_name:
					phase_text = "Turno de %s..." % opponent_name
					info_text = "%s está atacando. Esperá su disparo." % opponent_name
				else:
					phase_text = "Turno del oponente..."
					info_text = "Esperá el disparo del oponente."
		_:
			current_ship_size = 0
			phase_text = "Preparando partida..."
			info_text = ""

	phase_label.text = phase_text
	turn_label.text = info_text
	_update_placement_icons(active_length)
	if header != 2 and header != 3 and header != 4 and header != 5:
		_hide_preview()

	# Cada vez que cambia el estado, refrescamos estilos del tablero enemigo
	_refresh_opponent_styles()


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

func _init_ship_textures() -> void:
	if not ship_textures_by_length.is_empty():
		return
	var textures_by_name := {}
	for name in SHIP_RECTS.keys():
		textures_by_name[name] = _create_ship_texture(SHIP_RECTS[name])
	for length in SHIP_ORDER_BY_LENGTH.keys():
		var texture_names: Array = SHIP_ORDER_BY_LENGTH[length]
		var textures: Array = []
		for name in texture_names:
			textures.append(textures_by_name[name])
		ship_textures_by_length[length] = textures

func _create_ship_texture(region: Rect2i) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = SHIP_ATLAS
	atlas.region = region
	return atlas

func _init_explosion_textures() -> void:
	if not explosion_textures.is_empty():
		return
	for bounds in HIT_ANIMATION_BOUNDS:
		var rect := _rect_from_bounds(bounds)
		explosion_textures.append(_create_explosion_texture(rect))

func _rect_from_bounds(bounds: Vector4i) -> Rect2i:
	var min_x: int = bounds.x
	var max_x: int = bounds.y
	var min_y: int = bounds.z
	var max_y: int = bounds.w
	var width: int = int(max(1, max_x - min_x))
	var height: int = int(max(1, max_y - min_y))
	return Rect2i(Vector2i(min_x, min_y), Vector2i(width, height))

func _create_explosion_texture(region: Rect2i) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = HIT_ANIMATION_ATLAS
	atlas.region = region
	return atlas

func _get_sequence_texture_for_index(index: int) -> Texture2D:
	if index < 0 or index >= PLACEMENT_SEQUENCE.size():
		return null
	var length: int = PLACEMENT_SEQUENCE[index]
	var textures: Array = ship_textures_by_length.get(length, [])
	if textures.is_empty():
		return null
	var repeats := 0
	for i in range(index):
		if PLACEMENT_SEQUENCE[i] == length:
			repeats += 1
	return textures[min(repeats, textures.size() - 1)]

func _get_sequence_name(index: int) -> String:
	if index >= 0 and index < PLACEMENT_NAMES.size():
		return PLACEMENT_NAMES[index]
	return "Barco"

func _init_status_ui() -> void:
	for child in placement_container.get_children():
		child.queue_free()

	placement_icon_nodes.clear()

	for i in range(PLACEMENT_SEQUENCE.size()):
		var texture := _get_sequence_texture_for_index(i)
		var icon := TextureRect.new()
		icon.texture = texture
		icon.expand = true
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.modulate = Color(1, 1, 1, 0.6)
		icon.tooltip_text = _get_sequence_name(i)

		var length := PLACEMENT_SEQUENCE[i]
		var target_size := Vector2(length * CELL_PIXEL_SIZE, CELL_PIXEL_SIZE)
		icon.custom_minimum_size = target_size

		placement_container.add_child(icon)
		icon.size = target_size

		placement_icon_nodes.append(icon)


func _update_placement_icons(active_length: int) -> void:
	if placement_icon_nodes.is_empty():
		return
	for i in range(placement_icon_nodes.size()):
		var icon: TextureRect = placement_icon_nodes[i]
		if i < placement_progress:
			icon.modulate = Color(1, 1, 1, 0.3)
		elif i == placement_progress and active_length >= 2:
			icon.modulate = Color(1, 1, 1, 1.0)
		else:
			icon.modulate = Color(1, 1, 1, 0.6)

func _process_destroyed_opponent_ships() -> void:
	if opponent_raw_values.is_empty():
		return
	var visited: Array = []
	for _row in range(GRID_SIZE):
		var visited_row: Array[bool] = []
		for _col in range(GRID_SIZE):
			visited_row.append(false)
		visited.append(visited_row)

	for row in range(GRID_SIZE):
		for col in range(GRID_SIZE):
			var visited_row: Array[bool] = visited[row] as Array[bool]
			if visited_row[col]:
				continue
			var cell_value: int = opponent_raw_values[row][col]
			if not _is_ship_value(cell_value):
				continue
			var ship_info: Dictionary = _collect_ship_from_raw(opponent_raw_values, visited, row, col)
			if ship_info.is_empty():
				continue
			var coords: Array[Vector2i] = ship_info.get("coords", []) as Array[Vector2i]
			if coords.is_empty():
				continue
			var all_hit := true
			for coord in coords:
				var pos: Vector2i = coord
				if opponent_raw_values[pos.x][pos.y] != 2:
					all_hit = false
					break
			if not all_hit:
				continue
			var ship_key := _ship_coords_key(coords)
			if opponent_destroyed_ship_keys.has(ship_key):
				continue
			opponent_destroyed_ship_keys[ship_key] = true
			_handle_opponent_ship_destroyed(coords)

func _process_destroyed_player_ships() -> void:
	if player_raw_values.is_empty():
		return

	var visited: Array = []
	for _row in range(GRID_SIZE):
		var visited_row: Array[bool] = []
		for _col in range(GRID_SIZE):
			visited_row.append(false)
		visited.append(visited_row)

	for row in range(GRID_SIZE):
		for col in range(GRID_SIZE):
			var visited_row: Array[bool] = visited[row] as Array[bool]
			if visited_row[col]:
				continue
			var cell_value: int = player_raw_values[row][col]
			if not _is_ship_value(cell_value):
				continue

			var ship_info: Dictionary = _collect_ship_from_raw(player_raw_values, visited, row, col)
			if ship_info.is_empty():
				continue

			var coords: Array[Vector2i] = ship_info.get("coords", []) as Array[Vector2i]
			if coords.is_empty():
				continue

			var all_hit := true
			for coord in coords:
				var pos: Vector2i = coord
				if player_raw_values[pos.x][pos.y] != 2:
					all_hit = false
					break

			if not all_hit:
				continue

			var ship_key := _ship_coords_key(coords)
			if player_destroyed_ship_keys.has(ship_key):
				continue

			player_destroyed_ship_keys[ship_key] = true
			_handle_player_ship_destroyed(coords)

func _collect_ship_from_raw(raw_values: Array, visited: Array, start_row: int, start_col: int) -> Dictionary:
	var stack: Array[Vector2i] = [Vector2i(start_row, start_col)]
	var coords: Array[Vector2i] = []
	while not stack.is_empty():
		var current: Vector2i = stack.pop_back()
		var row: int = current.x
		var col: int = current.y
		if row < 0 or row >= GRID_SIZE or col < 0 or col >= GRID_SIZE:
			continue
		var visited_row: Array[bool] = visited[row] as Array[bool]
		if visited_row[col]:
			continue
		visited_row[col] = true
		var cell_value: int = raw_values[row][col]
		if not _is_ship_value(cell_value):
			continue
		coords.append(Vector2i(row, col))
		stack.append(Vector2i(row + 1, col))
		stack.append(Vector2i(row - 1, col))
		stack.append(Vector2i(row, col + 1))
		stack.append(Vector2i(row, col - 1))

	if coords.is_empty():
		return {}

	var horizontal := true
	var base_row: int = coords[0].x
	for coord in coords:
		if coord.x != base_row:
			horizontal = false
			break

	return {
		"coords": coords,
		"horizontal": horizontal,
	}

func _ship_coords_key(coords: Array) -> String:
	var ordered := coords.duplicate()
	ordered.sort_custom(Callable(self, "_compare_vector2i"))
	var parts: Array[String] = []
	for coord in ordered:
		var pos: Vector2i = coord
		parts.append("%d_%d" % [pos.x, pos.y])
	return String(";").join(parts)

func _handle_opponent_ship_destroyed(coords: Array) -> void:
	var ordered := coords.duplicate()
	ordered.sort_custom(Callable(self, "_compare_vector2i"))
	for i in range(ordered.size()):
		var coord: Vector2i = ordered[i]
		var delay := float(i) * HIT_ANIMATION_TILE_DELAY
		_trigger_cell_explosion(coord.x, coord.y, opponent_effects_overlay, opponent_explosions, delay)

func _handle_player_ship_destroyed(coords: Array) -> void:
	var ordered := coords.duplicate()
	ordered.sort_custom(Callable(self, "_compare_vector2i"))

	for i in range(ordered.size()):
		var coord: Vector2i = ordered[i]
		var delay := float(i) * HIT_ANIMATION_TILE_DELAY
		_clear_cell_explosion(coord.x, coord.y, player_explosions)
		_trigger_cell_explosion(coord.x, coord.y, player_effects_overlay, player_explosions, delay)


func _trigger_player_explosion(row: int, col: int) -> void:
	_trigger_cell_explosion(row, col, player_effects_overlay, player_explosions)

func _trigger_cell_explosion(row: int, col: int, overlay: Node2D, store: Dictionary, start_delay: float = 0.0) -> void:
	if overlay == null:
		return
	var key := _cell_key(row, col)
	if store.has(key):
		var existing: Sprite2D = store[key]
		if is_instance_valid(existing):
			return
		else:
			store.erase(key)
	var sprite := Sprite2D.new()
	sprite.centered = true
	sprite.visible = false
	sprite.z_index = 10
	sprite.position = _cell_center_position(row, col)
	overlay.add_child(sprite)
	store[key] = sprite
	_play_explosion(sprite, start_delay)

func _play_explosion(sprite: Sprite2D, start_delay: float) -> void:
	if explosion_textures.is_empty():
		return
	var tween := create_tween()
	tween.tween_callback(Callable(self, "_set_explosion_frame").bind(sprite, 0)).set_delay(start_delay)
	tween.tween_interval(HIT_ANIMATION_PHASE_TIME)
	tween.tween_callback(Callable(self, "_set_explosion_frame").bind(sprite, 1))
	tween.tween_interval(HIT_ANIMATION_PHASE_TIME)
	tween.tween_callback(Callable(self, "_set_explosion_frame").bind(sprite, 2))

func _set_explosion_frame(sprite: Sprite2D, frame_index: int) -> void:
	if not is_instance_valid(sprite):
		return
	if explosion_textures.is_empty():
		return
	var idx: int = clamp(frame_index, 0, explosion_textures.size() - 1)
	var texture: Texture2D = explosion_textures[idx]
	sprite.texture = texture
	sprite.scale = _get_texture_scale(texture)
	sprite.visible = true

func _get_texture_scale(texture: Texture2D) -> Vector2:
	if texture == null:
		return Vector2.ONE
	var tex_size := texture.get_size()
	if tex_size.x <= 0 or tex_size.y <= 0:
		return Vector2.ONE
	return Vector2(CELL_PIXEL_SIZE / tex_size.x, CELL_PIXEL_SIZE / tex_size.y)

func _clear_cell_explosion(row: int, col: int, store: Dictionary) -> void:
	var key := _cell_key(row, col)
	if not store.has(key):
		return
	var sprite: Sprite2D = store[key]
	if is_instance_valid(sprite):
		sprite.queue_free()
	store.erase(key)

func _cell_key(row: int, col: int) -> String:
	return "%d_%d" % [row, col]

func _cell_center_position(row: int, col: int) -> Vector2:
	return Vector2(col, row) * CELL_PIXEL_SIZE + Vector2(CELL_PIXEL_SIZE / 2.0, CELL_PIXEL_SIZE / 2.0)

func _clear_all_explosions(clear_player_layout: bool = true) -> void:
	_clear_explosion_store(player_explosions)
	_clear_explosion_store(opponent_explosions)
	opponent_destroyed_ship_keys.clear()
	player_destroyed_ship_keys.clear()
	if clear_player_layout:
		player_ship_layout.clear()

func _clear_explosion_store(store: Dictionary) -> void:
	for key in store.keys():
		var sprite: Sprite2D = store[key]
		if is_instance_valid(sprite):
			sprite.queue_free()
	store.clear()

func _compare_vector2i(a: Vector2i, b: Vector2i) -> bool:
	if a.x == b.x:
		return a.y < b.y
	return a.x < b.x

func _apply_style(button: Button, state: int, disabled: bool, allow_hover: bool) -> void:
	var style: StyleBoxTexture = cell_styles.get(state, cell_styles[CellVisualState.BASE])
	button.disabled = disabled
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("disabled", style)
	button.add_theme_stylebox_override("pressed", style)

	# ¿En principio podría tener hover?
	var can_hover: bool = allow_hover and not disabled and state == CellVisualState.BASE

	# Identificamos de qué tablero es el botón
	var is_player_board: bool = (button.get_parent() == grid_player_1)
	var is_opponent_board: bool = (button.get_parent() == grid_player_2)

	var hover_allowed: bool = false

	# 1) Tablero del jugador (izquierdo):
	#    hover SOLO mientras se están colocando barcos
	#    (pre_start_mode, con un barco activo y aún faltan por colocar)
	if can_hover \
			and is_player_board \
			and pre_start_mode \
			and current_ship_size > 0 \
			and placement_progress < PLACEMENT_SEQUENCE.size():
		hover_allowed = true

	# 2) Tablero del oponente (derecho):
	#    hover SOLO cuando se está jugando y es tu turno
	#    (interactions_enabled lo maneja update_status con header == 0 e is_player_turn == true)
	elif can_hover \
			and is_opponent_board \
			and not pre_start_mode \
			and interactions_enabled:
		hover_allowed = true

	if hover_allowed:
		button.add_theme_stylebox_override("hover", hover_style)
	else:
		# En cualquier otro caso, hover igual al estilo normal (no se “ilumina”)
		button.add_theme_stylebox_override("hover", style)
