extends Node

enum ConnectionStatus {
	DISCONNECTED,
	CONNECTING,
	CONNECTED,
	FAILED
}

var status: ConnectionStatus = ConnectionStatus.DISCONNECTED
var tcp: StreamPeerTCP
