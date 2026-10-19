class_name Balon3D
extends RigidBody3D

## Controlador de física para balón pesado de fútbol sala (medio pique) en Godot 4.
## Soporta estados de juego (LIBRE y CONDUCIDO) para posesión magnética estilo FC Mobile.

signal balon_liberado

enum EstadoBalon {
	LIBRE,
	CONDUCIDO
}

@export_group("Física de Futsal 3D")
## Coeficiente de restitución / rebote amortiguado (en futsal es bajo, típicamente entre 0.25 y 0.35).
@export_range(0.0, 1.0, 0.05) var rebote_amortiguado: float = 0.32:
	set(valor):
		rebote_amortiguado = valor
		if is_node_ready() and physics_material_override:
			physics_material_override.bounce = valor

## Coeficiente de fricción en contacto con suelo, paredes y porterías.
@export_range(0.0, 1.0, 0.05) var friccion_suelo: float = 0.45:
	set(valor):
		friccion_suelo = valor
		if is_node_ready() and physics_material_override:
			physics_material_override.friction = valor

## Amortiguación lineal que simula la resistencia y arrastre al rodar por la pista (linear_damp).
@export_range(0.0, 10.0, 0.1) var amortiguacion_lineal: float = 0.9:
	set(valor):
		amortiguacion_lineal = valor
		linear_damp = valor

## Amortiguación angular que frena la rotación del balón sobre su propio eje (angular_damp).
@export_range(0.0, 10.0, 0.1) var amortiguacion_giro: float = 1.4:
	set(valor):
		amortiguacion_giro = valor
		angular_damp = valor

## Masa del balón en kg (balón reglamentario de futsal talla 4: 410 - 440 gramos).
@export_range(0.1, 2.0, 0.01) var masa_balon: float = 0.43:
	set(valor):
		masa_balon = valor
		mass = valor

@export_group("Límites de Velocidad")
## Velocidad máxima en m/s para prevenir túneles de colisión a altas velocidades (~120 km/h).
@export var velocidad_maxima: float = 34.0

## Umbral de velocidad (m/s) por debajo del cual el balón frena por completo.
@export var umbral_detencion: float = 0.15

# Referencias a nodos hijos
@onready var collision_shape_3d: CollisionShape3D = $CollisionShape3D
@onready var mesh_instance_3d: MeshInstance3D = $MeshInstance3D

# Estado de Posesión y Conducción
var estado: EstadoBalon = EstadoBalon.LIBRE
var portador_actual: Node3D = null
var ultimo_toque_equipo: int = 0 # 0: Local, 1: Visitante
var esta_fuera_de_juego: bool = false
var _t_sin_captura: float = 0.0
var sacador_autorizado: Jugador3D = null

# Curva de desaceleración progresiva para pases al hueco (rodado pesado de futsal)
var _en_pase_hueco: bool = false
var _punto_objetivo_hueco: Vector3 = Vector3.ZERO
var _tiempo_pase_hueco: float = 0.0

# Efecto Magnus aerodinámico para Tiro Colocado (Swipe Down)
var _efecto_magnus_activo: bool = false
var _vector_giro_magnus: Vector3 = Vector3.ZERO
var _tiempo_magnus: float = 0.0
@export var coeficiente_magnus: float = 0.24


func _ready() -> void:
	_configurar_fisicas()


func _physics_process(delta: float) -> void:
	if _t_sin_captura > 0.0:
		_t_sin_captura -= delta
	if estado == EstadoBalon.LIBRE:
		_aplicar_efecto_magnus(delta)
		_controlar_velocidad(delta)


func _aplicar_efecto_magnus(delta: float) -> void:
	if not _efecto_magnus_activo:
		return
	_tiempo_magnus += delta
	var vel_plana: Vector3 = Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	if _tiempo_magnus > 1.65 or vel_plana.length() < 2.2:
		_efecto_magnus_activo = false
		_vector_giro_magnus = Vector3.ZERO
		return
	
	# Fuerza de Magnus: F_m = k * (omega x v)
	var fuerza_magnus: Vector3 = _vector_giro_magnus.cross(vel_plana) * coeficiente_magnus
	fuerza_magnus.y = 0.0
	apply_central_force(fuerza_magnus)
	# Decaimiento suave del spin aerodinámico
	_vector_giro_magnus = _vector_giro_magnus.move_toward(Vector3.ZERO, delta * 3.5)


func _configurar_fisicas() -> void:
	mass = masa_balon
	continuous_cd = true
	linear_damp = amortiguacion_lineal
	angular_damp = amortiguacion_giro
	
	if physics_material_override == null:
		physics_material_override = PhysicsMaterial.new()
	
	physics_material_override.bounce = rebote_amortiguado
	physics_material_override.friction = friccion_suelo


func _controlar_velocidad(delta: float = 0.016) -> void:
	var vel_actual: float = linear_velocity.length()
	
	# Curva de desaceleración y fricción específica para el rodado en pase al hueco
	if _en_pase_hueco:
		_tiempo_pase_hueco += delta
		var dist_al_hueco: float = Vector2(global_position.x - _punto_objetivo_hueco.x, global_position.z - _punto_objetivo_hueco.z).length()
		
		# A medida que el balón se aproxima a P_destino, aplicamos mayor fricción de pista para que se asiente en el hueco
		if dist_al_hueco < 3.2:
			var factor_frenado: float = lerpf(4.8, 1.6, clampf(dist_al_hueco / 3.2, 0.0, 1.0))
			linear_velocity.x = move_toward(linear_velocity.x, 0.0, factor_frenado * delta * maxf(vel_actual, 2.5))
			linear_velocity.z = move_toward(linear_velocity.z, 0.0, factor_frenado * delta * maxf(vel_actual, 2.5))
		
		# Amortiguar bote vertical para simular balón oficial de futsal de bajo rebote
		if global_position.y < 0.45 and abs(linear_velocity.y) > 0.2:
			linear_velocity.y *= 0.72
		
		if vel_actual < 1.2 or _tiempo_pase_hueco > 2.6:
			_en_pase_hueco = false
			linear_damp = amortiguacion_lineal
	
	# Limitar a velocidad máxima
	if vel_actual > velocidad_maxima:
		linear_velocity = linear_velocity.normalized() * velocidad_maxima
	# Detener completamente si la velocidad residual es despreciable
	elif vel_actual > 0.0 and vel_actual < umbral_detencion:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		_en_pase_hueco = false
		_efecto_magnus_activo = false


## Limpia el flag de posesión en cualquier jugador previo para evitar posesiones fantasmas
func _limpiar_portadores_previos(excepto: Node3D = null) -> void:
	if portador_actual != null and is_instance_valid(portador_actual) and portador_actual != excepto:
		if portador_actual.has_method("soltar_posesion"):
			portador_actual.soltar_posesion()
	
	if get_tree() != null:
		var jugadores: Array[Node] = get_tree().get_nodes_in_group("jugadores_futsal")
		for n: Node in jugadores:
			if n != null and is_instance_valid(n) and n != excepto:
				if "tiene_posesion" in n and n.tiene_posesion:
					n.tiene_posesion = false
				if "tiene_balon_en_manos" in n and n.tiene_balon_en_manos:
					n.tiene_balon_en_manos = false


## Pasa el balón al estado de posesión magnética con el jugador indicado
func capturar_por(jugador: Node3D) -> void:
	_limpiar_portadores_previos(jugador)
	estado = EstadoBalon.CONDUCIDO
	_en_pase_hueco = false
	_efecto_magnus_activo = false
	_vector_giro_magnus = Vector3.ZERO
	linear_damp = amortiguacion_lineal
	portador_actual = jugador
	if jugador and "equipo" in jugador:
		ultimo_toque_equipo = int(jugador.equipo)
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	
	# Aislar la CollisionShape3D del balón respecto a las Area3D de gol mientras esté en posesión del portero
	var es_portero_con_manos: bool = false
	if jugador != null:
		if ("tiene_balon_en_manos" in jugador and bool(jugador.tiene_balon_en_manos)) or ("posicion_tactica" in jugador and str(jugador.posicion_tactica) == "PORTERO"):
			es_portero_con_manos = true
	if collision_shape_3d:
		collision_shape_3d.set_deferred("disabled", es_portero_con_manos)


## Interpola suavemente la posición del balón hacia el socket de conducción del portador
func conducir_hacia(pos_socket: Vector3, delta: float, firmeza: float, conductor: Node3D = null) -> void:
	if estado != EstadoBalon.CONDUCIDO or portador_actual == null or not is_instance_valid(portador_actual):
		return
	if conductor != null and conductor != portador_actual:
		return
	
	var dist_socket: float = global_position.distance_to(pos_socket)
	if dist_socket > 1.6:
		# Si hubo un salto brusco o recepción lejana, ajustar inmediatamente al pie
		global_position = pos_socket
	else:
		# Ponderación de interpolación basada en control_balon (70 a 99)
		var factor_suavizado: float = clampf(22.0 * (firmeza / 85.0), 15.0, 30.0)
		var t: float = clampf(factor_suavizado * delta, 0.0, 1.0)
		global_position = global_position.lerp(pos_socket, t)
	
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


## Libera el balón del portador y aplica un impulso físico
func liberar(impulso: Vector3, equipo_origen: int = -1) -> void:
	if equipo_origen != -1:
		ultimo_toque_equipo = equipo_origen
	elif portador_actual and "equipo" in portador_actual:
		ultimo_toque_equipo = int(portador_actual.equipo)
	
	_limpiar_portadores_previos(null)
	estado = EstadoBalon.LIBRE
	_en_pase_hueco = false
	_efecto_magnus_activo = false
	_vector_giro_magnus = Vector3.ZERO
	linear_damp = amortiguacion_lineal
	portador_actual = null
	if collision_shape_3d:
		collision_shape_3d.set_deferred("disabled", false)
	freeze = false
	sleeping = false
	_t_sin_captura = 0.15
	balon_liberado.emit()
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	apply_central_impulse(impulso)


## Libera el balón aplicando Efecto Magnus (curva de calidad para Tiro Colocado / Swipe Down)
func liberar_con_efecto_magnus(impulso: Vector3, vector_giro: Vector3, equipo_origen: int = -1) -> void:
	liberar(impulso, equipo_origen)
	_efecto_magnus_activo = true
	_vector_giro_magnus = vector_giro
	_tiempo_magnus = 0.0
	angular_velocity = vector_giro


## Libera el balón con curva de desaceleración progresiva hacia un punto proyectado en el espacio libre
func liberar_al_hueco(impulso: Vector3, punto_objetivo: Vector3, equipo_origen: int = -1) -> void:
	liberar(impulso, equipo_origen)
	_en_pase_hueco = true
	_punto_objetivo_hueco = punto_objetivo
	_tiempo_pase_hueco = 0.0
	linear_damp = amortiguacion_lineal * 1.35


## Retorna true si el balón puede ser capturado por un jugador específico (true si sacador_autorizado == null o j == sacador_autorizado)
func puede_ser_capturado_por(j: Jugador3D) -> bool:
	return (sacador_autorizado == null or j == sacador_autorizado) and puede_ser_capturado()


## Retorna true si el balón puede ser capturado por un jugador
func puede_ser_capturado() -> bool:
	return _t_sin_captura <= 0.0 and not esta_fuera_de_juego


## Retorna true si el balón está actualmente bajo control de algún jugador
func esta_siendo_conducido() -> bool:
	return estado == EstadoBalon.CONDUCIDO and portador_actual != null and is_instance_valid(portador_actual)


## Aplica un impulso tridimensional al balón (pases, disparos, despejes).
func patear(fuerza: Vector3, equipo_origen: int = -1) -> void:
	liberar(fuerza, equipo_origen)


## Detiene por completo el movimiento lineal y rotacional del balón.
func detener() -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_en_pase_hueco = false


## Coloca el balón en un punto específico para reanudación reglamentaria (saques de banda, meta, córner)
func colocar_en_reanudacion(nueva_posicion: Vector3) -> void:
	_limpiar_portadores_previos(null)
	estado = EstadoBalon.LIBRE
	_en_pase_hueco = false
	linear_damp = amortiguacion_lineal
	portador_actual = null
	if collision_shape_3d:
		collision_shape_3d.set_deferred("disabled", false)
	freeze = false
	sleeping = false
	detener()
	global_position = nueva_posicion
	esta_fuera_de_juego = false


## Restablece la posición del balón y cancela toda fuerza acumulada.
func reiniciar_posicion(nueva_posicion: Vector3 = Vector3(0.0, 0.25, 0.0)) -> void:
	colocar_en_reanudacion(nueva_posicion)

