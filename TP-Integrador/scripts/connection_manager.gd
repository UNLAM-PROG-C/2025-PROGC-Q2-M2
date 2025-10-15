extends Node

# 50 ms
const POLL_INTERVAL := 0.05
var poll_timer := 0.0

func _process(delta: float) -> void:
	if not ConnectionState.tcp:
		return

	poll_timer += delta
	if poll_timer < POLL_INTERVAL:
		return

	poll_timer = 0.0
	
	var tcp := ConnectionState.tcp

	match tcp.get_status():
		StreamPeerTCP.STATUS_CONNECTING:
			print("Still connecting...")
		StreamPeerTCP.STATUS_CONNECTED:
			# Message type 0 = GetState 
			# Bytes 1 to 4padding
			tcp.put_data(PackedByteArray([0,0,0,0,0]))
			var boards = tcp.get_data(202)[1]
			var game_board := get_node("HFlowContainer")
			match boards[0]:
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
					get_tree().change_scene_to_file("res://scenes/game/won.tscn")
				255:
					ConnectionState.tcp = null
					get_tree().change_scene_to_file("res://scenes/game/lost.tscn")

			for i in range(100):
				var row = i / 10
				var col = i % 10
				var button = game_board.button_grid_player_1[row][col]

				# This 2 skips the first two bytes that are not board
				match boards[i + 2]:
					0:
						if button not in game_board.highlighted_cells:
							var style = StyleBoxFlat.new()
							style.bg_color = Color(0.0, 0.624, 0.953, 1.0)
							button.add_theme_stylebox_override("disabled", style)
							button.add_theme_stylebox_override("normal", style)
					1:
						button.disabled = true
						var style = StyleBoxFlat.new()
						style.bg_color = Color(0.992, 0.0, 0.836, 1.0)
						button.add_theme_stylebox_override("disabled", style)
						
					2:
						var style = StyleBoxFlat.new()
						style.bg_color = Color(1.0, 0.0, 0.141, 1.0)
						button.add_theme_stylebox_override("disabled", style)
					3:
						var style = StyleBoxFlat.new()
						style.bg_color = Color(0.672, 0.496, 0.337, 1.0)
						button.add_theme_stylebox_override("disabled", style)

			# TODO move to a function
			# This updates the oponent board
			for i in range(100):
				var row = i / 10
				var col = i % 10
				# Empty = 0,
				# Boat = 1,
				# Hit = 2,
				# Missed = 3,
				# This 102 is skips the first 2 bytes and the 100 slots for the first player board
				var button = game_board.button_grid_player_2[row][col]
				match boards[i + 102]:
					0:
						var style = StyleBoxFlat.new()
						style.bg_color = Color(0.0, 0.624, 0.953, 1.0)
						button.add_theme_stylebox_override("disabled", style)
						button.add_theme_stylebox_override("normal", style)
					1:
						pass
					2:
						button.disabled = true
						var style = StyleBoxFlat.new()
						style.bg_color = Color(0.144, 0.713, 0.0, 1.0)
						button.add_theme_stylebox_override("disabled", style)
					3:
						button.disabled = true
						var style = StyleBoxFlat.new()
						style.bg_color = Color(1.0, 0.323, 0.207, 1.0)
						button.add_theme_stylebox_override("disabled", style)
					
		_:
			print("Disconnected or connection failed.")
			ConnectionState.status = ConnectionState.ConnectionStatus.FAILED
			_handle_disconnection()

func _handle_disconnection():
	ConnectionState.tcp = null
	ConnectionState.status = ConnectionState.ConnectionStatus.DISCONNECTED
	get_tree().change_scene_to_file("res://main.tscn")
	
