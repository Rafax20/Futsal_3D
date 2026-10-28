class_name Balon3D
extends RigidBody3D

## Controlador de física para balón reglamentario de fútbol sala (talla 4, bajo rebote) en Godot 4.
## Incluye:
## 1. Trayectoria balística con curva exponencial decaída (F_magnus * e^(-lambda * t)) para Tiro Colocado,
##    garantizando avance continuo hacia portería sin giros en círculos.
## 2. Pase al hueco con impulso limpio (apply_central_impulse) y fricción de rodadura constante y orgánica.
## 3. Registro de cesión intencional con el pie al portero (Regla FIFA Futsal: prohibición de manos).

signal balon_liberado
signal atajada_realizada(zona: String, nombre_arquero: String)
signal bloqueo_barrera_realizado(defensor: Jugador3D, zona: String)
signal mano_cometida(defensor: Jugador3D, posicion: Vector3, es_penal: bool)

enum EstadoBalon {
	LIBRE,
	CONDUCIDO
}

var _t_cooldown_impacto_arquero: float = 0.0
var _t_cooldown_impacto_barrera: float = 0.0

@export_group("Física de Futsal 3D")
## Coeficiente de restitución / rebote amortiguado (FIFA Tamaño 4: bajo rebote, máx. 55-65 cm en caída libre).
@export_range(0.0, 1.0, 0.01) var rebote_amortiguado: float = 0.28:
	set(valor):
		rebote_amortiguado = valor
		if is_node_ready() and physics_material_override:
			physics_material_override.bounce = valor

## Coeficiente de fricción en contacto con suelo, paredes y porterías.
@export_range(0.0, 1.0, 0.01) var friccion_suelo: float = 0.45:
	set(valor):
		friccion_suelo = valor
		if is_node_ready() and physics_material_override:
			physics_material_override.friction = valor

## Amortiguación lineal constante que simula la resistencia en pista de fútsal (linear_damp = 0.3).
@export_range(0.0, 10.0, 0.05) var amortiguacion_lineal: float = 0.3:
	set(valor):
		amortiguacion_lineal = valor
		linear_damp = valor

## Desaceleración suave y constante de rodadura sobre el parqué (m/s²).
@export var desaceleracion_rodadura: float = 1.15

## Amortiguación angular que frena la rotación del balón sobre su propio eje (angular_damp = 1.3).
@export_range(0.0, 10.0, 0.05) var amortiguacion_giro: float = 1.3:
	set(valor):
		amortiguacion_giro = valor
		angular_damp = valor

## Masa del balón en kg (balón reglamentario FIFA Futsal Tamaño 4: 430 gramos).
@export_range(0.1, 2.0, 0.01) var masa_balon: float = 0.43:
	set(valor):
		masa_balon = valor
		mass = valor

## Radio reglamentario del balón de fútsal ajustado a proporción anatómica (FIFA Tamaño 4 escalado: 0.143 m / 14.3 cm de radio, 28.6 cm de diámetro).
@export_range(0.05, 0.30, 0.005) var radio_balon: float = 0.143

@export_group("Límites de Velocidad, Curva Magnus y Cucharita")
## Velocidad máxima en m/s para prevenir túneles de colisión a altas velocidades (~120 km/h).
@export var velocidad_maxima: float = 34.0

## Umbral de velocidad (m/s) por debajo del cual el balón frena por completo.
@export var umbral_detencion: float = 0.15

## Fuerza lateral inicial moderada para el Tiro Colocado (N) y factor de decaimiento exponencial lambda (1/s).
@export var fuerza_magnus_base: float = 2.65
@export var lambda_decaimiento_magnus: float = 2.85

## Factor de spin Magnus proporcional a la densidad y masa del balón de fútsal (0.43 kg).
@export var factor_spin: float = 3.85

## Factor de torque negativo sobre el eje X de la cámara para generar backspin regresivo en "Cucharita" (N·m·s).
@export var backspin_factor: float = 0.32

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

# Regla FIFA/IFAB Futsal: Tiro Directo vs. Indirecto y Control de Doble Toque
var es_tiro_indirecto: bool = false
var toques_en_jugada: int = 0
var ultimo_ejecutor_saque: Node3D = null

# Control estricto de auto-recepción del pasador (cooldown de doble toque en pases rasos y saques)
var ultimo_pasador: Node3D = null
var _t_bloqueo_pasador: float = 0.0

# Indicador de pase al hueco en curso (para seguimiento de cámara/IA, sin frenado magnético artificial)
var _en_pase_hueco: bool = false
var _punto_objetivo_hueco: Vector3 = Vector3.ZERO
var _tiempo_pase_hueco: float = 0.0

# Estado de Curva Balística Decaída para Tiro Colocado y Tiro Libre Swipe (F_magnus * e^(-lambda * t))
var _efecto_magnus_activo: bool = false
var _dir_avance_tiro: Vector3 = Vector3.ZERO
var _dir_lateral_curva: Vector3 = Vector3.ZERO
var _fuerza_magnus_inicial: float = 0.0
var _vector_fuerza_magnus: Vector3 = Vector3.ZERO
var _vel_avance_minima: float = 0.0
var _tiempo_magnus: float = 0.0


## Retorna el radio exacto de la colisión o malla del balón para contacto perfecto con el suelo
func obtener_radio_efectivo() -> float:
	if collision_shape_3d and collision_shape_3d.shape is SphereShape3D:
		return (collision_shape_3d.shape as SphereShape3D).radius
	return radio_balon


func _ready() -> void:
	_configurar_fisicas()
	if not body_entered.is_connected(_on_cuerpo_contactado):
		body_entered.connect(_on_cuerpo_contactado)


func _physics_process(delta: float) -> void:
	if _t_cooldown_impacto_arquero > 0.0:
		_t_cooldown_impacto_arquero -= delta
	if _t_cooldown_impacto_barrera > 0.0:
		_t_cooldown_impacto_barrera -= delta
	if _t_sin_captura > 0.0:
		_t_sin_captura -= delta
	if _t_bloqueo_pasador > 0.0:
		_t_bloqueo_pasador -= delta
		if _t_bloqueo_pasador <= 0.0:
			ultimo_pasador = null
	if estado == EstadoBalon.LIBRE:
		_verificar_colision_alta_velocidad_raycast(delta)
		_aplicar_curva_tiro_colocado(delta)
		_controlar_rodadura_y_velocidad(delta)


## Aplica la curva balística del Tiro Colocado / Swipe mediante la fuerza Magnus proporcional a la masa
## y densidad del balón de fútsal (`fuerza_magnus = vector_lateral * curvatura_swipe * factor_spin`)
## con decaimiento exponencial (F_magnus * e^(-lambda * t)), garantizando avance continuo hacia portería.
func _aplicar_curva_tiro_colocado(delta: float) -> void:
	if not _efecto_magnus_activo:
		return
	
	_tiempo_magnus += delta
	var vel_plana: Vector3 = Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	var vel_avance_actual: float = vel_plana.dot(_dir_avance_tiro)
	
	# Si el tiempo de vuelo concluyó, o el balón chocó/perdió su avance hacia el arco, desactivar curva
	if _tiempo_magnus > 1.85 or vel_avance_actual < maxf(1.8, _vel_avance_minima * 0.25):
		_efecto_magnus_activo = false
		return
	
	# Fuerza Magnus con decaimiento exponencial: F(t) = fuerza_magnus * e^(-lambda * t)
	var factor_exponencial: float = exp(-lambda_decaimiento_magnus * _tiempo_magnus)
	var fuerza_lateral: Vector3 = _vector_fuerza_magnus * factor_exponencial
	if fuerza_lateral.length_squared() < 0.0001:
		fuerza_lateral = _dir_lateral_curva * (_fuerza_magnus_inicial * factor_exponencial)
	fuerza_lateral.y = 0.0
	apply_central_force(fuerza_lateral)
	
	# Garantizar que el componente de avance hacia la portería nunca se invierta ni sea anulado por la curva
	if _dir_lateral_curva.length_squared() > 0.01:
		var vel_despues: Vector3 = Vector3(linear_velocity.x, 0.0, linear_velocity.z)
		var avance_actual: float = vel_despues.dot(_dir_avance_tiro)
		var comp_lateral: float = vel_despues.dot(_dir_lateral_curva)
		var max_lateral_permitido: float = maxf(1.5, avance_actual * 0.42)
		if abs(comp_lateral) > max_lateral_permitido:
			var lateral_corregido: float = clampf(comp_lateral, -max_lateral_permitido, max_lateral_permitido)
			var nueva_vel_plana: Vector3 = _dir_avance_tiro * avance_actual + _dir_lateral_curva * lateral_corregido
			linear_velocity.x = nueva_vel_plana.x
			linear_velocity.z = nueva_vel_plana.z


func _configurar_fisicas() -> void:
	mass = masa_balon
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	linear_damp = amortiguacion_lineal
	angular_damp = amortiguacion_giro
	
	if physics_material_override == null:
		physics_material_override = PhysicsMaterial.new()
	
	physics_material_override.bounce = rebote_amortiguado
	physics_material_override.friction = friccion_suelo


## Registra el contacto físico de un jugador distinto al pateador inicial (habilita segundo toque y valida goles tras tiro indirecto)
func registrar_contacto_jugador(jugador: Node3D) -> void:
	if jugador == null or not is_instance_valid(jugador):
		return
	if jugador != ultimo_pasador and jugador != ultimo_ejecutor_saque:
		if ultimo_pasador != null and is_instance_valid(ultimo_pasador) and ultimo_pasador.has_method("desbloquear_recaptura"):
			ultimo_pasador.desbloquear_recaptura()
		ultimo_pasador = null
		_t_bloqueo_pasador = 0.0
		if toques_en_jugada >= 1:
			toques_en_jugada += 1
			ultimo_ejecutor_saque = null


func _on_cuerpo_contactado(body: Node) -> void:
	if body != null and (body.is_in_group("postes_arco") or body.name == "MarcoPostes"):
		# Impacto con poste o travesaño: cancelar efecto Magnus para rebote balístico 100% natural
		_efecto_magnus_activo = false
		_fuerza_magnus_inicial = 0.0
		_tiempo_magnus = 99.0
		_dir_lateral_curva = Vector3.ZERO
	elif estado == EstadoBalon.LIBRE and body is Jugador3D:
		registrar_contacto_jugador(body as Node3D)


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


## Procesa la respuesta física, desvíos y atajadas anatómicas ante impactos con las hitboxes del arquero
func procesar_impacto_arquero(zona: String, arquero: Jugador3D) -> void:
	if _t_cooldown_impacto_arquero > 0.0:
		return
	if esta_fuera_de_juego:
		return
	
	_t_cooldown_impacto_arquero = 0.35
	_efecto_magnus_activo = false
	toques_en_jugada += 1
	sleeping = false
	
	var nombre_arq: String = "ARQUERO"
	if arquero and is_instance_valid(arquero):
		nombre_arq = arquero.nombre_jugador if arquero.nombre_jugador != "" else ("#%d" % arquero.dorsal)
	
	var vel_tiro: float = linear_velocity.length()
	
	match zona:
		"manos":
			if vel_tiro < 12.0:
				# Velocidad baja (< 12 m/s): El arquero embolsa (bloquea y toma posesión inmediata del balón)
				linear_velocity = Vector3.ZERO
				angular_velocity = Vector3.ZERO
				if arquero and is_instance_valid(arquero):
					arquero.atrapar_con_manos(self)
				atajada_realizada.emit("manos", nombre_arq)
			else:
				# Tiro potente (> 12 m/s): Aplica un desvío angular hacia el lateral/córner con atenuación lineal (linear_velocity *= 0.45)
				var dir_alej_x: float = -1.0 if (arquero and arquero.global_position.x > 0.0) else 1.0
				var dir_lat_z: float = 1.0 if (arquero and global_position.z >= arquero.global_position.z) else -1.0
				var dir_desvio: Vector3 = Vector3(dir_alej_x * 0.45, 0.22, dir_lat_z * 0.88).normalized()
				var rapidez_atenuada: float = vel_tiro * 0.45
				linear_velocity = dir_desvio * rapidez_atenuada
				angular_velocity = Vector3(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0), randf_range(-4.0, 4.0))
				atajada_realizada.emit("manos", nombre_arq)
		
		"pecho", "cabeza":
			# Rebote hacia el frente con bajo coeficiente de restitución (bounce = 0.2), suelto en el área
			var dir_frente_x: float = -1.0 if (arquero and arquero.global_position.x > 0.0) else 1.0
			var diff_z: float = global_position.z - (arquero.global_position.z if arquero else 0.0)
			var dir_rebote_pecho: Vector3 = Vector3(dir_frente_x * 0.90, 0.16, clampf(diff_z * 0.65, -0.6, 0.6)).normalized()
			var rapidez_pecho: float = maxf(2.4, vel_tiro * 0.20)
			linear_velocity = dir_rebote_pecho * rapidez_pecho
			angular_velocity = Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0))
			atajada_realizada.emit("pecho", nombre_arq)
		
		"piernas":
			# Rebote seco hacia afuera de la portería, manteniendo la altura a ras de piso (velocity.y *= 0.2)
			var dir_despeje_x: float = -1.0 if (arquero and arquero.global_position.x > 0.0) else 1.0
			var dir_pie_z: float = 1.0 if (arquero and global_position.z >= arquero.global_position.z) else -1.0
			var dir_piernas: Vector3 = Vector3(dir_despeje_x * 0.75, 0.0, dir_pie_z * 0.70).normalized()
			var rapidez_piernas: float = maxf(3.8, vel_tiro * 0.38)
			linear_velocity = dir_piernas * rapidez_piernas
			linear_velocity.y = linear_velocity.y * 0.20
			angular_velocity = Vector3(0.0, randf_range(-3.0, 3.0), 0.0)
			atajada_realizada.emit("piernas", nombre_arq)
		
		_:
			linear_velocity *= 0.40
			atajada_realizada.emit(zona, nombre_arq)
	
	if arquero and is_instance_valid(arquero) and arquero.has_signal("atajada_realizada"):
		arquero.atajada_realizada.emit(zona, nombre_arq)


## Procesa la respuesta física de rebote o sanción disciplinaria ante impactos con la barrera defensiva
## (Segmentación "Torso_Legs_Head" vs "Arms_Hands")
func procesar_impacto_barrera(zona: String, defensor: Jugador3D, punto_impacto: Vector3 = Vector3.ZERO) -> void:
	if _t_cooldown_impacto_barrera > 0.0 or esta_fuera_de_juego:
		return
	_t_cooldown_impacto_barrera = 0.35
	_efecto_magnus_activo = false
	toques_en_jugada += 1
	sleeping = false

	if zona == "Arms_Hands" or zona == "brazos_manos":
		# Infracción por mano en posición antinatural (T-Pose / brazos extendidos)
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		var es_penal: bool = false
		var pos_eval: Vector3 = punto_impacto if punto_impacto != Vector3.ZERO else (defensor.global_position if defensor else global_position)
		var pos_arco_rival: Vector3 = Vector3(20.0, 0.0, 0.0)
		# En fútsal: área penal de 6.0 m desde la línea de portería
		if Vector2(pos_eval.x, pos_eval.z).distance_to(Vector2(pos_arco_rival.x, pos_arco_rival.z)) <= 6.2 or (pos_eval.x >= 14.0 and abs(pos_eval.z) <= 5.5):
			es_penal = true

		mano_cometida.emit(defensor, pos_eval, es_penal)
		if defensor and is_instance_valid(defensor) and defensor.has_signal("mano_en_barrera"):
			defensor.mano_en_barrera.emit(pos_eval, es_penal)
	else:
		# Bloqueo reglamentario: "Torso_Legs_Head"
		# Cancela trayectoria directa y calcula rebote elástico hacia la cancha con impulsos físicos
		var vel_tiro: float = linear_velocity.length()
		var dir_def: Vector3 = -defensor.global_transform.basis.z if defensor else Vector3(-1.0, 0.0, 0.0)
		dir_def.y = 0.0
		if dir_def.length_squared() < 0.01:
			dir_def = Vector3(-1.0, 0.0, 0.0)
		dir_def = dir_def.normalized()

		var vec_lat: Vector3 = defensor.global_transform.basis.x if defensor else Vector3(0.0, 0.0, 1.0)
		vec_lat.y = 0.0
		vec_lat = vec_lat.normalized()

		var diff_lateral: float = 0.0
		if defensor:
			var vec_rel: Vector3 = global_position - defensor.global_position
			diff_lateral = clampf(vec_rel.dot(vec_lat), -0.5, 0.5)

		# Rebote elástico hacia la pista con elevación y dispersión natural
		var dir_rebote: Vector3 = (dir_def * 0.88 + vec_lat * (diff_lateral * 0.6) + Vector3(0.0, 0.20, 0.0)).normalized()
		var rapidez_rebote: float = clampf(vel_tiro * 0.44, 4.2, 11.5)
		linear_velocity = dir_rebote * rapidez_rebote
		angular_velocity = Vector3(randf_range(-4.5, 4.5), randf_range(-2.0, 2.0), randf_range(-4.5, 4.5))

		bloqueo_barrera_realizado.emit(defensor, "Torso_Legs_Head")
		if defensor and is_instance_valid(defensor) and defensor.has_signal("bloqueo_barrera"):
			defensor.bloqueo_barrera.emit("Torso_Legs_Head")


## Comprueba mediante raycasting denso si el balón atraviesa o impacta una hitbox anatómica
## (barrera o arquero) en este paso de física a alta velocidad, evitando el efecto túnel.
func _verificar_colision_alta_velocidad_raycast(delta: float) -> void:
	if linear_velocity.length_squared() < 16.0:
		return
	var pos_actual: Vector3 = global_position
	var paso: Vector3 = linear_velocity * delta
	var pos_siguiente: Vector3 = pos_actual + paso + paso.normalized() * (radio_balon * 0.8)

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space_state == null:
		return
	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(pos_actual, pos_siguiente)
	params.collide_with_areas = true
	params.collide_with_bodies = false
	params.collision_mask = 1 | 2

	var res: Dictionary = space_state.intersect_ray(params)
	if res.is_empty():
		return

	var collider = res.collider
	var hit_pos: Vector3 = res.position
	if collider is Area3D:
		var area: Area3D = collider as Area3D
		if area.is_in_group("Arms_Hands"):
			var def: Jugador3D = area.get_meta("defensor", null) as Jugador3D
			procesar_impacto_barrera("Arms_Hands", def, hit_pos)
		elif area.is_in_group("Torso_Legs_Head"):
			var def: Jugador3D = area.get_meta("defensor", null) as Jugador3D
			procesar_impacto_barrera("Torso_Legs_Head", def, hit_pos)
		elif area.is_in_group("hitbox_arquero"):
			var arq: Jugador3D = area.get_meta("arquero", null) as Jugador3D
			var zona: String = area.get_meta("zona_cuerpo", "")
			procesar_impacto_arquero(zona, arq)


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
	if jugador != null and jugador != ultimo_pasador and jugador != ultimo_ejecutor_saque:
		if ultimo_pasador != null and is_instance_valid(ultimo_pasador) and ultimo_pasador.has_method("desbloquear_recaptura"):
			ultimo_pasador.desbloquear_recaptura()
		ultimo_pasador = null
		_t_bloqueo_pasador = 0.0
		if toques_en_jugada >= 1:
			toques_en_jugada += 1
			ultimo_ejecutor_saque = null
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


## Registra al jugador pasador y bloquea su recaptura hasta que expire el cooldown o intervenga otro jugador
func registrar_pasador(pasador: Node3D, duracion: float = 1.0) -> void:
	ultimo_pasador = pasador
	_t_bloqueo_pasador = duracion


## Libera el balón del portador y aplica un impulso físico limpio, contabilizando `toques_en_jugada`
func liberar(impulso: Vector3, equipo_origen: int = -1, es_pase_pie_companero: bool = false, pasador: Node3D = null) -> void:
	var ejecutante: Node3D = pasador
	if ejecutante == null:
		ejecutante = portador_actual if portador_actual != null else sacador_autorizado
	
	if ejecutante != null:
		registrar_pasador(ejecutante, 1.0)
	
	if equipo_origen != -1:
		ultimo_toque_equipo = equipo_origen
	elif portador_actual and "equipo" in portador_actual:
		ultimo_toque_equipo = int(portador_actual.equipo)
	elif ejecutante and "equipo" in ejecutante:
		ultimo_toque_equipo = int(ejecutante.equipo)
	
	# Contabilizar toques en jugada para la regla de Tiro Indirecto y Doble Toque
	if toques_en_jugada == 0 or sacador_autorizado != null:
		toques_en_jugada = 1
		ultimo_ejecutor_saque = ejecutante
	else:
		toques_en_jugada += 1
		ultimo_ejecutor_saque = null
	
	sacador_autorizado = null
	registrar_toque_cesion_pie(es_pase_pie_companero, ultimo_toque_equipo)
	_limpiar_portadores_previos(null)
	estado = EstadoBalon.LIBRE
	_en_pase_hueco = false
	_efecto_magnus_activo = false
	_vector_fuerza_magnus = Vector3.ZERO
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


## Mecánica de "Cucharita" (Pase elevado / Vaselina):
## - Reduce la fuerza de avance hacia adelante (Z) en un 40-50% (factor 0.55) a favor de la componente vertical (Y).
## - Aplica un torque negativo sobre el eje local X de la cámara activa para generar backspin regresivo:
##   `apply_torque_impulse(-camera.global_transform.basis.x * backspin_factor)`
func liberar_cucharita(
	impulso_base: Vector3,
	camera: Camera3D = null,
	equipo_origen: int = 0,
	es_pase_pie_companero: bool = false
) -> void:
	var cam_activa: Camera3D = camera
	if cam_activa == null and get_viewport() != null:
		cam_activa = get_viewport().get_camera_3d()
	
	# Reducir la fuerza hacia adelante (plano XZ / frontal Z) en un 45% (rango 40-50%) a favor de la componente vertical (Y)
	var imp_horiz: Vector3 = Vector3(impulso_base.x, 0.0, impulso_base.z)
	var mag_horiz_original: float = imp_horiz.length()
	var imp_horiz_reducido: Vector3 = imp_horiz * 0.55
	var transferencia_vertical: float = mag_horiz_original * 0.45
	var imp_vertical_final: float = maxf(impulso_base.y, transferencia_vertical)
	var impulso_cucharita: Vector3 = Vector3(imp_horiz_reducido.x, imp_vertical_final, imp_horiz_reducido.z)
	
	liberar(impulso_cucharita, equipo_origen, es_pase_pie_companero)
	
	# Aplicar torque negativo sobre el eje local X de la cámara para generar backspin regresivo
	if cam_activa != null and is_instance_valid(cam_activa):
		apply_torque_impulse(-cam_activa.global_transform.basis.x * backspin_factor)
	elif imp_horiz.length_squared() > 0.001:
		var dir_av: Vector3 = imp_horiz.normalized()
		var eje_x_local: Vector3 = Vector3(-dir_av.z, 0.0, dir_av.x).normalized()
		apply_torque_impulse(-eje_x_local * backspin_factor)


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
	
	_vector_fuerza_magnus = _dir_lateral_curva * _fuerza_magnus_inicial
	_efecto_magnus_activo = true
	_tiempo_magnus = 0.0
	# Rotación visual moderada sin generar torques cíclicos
	angular_velocity = Vector3(0.0, 9.0, 0.0)


## Libera el balón en tiro libre por trazo táctil (Swipe) aplicando impulso, proyección 3D de cámara,
## fuerza Magnus (`fuerza_magnus = vector_lateral * curvatura_swipe * factor_spin`) y soporte de "Cucharita":
## - impulso: vector tridimensional proyectado con los ejes de la cámara activa.
## - curvatura_swipe: curvatura normalizada [-1.0, 1.0] (positiva: derecha de cámara; negativa: izquierda de cámara).
## - equipo_origen: identificador del equipo ejecutor (0: Local, 1: Visitante).
## - camera: cámara activa de referencia para `vector_lateral` y eje de torque de backspin.
## - es_cucharita: si es true, aplica la reducción del 40-50% de fuerza frontal a favor de Y + backspin regresivo.
func liberar_tiro_libre_swipe(
	impulso: Vector3,
	curvatura_swipe: float,
	equipo_origen: int = 0,
	camera: Camera3D = null,
	es_cucharita: bool = false
) -> void:
	var cam_activa: Camera3D = camera
	if cam_activa == null and get_viewport() != null:
		cam_activa = get_viewport().get_camera_3d()
	
	if es_cucharita:
		liberar_cucharita(impulso, cam_activa, equipo_origen, false)
	else:
		liberar(impulso, equipo_origen, false)
	
	var imp_plano: Vector3 = Vector3(linear_velocity.x, 0.0, linear_velocity.z) * mass
	if imp_plano.length_squared() < 0.05:
		imp_plano = Vector3(impulso.x, 0.0, impulso.z)
	if imp_plano.length_squared() < 0.05:
		return
	
	_dir_avance_tiro = imp_plano.normalized()
	_vel_avance_minima = imp_plano.length() / maxf(0.1, mass)
	
	# Vector lateral de la cámara activa proyectado en el plano horizontal (o perpendicular al avance como respaldo)
	var vector_lateral: Vector3 = Vector3(-_dir_avance_tiro.z, 0.0, _dir_avance_tiro.x).normalized()
	if cam_activa != null and is_instance_valid(cam_activa):
		var lat_cam: Vector3 = cam_activa.global_transform.basis.x
		lat_cam.y = 0.0
		if lat_cam.length_squared() > 0.001:
			vector_lateral = lat_cam.normalized()
	
	# Fuerza Magnus proporcional a la densidad y masa del balón de fútsal:
	# fuerza_magnus = vector_lateral * curvatura_swipe * factor_spin
	var fuerza_magnus: Vector3 = vector_lateral * curvatura_swipe * factor_spin
	_vector_fuerza_magnus = fuerza_magnus
	_fuerza_magnus_inicial = fuerza_magnus.length()
	_dir_lateral_curva = fuerza_magnus.normalized() if _fuerza_magnus_inicial > 0.001 else vector_lateral * signf(curvatura_swipe)
	_efecto_magnus_activo = (absf(curvatura_swipe) > 0.04)
	_tiempo_magnus = 0.0
	
	# Si no fue cucharita con backspin, asignar rotación angular visual sobre el eje vertical coherente con el spin Magnus
	if not es_cucharita:
		angular_velocity = Vector3(0.0, -curvatura_swipe * 18.0, 0.0)
	elif absf(curvatura_swipe) > 0.04:
		angular_velocity.y = -curvatura_swipe * 12.0


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


## Libera el balón en pase raso firme hacia los pies de un compañero con física reglamentaria de fútsal:
## - linear_damp = 0.3 (fricción de parqué) y amortiguación angular (1.3)
## - anulación de componente vertical (Y = 0) para rodadura limpia a ras de suelo
## - registro de cesión intencional (es_cesion_pie_companero = true) y cómputo de toques en jugada
func liberar_pase_raso(impulso: Vector3, equipo_origen: int = 0, es_pase_pie_companero: bool = true, pasador: Node3D = null) -> void:
	var imp_raso: Vector3 = Vector3(impulso.x, 0.0, impulso.z)
	liberar(imp_raso, equipo_origen, es_pase_pie_companero, pasador)
	linear_damp = 0.3
	angular_damp = 1.3
	linear_velocity.y = 0.0


## Retorna true si el balón puede ser capturado por un jugador específico:
## - Mientras el saque no se haya ejecutado (`sacador_autorizado != null`), solo el sacador autorizado puede tomarlo.
## - Regla del Doble Toque (FIFA/IFAB): el pateador (`ultimo_ejecutor_saque`) NO puede volver a contactar
##   el balón hasta que `toques_en_jugada >= 2` (tocado por otro jugador o arquero).
## - Cooldown estricto de auto-recepción del pasador (`_t_bloqueo_pasador > 0.0` y `ultimo_pasador`).
func puede_ser_capturado_por(j: Jugador3D) -> bool:
	if not puede_ser_capturado():
		return false
	if sacador_autorizado != null and j != sacador_autorizado:
		return false
	if _t_bloqueo_pasador > 0.0 and ultimo_pasador != null and j == ultimo_pasador:
		return false
	if toques_en_jugada == 1 and ultimo_ejecutor_saque != null and j == ultimo_ejecutor_saque:
		return false
	return true


## Retorna true si el gol es válido según la regla de Tiro Libre Indirecto:
## Si `es_tiro_indirecto == true` y `toques_en_jugada == 1` (sin haber tocado a ningún otro jugador), el gol NO es válido.
func es_gol_valido_reglamentario() -> bool:
	return not (es_tiro_indirecto and toques_en_jugada <= 1)


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


## Configura el balón en un punto específico para una reanudación reglamentaria indicando si es tiro indirecto
func configurar_saque_reglamentario(nueva_posicion: Vector3, autor_saque: Jugador3D = null, indirecto: bool = false) -> void:
	colocar_en_reanudacion(nueva_posicion)
	sacador_autorizado = autor_saque
	ultimo_ejecutor_saque = autor_saque
	es_tiro_indirecto = indirecto
	toques_en_jugada = 0


## Coloca el balón en un punto específico para reanudación reglamentaria
func colocar_en_reanudacion(nueva_posicion: Vector3) -> void:
	_limpiar_portadores_previos(null)
	estado = EstadoBalon.LIBRE
	_en_pase_hueco = false
	_efecto_magnus_activo = false
	es_cesion_pie_companero = false
	equipo_cesion_pie = -1
	es_tiro_indirecto = false
	toques_en_jugada = 0
	ultimo_ejecutor_saque = null
	ultimo_pasador = null
	_t_bloqueo_pasador = 0.0
	sacador_autorizado = null
	linear_damp = amortiguacion_lineal
	portador_actual = null
	if collision_shape_3d:
		collision_shape_3d.set_deferred("disabled", false)
	freeze = false
	sleeping = false
	detener()
	var pos_ajustada: Vector3 = nueva_posicion
	pos_ajustada.y = maxf(pos_ajustada.y, obtener_radio_efectivo())
	global_position = pos_ajustada
	global_transform.origin = pos_ajustada
	if is_inside_tree():
		PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), pos_ajustada))
		PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
		PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
	esta_fuera_de_juego = false


## Restablece la posición del balón y cancela toda fuerza acumulada.
func reiniciar_posicion(nueva_posicion: Vector3 = Vector3(0.0, 0.25, 0.0)) -> void:
	colocar_en_reanudacion(nueva_posicion)
