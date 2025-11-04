extends Node

signal state_update(payload: PackedByteArray)

enum ConnectionStatus {
	DISCONNECTED,
	CONNECTING,
	CONNECTED,
	FAILED
}

const HEADER_SIZE := 3

const ServerMessageType := {
	STATE_UPDATE = 0,
}

const ClientMessageType := {
	GET_STATE = 0,
	HIT = 1,
	PLACE_BOAT = 2,
}

var status: ConnectionStatus = ConnectionStatus.DISCONNECTED
var tcp: StreamPeerTCP
var _receive_buffer := PackedByteArray()

func reset() -> void:
	_receive_buffer.clear()

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
			_:
				print("Warning: received unknown server message type: %d" % message_type)

		if _receive_buffer.size() == total_length:
			_receive_buffer.clear()
		else:
			_receive_buffer = _receive_buffer.slice(total_length, _receive_buffer.size())
