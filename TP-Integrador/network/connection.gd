extends Node

signal state_update(payload: PackedByteArray)
signal names_update(player_name: String, opponent_name: String)

enum ConnectionStatus {
	DISCONNECTED,
	CONNECTING,
	CONNECTED,
	FAILED
}

const HEADER_SIZE := 3

const ServerMessageType := {
	STATE_UPDATE = 0,
	NAMES_UPDATE = 1,
}

const ClientMessageType := {
	GET_STATE = 0,
	HIT = 1,
	PLACE_BOAT = 2,
	SET_NAME = 3,
}

var status: ConnectionStatus = ConnectionStatus.DISCONNECTED
var tcp: StreamPeerTCP
var _receive_buffer := PackedByteArray()
var player_name: String = ""
var opponent_name: String = ""

func reset() -> void:
	_receive_buffer.clear()
	opponent_name = ""

func send_message(message_type: int, payload: PackedByteArray = PackedByteArray()) -> void:
	if not tcp:
		return
	var packet := PackedByteArray()
	var length := payload.size()
	packet.append(message_type & 0xFF)
	packet.append(length & 0xFF)
	packet.append((length >> 8) & 0xFF)
	packet.append_array(payload)
	tcp.put_data(packet)

func poll() -> void:
	if not tcp:
		return
	tcp.poll()
	var available := tcp.get_available_bytes()
	if available > 0:
		var result := tcp.get_data(available)
		if result[0] != OK:
			print("Warning: failed to read data from tcp: %s" % result[0])
			return
		_receive_buffer.append_array(result[1])
	_process_buffer()

func _process_buffer() -> void:
	while _receive_buffer.size() >= HEADER_SIZE:
		var message_type := _receive_buffer[0]
		var length := _receive_buffer[1] | (_receive_buffer[2] << 8)
		var total_length := HEADER_SIZE + length
		if _receive_buffer.size() < total_length:
			return

		var payload := PackedByteArray()
		if length > 0:
			payload = _receive_buffer.slice(HEADER_SIZE, total_length)

		match message_type:
			ServerMessageType.STATE_UPDATE:
				emit_signal("state_update", payload)
			ServerMessageType.NAMES_UPDATE:
				_process_names_payload(payload)
			_:
				print("Warning: received unknown server message type: %d" % message_type)

		if _receive_buffer.size() == total_length:
			_receive_buffer.clear()
		else:
			_receive_buffer = _receive_buffer.slice(total_length, _receive_buffer.size())

func _process_names_payload(payload: PackedByteArray) -> void:
	if payload.size() < 2:
		print("Warning: received names payload too short")
		return
	var index := 0
	var self_len := payload[index]
	index += 1
	if payload.size() < index + self_len + 1:
		print("Warning: names payload truncated for player name")
		return
	var self_bytes := payload.slice(index, index + self_len)
	index += self_len
	var opponent_len := payload[index]
	index += 1
	if payload.size() < index + opponent_len:
		print("Warning: names payload truncated for opponent name")
		return
	var opponent_bytes := payload.slice(index, index + opponent_len)
	player_name = self_bytes.get_string_from_utf8().strip_edges()
	opponent_name = opponent_bytes.get_string_from_utf8().strip_edges()
	emit_signal("names_update", player_name, opponent_name)
