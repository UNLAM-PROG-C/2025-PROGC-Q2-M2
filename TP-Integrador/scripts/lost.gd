extends Control

func _ready():
	# Conectar botones
	$Panel/RetryButton.pressed.connect(_on_retry_pressed)
	$Panel/ExitButton.pressed.connect(_on_exit_pressed)

func _on_retry_pressed():
	# Reiniciar partida (cargar escena del juego)
	get_tree().change_scene_to_file("res://login.tscn")

func _on_exit_pressed():
	# Cerrar el juego
	get_tree().quit()
