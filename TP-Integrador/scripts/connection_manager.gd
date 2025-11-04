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
		game_board.update_player_cell_from_value(row, col, payload[i + 2])

	for i in range(100):
		var row: int = i / 10
		var col: int = i % 10
		var cell_value := payload[i + 102]
		var disable_target := cell_value == 2 or cell_value == 3
		game_board.update_opponent_cell_from_value(row, col, cell_value, disable_target)

	game_board.rebuild_player_ships(payload)

func _handle_disconnection():
	ConnectionState.tcp = null
	ConnectionState.reset()
	ConnectionState.status = ConnectionState.ConnectionStatus.DISCONNECTED
	get_tree().change_scene_to_file("res://main.tscn")
	
