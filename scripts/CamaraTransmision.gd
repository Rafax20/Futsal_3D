class_name CamaraTransmision
extends Camera3D

## Cámara de transmisión broadcast dinámica estilo FC Mobile / eFootball.
## Sigue el juego con suavidad y amortiguación sin vibraciones, y gestiona
## transiciones cinemáticas fluidas a vista trasera baja en tiros libres.

enum ModoCamara {
	BROADCAST,
	TRANSICION_TIRO_LIBRE,
	TIRO_LIBRE,
	TRANSICION_BROADCAST,
	CENITAL_SELECCION,
	CINEMATICA_FALTA,
	REPETICION_JUGADA
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

@export_group("Tiro Libre Cinemático (Over-The-Shoulder)")
## Distancia detrás del balón para la vista de tiro libre (3.8 m).
@export var distancia_detras_tl: float = 3.8
## Altura de la cámara en tiro libre (1.6 m).
@export var altura_tl: float = 1.6
## Desplazamiento lateral horizontal (0.8 a 1.0 m) para lograr un plano "sobre el hombro" (Over-The-Shoulder) despejado.
@export_range(0.8, 1.0, 0.02) var offset_lateral_tl: float = 0.90
## Factor de interpolación (0..1) entre el balón y el arco rival para el punto de mira de `look_at()`.
@export_range(0.35, 0.85, 0.05) var factor_punto_mira_tl: float = 0.62
## Altura del punto intermedio de mira entre balón y portería.
@export var altura_punto_mira_tl: float = 1.05
## Duración de transición suave entre modos de cámara (segundos).
@export var duracion_transicion_tl: float = 0.78

@export_group("FOV y Calibración Óptica")
@export var fov_tiro_libre: float = 50.0
@export var fov_broadcast: float = 50.0
@export var fov_cenital: float = 50.0

# Estado de cámara
var modo_camara: ModoCamara = ModoCamara.BROADCAST
var _gestor_partido: GestorPartido = null

# Nodos cacheados
var _nodo_balon: Node3D = null
var _nodo_jugador: Node3D = null

# Variables para interpolación, paneo horizontal y retorno tras superar la barrera
var _pos_origen_tl: Vector3 = Vector3.ZERO
var _pos_arco_rival_tl: Vector3 = Vector3.ZERO
var _dir_base_arco_tl: Vector3 = Vector3(1.0, 0.0, 0.0)
var _distancia_barrera_tl: float = 5.0
var _offset_lateral_actual_tl: float = 0.90
var _angulo_paneo_yaw_tl: float = 0.0
var _balon_pateado_tl: bool = false
var _tiempo_desde_patada_tl: float = 0.0

var _tf_origen_transicion: Transform3D
var _tf_destino_transicion: Transform3D
var _t_transicion_acumulada: float = 0.0
var _duracion_transicion_actual: float = 0.82

# Variables cinemáticas de presentación de faltas y repetición
var _tf_cinematica_objetivo: Transform3D
var _punto_mira_cinematica: Vector3 = Vector3.ZERO
var _en_cinematica_activa: bool = false


func _ready() -> void:
	add_to_group("camara_transmision")
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
		var eq_sacador: int = _gestor_partido.obtener_equipo_sacador() if _gestor_partido else -1
		if eq_sacador == 0:
			var pos_b: Vector3 = _gestor_partido.obtener_pos_saque()
			var pos_arco: Vector3 = Vector3(20.0, 0.0, 0.0) # Portería rival para equipo local
			var dist_al_arco: float = pos_b.distance_to(pos_arco)
			if dist_al_arco <= 15.0:
				activar_camara_tiro_libre(pos_b, pos_arco, 5.0)
			else:
				regresar_a_broadcast(0.75)
		else:
			# Si saca la CPU / Visitante, NUNCA activar cámara trasera de tiro libre
			regresar_a_broadcast(0.5)
	elif nuevo_estado == GestorPartido.EstadoPartido.EN_JUEGO or nuevo_estado == GestorPartido.EstadoPartido.SAQUE_META or nuevo_estado == GestorPartido.EstadoPartido.SAQUE_BANDA or nuevo_estado == GestorPartido.EstadoPartido.SAQUE_CENTRO:
		regresar_a_broadcast(0.75)


const LIMITE_YAW_TL_RAD: float = deg_to_rad(40.0) # Cono de paneo horizontal reglamentario (±40°)

## Activa la vista de Tiro Libre "Sobre el Hombro" (Over-The-Shoulder):
## - Define un vector de referencia inmutable para cada tiro libre:
##   `base_forward = (goal_center_position - ball_position).normalized()` en el plano XZ.
## - Los límites de paneo horizontal de la cámara trasera (clamp yaw: -40° a +40°) se calculan
##   siempre relativos a `base_forward`, NUNCA al transform local del jugador.
## - Al conmutar entre vistas, restablece la orientación al centro del arco o al último ángulo
##   válido dentro de `base_forward`, evitando desorientación hacia las bandas.
func activar_camara_tiro_libre(
	pos_balon: Vector3,
	pos_arco: Vector3,
	dist_barrera: float = 5.0,
	offset_perfil: float = -1.0,
	_dir_lanzador_ignorado: Vector3 = Vector3.ZERO,
	inmediato: bool = false
) -> void:
	_pos_origen_tl = pos_balon
	_pos_arco_rival_tl = pos_arco
	_distancia_barrera_tl = dist_barrera
	_offset_lateral_actual_tl = offset_lateral_tl if offset_perfil < 0.0 else clampf(offset_perfil, 0.8, 1.0)
	_balon_pateado_tl = false
	_tiempo_desde_patada_tl = 0.0

	if _en_cinematica_activa:
		_en_cinematica_activa = false
		aplicar_lod_bias_personajes(1.0)

	# 1. Vector de referencia inmutable para cada tiro libre (apuntando al centro de portería rival):
	var base_forward: Vector3 = Vector3(pos_arco.x - pos_balon.x, 0.0, pos_arco.z - pos_balon.z).normalized()
	if base_forward.length_squared() < 0.01:
		base_forward = Vector3(1.0, 0.0, 0.0)
	_dir_base_arco_tl = base_forward

	# 2. Si el usuario conmuta entre vistas o inicia la fase de tiro, restablecer la orientación centrada al arco (0.0 rad)
	# o clampear estrictamente dentro del cono inmutable [-40°, +40°]
	_angulo_paneo_yaw_tl = clampf(_angulo_paneo_yaw_tl, -LIMITE_YAW_TL_RAD, LIMITE_YAW_TL_RAD)
	if modo_camara == ModoCamara.BROADCAST or modo_camara == ModoCamara.CENITAL_SELECCION or modo_camara == ModoCamara.TRANSICION_BROADCAST:
		_angulo_paneo_yaw_tl = 0.0

	# Restablecer FOV, ángulo y altura de cámara en vista de tiro
	fov = fov_tiro_libre

	var tf_objetivo: Transform3D = _calcular_transform_tiro_libre()

	# Si se solicita inmediato o venimos de la vista cenital de selección de posición,
	# aplicar el transform inmediatamente para evitar giros o interpolaciones a ángulos incoherentes
	if inmediato or modo_camara == ModoCamara.CENITAL_SELECCION:
		global_transform = tf_objetivo
		_tf_origen_transicion = tf_objetivo
		_tf_destino_transicion = tf_objetivo
		_t_transicion_acumulada = 0.0
		modo_camara = ModoCamara.TIRO_LIBRE
	else:
		_tf_origen_transicion = global_transform
		_tf_destino_transicion = tf_objetivo
		_t_transicion_acumulada = 0.0
		_duracion_transicion_actual = duracion_transicion_tl
		modo_camara = ModoCamara.TRANSICION_TIRO_LIBRE


## Calcula el Transform3D de la cámara en modo Tiro Libre (Over-The-Shoulder)
## siguiendo un punto pivote fijo vinculado directamente a (Ball.position + Lanzador.forward)
func _calcular_transform_tiro_libre() -> Transform3D:
	var dir_arco: Vector3 = _dir_base_arco_tl.rotated(Vector3.UP, _angulo_paneo_yaw_tl).normalized()
	var vec_derecha: Vector3 = Vector3(-dir_arco.z, 0.0, dir_arco.x).normalized()

	# Posición de la cámara Over-The-Shoulder:
	# 3.8 m detrás del balón, altura calibrada (1.6 m) y offset lateral (0.9 m)
	var pos_camara: Vector3 = (
		_pos_origen_tl
		- dir_arco * distancia_detras_tl
		+ vec_derecha * _offset_lateral_actual_tl
	)
	pos_camara.y = altura_tl

	# Punto pivote fijo vinculado a (Ball.position + base_forward)
	# en lugar de alternar o quedar huérfano entre coordenadas viejas y nuevas
	var dist_pivote: float = 7.5
	var punto_pivote_target: Vector3 = _pos_origen_tl + dir_arco * dist_pivote + vec_derecha * (_offset_lateral_actual_tl * 0.25)
	punto_pivote_target.y = altura_punto_mira_tl

	var tf_objetivo: Transform3D = Transform3D().looking_at(punto_pivote_target - pos_camara, Vector3.UP)
	tf_objetivo.origin = pos_camara
	return tf_objetivo


## Ajusta el ángulo horizontal de paneo de la cámara durante el apuntado del Tiro Libre (Zona Izquierda de la pantalla)
func ajustar_paneo_tiro_libre(delta_yaw_rad: float) -> void:
	if modo_camara != ModoCamara.TIRO_LIBRE and modo_camara != ModoCamara.TRANSICION_TIRO_LIBRE:
		return
	if _balon_pateado_tl:
		return
	_angulo_paneo_yaw_tl = clampf(_angulo_paneo_yaw_tl + delta_yaw_rad, -LIMITE_YAW_TL_RAD, LIMITE_YAW_TL_RAD)
	_tf_destino_transicion = _calcular_transform_tiro_libre()
	if modo_camara == ModoCamara.TIRO_LIBRE:
		global_transform = _tf_destino_transicion


## Retorna el ángulo horizontal de paneo acumulado en radianes
func obtener_angulo_paneo_tl() -> float:
	return _angulo_paneo_yaw_tl


## Retorna el vector unitario horizontal hacia donde apunta actualmente la cámara de tiro libre
func obtener_direccion_apuntado_tl() -> Vector3:
	return _dir_base_arco_tl.rotated(Vector3.UP, _angulo_paneo_yaw_tl).normalized()


## Notifica a la cámara el instante exacto en que el pie del lanzador impacta el balón tras la carrera previa
func notificar_impacto_tiro_libre() -> void:
	_balon_pateado_tl = true
	_tiempo_desde_patada_tl = 0.0


## Inicia la transición interpolada suave de regreso a la vista broadcast
func regresar_a_broadcast(duracion: float = 0.9) -> void:
	_en_cinematica_activa = false
	aplicar_lod_bias_personajes(1.0)
	if not is_current():
		make_current()
	if modo_camara == ModoCamara.BROADCAST or modo_camara == ModoCamara.TRANSICION_BROADCAST:
		return
	fov = fov_broadcast
	_tf_origen_transicion = global_transform
	_t_transicion_acumulada = 0.0
	_duracion_transicion_actual = duracion
	modo_camara = ModoCamara.TRANSICION_BROADCAST


## Asegura que la cámara principal de transmisión esté activa, en perspectiva broadcast y con LOD normal
func asegurar_camara_principal() -> void:
	if not is_current():
		make_current()
	if modo_camara == ModoCamara.CINEMATICA_FALTA or modo_camara == ModoCamara.REPETICION_JUGADA or modo_camara == ModoCamara.TIRO_LIBRE:
		regresar_a_broadcast(0.5)
	aplicar_lod_bias_personajes(1.0)


## Modifica el sesgo de LOD (lod_bias) en todos los jugadores del campo y en el árbitro
func aplicar_lod_bias_personajes(bias: float) -> void:
	if get_tree() == null:
		return
	var jugadores: Array[Node] = get_tree().get_nodes_in_group("jugadores_futsal")
	for n: Node in jugadores:
		var j: Jugador3D = n as Jugador3D
		if j and is_instance_valid(j) and j.has_method("establecer_lod_bias"):
			j.establecer_lod_bias(bias)
	
	var arbitros: Array[Node] = get_tree().get_nodes_in_group("arbitro_3d")
	for a: Node in arbitros:
		if a and is_instance_valid(a) and a.has_method("establecer_lod_bias"):
			a.call("establecer_lod_bias", bias)


## Activa la cámara cinemática a ras de campo (distancia 2.2 a 3.5m, altura 1.35m, FOV 45.0) en contrapicado
func activar_camara_cinematica_falta(
	pos_infractor: Vector3,
	pos_referencia: Vector3,
	_es_tarjeta: bool = true,
	inmediato: bool = false
) -> void:
	_en_cinematica_activa = true
	fov = 45.0
	aplicar_lod_bias_personajes(4.0)

	var centro_accion: Vector3 = pos_infractor.lerp(pos_referencia, 0.40)
	var dir_eje: Vector3 = (pos_referencia - pos_infractor)
	dir_eje.y = 0.0
	if dir_eje.length_squared() < 0.01:
		dir_eje = Vector3(1.0, 0.0, 0.0)
	else:
		dir_eje = dir_eje.normalized()
	
	var vec_lateral: Vector3 = Vector3(-dir_eje.z, 0.0, dir_eje.x).normalized()
	if (centro_accion.z > 0.0 and vec_lateral.z > 0.0) or (centro_accion.z < 0.0 and vec_lateral.z < 0.0):
		vec_lateral = -vec_lateral
	
	var pos_camara: Vector3 = centro_accion + vec_lateral * 2.85 - dir_eje * 0.35
	pos_camara.y = 1.35
	pos_camara.x = clampf(pos_camara.x, -18.5, 18.5)
	pos_camara.z = clampf(pos_camara.z, -8.8, 8.8)

	_punto_mira_cinematica = centro_accion + Vector3(0.0, 1.45, 0.0)
	var dir_mira: Vector3 = (_punto_mira_cinematica - pos_camara).normalized()
	var tf_cinematica: Transform3D = Transform3D().looking_at(dir_mira, Vector3.UP)
	tf_cinematica.origin = pos_camara

	_tf_cinematica_objetivo = tf_cinematica
	modo_camara = ModoCamara.CINEMATICA_FALTA

	if inmediato:
		global_transform = tf_cinematica
	else:
		var tw: Tween = create_tween().set_ignore_time_scale(true)
		tw.tween_property(self, "global_transform", tf_cinematica, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Activa la cámara cercana dinámica para la repetición breve de la falta o impacto
func activar_camara_repeticion(pos_contacto: Vector3) -> void:
	_en_cinematica_activa = true
	fov = 45.0
	aplicar_lod_bias_personajes(4.0)
	
	var pos_camara: Vector3 = pos_contacto + Vector3(0.0, 1.45, 3.2)
	pos_camara.x = clampf(pos_camara.x, -18.0, 18.0)
	pos_camara.z = clampf(pos_camara.z, -8.5, 8.5)
	
	_punto_mira_cinematica = pos_contacto + Vector3(0.0, 0.85, 0.0)
	var dir_mira: Vector3 = (_punto_mira_cinematica - pos_camara).normalized()
	var tf_rep: Transform3D = Transform3D().looking_at(dir_mira, Vector3.UP)
	tf_rep.origin = pos_camara
	
	_tf_cinematica_objetivo = tf_rep
	global_transform = tf_rep
	modo_camara = ModoCamara.REPETICION_JUGADA


## Coloca de inmediato la cámara hacia la vista cenital enfocando el medio campo rival (Modo Selección de Posición)
func activar_camara_cenital_seleccion(centro_campo_ofensivo: Vector3 = Vector3(10.0, 0.0, 0.0), altura_cenital: float = 24.5, _inmediato: bool = true) -> void:
	_balon_pateado_tl = false
	_tiempo_desde_patada_tl = 0.0
	_angulo_paneo_yaw_tl = 0.0
	fov = fov_cenital
	var pos_cam: Vector3 = Vector3(centro_campo_ofensivo.x, altura_cenital, centro_campo_ofensivo.z)
	var punto_mira: Vector3 = Vector3(centro_campo_ofensivo.x, 0.0, centro_campo_ofensivo.z)
	var tf_cenital: Transform3D = Transform3D().looking_at(punto_mira - pos_cam, Vector3(0.0, 0.0, -1.0))
	tf_cenital.origin = pos_cam
	
	global_transform = tf_cenital
	_tf_origen_transicion = tf_cenital
	_tf_destino_transicion = tf_cenital
	modo_camara = ModoCamara.CENITAL_SELECCION


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
		
		ModoCamara.CENITAL_SELECCION:
			pass
		
		ModoCamara.CINEMATICA_FALTA:
			if _punto_mira_cinematica.length_squared() > 0.01:
				var dir_mira_c: Vector3 = (_punto_mira_cinematica - global_position).normalized()
				var tf_mira_c: Transform3D = Transform3D().looking_at(dir_mira_c, Vector3.UP)
				tf_mira_c.origin = global_position
				global_transform = global_transform.interpolate_with(tf_mira_c, clampf(delta * 4.0, 0.0, 1.0))
		
		ModoCamara.REPETICION_JUGADA:
			if _punto_mira_cinematica.length_squared() > 0.01:
				var dir_mira_r: Vector3 = (_punto_mira_cinematica - global_position).normalized()
				var tf_mira_r: Transform3D = Transform3D().looking_at(dir_mira_r, Vector3.UP)
				tf_mira_r.origin = global_position
				global_transform = global_transform.interpolate_with(tf_mira_r, clampf(delta * 5.0, 0.0, 1.0))


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
	if dist_origen > 0.38:
		_balon_pateado_tl = true

	if not _balon_pateado_tl:
		# Mientras no se haya pateado, interpolar suavemente el ángulo de paneo Over-The-Shoulder
		global_transform = global_transform.interpolate_with(_tf_destino_transicion, clampf(delta * 12.0, 0.0, 1.0))
		return

	_tiempo_desde_patada_tl += delta

	# Regla eFootball: Al rebasar la barrera (5.0 metros), transicionar con interpolación suave a la vista de seguimiento aéreo
	if dist_origen >= _distancia_barrera_tl:
		regresar_a_broadcast(0.85)
		return

	# Timeout de contingencia (rebote en barrera, detención, etc.)
	var vel_balon: float = 0.0
	if balon is RigidBody3D:
		vel_balon = (balon as RigidBody3D).linear_velocity.length()

	if _tiempo_desde_patada_tl > 1.35 or (_tiempo_desde_patada_tl > 0.35 and vel_balon < 0.9):
		regresar_a_broadcast(0.85)
		return

	# Seguimiento suave de elevación y trayectoria del balón mientras se aproxima a la barrera
	var punto_mira_vuelo: Vector3 = pos_b.lerp(_pos_arco_rival_tl + Vector3(0.0, 1.1, 0.0), 0.45)
	var dir_mira: Vector3 = punto_mira_vuelo - global_position
	if dir_mira.length_squared() > 0.01:
		var tf_mira: Transform3D = global_transform.looking_at(punto_mira_vuelo, Vector3.UP)
		global_transform = global_transform.interpolate_with(tf_mira, clampf(delta * 5.5, 0.0, 1.0))


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

