class_name GestorPartido
extends Node

## Gestor central del flujo de partido y reanudaciones reglamentarias de fútbol sala.
## Controla los estados de juego (saques de banda, meta, esquina y goles),
## la aplicación estricta de la regla de los 4 metros para los rivales,
## congelamiento temporal durante posicionamiento y timeouts de saque.

enum EstadoPartido {
	EN_JUEGO,
	SAQUE_BANDA,
	SAQUE_META,
	SAQUE_ESQUINA,
	GOL
}

signal estado_cambiado(nuevo: EstadoPartido)

@export var distancia_reglamentaria: float = 4.0
@export var margen_distancia: float = 0.3
@export var t_pausa_saque: float = 1.0
@export var t_celebracion_gol: float = 2.0
@export var t_timeout_saque: float = 5.0

var estado: EstadoPartido = EstadoPartido.EN_JUEGO
var _balon: Balon3D = null
var _sacador_actual: Jugador3D = null
var _equipo_sacador: int = 0
var _timer_timeout: float = 0.0
var _esperando_toque: bool = false
var _pos_saque: Vector3 = Vector3.ZERO


func _ready() -> void:
	add_to_group("gestor_partido")
	_conectar_balon()


func _conectar_balon() -> void:
	var balones: Array[Node] = get_tree().get_nodes_in_group("balon")
	if not balones.is_empty():
		_balon = balones[0] as Balon3D
		if _balon and not _balon.balon_liberado.is_connected(_on_balon_liberado):
			_balon.balon_liberado.connect(_on_balon_liberado)


func _physics_process(delta: float) -> void:
	if estado == EstadoPartido.EN_JUEGO:
		return
	
	if _balon == null:
		_conectar_balon()
		if _balon == null:
			return
	
	# Mantener al sacador plantado en su posición reglamentaria de saque hasta que suelte el balón con pase o tiro
	if _esperando_toque and _sacador_actual and is_instance_valid(_sacador_actual):
		if not _sacador_actual._en_posicion_saque:
			_sacador_actual.fijar_en_saque(true, _sacador_actual._pos_anclaje_saque)
	
	# Aplicar continuamente la barrera reglamentaria de 4 metros a todos los rivales (incluido el jugador controlado)
	_aplicar_regla_4m(false)
	
	# Gestionar el timeout del saque (pase automático si el sacador se demora más de 5 segundos)
	if _esperando_toque and _timer_timeout > 0.0:
		_timer_timeout -= delta
		if _timer_timeout <= 0.0:
			_ejecutar_timeout_saque()


## Inicia una reanudación reglamentaria (Banda, Córner o Saque de Meta)
func iniciar_reanudacion(tipo: EstadoPartido, pos: Vector3, equipo_sacador: int) -> void:
	if _balon == null:
		_conectar_balon()
	
	estado = tipo
	_equipo_sacador = equipo_sacador
	_pos_saque = pos
	estado_cambiado.emit(tipo)
	
	var todos: Array[Node] = get_tree().get_nodes_in_group("jugadores_futsal")
	for n: Node in todos:
		var j_limpio: Jugador3D = n as Jugador3D
		if j_limpio:
			j_limpio.fijar_en_saque(false)
	
	# Obtener al jugador de campo más cercano (nunca el portero)
	var sacador: Jugador3D = _obtener_sacador_campo(pos, equipo_sacador)
	_sacador_actual = sacador
	
	# Colocar el balón y asignar sacador autorizado
	if _balon:
		_balon.colocar_en_reanudacion(pos)
		_balon.sacador_autorizado = sacador
	
	# Posicionar al sacador detrás del balón, anclarlo sin poder caminar y darle la posesión lista para sacar
	if sacador != null:
		var dir_hacia_campo: Vector3 = Vector3(1.0 if equipo_sacador == 0 else -1.0, 0.0, 0.0)
		if tipo == EstadoPartido.SAQUE_BANDA:
			dir_hacia_campo = Vector3(0.0, 0.0, -1.0 if pos.z > 0.0 else 1.0)
		elif tipo == EstadoPartido.SAQUE_ESQUINA:
			dir_hacia_campo = Vector3(-signf(pos.x), 0.0, -signf(pos.z)).normalized()
		elif tipo == EstadoPartido.SAQUE_META:
			dir_hacia_campo = Vector3(1.0 if equipo_sacador == 0 else -1.0, 0.0, 0.0)
		
		var pos_anclaje: Vector3 = pos - dir_hacia_campo * 0.62
		pos_anclaje.y = 0.0
		sacador.fijar_en_saque(true, pos_anclaje)
		sacador.rotation.y = atan2(-dir_hacia_campo.x, -dir_hacia_campo.z)
		sacador.velocity = Vector3.ZERO
		if _balon:
			sacador.tomar_posesion(_balon)
			sacador._tiempo_inmunidad_robo = t_timeout_saque + 1.5
		
		# Si el equipo sacador es LOCAL, conceder control exclusivo al sacador (solo podrá apuntar y pasar/despejar)
		if equipo_sacador == 0:
			_asignar_control_exclusivo(sacador)
		else:
			sacador._cooldown_decision_ia = t_pausa_saque + 0.35
	
	# Congelar a todos los jugadores excepto al sacador durante la preparación inicial
	for n: Node in todos:
		var j: Jugador3D = n as Jugador3D
		if j:
			if j == sacador:
				j.set_congelado(false)
			else:
				j.set_congelado(true)
				j.velocity = Vector3.ZERO
	
	_esperando_toque = true
	_timer_timeout = t_timeout_saque
	
	# Aplicar regla de 4m inicial reubicando rivales fuera del círculo reglamentario
	_aplicar_regla_4m(true)
	
	# Pausa de preparación antes de descongelar al resto para desmarques (el sacador sigue anclado en su sitio)
	await get_tree().create_timer(t_pausa_saque).timeout
	
	if estado == tipo:
		for n: Node in todos:
			var j: Jugador3D = n as Jugador3D
			if j and is_instance_valid(j):
				j.set_congelado(false)


## Gestiona la celebración del gol y el saque desde el centro del campo
func iniciar_gol(equipo_que_anoto: int) -> void:
	if _balon == null:
		_conectar_balon()
	
	estado = EstadoPartido.GOL
	estado_cambiado.emit(EstadoPartido.GOL)
	_esperando_toque = false
	
	if _balon:
		_balon.esta_fuera_de_juego = true
		_balon.detener()
	
	# 1. Congelar a todos los jugadores durante la celebración del gol
	var todos: Array[Node] = get_tree().get_nodes_in_group("jugadores_futsal")
	for n: Node in todos:
		var j: Jugador3D = n as Jugador3D
		if j:
			j.fijar_en_saque(false)
			j.set_congelado(true)
			j.velocity = Vector3.ZERO
	
	await get_tree().create_timer(t_celebracion_gol).timeout
	
	# 2. Retornar a cada jugador a su posición táctica inicial
	for n: Node in todos:
		var j: Jugador3D = n as Jugador3D
		if j and is_instance_valid(j):
			j.global_position = j._posicion_tactica_inicial
			j.velocity = Vector3.ZERO
			j.set_congelado(false)
	
	# 3. Colocar el balón en el punto central
	var pos_centro: Vector3 = Vector3(0.0, 0.25, 0.0)
	_pos_saque = pos_centro
	if _balon:
		_balon.colocar_en_reanudacion(pos_centro)
	
	# 4. Saca el equipo que recibió el gol
	_equipo_sacador = 1 if equipo_que_anoto == 0 else 0
	var sacador: Jugador3D = _obtener_sacador_centro(_equipo_sacador)
	_sacador_actual = sacador
	
	if _balon:
		_balon.sacador_autorizado = sacador
	
	if sacador != null:
		var dir_frente: Vector3 = Vector3(1.0 if _equipo_sacador == 0 else -1.0, 0.0, 0.0)
		var pos_anclaje_centro: Vector3 = pos_centro - dir_frente * 0.62
		pos_anclaje_centro.y = 0.0
		sacador.fijar_en_saque(true, pos_anclaje_centro)
		sacador.rotation.y = atan2(-dir_frente.x, -dir_frente.z)
		sacador.velocity = Vector3.ZERO
		if _balon:
			sacador.tomar_posesion(_balon)
			sacador._tiempo_inmunidad_robo = t_timeout_saque + 1.5
		
		if _equipo_sacador == 0:
			_asignar_control_exclusivo(sacador)
		else:
			sacador._cooldown_decision_ia = 0.55
	
	# 5. Aplicar la regla de 4 metros alrededor del círculo central
	_esperando_toque = true
	_aplicar_regla_4m(true)
	_timer_timeout = t_timeout_saque


## Callback cuando el balón es pateado o soltado por el sacador
func _on_balon_liberado() -> void:
	_finalizar_reanudacion()


## Finaliza la reanudación pasando al estado EN_JUEGO y liberando el anclaje del sacador
func _finalizar_reanudacion() -> void:
	if _esperando_toque or estado != EstadoPartido.EN_JUEGO:
		_esperando_toque = false
		if _balon:
			_balon.sacador_autorizado = null
		
		if _sacador_actual and is_instance_valid(_sacador_actual):
			_sacador_actual.fijar_en_saque(false)
			_sacador_actual._tiempo_inmunidad_robo = 1.2
		
		var todos: Array[Node] = get_tree().get_nodes_in_group("jugadores_futsal")
		for n: Node in todos:
			var j: Jugador3D = n as Jugador3D
			if j and is_instance_valid(j):
				j.fijar_en_saque(false)
				if j._congelado:
					j.set_congelado(false)
		
		_sacador_actual = null
		estado = EstadoPartido.EN_JUEGO
		estado_cambiado.emit(EstadoPartido.EN_JUEGO)


## Si se agota el tiempo reglamentario de 5s, el sacador pasa automáticamente al compañero más cercano
func _ejecutar_timeout_saque() -> void:
	if _sacador_actual and is_instance_valid(_sacador_actual):
		var companero: Jugador3D = _obtener_companero_mas_cercano(_sacador_actual)
		if companero:
			var dir_pase: Vector3 = (companero.global_position - _sacador_actual.global_position).normalized()
			_sacador_actual._direccion_deseada = dir_pase
			_sacador_actual.rotation.y = atan2(-dir_pase.x, -dir_pase.z)
		
		if not _sacador_actual.tiene_posesion and _balon and _sacador_actual.puede_tomar_balon():
			_sacador_actual.tomar_posesion(_balon)
		_sacador_actual.ejecutar_pase(0.5)
	
	# Salvaguarda: si tras ejecutar_pase el balón aún no fue liberado, forzar liberación directa
	if _esperando_toque and _balon and is_instance_valid(_balon):
		var comp_fallback: Jugador3D = _obtener_companero_mas_cercano(_sacador_actual)
		var dir_balon: Vector3 = Vector3(1.0 if _equipo_sacador == 0 else -1.0, 0.0, 0.0)
		if comp_fallback:
			dir_balon = (comp_fallback.global_position - _balon.global_position).normalized()
		_balon.liberar(dir_balon * 8.5 + Vector3(0.0, 0.1, 0.0), _equipo_sacador)


## Aplica la barrera reglamentaria de 4 metros a todos los rivales del equipo sacador
func _aplicar_regla_4m(reubicacion_inicial: bool = false) -> void:
	if _balon == null:
		return
	
	var pos_b: Vector3 = _pos_saque
	var grupo_rival: String = "equipo_visitante" if _equipo_sacador == 0 else "equipo_local"
	var rivales: Array[Node] = get_tree().get_nodes_in_group(grupo_rival)
	
	var R: float = distancia_reglamentaria + margen_distancia
	
	for nodo: Node in rivales:
		var rival: Jugador3D = nodo as Jugador3D
		if rival == null or rival.posicion_tactica == "PORTERO":
			continue
		
		var pos_r: Vector3 = rival.global_position
		var diff: Vector3 = pos_r - pos_b
		diff.y = 0.0
		var d: float = diff.length()
		
		var viola_distancia: bool = (d < distancia_reglamentaria)
		var viola_area_meta: bool = false
		
		# En SAQUE_META el rival tampoco puede estar en |x| > 14 del lado del sacador
		if estado == EstadoPartido.SAQUE_META:
			if _equipo_sacador == 0 and pos_r.x < -14.0:
				viola_area_meta = true
			elif _equipo_sacador == 1 and pos_r.x > 14.0:
				viola_area_meta = true
		
		if viola_distancia or viola_area_meta:
			if not reubicacion_inicial and d > 0.25 and not viola_area_meta:
				# Barrera física suave continua cuando el jugador intenta acercarse caminando al sacador rival
				var dir_radial: Vector3 = diff.normalized()
				var nueva_pos: Vector3 = pos_b + dir_radial * (distancia_reglamentaria + 0.06)
				nueva_pos.x = clampf(nueva_pos.x, -19.2, 19.2)
				nueva_pos.z = clampf(nueva_pos.z, -9.5, 9.5)
				rival.global_position = Vector3(nueva_pos.x, 0.0, nueva_pos.z)
				var vel_radial: float = rival.velocity.dot(dir_radial)
				if vel_radial < 0.0:
					rival.velocity -= dir_radial * vel_radial
				continue
			
			var angulo_base: float = atan2(diff.z, diff.x)
			if diff.length_squared() < 0.001:
				angulo_base = 0.0 if _equipo_sacador == 0 else PI
			
			var indices_ordenados: Array[int] = [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6, 7, -7, 8]
			var paso_angular: float = TAU / 16.0
			
			var pos_reubicada: Vector3 = Vector3.ZERO
			var posicion_encontrada: bool = false
			
			for idx: int in indices_ordenados:
				var ang: float = angulo_base + (float(idx) * paso_angular)
				var cand_x: float = pos_b.x + cos(ang) * R
				var cand_z: float = pos_b.z + sin(ang) * R
				
				# Comprobar límites de campo (|x| <= 19 y |z| <= 9.5)
				if abs(cand_x) <= 19.0 and abs(cand_z) <= 9.5:
					if estado == EstadoPartido.SAQUE_META:
						if _equipo_sacador == 0 and cand_x < -14.0:
							continue
						elif _equipo_sacador == 1 and cand_x > 14.0:
							continue
					
					pos_reubicada = Vector3(cand_x, 0.0, cand_z)
					posicion_encontrada = true
					break
			
			if not posicion_encontrada:
				var fallback_x: float = clampf(pos_b.x + cos(angulo_base) * R, -19.0, 19.0)
				var fallback_z: float = clampf(pos_b.z + sin(angulo_base) * R, -9.5, 9.5)
				if estado == EstadoPartido.SAQUE_META:
					if _equipo_sacador == 0 and fallback_x < -14.0:
						fallback_x = -13.5
					elif _equipo_sacador == 1 and fallback_x > 14.0:
						fallback_x = 13.5
				pos_reubicada = Vector3(fallback_x, 0.0, fallback_z)
				posicion_encontrada = true
			
			if posicion_encontrada:
				rival.global_position = pos_reubicada
				rival.velocity = Vector3.ZERO



func _obtener_companero_mas_cercano(sacador: Jugador3D) -> Jugador3D:
	var grupo: String = "equipo_local" if _equipo_sacador == 0 else "equipo_visitante"
	var jugadores: Array[Node] = get_tree().get_nodes_in_group(grupo)
	var mas_cercano: Jugador3D = null
	var min_dist: float = 999.0
	for n: Node in jugadores:
		var j: Jugador3D = n as Jugador3D
		if j and j != sacador and j.posicion_tactica != "PORTERO":
			var d: float = 999.0
			if sacador != null:
				d = sacador.global_position.distance_to(j.global_position)
			elif _balon != null:
				d = _balon.global_position.distance_to(j.global_position)
			if d < min_dist:
				min_dist = d
				mas_cercano = j
	return mas_cercano



func _obtener_sacador_campo(pos_balon: Vector3, equipo_sac: int) -> Jugador3D:
	var grupo: String = "equipo_local" if equipo_sac == 0 else "equipo_visitante"
	var jugadores: Array[Node] = get_tree().get_nodes_in_group(grupo)
	
	var mas_cercano: Jugador3D = null
	var min_dist: float = 999.0
	
	for n: Node in jugadores:
		var jug: Jugador3D = n as Jugador3D
		if jug and jug.posicion_tactica != "PORTERO":
			var d: float = jug.global_position.distance_to(pos_balon)
			if d < min_dist:
				min_dist = d
				mas_cercano = jug
	
	return mas_cercano


func _obtener_sacador_centro(equipo_sac: int) -> Jugador3D:
	var grupo: String = "equipo_local" if equipo_sac == 0 else "equipo_visitante"
	var jugadores: Array[Node] = get_tree().get_nodes_in_group(grupo)
	
	for n: Node in jugadores:
		var jug: Jugador3D = n as Jugador3D
		if jug and jug.posicion_tactica == "PIVOT":
			return jug
	
	return _obtener_sacador_campo(Vector3.ZERO, equipo_sac)


func _asignar_control_exclusivo(jugador_a_controlar: Jugador3D) -> void:
	if jugador_a_controlar == null:
		return
	jugador_a_controlar._asignar_control_a_este_jugador()
