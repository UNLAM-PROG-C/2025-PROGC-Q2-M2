extends Control

@onready var ip_input = $Panel/VBoxContainer/IpInput
@onready var name_input = $Panel/VBoxContainer/NameInput
@onready var start_button = $Panel/VBoxContainer/StartButton
# Amount of retries for connection
var MAX_RETRIES = 30
const DEFAULT_PORT := 1234
const MAX_NAME_LENGTH := 24

func _ready() -> void:
	start_button.pressed.connect(_on_start_button_pressed)
	
func _on_start_button_pressed():
	start_button.disabled = true
	var ip_address: String = ip_input.text.strip_edges()
	var player_name: String = name_input.text.strip_edges()
	
	if player_name == "":
		print("Please enter a name")
		start_button.disabled = false
		return
	if player_name.length() > MAX_NAME_LENGTH:
		player_name = player_name.substr(0, MAX_NAME_LENGTH)
		name_input.text = player_name
	
	if ip_address == "":
		print("Please enter a valid ip address")
		start_button.disabled = false
		return
	var parts := ip_address.split(":", false, 1)
	var ip: String
	var port: int = DEFAULT_PORT
	if parts.size() == 0 or parts[0] == "":
		print("Please enter a valid ip address")
		start_button.disabled = false
		return
	ip = parts[0]
	if parts.size() > 1:
		if parts[1] == "":
			print("Please enter a valid port")
			start_button.disabled = false
			return
		port = int(parts[1])
		if port <= 0 or port > 65535:
			print("Please enter a valid port")
			start_button.disabled = false
			return
	
	var err = await connect_to_host_and_check_success(ip, port, player_name)

	if err == OK:
		get_tree().change_scene_to_file("res://scenes/game/board.tscn")
	else:
		ConnectionState.status = ConnectionState.ConnectionStatus.FAILED
		print("Failed to connect: %s" % err)
		start_button.disabled = false
		return


func connect_to_host_and_check_success(ip: String, port: int, player_name: String) -> Error:
	var tcp = StreamPeerTCP.new()
	var err = tcp.connect_to_host(ip, int(port))
	if err != OK:
		return err
	ConnectionState.tcp = tcp
	ConnectionState.reset()
	ConnectionState.status = ConnectionState.ConnectionStatus.CONNECTING
	var attempts = 0
	tcp.poll()
	while attempts <  MAX_RETRIES and tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED and tcp.get_status() != StreamPeerTCP.STATUS_ERROR:
		# We wait for 1 second before checking the connection again
		await get_tree().create_timer(1).timeout
		tcp.poll()
		attempts += 1
		
	match tcp.get_status():
		StreamPeerTCP.STATUS_CONNECTED:
			ConnectionState.status = ConnectionState.ConnectionStatus.CONNECTED
			ConnectionState.player_name = player_name
			var name_payload := player_name.to_utf8_buffer()
			ConnectionState.send_message(ConnectionState.ClientMessageType.SET_NAME, name_payload)
			ConnectionState.send_message(ConnectionState.ClientMessageType.GET_STATE)
			return OK
		_:
			ConnectionState.tcp = null
			return ERR_CANT_CONNECT
