extends Control

@onready var ip_input = $Panel/VBoxContainer/IpInput
@onready var start_button = $Panel/VBoxContainer/StartButton
# Amount of retries for connection
var MAX_RETRIES = 30

func _ready() -> void:
	start_button.pressed.connect(_on_start_button_pressed)
	
func _on_start_button_pressed():
	start_button.disabled = true
	var ip_address: String = ip_input.text.strip_edges()
	
	if ip_address == "":
		print("Please enter a valid ip address")
		start_button.disabled = false
		return
	print("IP entered: ", ip_address)
	
	var ip = ip_address.split(":", true, 1)[0]
	var port = ip_address.split(":",true, 1)[1]
	
	var err = await connect_to_host_and_check_success(ip, int(port))

	if err == OK:
		get_tree().change_scene_to_file("res://scenes/game/board.tscn")
	else:
		ConnectionState.status = ConnectionState.ConnectionStatus.FAILED
		print("Failed to connect: %s" % err)
		start_button.disabled = false
		return


func connect_to_host_and_check_success(ip: String, port: int) -> Error:
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
			ConnectionState.send_message(ConnectionState.ClientMessageType.GET_STATE)
			return OK
		_:
			ConnectionState.tcp = null
			return ERR_CANT_CONNECT
