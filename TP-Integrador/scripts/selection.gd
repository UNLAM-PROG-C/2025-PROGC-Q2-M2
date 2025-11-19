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
	# Limitar caracteres de la IP: solo dígitos, punto y dos puntos (para puerto opcional)
	ip_input.text_changed.connect(_on_ip_text_changed)


func _on_start_button_pressed():
	start_button.disabled = true
	# Limpiamos el label
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
		errores += "Debe ingresar un nombre.\n"
	elif player_name.length() > MAX_NAME_LENGTH:
		player_name = player_name.substr(0, MAX_NAME_LENGTH)
		name_input.text = player_name

	# Validación de IP + puerto opcional
	if ip_address == "":
		print("Please enter a valid ip address")
		errores += "Debe ingresar una dirección IP.\n"
	else:
		# Separamos IP y puerto (si existe)
		var ip_part := ip_address
		var port_part := ""
		var colon_index := ip_address.find(":")

		if colon_index != -1:
			ip_part = ip_address.substr(0, colon_index)
			port_part = ip_address.substr(colon_index + 1)

		# Validar IP en formato XXX.XXX.XXX.XXX
		if not _is_valid_ipv4(ip_part):
			print("Please enter a valid ip address")
			errores += "Debe ingresar una dirección IP válida (formato XXX.XXX.XXX.XXX).\n"

		# Validar puerto si fue ingresado
		if port_part != "":
			if not port_part.is_valid_int():
				print("Please enter a valid port")
				errores += "Debe ingresar un puerto válido.\n"
			else:
				var port_temp := int(port_part)
				if port_temp <= 0 or port_temp > 65535:
					print("Please enter a valid port")
					errores += "El puerto debe estar entre 1 y 65535.\n"

	# Si hubo errores, los mostramos y salimos
	if errores != "":
		_show_error(errores.strip_edges())
		start_button.disabled = false
		return

	# ---------------------------------------
	# 2) CONSTRUIR IP Y PUERTO FINALES
	# ---------------------------------------
	var ip: String
	var port: int = DEFAULT_PORT

	var colon_idx := ip_address.find(":")
	if colon_idx != -1:
		ip = ip_address.substr(0, colon_idx)
		var port_str := ip_address.substr(colon_idx + 1)
		if port_str != "":
			port = int(port_str)
	else:
		# Sin puerto → usamos el DEFAULT_PORT
		ip = ip_address

	# ---------------------------------------
	# 3) MENSAJE DE CONEXIÓN Y LÓGICA ORIGINAL
	# ---------------------------------------
	_show_error("Conectando con el servidor...")

	var err = await connect_to_host_and_check_success(ip, port, player_name)

	if err == OK:
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
	error_label.visible = true
	if message.begins_with("Conectando"):
		error_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	else:
		error_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	error_label.text = message


# Valida formato IPv4 XXX.XXX.XXX.XXX
func _is_valid_ipv4(ip: String) -> bool:
	var parts := ip.split(".", false)
	if parts.size() != 4:
		return false

	for part in parts:
		if part == "":
			return false
		if not part.is_valid_int():
			return false
		var n := int(part)
		if n < 0 or n > 255:
			return false

	return true


# Filtra la IP para que solo acepte dígitos, punto y dos puntos
func _on_ip_text_changed(new_text: String) -> void:
	var allowed := "0123456789.:"
	var filtered := ""
	for c in new_text:
		if c in allowed:
			filtered += c

	if filtered != new_text:
		ip_input.text = filtered
		ip_input.caret_column = filtered.length()
		
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			# Solo actuamos si el botón no está deshabilitado
			if not start_button.disabled:
				_on_start_button_pressed()
