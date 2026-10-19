class_name CamaraTransmision
extends Camera3D

## Cámara de transmisión broadcast dinámica estilo FC Mobile / eFootball.
## Sigue el juego con suavidad y amortiguación sin vibraciones, manteniendo
## un encuadre profesional de la pista de futsal y los desmarques tácticos.

@export_group("Objetivo de Seguimiento")
## Ruta al nodo principal a seguir (típicamente el balón).
@export var ruta_balon: NodePath = ^"../Balon3D"
## Jugador con posesión o jugador activo si aplica.
@export var ruta_jugador_activo: NodePath = ^"../Jugadores/Local_Pivot"

@export_group("Encuadre Broadcast")
## Altura constante de la cámara respecto al piso.
@export_range(10.0, 40.0, 0.5) var altura_camara: float = 21.0
## Distancia en Z hacia atrás para la vista televisiva en banda.
@export_range(10.0, 40.0, 0.5) var distancia_z: float = 23.0
## Ángulo de inclinación cenital hacia el centro de la jugada.
@export_range(-80.0, -10.0, 0.5) var inclinacion_grados: float = -42.0
## Factor de suavizado (velocidad de seguimiento de la cámara sin tirones).
@export_range(1.0, 15.0, 0.5) var factor_suavizado: float = 4.5

@export_group("Límites del Estadio (Clamping)")
## Límite mínimo en X para que la cámara no se desplace fuera del estadio.
@export var limite_min_x: float = -13.0
## Límite máximo en X.
@export var limite_max_x: float = 13.0
## Límite mínimo en Z.
@export var limite_min_z: float = -3.5
## Límite máximo en Z.
@export var limite_max_z: float = 3.5

# Nodos cacheados
var _nodo_balon: Node3D = null
var _nodo_jugador: Node3D = null


func _ready() -> void:
	if has_node(ruta_balon):
		_nodo_balon = get_node(ruta_balon) as Node3D
	if has_node(ruta_jugador_activo):
		_nodo_jugador = get_node(ruta_jugador_activo) as Node3D
	
	# Inicializar orientación fija broadcast
	rotation_degrees = Vector3(inclinacion_grados, 0.0, 0.0)


func _physics_process(delta: float) -> void:
	var punto_foco: Vector3 = _obtener_punto_foco()
	
	# Clamping para mantener la cámara dentro de los límites visuales del pabellón
	var foco_x_clampeado: float = clampf(punto_foco.x, limite_min_x, limite_max_x)
	var foco_z_clampeado: float = clampf(punto_foco.z, limite_min_z, limite_max_z)
	
	var pos_deseada: Vector3 = Vector3(
		foco_x_clampeado,
		altura_camara,
		foco_z_clampeado + distancia_z
	)
	
	# Interpolación exponencial suave (independiente de framerate)
	var factor_amortiguacion: float = 1.0 - exp(-factor_suavizado * delta)
	global_position.x = lerpf(global_position.x, pos_deseada.x, factor_amortiguacion)
	global_position.y = altura_camara
	global_position.z = lerpf(global_position.z, pos_deseada.z, factor_amortiguacion)
	
	# Mantener ángulo constante broadcast sin balanceo
	rotation_degrees.x = inclinacion_grados
	rotation_degrees.y = 0.0
	rotation_degrees.z = 0.0


func _obtener_punto_foco() -> Vector3:
	if _nodo_balon == null or not is_instance_valid(_nodo_balon):
		if has_node(ruta_balon):
			_nodo_balon = get_node(ruta_balon) as Node3D
		elif get_tree() != null:
			var balones: Array[Node] = get_tree().get_nodes_in_group("balon")
			if not balones.is_empty():
				_nodo_balon = balones[0] as Node3D
	
	if _nodo_balon != null and is_instance_valid(_nodo_balon):
		return _nodo_balon.global_position
	elif _nodo_jugador != null and is_instance_valid(_nodo_jugador):
		return _nodo_jugador.global_position
	
	return Vector3.ZERO
