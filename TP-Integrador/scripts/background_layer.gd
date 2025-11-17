extends Node2D

@onready var boat1: Sprite2D = $Boat1
@onready var boat2: Sprite2D = $Boat2
@onready var boat3: Sprite2D = $Boat3

var t: float = 0.0

var base_pos1: Vector2
var base_pos2: Vector2
var base_pos3: Vector2

func _ready() -> void:
	# Guardamos la posición “de reposo” de cada barco
	base_pos1 = boat1.position
	base_pos2 = boat2.position
	base_pos3 = boat3.position

func _process(delta: float) -> void:
	t += delta

	# Boat1 – se mueve poquito
	boat1.position.y = base_pos1.y + sin(t * 1.2) * 4.0
	boat1.position.x = base_pos1.x + cos(t * 0.8) * 3.0
	boat1.rotation_degrees = sin(t * 1.0) * 2.0

	# Boat2 – se tambalea un poco más
	boat2.position.y = base_pos2.y + sin(t * 1.5) * 6.0
	boat2.position.x = base_pos2.x + cos(t * 1.1) * 4.0
	boat2.rotation_degrees = sin(t * 1.3) * 3.0

	# Boat3 – el más inquieto
	boat3.position.y = base_pos3.y + sin(t * 1.8) * 8.0
	boat3.position.x = base_pos3.x + cos(t * 1.4) * 5.0
	boat3.rotation_degrees = sin(t * 1.6) * 4.0
