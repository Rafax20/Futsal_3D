class_name Balon3D
extends RigidBody3D

## Controlador de física para balón reglamentario de fútbol sala (talla 4, bajo rebote) en Godot 4.
## Incluye:
## 1. Trayectoria balística con curva exponencial decaída (F_magnus * e^(-lambda * t)) para Tiro Colocado,
##    garantizando avance continuo hacia portería sin giros en círculos.
## 2. Pase al hueco con impulso limpio (apply_central_impulse) y fricción de rodadura constante y orgánica.
## 3. Registro de cesión intencional con el pie al portero (Regla FIFA Futsal: prohibición de manos).

signal balon_liberado

enum EstadoBalon {
	LIBRE,
	CONDUCIDO
}

@export_group("Física de Futsal 3D")
## Coeficiente de restitución / rebote amortiguado (en futsal es bajo, típicamente entre 0.25 y 0.35).
@export_range(0.0, 1.0, 0.05) var rebote_amortiguado: float = 0.30:
	set(valor):
		rebote_amortiguado = valor
		if is_node_ready() and physics_material_override:
			physics_material_override.bounce = valor

## Coeficiente de fricción en contacto con suelo, paredes y porterías.
@export_range(0.0, 1.0, 0.05) var friccion_suelo: float = 0.42:
	set(valor):
		friccion_suelo = valor
		if is_node_ready() and physics_material_override:
			physics_material_override.friction = valor

## Amortiguación lineal constante que simula la resistencia natural al rodar por la pista (linear_damp).
@export_range(0.0, 10.0, 0.1) var amortiguacion_lineal: float = 0.85:
	set(valor):
		amortiguacion_lineal = valor
		linear_damp = valor

## Desaceleración suave y constante de rodadura sobre el parqué (m/s²).
@export var desaceleracion_rodadura: float = 1.15

## Amortiguación angular que frena la rotación del balón sobre su propio eje (angular_damp).
@export_range(0.0, 10.0, 0.1) var amortiguacion_giro: float = 1.5:
	set(valor):
		amortiguacion_giro = valor
		angular_damp = valor

## Masa del balón en kg (balón reglamentario de futsal talla 4: 410 - 440 gramos).
@export_range(0.1, 2.0, 0.01) var masa_balon: float = 0.43:
	set(valor):
		masa_balon = valor
		mass = valor

@export_group("Límites de Velocidad y Curva Magnus")
## Velocidad máxima en m/s para prevenir túneles de colisión a altas velocidades (~120 km/h).
@export var velocidad_maxima: float = 34.0

## Umbral de velocidad (m/s) por debajo del cual el balón frena por completo.
@export var umbral_detencion: float = 0.15

## Fuerza lateral inicial moderada para el Tiro Colocado (N) y factor de decaimiento exponencial lambda (1/s).
@export var fuerza_magnus_base: float = 2.65
@export var lambda_decaimiento_magnus: float = 3.25

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

# Regla Oficial de Futsal: Cesión al Portero con el pie de un compañero
var es_cesion_pie_companero: bool = false
var equipo_cesion_pie: int = -1

# Indicador de pase al hueco en curso (para seguimiento de cámara/IA, sin frenado magnético artificial)
var _en_pase_hueco: bool = false
var _punto_objetivo_hueco: Vector3 = Vector3.ZERO
var _tiempo_pase_hueco: float = 0.0

# Estado de Curva Balística Decaída para Tiro Colocado (F_magnus * e^(-lambda * t))
var _efecto_magnus_activo: bool = false
var _dir_avance_tiro: Vector3 = Vector3.ZERO
var _dir_lateral_curva: Vector3 = Vector3.ZERO
var _fuerza_magnus_inicial: float = 0.0
var _vel_avance_minima: float = 0.0
var _tiempo_magnus: float = 0.0


func _ready() -> void:
	_configurar_fisicas()


func _physics_process(delta: float) -> void:
	if _t_sin_captura > 0.0:
		_t_sin_captura -= delta
	if estado == EstadoBalon.LIBRE:
		_aplicar_curva_tiro_colocado(delta)
		_controlar_rodadura_y_velocidad(delta)


## Aplica la curva balística del Tiro Colocado mediante una fuerza lateral moderada con decaimiento
## exponencial (F_magnus * e^(-lambda * t)) sobre un eje fijo, garantizando que el vector principal
## de avance hacia la portería nunca se anule ni gire en círculos.
func _aplicar_curva_tiro_colocado(delta: float) -> void:
	if not _efecto_magnus_activo:
		return
	
	_tiempo_magnus += delta
	var vel_plana: Vector3 = Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	var vel_avance_actual: float = vel_plana.dot(_dir_avance_tiro)
	
	# Si el tiempo de vuelo concluyó, o el balón chocó/perdió su avance hacia el arco, desactivar curva
	if _tiempo_magnus > 1.25 or vel_avance_actual < maxf(3.0, _vel_avance_minima * 0.35):
		_efecto_magnus_activo = false
		return
	
	# Fuerza lateral con decaimiento exponencial: F(t) = F_0 * e^(-lambda * t)
	var factor_exponencial: float = exp(-lambda_decaimiento_magnus * _tiempo_magnus)
	var fuerza_lateral: Vector3 = _dir_lateral_curva * (_fuerza_magnus_inicial * factor_exponencial)
	fuerza_lateral.y = 0.0
	apply_central_force(fuerza_lateral)
	
	# Garantizar que el componente de avance hacia la portería nunca se invierta ni sea anulado por la curva
	var vel_despues: Vector3 = Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	var avance_actual: float = vel_despues.dot(_dir_avance_tiro)
	var comp_lateral: float = vel_despues.dot(_dir_lateral_curva)
	var max_lateral_permitido: float = maxf(1.5, avance_actual * 0.38)
	if abs(comp_lateral) > max_lateral_permitido:
		var lateral_corregido: float = clampf(comp_lateral, -max_lateral_permitido, max_lateral_permitido)
		var nueva_vel_plana: Vector3 = _dir_avance_tiro * avance_actual + _dir_lateral_curva * lateral_corregido
		linear_velocity.x = nueva_vel_plana.x
		linear_velocity.z = nueva_vel_plana.z


func _configurar_fisicas() -> void:
	mass = masa_balon
	continuous_cd = true
	linear_damp = amortiguacion_lineal
	angular_damp = amortiguacion_giro
	
	if physics_material_override == null:
		physics_material_override = PhysicsMaterial.new()
	
	physics_material_override.bounce = rebote_amortiguado
	physics_material_override.friction = friccion_suelo


## Controla la fricción de rodadura constante y orgánica sobre la pista sin frenazos artificiales
func _controlar_rodadura_y_velocidad(delta: float = 0.016) -> void:
	var vel_actual: float = linear_velocity.length()
	
	if _en_pase_hueco:
		_tiempo_pase_hueco += delta
		if vel_actual < 1.0 or _tiempo_pase_hueco > 2.8:
			_en_pase_hueco = false
	
	# Fricción de rodadura constante y lineal cuando el balón rueda a ras de suelo
	if global_position.y < 0.36 and vel_actual > umbral_detencion:
		var vel_xz: Vector2 = Vector2(linear_velocity.x, linear_velocity.z)
		var rapidez_xz: float = vel_xz.length()
		if rapidez_xz > 0.01:
			var nueva_rapidez_xz: float = move_toward(rapidez_xz, 0.0, desaceleracion_rodadura * delta)
			var dir_xz: Vector2 = vel_xz / rapidez_xz
			linear_velocity.x = dir_xz.x * nueva_rapidez_xz
			linear_velocity.z = dir_xz.y * nueva_rapidez_xz
		
		# Amortiguar micro-botes verticales propios del balón pesado de futsal
		if abs(linear_velocity.y) < 0.45:
			linear_velocity.y *= 0.80
	
	# Limitar a velocidad máxima
	vel_actual = linear_velocity.length()
	if vel_actual > velocidad_maxima:
		linear_velocity = linear_velocity.normalized() * velocidad_maxima
	elif vel_actual > 0.0 and vel_actual < umbral_detencion:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		_en_pase_hueco = false
		_efecto_magnus_activo = false


## Registra si el último toque fue un pase intencional con el pie de un jugador de campo (Regla de Cesión)
func registrar_toque_cesion_pie(activo: bool, equipo_pasador: int = -1) -> void:
	es_cesion_pie_companero = activo
	equipo_cesion_pie = equipo_pasador if activo else -1


## Retorna true si el portero del equipo indicado tiene PROHIBIDO usar las manos por venir de cesión con el pie
func prohibido_manos_portero(equipo_portero: int) -> bool:
	return es_cesion_pie_companero and equipo_cesion_pie == equipo_portero


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
	linear_damp = amortiguacion_lineal
	portador_actual = jugador
	if jugador and "equipo" in jugador:
		var eq_jug: int = int(jugador.equipo)
		# Si lo controla un rival o un jugador de campo, se limpia el estado previo de cesión
		if eq_jug != equipo_cesion_pie or ("posicion_tactica" in jugador and str(jugador.posicion_tactica) != "PORTERO"):
			es_cesion_pie_companero = false
			equipo_cesion_pie = -1
		ultimo_toque_equipo = eq_jug
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	
	# Aislar la CollisionShape3D del balón respecto a las Area3D de gol mientras esté en manos del portero
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
		global_position = pos_socket
	else:
		var factor_suavizado: float = clampf(22.0 * (firmeza / 85.0), 15.0, 30.0)
		var t: float = clampf(factor_suavizado * delta, 0.0, 1.0)
		global_position = global_position.lerp(pos_socket, t)
	
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


## Libera el balón del portador y aplica un impulso físico limpio
func liberar(impulso: Vector3, equipo_origen: int = -1, es_pase_pie_companero: bool = false) -> void:
	if equipo_origen != -1:
		ultimo_toque_equipo = equipo_origen
	elif portador_actual and "equipo" in portador_actual:
		ultimo_toque_equipo = int(portador_actual.equipo)
	
	registrar_toque_cesion_pie(es_pase_pie_companero, ultimo_toque_equipo)
	_limpiar_portadores_previos(null)
	estado = EstadoBalon.LIBRE
	_en_pase_hueco = false
	_efecto_magnus_activo = false
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


## Libera el balón en Tiro Colocado hacia el poste alejado con fuerza lateral moderada y decaimiento exponencial:
## - impulso: vector inicial dirigido hacia la zona del poste opuesto * velocidad.
## - dir_lateral_curva: vector unitario perpendicular fijo en XZ hacia donde cierra la rosca.
## - intensidad_curva: multiplicador normalizado (0.8 a 1.3) según la calidad/precisión del tirador.
func liberar_con_efecto_magnus(impulso: Vector3, vector_giro_o_lateral: Vector3, equipo_origen: int = -1) -> void:
	liberar(impulso, equipo_origen, false)
	var imp_plano: Vector3 = Vector3(impulso.x, 0.0, impulso.z)
	if imp_plano.length_squared() < 0.1:
		return
	
	_dir_avance_tiro = imp_plano.normalized()
	_vel_avance_minima = imp_plano.length() / maxf(0.1, mass)
	
	# Si se pasó un vector de giro en Y (compatibilidad) o un vector lateral en XZ, obtener la dirección lateral fija
	if abs(vector_giro_o_lateral.y) > 0.01 and abs(vector_giro_o_lateral.x) < 0.01 and abs(vector_giro_o_lateral.z) < 0.01:
		var signo_giro: float = signf(vector_giro_o_lateral.y)
		_dir_lateral_curva = Vector3(0.0, signo_giro, 0.0).cross(_dir_avance_tiro).normalized()
		_fuerza_magnus_inicial = fuerza_magnus_base
	else:
		var lat_plano: Vector3 = Vector3(vector_giro_o_lateral.x, 0.0, vector_giro_o_lateral.z)
		_dir_lateral_curva = lat_plano.normalized() if lat_plano.length_squared() > 0.001 else Vector3(-_dir_avance_tiro.z, 0.0, _dir_avance_tiro.x)
		_fuerza_magnus_inicial = clampf(lat_plano.length(), 1.8, 3.4) if lat_plano.length() > 0.5 else fuerza_magnus_base
	
	_efecto_magnus_activo = true
	_tiempo_magnus = 0.0
	# Rotación visual moderada sin generar torques cíclicos
	angular_velocity = Vector3(0.0, 9.0, 0.0)


## Calcula el módulo del impulso (N·s) necesario para que el balón, rodando bajo linear_damp + fricción de rodadura
## constante, recorra `distancia` metros y llegue con `vel_llegada` m/s (el receptor lo intercepta en movimiento).
## Modelo: v(t) = v0·e^(-d·t) - a_roll·t  =>  v0 ≈ v_llegada + d·D + a_roll·t_estimado
func calcular_impulso_rodado(distancia: float, vel_llegada: float = 4.5) -> float:
	var v_est: float = vel_llegada + distancia * amortiguacion_lineal
	var v_media: float = maxf(3.0, (v_est + vel_llegada) * 0.5)
	var t_vuelo: float = distancia / v_media
	var v0: float = clampf(v_est + desaceleracion_rodadura * t_vuelo, 5.0, 24.0)
	return v0 * masa_balon


## Libera el balón al hueco mediante un impulso físico limpio (apply_central_impulse) con fricción de rodadura
## constante y orgánica, sin frenadas artificiales ni desaceleraciones magnéticas.
func liberar_al_hueco(impulso: Vector3, punto_objetivo: Vector3, equipo_origen: int = -1, es_pase_pie_companero: bool = true) -> void:
	liberar(impulso, equipo_origen, es_pase_pie_companero)
	_en_pase_hueco = true
	_punto_objetivo_hueco = punto_objetivo
	_tiempo_pase_hueco = 0.0
	# Mantenemos la amortiguación lineal natural y constante del RigidBody3D
	linear_damp = amortiguacion_lineal


## Retorna true si el balón puede ser capturado por un jugador específico
func puede_ser_capturado_por(j: Jugador3D) -> bool:
	return (sacador_autorizado == null or j == sacador_autorizado) and puede_ser_capturado()


## Retorna true si el balón puede ser capturado por un jugador
func puede_ser_capturado() -> bool:
	return _t_sin_captura <= 0.0 and not esta_fuera_de_juego


## Retorna true si el balón está actualmente bajo control de algún jugador
func esta_siendo_conducido() -> bool:
	return estado == EstadoBalon.CONDUCIDO and portador_actual != null and is_instance_valid(portador_actual)


## Aplica un impulso tridimensional al balón (despejes, rebotes de atajada).
func patear(fuerza: Vector3, equipo_origen: int = -1) -> void:
	liberar(fuerza, equipo_origen, false)


## Detiene por completo el movimiento lineal y rotacional del balón.
func detener() -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_en_pase_hueco = false
	_efecto_magnus_activo = false


## Coloca el balón en un punto específico para reanudación reglamentaria
func colocar_en_reanudacion(nueva_posicion: Vector3) -> void:
	_limpiar_portadores_previos(null)
	estado = EstadoBalon.LIBRE
	_en_pase_hueco = false
	_efecto_magnus_activo = false
	es_cesion_pie_companero = false
	equipo_cesion_pie = -1
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
