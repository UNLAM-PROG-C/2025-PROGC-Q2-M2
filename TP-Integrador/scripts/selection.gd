extends Control

@onready var ip_input = $Panel/VBoxContainer/IpInput
@onready var name_input = $Panel/VBoxContainer/NameInput
@onready var start_button = $Panel/VBoxContainer/StartButton
@onready var error_label: Label = $Panel/VBoxContainer/ErrorLabel

# Amount of retries for connection
var MAX_RETRIES = 30
const DEFAULT_PORT := 1234
const MAX_NAME_LENGTH := 24

func _ready() -> void:
	error_label.visible = false
	error_label.text = ""
	start_button.pressed.connect(_on_start_button_pressed)
	
	# Limitar caracteres de la IP: solo dígitos y punto
	ip_input.text_changed.connect(_on_ip_text_changed)


func _on_start_button_pressed():
	start_button.disabled = true
	# limpiamos el label
	error_label.visible = false
	error_label.text = ""

	var ip_address: String = ip_input.text.strip_edges()
	var player_name: String = name_input.text.strip_edges()
	

	# ---------------------------------------
	# 1) VALIDACIONES CON MENSAJES CONCATENADOS
	# ---------------------------------------
	var errores := ""

	# Validación de nombre
	if player_name == "":
		print("Please enter a name")
		start_button.disabled = false
		return
	if player_name.length() > MAX_NAME_LENGTH:
		errores += ("Debe ingresar un nombre.\n")
	elif player_name.length() > MAX_NAME_LENGTH:
		player_name = player_name.substr(0, MAX_NAME_LENGTH)
		name_input.text = player_name
	

	# Validación de IP vacía
	if ip_address == "":
		print("Please enter a valid ip address")
		errores += ("Debe ingresar una dirección IP.\n")

	# Si ya faltan nombre y/o IP, mostramos todo junto y salimos.
	if errores != "":
		_show_error(errores.strip_edges())
		start_button.disabled = false
		return

	# A partir de acá ya sabemos que hay algo escrito en IP y en nombre.
	# ---------------------------------------
	# 2) VALIDACIONES DE IP / PUERTO (como antes, pero con label)
	# ---------------------------------------
	var parts := ip_address.split(":", false, 1)
	var ip: String
	var port: int = DEFAULT_PORT

	if parts.size() == 0 or parts[0] == "":
		print("Please enter a valid ip address")
		_show_error("Debe ingresar una dirección IP válida.")
		start_button.disabled = false
		return

	ip = parts[0]

	if parts.size() > 1:
		if parts[1] == "":
			print("Please enter a valid port")
			_show_error("Debe ingresar un puerto válido.")
			start_button.disabled = false
			return
		port = int(parts[1])
		if port <= 0 or port > 65535:
			print("Please enter a valid port")
			_show_error("El puerto debe estar entre 1 y 65535.")
			start_button.disabled = false
			return
	

	# ---------------------------------------
	# 3) MENSAJE DE CONEXIÓN Y LÓGICA ORIGINAL
	# ---------------------------------------

	# Mostrar mensaje antes de iniciar la espera
	_show_error("Conectando con el servidor...")

	# IMPORTANTE: este await es el mismo que ya tenías
	var err = await connect_to_host_and_check_success(ip, port, player_name)

	if err == OK:
		# si conecta, ya no nos importa el label, cambiamos de escena
		get_tree().change_scene_to_file("res://scenes/game/board.tscn")
	else:
		ConnectionState.status = ConnectionState.ConnectionStatus.FAILED
		print("Failed to connect: %s" % err)
		_show_error("No se pudo conectar al servidor. Código de error: %s" % err)
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


func _show_error(message: String) -> void:
	if message.begins_with("Conectando"):
		error_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	else:
		error_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))

	error_label.text = message
	error_label.visible = true


# Filtra la IP para que solo acepte dígitos y punto
func _on_ip_text_changed(new_text: String) -> void:
	var allowed := "0123456789.:"
	var filtered := ""
	for c in new_text:
		if c in allowed:
			filtered += c

	if filtered != new_text:
		ip_input.text = filtered
		ip_input.caret_column = filtered.length()
