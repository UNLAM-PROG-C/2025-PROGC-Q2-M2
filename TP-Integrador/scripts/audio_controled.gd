extends Node

@onready var sfx_connect: AudioStreamPlayer = $SFX_Connect
@onready var sfx_disconnect: AudioStreamPlayer = $SFX_Disconnect
@onready var sfx_error: AudioStreamPlayer = $SFX_Error
@onready var sfx_waiting: AudioStreamPlayer = $SFX_Waiting
@onready var sfx_timeout: AudioStreamPlayer = $SFX_Timeout

func play_connect():
	sfx_connect.play()

func play_disconnect():
	sfx_disconnect.play()

func play_error():
	sfx_error.play()

func play_waiting():
	sfx_waiting.play()

func play_timeout():
	sfx_timeout.play()
