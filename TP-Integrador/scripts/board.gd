extends Node

@onready var grid_player_1 = $VFlowContainer/Player1Board
@onready var grid_player_2 = $VFlowContainer2/Player2Board

const GRID_SIZE := 10

const CellButton = preload("res://scenes/game/cell_button.tscn")

# This will be the grid for the current player
var button_grid_player_1 := []
# This will be the grid for the oponent
var button_grid_player_2 := []
var pre_start_mode := true
var current_ship_size := 0
var current_orientation := "horizontal" 
var highlighted_cells := []
var last_hover_start := Vector2i(-1, -1)
var last_hover_end := Vector2i(-1, -1)

func _input(event):
	if event.is_action_released("rotate"):
		if current_orientation == "horizontal":
			current_orientation = "vertical"
		else:
			current_orientation = "horizontal"
		_on_cell_hover_enter(last_hover_start.x, last_hover_start.y)

func _ready() -> void:
	for row in range(GRID_SIZE):
		var row_array := []
		for col in range(GRID_SIZE):
			var btn = CellButton.instantiate()
			btn.name = "Cell_%d_%d" % [row, col]
			btn.text = "%d, %d" % [row, col]
			btn.pressed.connect(_on_cell_pressed.bind(row, col))
			btn.mouse_entered.connect(_on_cell_hover_enter.bind(row, col))
			btn.mouse_exited.connect(_on_cell_hover_exit)
			grid_player_1.add_child(btn)
			row_array.append(btn)
		button_grid_player_1.append(row_array)
	
	for row in range(GRID_SIZE):
		var row_array := []
		for col in range(GRID_SIZE):
			var btn = CellButton.instantiate()
			btn.name = "Cell_%d_%d" % [row, col]
			btn.text = "%d, %d" % [row, col]
			btn.pressed.connect(_hit_boat.bind(row, col))
			btn.disabled = true
			grid_player_2.add_child(btn)
			row_array.append(btn)
		button_grid_player_2.append(row_array)


func _hit_boat(x: int, y: int):
	if pre_start_mode:
		return

	var tcp := ConnectionState.tcp
	# Byte 0 -> Message type: hit
	# Byte 1 -> x position
	# Byte 2 -> y position
	# Byte 3 & 4 -> padding
	tcp.put_data(PackedByteArray([1,x,y,0,0]))


func _on_cell_pressed(row: int, col: int):
	print("Button at [%d %d] pressed!" % [row,col])
	if last_hover_start.x == -1:
		return
	# Byte 0: Message type 2 == PlaceBoat
	# Byte 1: Row
	# Byte 2: Column
	# Bytes 3 and 4 are padding
	ConnectionState.tcp.put_data(PackedByteArray([2, last_hover_start.x, last_hover_start.y, last_hover_end.x,  last_hover_end.y]))
	

func _on_cell_hover_enter(row: int, col: int):
	clear_highlight()
	
	last_hover_start = Vector2i(row, col)
	var cells_to_highlight: Array = []
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

		cells_to_highlight.append(button_grid_player_1[r][c])

	# The last valid cell is your "end"
	last_hover_end = Vector2i(r, c)

	# Highlight
	for btn in cells_to_highlight:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(1.0, 0.654, 0.44, 0.6)
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)

	highlighted_cells = cells_to_highlight

func _on_cell_hover_exit():
	clear_highlight()

func clear_highlight():
	for btn in highlighted_cells:
		btn.remove_theme_stylebox_override("normal")
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
	pre_start_mode = false

func switch_to_waiting_for_other_player():
	for row in button_grid_player_1:
			for button in row:
				button.disabled = true
