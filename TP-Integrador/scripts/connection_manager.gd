extends Node

func _ready() -> void:
	ConnectionState.state_update.connect(_on_state_update)
	ConnectionState.names_update.connect(_on_names_update)
	if ConnectionState.tcp:
		ConnectionState.reset()
	_apply_names()

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
	var header := payload[0]

	match header:
		0:
			game_board.switch_to_start()
		1:
			game_board.switch_to_waiting_for_other_player()
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

	game_board.handle_state_payload(payload)
	game_board.rebuild_player_ships(payload)
	game_board.update_status(header, payload[1] == 1)

func _handle_disconnection():
	ConnectionState.tcp = null
	ConnectionState.reset()
	ConnectionState.status = ConnectionState.ConnectionStatus.DISCONNECTED
	get_tree().change_scene_to_file("res://main.tscn")

func _on_names_update(player_name: String, opponent_name: String) -> void:
	_apply_names()

func _apply_names() -> void:
	var game_board := get_node_or_null("HFlowContainer")
	if not game_board:
		return
	if not game_board.has_method("update_player_names"):
		return
	game_board.update_player_names(ConnectionState.player_name, ConnectionState.opponent_name)
