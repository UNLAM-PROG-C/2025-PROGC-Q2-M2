extends Node

@onready var grid_player_1 = $Player1Panel/Player1Board
@onready var grid_player_2 = $Player2Panel/Player2Board
@onready var player_ships_overlay: Node2D = $Player1Panel/Player1Overlay
@onready var preview_overlay: Node2D = $Player1Panel/Player1Preview
@onready var status_panel: Panel = get_parent().get_node("StatusPanel")
@onready var phase_label: Label = status_panel.get_node("MarginContainer/VBoxContainer/PhaseLabel")
@onready var turn_label: Label = status_panel.get_node("MarginContainer/VBoxContainer/TurnLabel")
@onready var placement_container: HBoxContainer = status_panel.get_node("MarginContainer/VBoxContainer/PlacementContainer")

const GRID_SIZE := 10
const CELL_PIXEL_SIZE := 60
const TILE_ATLAS := preload("res://assets/cells.png")
const TILE_RECTS := {
	"base": Rect2i(Vector2i(73, 98), Vector2i(428, 393)),
	"hit": Rect2i(Vector2i(535, 98), Vector2i(415, 393)),
	"miss": Rect2i(Vector2i(73, 525), Vector2i(428, 393)),
	"hover": Rect2i(Vector2i(535, 525), Vector2i(415, 393)),
}

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

const PLACEMENT_SEQUENCE := [5, 4, 3, 3, 2, 2]
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

func _input(event):
	if event.is_action_released("rotate"):
		if current_orientation == "horizontal":
			current_orientation = "vertical"
		else:
			current_orientation = "horizontal"
		_on_cell_hover_enter(last_hover_start.x, last_hover_start.y)

func _ready() -> void:
	_init_styles()
	_init_ship_textures()
	_init_status_ui()
	_update_placement_icons(0)
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

	var visited := []
	for _row in range(GRID_SIZE):
		var row_flags := []
		for _col in range(GRID_SIZE):
			row_flags.append(false)
		visited.append(row_flags)

	var ships_found: Array = []
	for row in range(GRID_SIZE):
		for col in range(GRID_SIZE):
			if visited[row][col]:
				continue
			var value := _get_player_cell_value(payload, row, col)
			if not _is_ship_value(value):
				continue
			var ship_info := _collect_ship(payload, row, col, visited)
			var length: int = ship_info.get("length", 0)
			if length < 2:
				continue
			ships_found.append(ship_info)

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

func _spawn_ship_sprite(texture: Texture2D, length: int, start_row: int, start_col: int, horizontal: bool) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = true
	var target_size: Vector2
	var tex_size := texture.get_size()
	target_size = Vector2(length * CELL_PIXEL_SIZE, CELL_PIXEL_SIZE)
	sprite.scale = Vector2(target_size.x / tex_size.x, target_size.y / tex_size.y)


	var top_left := Vector2(start_col, start_row) * CELL_PIXEL_SIZE
	sprite.position = top_left + target_size / 2.0
	if not horizontal:
		target_size = Vector2(target_size.y, target_size.x)
		sprite.position = top_left + target_size / 2.0
		sprite.rotation = -PI / 2.0
	sprite.z_index = 2
	player_ships_overlay.add_child(sprite)

func update_status(header: int, is_player_turn: bool) -> void:
	var active_length: int = 0
	var phase_text: String = ""
	var info_text: String = ""
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
			phase_text = "Colocá tu %s (%d casillas)" % [ship_name, header]
			var remaining: Array[String] = []
			for i in range(seq_index + 1, PLACEMENT_SEQUENCE.size()):
				remaining.append(_get_sequence_name(i))
			if remaining.is_empty():
				info_text = ""
			else:
				info_text = "Faltan: %s" % String(", ").join(remaining)
		1:
			current_ship_size = 0
			phase_text = "Esperando a que el oponente coloque sus barcos..."
			info_text = "Barcos listos: %d / %d" % [placement_progress, PLACEMENT_SEQUENCE.size()]
		0:
			current_ship_size = 0
			if is_player_turn:
				phase_text = "¡Tu turno para atacar!"
				info_text = "Seleccioná una celda del tablero enemigo."
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
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(96, 40)
		icon.modulate = Color(1, 1, 1, 0.6)
		icon.tooltip_text = _get_sequence_name(i)
		placement_container.add_child(icon)
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
