extends Node

func _ready() -> void:
	ConnectionState.state_update.connect(_on_state_update)
	if ConnectionState.tcp:
		ConnectionState.reset()

func _process(delta: float) -> void:
	if not ConnectionState.tcp:
		return

	var tcp := ConnectionState.tcp

	match tcp.get_status():
		StreamPeerTCP.STATUS_CONNECTING:
			print("Still connecting...")
		StreamPeerTCP.STATUS_CONNECTED:
			ConnectionState.poll()
		_:
			print("Disconnected or connection failed.")
			ConnectionState.status = ConnectionState.ConnectionStatus.FAILED
			_handle_disconnection()

func _on_state_update(payload: PackedByteArray) -> void:
	if payload.size() < 202:
		print("Warning: received state update with invalid size: %d" % payload.size())
		return

	var game_board := get_node("HFlowContainer")

	match payload[0]:
		0:
			game_board.switch_to_start()
		1:
			game_board.switch_to_waiting_for_other_player()
		2:
			game_board.current_ship_size = 2
		3:
			game_board.current_ship_size = 3
		4:
			game_board.current_ship_size = 4
		5:
			game_board.current_ship_size = 5
		254:
			ConnectionState.tcp = null
			ConnectionState.reset()
			ConnectionState.status = ConnectionState.ConnectionStatus.DISCONNECTED
			get_tree().change_scene_to_file("res://scenes/game/won.tscn")
			return
		255:
			ConnectionState.tcp = null
			ConnectionState.reset()
			ConnectionState.status = ConnectionState.ConnectionStatus.DISCONNECTED
			get_tree().change_scene_to_file("res://scenes/game/lost.tscn")
			return

	for i in range(100):
		var row: int = i / 10
		var col: int = i % 10
		var button: Button = game_board.button_grid_player_1[row][col]
		match payload[i + 2]:
			0:
				if button not in game_board.highlighted_cells:
					var style := StyleBoxFlat.new()
					style.bg_color = Color(0.0, 0.624, 0.953, 1.0)
					button.add_theme_stylebox_override("disabled", style)
					button.add_theme_stylebox_override("normal", style)
			1:
				button.disabled = true
				var style := StyleBoxFlat.new()
				style.bg_color = Color(0.992, 0.0, 0.836, 1.0)
				button.add_theme_stylebox_override("disabled", style)
			2:
				var style := StyleBoxFlat.new()
				style.bg_color = Color(1.0, 0.0, 0.141, 1.0)
				button.add_theme_stylebox_override("disabled", style)
			3:
				var style := StyleBoxFlat.new()
				style.bg_color = Color(0.672, 0.496, 0.337, 1.0)
				button.add_theme_stylebox_override("disabled", style)

	for i in range(100):
		var row: int = i / 10
		var col: int = i % 10
		var button: Button = game_board.button_grid_player_2[row][col]
		match payload[i + 102]:
			0:
				var style := StyleBoxFlat.new()
				style.bg_color = Color(0.0, 0.624, 0.953, 1.0)
				button.add_theme_stylebox_override("disabled", style)
				button.add_theme_stylebox_override("normal", style)
			1:
				pass
			2:
				button.disabled = true
				var style := StyleBoxFlat.new()
				style.bg_color = Color(0.144, 0.713, 0.0, 1.0)
				button.add_theme_stylebox_override("disabled", style)
			3:
				button.disabled = true
				var style := StyleBoxFlat.new()
				style.bg_color = Color(1.0, 0.323, 0.207, 1.0)
				button.add_theme_stylebox_override("disabled", style)

func _handle_disconnection():
	ConnectionState.tcp = null
	ConnectionState.reset()
	ConnectionState.status = ConnectionState.ConnectionStatus.DISCONNECTED
	get_tree().change_scene_to_file("res://main.tscn")
	
