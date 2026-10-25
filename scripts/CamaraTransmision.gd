class_name CamaraTransmision
extends Camera3D

## Cámara de transmisión broadcast dinámica estilo FC Mobile / eFootball.
## Sigue el juego con suavidad y amortiguación sin vibraciones, y gestiona
## transiciones cinemáticas fluidas a vista trasera baja en tiros libres.

enum ModoCamara {
	BROADCAST,
	TRANSICION_TIRO_LIBRE,
	TIRO_LIBRE,
	TRANSICION_BROADCAST
}

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

@export_group("Tiro Libre Cinemático")
## Distancia detrás del balón para la vista trasera baja (3.5 m).
@export var distancia_detras_tl: float = 3.5
## Altura de la cámara en tiro libre (1.8 m).
@export var altura_tl: float = 1.8
## Duración de transición suave entre modos de cámara (segundos).
@export var duracion_transicion_tl: float = 0.82

# Estado de cámara
var modo_camara: ModoCamara = ModoCamara.BROADCAST
var _gestor_partido: GestorPartido = null

# Nodos cacheados
var _nodo_balon: Node3D = null
var _nodo_jugador: Node3D = null

# Variables para interpolación y retorno tras superar la barrera
var _pos_origen_tl: Vector3 = Vector3.ZERO
var _pos_arco_rival_tl: Vector3 = Vector3.ZERO
var _distancia_barrera_tl: float = 5.0
var _balon_pateado_tl: bool = false
var _tiempo_desde_patada_tl: float = 0.0

var _tf_origen_transicion: Transform3D
var _tf_destino_transicion: Transform3D
var _t_transicion_acumulada: float = 0.0
var _duracion_transicion_actual: float = 0.82


func _ready() -> void:
	if has_node(ruta_balon):
		_nodo_balon = get_node(ruta_balon) as Node3D
	if has_node(ruta_jugador_activo):
		_nodo_jugador = get_node(ruta_jugador_activo) as Node3D
	
	# Inicializar orientación fija broadcast
	rotation_degrees = Vector3(inclinacion_grados, 0.0, 0.0)
	_conectar_gestor_partido()


func _conectar_gestor_partido() -> void:
	if _gestor_partido == null:
		_gestor_partido = get_tree().get_first_node_in_group("gestor_partido") as GestorPartido
		if _gestor_partido and not _gestor_partido.estado_cambiado.is_connected(_on_estado_partido_cambiado):
			_gestor_partido.estado_cambiado.connect(_on_estado_partido_cambiado)


func _on_estado_partido_cambiado(nuevo_estado: GestorPartido.EstadoPartido) -> void:
	if nuevo_estado == GestorPartido.EstadoPartido.TIRO_LIBRE or nuevo_estado == GestorPartido.EstadoPartido.DOBLE_PENALTI:
		if _gestor_partido and _gestor_partido.obtener_equipo_sacador() == 0:
			var pos_b: Vector3 = _gestor_partido.obtener_pos_saque()
			var pos_arco: Vector3 = Vector3(20.0, 0.0, 0.0) # Portería rival para equipo local
			activar_camara_tiro_libre(pos_b, pos_arco, 5.0)
	elif nuevo_estado == GestorPartido.EstadoPartido.EN_JUEGO:
		if modo_camara == ModoCamara.TIRO_LIBRE and not _balon_pateado_tl:
			regresar_a_broadcast(0.85)


## Activa la transición suave a la vista trasera baja orientada al arco rival
func activar_camara_tiro_libre(pos_balon: Vector3, pos_arco: Vector3, dist_barrera: float = 5.0) -> void:
	_pos_origen_tl = pos_balon
	_pos_arco_rival_tl = pos_arco
	_distancia_barrera_tl = dist_barrera
	_balon_pateado_tl = false
	_tiempo_desde_patada_tl = 0.0
	
	# Vector unitario en dirección hacia la portería rival
	var dir_hacia_arco: Vector3 = (pos_arco - pos_balon).normalized()
	if dir_hacia_arco.length_squared() < 0.01:
		dir_hacia_arco = Vector3(1.0, 0.0, 0.0)
	
	# Vista trasera baja: 3.5 m detrás del balón, altura 1.8 m
	var pos_camara: Vector3 = pos_balon - dir_hacia_arco * distancia_detras_tl
	pos_camara.y = altura_tl
	
	# Orientada con look_at hacia la portería rival
	var punto_mira: Vector3 = Vector3(pos_arco.x, 1.1, pos_arco.z)
	var tf_objetivo: Transform3D = Transform3D().looking_at(punto_mira - pos_camara, Vector3.UP)
	tf_objetivo.origin = pos_camara
	
	_tf_origen_transicion = global_transform
	_tf_destino_transicion = tf_objetivo
	_t_transicion_acumulada = 0.0
	_duracion_transicion_actual = duracion_transicion_tl
	modo_camara = ModoCamara.TRANSICION_TIRO_LIBRE


## Inicia la transición interpolada suave de regreso a la vista broadcast
func regresar_a_broadcast(duracion: float = 0.9) -> void:
	if modo_camara == ModoCamara.BROADCAST or modo_camara == ModoCamara.TRANSICION_BROADCAST:
		return
	_tf_origen_transicion = global_transform
	_t_transicion_acumulada = 0.0
	_duracion_transicion_actual = duracion
	modo_camara = ModoCamara.TRANSICION_BROADCAST


func _physics_process(delta: float) -> void:
	if _gestor_partido == null:
		_conectar_gestor_partido()
	
	match modo_camara:
		ModoCamara.BROADCAST:
			_procesar_camara_broadcast(delta)
		
		ModoCamara.TRANSICION_TIRO_LIBRE:
			_t_transicion_acumulada += delta
			var peso: float = clampf(_t_transicion_acumulada / _duracion_transicion_actual, 0.0, 1.0)
			var t_suave: float = peso * peso * (3.0 - 2.0 * peso)
			global_transform = _tf_origen_transicion.interpolate_with(_tf_destino_transicion, t_suave)
			if peso >= 1.0:
				global_transform = _tf_destino_transicion
				modo_camara = ModoCamara.TIRO_LIBRE
		
		ModoCamara.TIRO_LIBRE:
			_procesar_seguimiento_tiro_libre(delta)
		
		ModoCamara.TRANSICION_BROADCAST:
			_t_transicion_acumulada += delta
			var peso_b: float = clampf(_t_transicion_acumulada / _duracion_transicion_actual, 0.0, 1.0)
			var t_suave_b: float = peso_b * peso_b * (3.0 - 2.0 * peso_b)
			var tf_dest_b: Transform3D = _obtener_transform_broadcast()
			global_transform = _tf_origen_transicion.interpolate_with(tf_dest_b, t_suave_b)
			if peso_b >= 1.0:
				modo_camara = ModoCamara.BROADCAST


func _procesar_camara_broadcast(delta: float) -> void:
	var punto_foco: Vector3 = _obtener_punto_foco()
	var foco_x_clampeado: float = clampf(punto_foco.x, limite_min_x, limite_max_x)
	var foco_z_clampeado: float = clampf(punto_foco.z, limite_min_z, limite_max_z)
	
	var pos_deseada: Vector3 = Vector3(
		foco_x_clampeado,
		altura_camara,
		foco_z_clampeado + distancia_z
	)
	
	var factor_amortiguacion: float = 1.0 - exp(-factor_suavizado * delta)
	global_position.x = lerpf(global_position.x, pos_deseada.x, factor_amortiguacion)
	global_position.y = altura_camara
	global_position.z = lerpf(global_position.z, pos_deseada.z, factor_amortiguacion)
	
	rotation_degrees.x = inclinacion_grados
	rotation_degrees.y = 0.0
	rotation_degrees.z = 0.0


func _obtener_transform_broadcast() -> Transform3D:
	var punto_foco: Vector3 = _obtener_punto_foco()
	var foco_x_clampeado: float = clampf(punto_foco.x, limite_min_x, limite_max_x)
	var foco_z_clampeado: float = clampf(punto_foco.z, limite_min_z, limite_max_z)
	var pos_deseada: Vector3 = Vector3(foco_x_clampeado, altura_camara, foco_z_clampeado + distancia_z)
	var rot_rad: Vector3 = Vector3(deg_to_rad(inclinacion_grados), 0.0, 0.0)
	return Transform3D(Basis.from_euler(rot_rad), pos_deseada)


func _procesar_seguimiento_tiro_libre(delta: float) -> void:
	var balon: Node3D = _obtener_nodo_balon()
	if balon == null or not is_instance_valid(balon):
		return
	
	var pos_b: Vector3 = balon.global_position
	var dist_origen: float = pos_b.distance_to(_pos_origen_tl)
	
	# Detectar salida del balón desde el punto de tiro libre
	if dist_origen > 0.45:
		_balon_pateado_tl = true
	
	if _balon_pateado_tl:
		_tiempo_desde_patada_tl += delta
		
		# Regla eFootball: Al superar la barrera (5.0 metros), volver suavemente a vista aérea estándar
		if dist_origen >= (_distancia_barrera_tl + 0.15):
			regresar_a_broadcast(0.92)
			return
		
		# Timeout de contingencia (rebote en barrera, detención, etc.)
		var vel_balon: float = 0.0
		if balon is RigidBody3D:
			vel_balon = (balon as RigidBody3D).linear_velocity.length()
		
		if _tiempo_desde_patada_tl > 1.35 or (_tiempo_desde_patada_tl > 0.4 and vel_balon < 0.9):
			regresar_a_broadcast(0.92)
			return
		
		# Micro-seguimiento angular hacia el balón mientras se eleva hacia la barrera
		var dir_balon: Vector3 = (pos_b - global_position).normalized()
		if dir_balon.length_squared() > 0.01:
			var tf_mira: Transform3D = global_transform.looking_at(pos_b + Vector3(0, 0.3, 0), Vector3.UP)
			global_transform = global_transform.interpolate_with(tf_mira, delta * 4.0)


func _obtener_nodo_balon() -> Node3D:
	if _nodo_balon != null and is_instance_valid(_nodo_balon):
		return _nodo_balon
	if has_node(ruta_balon):
		_nodo_balon = get_node(ruta_balon) as Node3D
		return _nodo_balon
	if get_tree() != null:
		var balones: Array[Node] = get_tree().get_nodes_in_group("balon")
		if not balones.is_empty():
			_nodo_balon = balones[0] as Node3D
			return _nodo_balon
	return null


func _obtener_punto_foco() -> Vector3:
	var balon: Node3D = _obtener_nodo_balon()
	var foco_base: Vector3 = Vector3.ZERO
	if balon != null and is_instance_valid(balon):
		foco_base = balon.global_position
	elif _nodo_jugador != null and is_instance_valid(_nodo_jugador):
		foco_base = _nodo_jugador.global_position
	
	# Prioridad de encuadre para el compañero en desmarque "Pasa y Corre" (es_opcion_de_pase == true)
	if get_tree() != null:
		var locales: Array[Node] = get_tree().get_nodes_in_group("equipo_local")
		for n: Node in locales:
			if n != null and is_instance_valid(n) and "es_opcion_de_pase" in n and bool(n.es_opcion_de_pase):
				var corredor: Node3D = n as Node3D
				if corredor:
					foco_base = foco_base.lerp(corredor.global_position, 0.22)
					break
	
	return foco_base

